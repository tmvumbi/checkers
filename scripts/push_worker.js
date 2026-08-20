// Cloudflare Worker "checkers-push" — FCM v1 relay for tournament
// reminders. Postgres (pg_net) POSTs { tokens, title, body, data } to
// /send with the shared RELAY_KEY; the worker mints a Google OAuth token
// from the FCM_SA service-account secret and fans out to FCM.
//
// Deploy:   npx wrangler deploy scripts/push_worker.js --name checkers-push
// Secrets:  npx wrangler secret put FCM_SA --name checkers-push   (service-account JSON)
//           npx wrangler secret put RELAY_KEY --name checkers-push

let cachedToken = null; // { value, expiresAt }

function base64url(bytes) {
  let raw = "";
  for (const b of bytes) raw += String.fromCharCode(b);
  return btoa(raw).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem) {
  const body = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  const raw = atob(body);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes.buffer;
}

async function mintAccessToken(sa) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt > now + 60) {
    return cachedToken.value;
  }
  const encoder = new TextEncoder();
  const header = base64url(
    encoder.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })),
  );
  const claims = base64url(
    encoder.encode(
      JSON.stringify({
        iss: sa.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: sa.token_uri,
        iat: now,
        exp: now + 3600,
      }),
    ),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(`${header}.${claims}`),
  );
  const jwt = `${header}.${claims}.${base64url(new Uint8Array(signature))}`;

  const response = await fetch(sa.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!response.ok) {
    throw new Error(`token mint failed: ${response.status}`);
  }
  const data = await response.json();
  cachedToken = { value: data.access_token, expiresAt: now + data.expires_in };
  return cachedToken.value;
}

async function sendOne(projectId, accessToken, token, title, body, data) {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: data ?? {},
          android: { priority: "HIGH" },
          apns: {
            headers: { "apns-priority": "10" },
            payload: { aps: { sound: "default" } },
          },
        },
      }),
    },
  );
  if (response.ok) return { ok: true };
  const text = await response.text();
  return { ok: false, status: response.status, error: text.slice(0, 300) };
}

export default {
  async fetch(request, env) {
    if (request.method !== "POST" || new URL(request.url).pathname !== "/send") {
      return new Response("not found", { status: 404 });
    }
    const auth = request.headers.get("Authorization") ?? "";
    if (!env.RELAY_KEY || auth !== `Bearer ${env.RELAY_KEY}`) {
      return new Response("unauthorized", { status: 401 });
    }
    let payload;
    try {
      payload = await request.json();
    } catch {
      return new Response("bad json", { status: 400 });
    }
    const tokens = Array.isArray(payload.tokens) ? payload.tokens : [];
    if (tokens.length === 0 || tokens.length > 500) {
      return Response.json({ sent: 0, failed: 0 });
    }
    const sa = JSON.parse(env.FCM_SA);
    const accessToken = await mintAccessToken(sa);
    const results = await Promise.all(
      tokens.map((token) =>
        sendOne(
          sa.project_id,
          accessToken,
          token,
          String(payload.title ?? ""),
          String(payload.body ?? ""),
          payload.data,
        ),
      ),
    );
    const failed = results.filter((r) => !r.ok);
    return Response.json({
      sent: results.length - failed.length,
      failed: failed.length,
      errors: failed.slice(0, 5),
    });
  },
};
