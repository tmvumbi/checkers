// Cloudflare Worker for checkers.contribution.club — serves the app-link
// verification files and a deep-link fallback page for invite links.
// Deployed on the route checkers.contribution.club/* .

const ASSETLINKS = [
  {
    relation: ["delegate_permission/common.handle_all_urls"],
    target: {
      namespace: "android_app",
      package_name: "club.contribution.checkers",
      sha256_cert_fingerprints: [
        // Debug keystore.
        "99:D5:F9:DB:83:5C:52:CE:4C:D3:AD:03:72:9D:B0:10:22:3A:E0:B8:B7:0A:9E:F4:12:7B:2E:50:00:3B:B4:EA",
        // Release keystore (~/.config/checkers/checkers-release.keystore).
        // If Play App Signing re-signs at launch, add Google's fingerprint
        // from Play Console -> App integrity as a third entry.
        "3E:5A:90:05:CC:D6:22:35:79:18:CF:96:B9:D5:07:F1:5E:87:7A:57:6C:59:6C:E7:0F:24:04:8D:AF:76:92:07",
      ],
    },
  },
];

const AASA = {
  applinks: {
    apps: [],
    details: [
      {
        appIDs: ["TKDDB59257.club.contribution.checkers"],
        components: [{ "/": "/party/*" }, { "/": "/tournament" }],
      },
    ],
  },
};

function deepLinkPage(scheme, label) {
  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Checkers</title>
<style>
  body{margin:0;font-family:-apple-system,Segoe UI,Roboto,sans-serif;
    background:linear-gradient(#12261B,#071109);color:#fff;display:flex;
    align-items:center;justify-content:center;min-height:100vh;text-align:center}
  .card{padding:32px 24px;max-width:340px}
  h1{color:#FFC801;letter-spacing:3px;font-size:26px}
  p{opacity:.85;line-height:1.5}
  a.btn{display:block;margin:12px auto;padding:14px 18px;border-radius:10px;
    background:#263F6D;color:#fff;text-decoration:none;font-weight:700;
    border:2px solid #fff;max-width:260px}
  a.gold{background:#7240B0}
</style></head><body><div class="card">
<h1>CHECKERS</h1>
<p>${label}</p>
<a class="btn" href="${scheme}">Open the app</a>
<p style="font-size:13px;opacity:.6">If nothing happens, install Checkers
first, then tap the link again.</p>
<p style="font-size:12px;opacity:.45">Opens club.contribution.checkers</p>
</div>
<script>setTimeout(function(){window.location=${JSON.stringify(scheme)}},400)</script>
</body></html>`;
}

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const p = url.pathname;
    const json = (obj) =>
      new Response(JSON.stringify(obj), {
        headers: { "content-type": "application/json" },
      });
    const html = (body) =>
      new Response(body, {
        headers: { "content-type": "text/html; charset=utf-8" },
      });

    if (p === "/.well-known/assetlinks.json") return json(ASSETLINKS);
    if (
      p === "/.well-known/apple-app-site-association" ||
      p === "/apple-app-site-association"
    )
      return json(AASA);

    const party = p.match(/^\/party\/([A-Za-z0-9-]+)/);
    if (party)
      return html(
        deepLinkPage(
          "club.contribution.checkers://party/" + party[1],
          "You've been invited to a game!"
        )
      );
    if (p === "/tournament" || p.startsWith("/tournament/"))
      return html(
        deepLinkPage(
          "club.contribution.checkers://tournament",
          "You've been invited to a tournament!"
        )
      );
    return html(
      deepLinkPage("club.contribution.checkers://home", "Draughts & checkers, together.")
    );
  },
};
