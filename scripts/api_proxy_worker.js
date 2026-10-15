// Temporary compatibility proxy for api.dame.cd.
//
// The dame.cd zone and the existing Cloudflare Tunnel are owned by different
// Cloudflare accounts. Keeping the tunnel untouched preserves the production
// contribution.club endpoint while this Worker gives the replacement app a
// stable API hostname. A plain fetch response also passes WebSocket upgrades
// through Cloudflare, which is required by Supabase Realtime.

const UPSTREAM_ORIGIN = "https://checkers-api.contribution.club";
const PUBLIC_ORIGIN = "https://api.dame.cd";

export default {
  async fetch(request) {
    const incomingUrl = new URL(request.url);
    const upstreamUrl = new URL(incomingUrl.pathname + incomingUrl.search,
      UPSTREAM_ORIGIN);

    const headers = new Headers(request.headers);
    headers.set("X-Forwarded-Host", incomingUrl.host);
    headers.set("X-Forwarded-Proto", "https");

    try {
      const response = await fetch(new Request(upstreamUrl, {
        method: request.method,
        headers,
        body: request.body,
        redirect: "manual",
      }));

      // Successful WebSocket upgrades must be returned unchanged so the
      // Workers runtime can proxy the connection end to end.
      if (response.webSocket) return response;

      const location = response.headers.get("Location");
      if (!location || !location.startsWith(UPSTREAM_ORIGIN)) return response;

      const responseHeaders = new Headers(response.headers);
      responseHeaders.set(
        "Location",
        PUBLIC_ORIGIN + location.slice(UPSTREAM_ORIGIN.length),
      );
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: responseHeaders,
      });
    } catch (error) {
      console.error("API upstream fetch failed", error);
      return new Response("Bad Gateway", { status: 502 });
    }
  },
};
