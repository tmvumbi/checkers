// Cloudflare Worker "checkers-admin" — advertisement admin console on
// checkers.contribution.club/admin*. Basic-auth protected (secrets
// ADMIN_USER / ADMIN_PASS); talks to Supabase with the service role key
// (secrets SUPABASE_URL / SERVICE_KEY), which never reaches the browser.
//
// Deploy:  npx wrangler deploy scripts/admin_worker.js --name checkers-admin \
//            --compatibility-date 2026-08-01 \
//            --route "checkers.contribution.club/admin*"

function unauthorized() {
  return new Response("Authentication required", {
    status: 401,
    headers: { "WWW-Authenticate": 'Basic realm="Checkers Admin"' },
  });
}

function checkAuth(request, env) {
  const header = request.headers.get("Authorization") ?? "";
  if (!header.startsWith("Basic ")) return false;
  let decoded;
  try {
    decoded = atob(header.slice(6));
  } catch {
    return false;
  }
  const idx = decoded.indexOf(":");
  const user = decoded.slice(0, idx);
  const pass = decoded.slice(idx + 1);
  return user === env.ADMIN_USER && pass === env.ADMIN_PASS;
}

async function sb(env, path, init = {}) {
  const headers = {
    apikey: env.SERVICE_KEY,
    Authorization: `Bearer ${env.SERVICE_KEY}`,
    "Content-Type": "application/json",
    Prefer: "return=representation",
    ...(init.headers ?? {}),
  };
  const response = await fetch(`${env.SUPABASE_URL}${path}`, {
    ...init,
    headers,
  });
  const text = await response.text();
  return new Response(text, {
    status: response.status,
    headers: { "Content-Type": "application/json" },
  });
}

async function sbJson(env, path, init = {}) {
  const response = await fetch(`${env.SUPABASE_URL}${path}`, {
    ...init,
    headers: {
      apikey: env.SERVICE_KEY,
      Authorization: `Bearer ${env.SERVICE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
      ...(init.headers ?? {}),
    },
  });
  if (!response.ok) {
    throw new Error(await response.text());
  }
  return response.json();
}

async function handleApi(request, env, path) {
  const url = new URL(request.url);
  const method = request.method;

  if (path === "/customers" && method === "GET") {
    return sb(env, "/rest/v1/ad_customers?select=*&order=created_at.desc");
  }
  if (path === "/customers" && method === "POST") {
    return sb(env, "/rest/v1/ad_customers", {
      method: "POST",
      body: JSON.stringify(await request.json()),
    });
  }
  if (path.startsWith("/customers/") && method === "PATCH") {
    const id = path.split("/")[2];
    return sb(env, `/rest/v1/ad_customers?id=eq.${id}`, {
      method: "PATCH",
      body: JSON.stringify(await request.json()),
    });
  }

  if (path === "/campaigns" && method === "GET") {
    return sb(
      env,
      "/rest/v1/ad_campaigns?select=*,ad_customers(name)&order=created_at.desc",
    );
  }
  if (path === "/campaigns" && method === "POST") {
    return sb(env, "/rest/v1/ad_campaigns", {
      method: "POST",
      body: JSON.stringify(await request.json()),
    });
  }
  if (path.startsWith("/campaigns/") && method === "PATCH") {
    const id = path.split("/")[2];
    return sb(env, `/rest/v1/ad_campaigns?id=eq.${id}`, {
      method: "PATCH",
      body: JSON.stringify(await request.json()),
    });
  }

  if (path === "/stats" && method === "GET") {
    const days = Math.min(parseInt(url.searchParams.get("days") ?? "30"), 90);
    const since = new Date(Date.now() - days * 86400000)
      .toISOString()
      .slice(0, 10);
    return sb(
      env,
      `/rest/v1/ad_daily_stats?select=*&day=gte.${since}&order=day.desc`,
    );
  }

  if (path === "/upload" && method === "POST") {
    const name = (url.searchParams.get("name") ?? "file.png")
      .replace(/[^a-zA-Z0-9._-]/g, "_");
    const key = `${Date.now()}-${crypto.randomUUID().slice(0, 8)}-${name}`;
    const body = await request.arrayBuffer();
    if (body.byteLength > 4 * 1024 * 1024) {
      return Response.json({ error: "file too large (max 4MB)" }, {
        status: 400,
      });
    }
    const response = await fetch(
      `${env.SUPABASE_URL}/storage/v1/object/ads/${key}`,
      {
        method: "POST",
        headers: {
          apikey: env.SERVICE_KEY,
          Authorization: `Bearer ${env.SERVICE_KEY}`,
          "Content-Type":
            request.headers.get("Content-Type") ?? "application/octet-stream",
        },
        body,
      },
    );
    if (!response.ok) {
      return Response.json(
        { error: `storage upload failed: ${await response.text()}` },
        { status: 500 },
      );
    }
    return Response.json({
      url: `${env.SUPABASE_URL}/storage/v1/object/public/ads/${key}`,
    });
  }

  if (path === "/messages" && method === "GET") {
    return sb(
      env,
      "/rest/v1/player_messages?select=*&order=created_at.desc&limit=50",
    );
  }
  if (path === "/messages" && method === "POST") {
    const b = await request.json();
    const days = parseInt(b.days) || 30;
    return sb(env, "/rest/v1/player_messages", {
      method: "POST",
      body: JSON.stringify({
        type: b.target_uid ? "private" : "public",
        language: b.language,
        target_uid: b.target_uid || null,
        html_text: b.html_text || null,
        image_url: b.image_url || null,
        link_url: b.link_url || null,
        expires_at: new Date(Date.now() + days * 86400000).toISOString(),
      }),
    });
  }
  if (path.startsWith("/messages/") && method === "PATCH") {
    const id = path.split("/")[2];
    return sb(env, `/rest/v1/player_messages?id=eq.${id}`, {
      method: "PATCH",
      body: JSON.stringify(await request.json()),
    });
  }

  if (path === "/players" && method === "GET") {
    const q = (url.searchParams.get("search") ?? "").replace(/[%_\\,()]/g, "");
    const pattern = encodeURIComponent("%" + q + "%");
    return sb(
      env,
      `/rest/v1/profiles?select=id,nickname,rating&nickname=ilike.${pattern}&order=nickname&limit=20`,
    );
  }

  if (path === "/blocks" && method === "GET") {
    const blocks = await sbJson(
      env,
      "/rest/v1/player_blocks?select=*&revoked_at=is.null&order=created_at.desc&limit=100",
    );
    const uids = [...new Set(blocks.map((b) => b.uid))];
    let names = {};
    if (uids.length) {
      const profiles = await sbJson(
        env,
        `/rest/v1/profiles?select=id,nickname&id=in.(${uids.join(",")})`,
      );
      names = Object.fromEntries(profiles.map((p) => [p.id, p.nickname]));
    }
    return Response.json(
      blocks.map((b) => ({ ...b, nickname: names[b.uid] ?? "" })),
    );
  }
  if (path === "/blocks" && method === "POST") {
    const b = await request.json();
    return sb(env, "/rest/v1/rpc/block_player", {
      method: "POST",
      body: JSON.stringify({
        p_uid: b.uid,
        p_level: b.level,
        p_days: b.days ?? null,
        p_reason: b.reason ?? null,
      }),
    });
  }
  if (path === "/unblock" && method === "POST") {
    const b = await request.json();
    return sb(env, "/rest/v1/rpc/unblock_player", {
      method: "POST",
      body: JSON.stringify({ p_uid: b.uid }),
    });
  }

  if (path === "/ops" && method === "GET") {
    const days = Math.min(
      Math.max(parseInt(url.searchParams.get("days") ?? "7"), 1), 90);
    const result = await sbJson(env, "/rest/v1/rpc/admin_operations_metrics", {
      method: "POST",
      body: JSON.stringify({ p_days: days }),
    });
    return Response.json(result);
  }

  if (path === "/player-stats" && method === "GET") {
    const days = Math.min(
      Math.max(parseInt(url.searchParams.get("days") ?? "7"), 1), 90);
    const result = await sbJson(env, "/rest/v1/rpc/admin_player_stats", {
      method: "POST",
      body: JSON.stringify({ p_days: days, p_limit: 200 }),
    });
    return Response.json(result);
  }

  if (path === "/settings" && method === "GET") {
    const rows = await sbJson(
      env,
      "/rest/v1/app_config?id=eq.public&select=config",
    );
    const config = rows[0]?.config ?? {};
    const ads = config.ads ?? {};
    return Response.json({
      adsEnabled: ads.enabled ?? true,
      interstitialFrequency: ads.interstitialFrequency ?? 15,
      adUnits: {
        android: {
          banner: ads.android?.bannerAdUnitId ?? "",
          interstitial: ads.android?.interstitialAdUnitId ?? "",
        },
        ios: {
          banner: ads.ios?.bannerAdUnitId ?? "",
          interstitial: ads.ios?.interstitialAdUnitId ?? "",
        },
      },
      allowedAndroidVersions: config.allowed_android_versions ?? [],
      allowedIosVersions: config.allowed_ios_versions ?? [],
      androidAppUrl: config.android_app_url ?? "",
      iosAppUrl: config.ios_app_url ?? "",
      turnMs: config.turn_ms ?? 15000,
      bankMs: config.bank_ms ?? 300000,
      leaderboardMinGames: config.leaderboard_min_games ?? 1,
    });
  }
  if (path === "/settings" && method === "PATCH") {
    const b = await request.json();
    const bad = (m) => Response.json({ error: m }, { status: 400 });

    // Guard rails: these keys reach every client, and a bad value either
    // locks players out of the app or breaks the clocks.
    const versionList = (value, label) => {
      if (!Array.isArray(value)) return label + " must be a list";
      for (const v of value) {
        if (typeof v !== "string" || !/^[0-9]+(\.[0-9]+)*$/.test(v.trim())) {
          return label + ': "' + v + '" is not a version number';
        }
      }
      return null;
    };
    const positiveInt = (value, label, min, max) => {
      if (!Number.isInteger(value) || value < min || value > max) {
        return label + " must be a whole number between " + min + " and " + max;
      }
      return null;
    };
    const httpsUrl = (value, label) => {
      if (typeof value !== "string" || !value.startsWith("https://")) {
        return label + " must be an https:// URL";
      }
      return null;
    };

    const checks = [
      b.allowedAndroidVersions !== undefined &&
        versionList(b.allowedAndroidVersions, "Android versions"),
      b.allowedIosVersions !== undefined &&
        versionList(b.allowedIosVersions, "iOS versions"),
      b.androidAppUrl !== undefined && httpsUrl(b.androidAppUrl, "Android app URL"),
      b.iosAppUrl !== undefined && httpsUrl(b.iosAppUrl, "iOS app URL"),
      b.turnMs !== undefined &&
        positiveInt(b.turnMs, "Turn time", 3000, 600000),
      b.bankMs !== undefined &&
        positiveInt(b.bankMs, "Time bank", 10000, 7200000),
      b.leaderboardMinGames !== undefined &&
        positiveInt(b.leaderboardMinGames, "Leaderboard minimum games", 0, 1000),
      b.interstitialFrequency !== undefined &&
        positiveInt(b.interstitialFrequency, "Interstitial frequency", 1, 1000),
    ].filter(Boolean);
    if (checks.length) return bad(checks[0]);

    const rows = await sbJson(
      env,
      "/rest/v1/app_config?id=eq.public&select=config",
    );
    const config = rows[0]?.config ?? {};
    const ads = { ...(config.ads ?? {}) };
    if (b.adsEnabled != null) ads.enabled = b.adsEnabled;
    if (b.interstitialFrequency != null) {
      ads.interstitialFrequency = b.interstitialFrequency;
    }
    for (const platform of ["android", "ios"]) {
      const units = b.adUnits?.[platform];
      if (!units) continue;
      ads[platform] = {
        ...(ads[platform] ?? {}),
        ...(units.banner !== undefined
          ? { bannerAdUnitId: units.banner.trim() }
          : {}),
        ...(units.interstitial !== undefined
          ? { interstitialAdUnitId: units.interstitial.trim() }
          : {}),
      };
    }
    config.ads = ads;

    if (b.allowedAndroidVersions !== undefined) {
      config.allowed_android_versions =
        b.allowedAndroidVersions.map((v) => v.trim());
    }
    if (b.allowedIosVersions !== undefined) {
      config.allowed_ios_versions = b.allowedIosVersions.map((v) => v.trim());
    }
    if (b.androidAppUrl !== undefined) {
      config.android_app_url = b.androidAppUrl.trim();
    }
    if (b.iosAppUrl !== undefined) config.ios_app_url = b.iosAppUrl.trim();
    if (b.turnMs !== undefined) config.turn_ms = b.turnMs;
    if (b.bankMs !== undefined) config.bank_ms = b.bankMs;
    if (b.leaderboardMinGames !== undefined) {
      config.leaderboard_min_games = b.leaderboardMinGames;
    }

    return sb(env, "/rest/v1/app_config?id=eq.public", {
      method: "PATCH",
      body: JSON.stringify({ config }),
    });
  }

  if (path === "/feedback" && method === "GET") {
    const scope = url.searchParams.get("scope") ?? "open";
    const filter = scope === "all" ? "" : "&handled_at=is.null";
    const items = await sbJson(
      env,
      "/rest/v1/feedback?select=*" + filter
        + "&order=created_at.desc&limit=100",
    );
    const uids = [...new Set(items.map((f) => f.uid).filter(Boolean))];
    let names = {};
    if (uids.length) {
      const profiles = await sbJson(
        env,
        `/rest/v1/profiles?select=id,nickname&id=in.(${uids.join(",")})`,
      );
      names = Object.fromEntries(profiles.map((p) => [p.id, p.nickname]));
    }
    const open = await sbJson(
      env,
      "/rest/v1/feedback?select=id&handled_at=is.null&limit=1000",
    );
    return Response.json({
      items: items.map((f) => ({ ...f, nickname: names[f.uid] ?? "" })),
      open_count: open.length,
    });
  }
  if (path.startsWith("/feedback/") && method === "PATCH") {
    const id = path.split("/")[2];
    const b = await request.json();
    return sb(env, `/rest/v1/feedback?id=eq.${id}`, {
      method: "PATCH",
      body: JSON.stringify({
        handled_at: b.handled ? new Date().toISOString() : null,
      }),
    });
  }

  return Response.json({ error: "not found" }, { status: 404 });
}

const PAGE = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Checkers Ads Admin</title>
<style>
:root {
  --bg: #0d1d14; --panel: #12261b; --panel2: #1a3325; --line: #2c4a38;
  --gold: #e5b94e; --text: #e8efe9; --muted: #93a89a; --purple: #7b4dbb;
}
* { box-sizing: border-box; margin: 0; }
body { background: var(--bg); color: var(--text);
  font: 15px/1.5 -apple-system, "Segoe UI", Roboto, sans-serif; }
header { display: flex; align-items: center; gap: 14px;
  padding: 14px 22px; background: var(--panel); border-bottom: 2px solid var(--line); }
header h1 { font-size: 19px; color: var(--gold); }
nav { display: flex; flex-wrap: wrap; gap: 2px; }
nav a { background: none; border: none; color: var(--muted);
  font-size: 15px; font-weight: 600; padding: 8px 14px; cursor: pointer;
  border-radius: 8px; text-decoration: none; display: inline-block; }
nav a.on { color: var(--gold); background: var(--panel2); }
main { max-width: 1060px; margin: 0 auto; padding: 22px; }
.card { background: var(--panel); border: 1px solid var(--line);
  border-radius: 12px; padding: 18px; margin-bottom: 18px; }
h2 { color: var(--gold); font-size: 17px; margin-bottom: 12px; }
table { width: 100%; border-collapse: collapse; font-size: 14px; }
th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--line); }
th { color: var(--muted); font-weight: 600; }
label { display: block; font-size: 13px; color: var(--muted); margin: 10px 0 4px; }
input, select, textarea { width: 100%; padding: 9px 11px; border-radius: 8px;
  border: 1px solid var(--line); background: var(--panel2); color: var(--text);
  font-size: 14px; }
input[type=checkbox] { width: auto; }
input[type=file] { padding: 6px; }
.row { display: grid; grid-template-columns: 1fr 1fr; gap: 0 16px; }
.row4 { display: grid; grid-template-columns: repeat(4, 1fr); gap: 0 12px; }
button.primary { margin-top: 14px; background: linear-gradient(135deg, #2a4d92, #1c3568);
  color: #fff; border: 1px solid #4666ab;
  padding: 10px 22px; border-radius: 9px; font-size: 15px; font-weight: 700;
  cursor: pointer; }
button.small { background: var(--panel2); color: var(--gold);
  border: 1px solid var(--line); padding: 4px 10px; border-radius: 7px;
  font-size: 13px; cursor: pointer; }
.pill { display: inline-block; padding: 2px 10px; border-radius: 99px;
  font-size: 12px; font-weight: 700; }
.pill.on { background: #1d4d2c; color: #7ce09a; }
.pill.off { background: #4d1d1d; color: #e07c7c; }
.bar { height: 10px; background: var(--gold); border-radius: 4px; min-width: 2px; }
.muted { color: var(--muted); }
img.thumb { height: 40px; border-radius: 6px; display: block; }
.msg { margin-top: 10px; font-size: 14px; color: #7ce09a; min-height: 20px; }
.msg.err { color: #e07c7c; }
.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 14px; margin-bottom: 18px; }
.stat { background: var(--panel); border: 1px solid var(--line);
  border-radius: 12px; padding: 14px 16px; }
.stat .n { font-size: 30px; font-weight: 800; color: var(--gold); line-height: 1.1; }
.stat .l { font-size: 13px; color: var(--muted); margin-top: 2px; }
.stat .sub { font-size: 12px; color: var(--muted); margin-top: 8px; line-height: 1.6; }
.chip { display: inline-block; padding: 2px 10px; border-radius: 99px;
  font-size: 12px; background: var(--panel2); border: 1px solid var(--line);
  margin: 2px 4px 2px 0; }
.chip b { color: var(--gold); font-weight: 700; }
.chartbox { position: relative; height: 320px; margin-top: 10px; }
details.raw { margin-top: 12px; }
details.raw summary { cursor: pointer; color: var(--muted); font-size: 13px; }
td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }
.wld b { color: #7ce09a; } .wld i { color: #e07c7c; font-style: normal; }
.wld s { color: var(--muted); text-decoration: none; }
.rank { color: var(--muted); font-size: 12px; width: 34px; }
</style>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.js"></script>
</head>
<body>
<header>
  <h1>Checkers &mdash; Ads Admin</h1>
  <nav id="nav"></nav>
</header>
<main>
  <section id="tab-dash"></section>
  <section id="tab-ops" hidden></section>
  <section id="tab-pstats" hidden></section>
  <section id="tab-camps" hidden></section>
  <section id="tab-custs" hidden></section>
  <section id="tab-msgs" hidden></section>
  <section id="tab-players" hidden></section>
  <section id="tab-settings" hidden></section>
</main>
<script>
const apiBase = location.origin + '/admin/api';
const api = (p, init) => fetch(apiBase + p, init).then(async r => {
  if (!r.ok) throw new Error(await r.text());
  return r.json();
});
const esc = s => (s ?? '').toString().replace(/[&<>"]/g,
  c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

let customers = [], campaigns = [], stats = [];
let messages = [], blocks = [], settings = {};
let feedback = { items: [], open_count: 0 }, feedbackScope = 'open';
let ops = null, opsDays = 7;
let pstats = null, pstatsDays = 7;

// --- Routing: one URL per page, so a refresh stays put. ----------------
const ROUTES = [
  ['dash', '/admin', 'Dashboard'],
  ['ops', '/admin/operations', 'Operations'],
  ['pstats', '/admin/player-stats', 'Player stats'],
  ['camps', '/admin/campaigns', 'Campaigns'],
  ['custs', '/admin/customers', 'Customers'],
  ['msgs', '/admin/messages', 'Messages'],
  ['players', '/admin/players', 'Players'],
  ['settings', '/admin/settings', 'Settings'],
];
let currentTab = 'dash';

function tabForPath(path) {
  let clean = path;
  while (clean.length > 1 && clean.endsWith('/')) clean = clean.slice(0, -1);
  const hit = ROUTES.find(r => r[1] === clean);
  return hit ? hit[0] : 'dash';
}

function renderNav() {
  document.getElementById('nav').innerHTML = ROUTES.map(r =>
    '<a href="' + r[1] + '" data-tab="' + r[0] + '">' + r[2] + '</a>').join('');
  document.querySelectorAll('#nav a').forEach(a => a.onclick = e => {
    // Let modified clicks open a real new tab.
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    const path = a.getAttribute('href');
    if (location.pathname !== path) history.pushState({}, '', path);
    showTab(tabForPath(path));
  });
}

function showTab(tab) {
  currentTab = tab;
  for (const r of ROUTES) {
    document.getElementById('tab-' + r[0]).hidden = r[0] !== tab;
  }
  document.querySelectorAll('#nav a').forEach(a =>
    a.classList.toggle('on', a.dataset.tab === tab));
  const hit = ROUTES.find(r => r[0] === tab);
  document.title = 'Checkers Admin — ' + (hit ? hit[2] : 'Dashboard');
  if (tab === 'ops') loadOps();
  if (tab === 'pstats') loadPstats();
}

window.addEventListener('popstate', () => showTab(tabForPath(location.pathname)));

async function refresh() {
  [customers, campaigns, stats, messages, blocks, settings, feedback] =
    await Promise.all([
      api('/customers'), api('/campaigns'), api('/stats?days=30'),
      api('/messages'), api('/blocks'), api('/settings'),
      api('/feedback?scope=' + feedbackScope)]);
  renderDash(); renderCamps(); renderCusts();
  renderMsgs(); renderPlayers(); renderSettings();
  updateInboxBadge();
}

function totals(id) {
  let prints = 0, clicks = 0;
  for (const s of stats) if (s.campaign_id === id) { prints += s.prints; clicks += s.clicks; }
  return { prints, clicks };
}

function renderDash() {
  const el = document.getElementById('tab-dash');
  const maxPrints = Math.max(1, ...campaigns.map(c => totals(c.id).prints));
  let rows = campaigns.map(c => {
    const t = totals(c.id);
    const ctr = t.prints ? (100 * t.clicks / t.prints).toFixed(1) + '%' : '—';
    return '<tr><td>' + esc(c.name) + '<div class="muted" style="font-size:12px">'
      + esc(c.ad_customers?.name ?? '') + '</div></td>'
      + '<td><span class="pill ' + (c.active ? 'on">active' : 'off">off') + '</span></td>'
      + '<td>' + t.prints + '<div class="bar" style="width:' + (100 * t.prints / maxPrints) + '%"></div></td>'
      + '<td>' + t.clicks + '</td><td>' + ctr + '</td></tr>';
  }).join('');
  const byDay = {};
  for (const s of stats) {
    byDay[s.day] = byDay[s.day] || { prints: 0, clicks: 0 };
    byDay[s.day].prints += s.prints; byDay[s.day].clicks += s.clicks;
  }
  const days = Object.keys(byDay).sort().reverse().slice(0, 14);
  const dayRows = days.map(d => '<tr><td>' + d + '</td><td>' + byDay[d].prints
    + '</td><td>' + byDay[d].clicks + '</td></tr>').join('');
  el.innerHTML =
    '<div class="card"><h2>Campaign totals (last 30 days)</h2><table><tr>'
    + '<th>Campaign</th><th>Status</th><th>Prints</th><th>Clicks</th><th>CTR</th></tr>'
    + (rows || '<tr><td colspan="5" class="muted">No campaigns yet.</td></tr>')
    + '</table></div>'
    + '<div class="card"><h2>Daily totals</h2><table><tr><th>Day</th><th>Prints</th><th>Clicks</th></tr>'
    + (dayRows || '<tr><td colspan="3" class="muted">No activity yet.</td></tr>')
    + '</table></div>';
}

const IMG_FIELDS = [
  ['banner_url', 'Banner image *'],
  ['piece_white_man_url', 'White piece'],
  ['piece_white_king_url', 'White king'],
  ['piece_black_man_url', 'Black piece'],
  ['piece_black_king_url', 'Black king'],
];

let editingId = null;

function renderCamps() {
  const el = document.getElementById('tab-camps');
  const editing = campaigns.find(x => x.id === editingId) ?? null;
  const custOpts = customers.map(c =>
    '<option value="' + c.id + '"'
    + (editing && editing.customer_id === c.id ? ' selected' : '')
    + '>' + esc(c.name) + '</option>').join('');
  const rows = campaigns.map(c => {
    const t = totals(c.id);
    return '<tr><td><img class="thumb" src="' + esc(c.banner_url) + '"></td>'
      + '<td>' + esc(c.name) + '<div class="muted" style="font-size:12px">'
      + esc(c.ad_customers?.name ?? '') + ' · ' + c.starts_at + ' → '
      + (c.ends_at ?? 'open') + (c.max_daily_prints ? ' · cap ' + c.max_daily_prints + '/day' : '')
      + '</div></td>'
      + '<td><span class="pill ' + (c.active ? 'on">active' : 'off">off') + '</span></td>'
      + '<td>' + t.prints + ' / ' + t.clicks + '</td>'
      + '<td style="white-space:nowrap"><button class="small" onclick="startEdit(\\'' + c.id + '\\')">Edit</button> '
      + '<button class="small" onclick="toggleCamp(\\'' + c.id + '\\',' + !c.active + ')">'
      + (c.active ? 'Deactivate' : 'Activate') + '</button></td></tr>';
  }).join('');
  el.innerHTML =
    '<div class="card"><h2>Campaigns</h2><table><tr><th></th><th>Campaign</th>'
    + '<th>Status</th><th>Prints / Clicks</th><th></th></tr>'
    + (rows || '<tr><td colspan="5" class="muted">No campaigns yet.</td></tr>')
    + '</table></div>'
    + '<div class="card"><h2>'
    + (editing ? 'Edit campaign — ' + esc(editing.name) : 'New campaign') + '</h2>'
    + '<div class="row"><div><label>Name</label><input id="c-name"></div>'
    + '<div><label>Customer</label><select id="c-cust">' + custOpts + '</select></div></div>'
    + '<div class="row"><div><label>Starts</label><input type="date" id="c-start"></div>'
    + '<div><label>Ends (empty = open)</label><input type="date" id="c-end"></div></div>'
    + '<div class="row"><div><label>Target URL</label><input id="c-url" placeholder="https://…"></div>'
    + '<div><label>Max daily prints (empty = unlimited)</label><input type="number" id="c-cap"></div></div>'
    + IMG_FIELDS.map(([k, label]) => {
        const current = editing && editing[k]
          ? '<div style="display:flex;align-items:center;gap:10px;margin:4px 0 6px">'
            + '<img class="thumb" src="' + esc(editing[k]) + '">'
            + (k === 'banner_url'
                ? '<span class="muted" style="font-size:12px">current — choose a file to replace</span>'
                : '<label style="margin:0;display:inline;font-size:12px">'
                  + '<input type="checkbox" data-clear="' + k + '"> remove</label>')
            + '</div>'
          : '';
        return '<label>' + label + '</label>' + current
          + '<input type="file" accept="image/*" data-field="' + k + '">';
      }).join('')
    + '<label><input type="checkbox" id="c-active"'
    + (!editing || editing.active ? ' checked' : '') + '> Active</label>'
    + '<button class="primary" onclick="saveCamp()">'
    + (editing ? 'Save changes' : 'Create campaign') + '</button>'
    + (editing
        ? ' <button class="small" style="margin-left:10px" onclick="cancelEdit()">Cancel</button>'
        : '')
    + '<div class="msg" id="c-msg"></div></div>';
  document.getElementById('c-name').value = editing?.name ?? '';
  document.getElementById('c-url').value = editing?.target_url ?? '';
  document.getElementById('c-start').value =
    editing?.starts_at ?? new Date().toISOString().slice(0, 10);
  document.getElementById('c-end').value = editing?.ends_at ?? '';
  document.getElementById('c-cap').value = editing?.max_daily_prints ?? '';
}

function startEdit(id) {
  editingId = id;
  renderCamps();
  const name = document.getElementById('c-name');
  name.scrollIntoView({ behavior: 'smooth', block: 'center' });
  name.focus();
}

function cancelEdit() {
  editingId = null;
  renderCamps();
}

async function uploadFile(file) {
  const r = await fetch(apiBase + '/upload?name=' + encodeURIComponent(file.name), {
    method: 'POST', headers: { 'Content-Type': file.type }, body: file });
  if (!r.ok) throw new Error(await r.text());
  return (await r.json()).url;
}

async function saveCamp() {
  const msg = document.getElementById('c-msg');
  msg.className = 'msg'; msg.textContent = 'Saving…';
  try {
    const editing = campaigns.find(x => x.id === editingId) ?? null;
    const body = {
      name: document.getElementById('c-name').value.trim(),
      customer_id: document.getElementById('c-cust').value || null,
      starts_at: document.getElementById('c-start').value,
      ends_at: document.getElementById('c-end').value || null,
      target_url: document.getElementById('c-url').value.trim(),
      max_daily_prints: parseInt(document.getElementById('c-cap').value) || null,
      active: document.getElementById('c-active').checked,
    };
    if (!body.name || !body.target_url) throw new Error('Name and target URL are required.');
    for (const [field] of IMG_FIELDS) {
      const input = document.querySelector('input[data-field="' + field + '"]');
      const clear = document.querySelector('input[data-clear="' + field + '"]');
      if (input.files[0]) body[field] = await uploadFile(input.files[0]);
      else if (clear?.checked) body[field] = null;
    }
    if (!editing && !body.banner_url) throw new Error('Banner image is required.');
    if (editing) {
      await api('/campaigns/' + editing.id, { method: 'PATCH',
        body: JSON.stringify(body),
        headers: { 'Content-Type': 'application/json' } });
    } else {
      await api('/campaigns', { method: 'POST', body: JSON.stringify(body),
        headers: { 'Content-Type': 'application/json' } });
    }
    editingId = null;
    await refresh();
    document.getElementById('c-msg').textContent =
      editing ? 'Campaign updated.' : 'Campaign created.';
  } catch (e) {
    msg.className = 'msg err'; msg.textContent = e.message;
  }
}

async function toggleCamp(id, active) {
  await api('/campaigns/' + id, { method: 'PATCH',
    body: JSON.stringify({ active }),
    headers: { 'Content-Type': 'application/json' } });
  await refresh();
}

function renderCusts() {
  const el = document.getElementById('tab-custs');
  const rows = customers.map(c =>
    '<tr><td>' + esc(c.name) + '</td><td>' + esc(c.contact ?? '') + '</td>'
    + '<td class="muted">' + esc(c.notes ?? '') + '</td></tr>').join('');
  el.innerHTML =
    '<div class="card"><h2>Customers</h2><table><tr><th>Name</th><th>Contact</th><th>Notes</th></tr>'
    + (rows || '<tr><td colspan="3" class="muted">No customers yet.</td></tr>')
    + '</table></div>'
    + '<div class="card"><h2>New customer</h2>'
    + '<label>Name</label><input id="k-name">'
    + '<label>Contact</label><input id="k-contact">'
    + '<label>Notes</label><textarea id="k-notes" rows="2"></textarea>'
    + '<button class="primary" onclick="createCust()">Add customer</button>'
    + '<div class="msg" id="k-msg"></div></div>';
}

async function createCust() {
  const msg = document.getElementById('k-msg');
  msg.className = 'msg';
  try {
    const name = document.getElementById('k-name').value.trim();
    if (!name) throw new Error('Name is required.');
    await api('/customers', { method: 'POST',
      body: JSON.stringify({
        name,
        contact: document.getElementById('k-contact').value.trim() || null,
        notes: document.getElementById('k-notes').value.trim() || null,
      }),
      headers: { 'Content-Type': 'application/json' } });
    msg.textContent = 'Customer added.';
    await refresh();
  } catch (e) { msg.className = 'msg err'; msg.textContent = e.message; }
}

async function loadOps() {
  try {
    ops = await api('/ops?days=' + opsDays);
    renderOps();
  } catch (e) { /* keep previous view on transient errors */ }
}

const STATE_LABELS = {
  pc: 'vs PC', human: 'vs human', watching: 'watching', idle: 'idle',
};

// [value, label]. "Today" is just a 1-day window: the RPCs bound on
// created_at::date >= current_date, i.e. midnight until now.
const DAY_OPTIONS = [7, 14, 30, 60, 90].map(d => [d, 'Last ' + d + ' days']);
const PSTATS_DAY_OPTIONS = [[1, 'Today']].concat(DAY_OPTIONS);

function daysSelect(id, value, options) {
  return '<select id="' + id + '" style="width:auto;margin-left:12px">'
    + options.map(o => '<option value="' + o[0] + '"'
        + (o[0] === value ? ' selected' : '') + '>' + o[1] + '</option>')
      .join('')
    + '</select>';
}

// --- Daily-activity line chart (Chart.js) ------------------------------
const OPS_SERIES = [
  ['human_games', 'Human games', '#e5b94e'],
  ['pc_games', 'PC games', '#6ea8fe'],
  ['active_players', 'Players who played', '#ef8fb5'],
  ['tournaments', 'Tournaments', '#a78bfa'],
  ['new_players', 'New players', '#7ce09a'],
];
const CHART_GRID = 'rgba(147,168,154,0.16)';
const CHART_OPTS = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: { mode: 'index', intersect: false },
  plugins: {
    legend: {
      labels: { color: '#e8efe9', usePointStyle: true, boxWidth: 8,
        padding: 16 },
    },
    tooltip: {
      backgroundColor: '#0d1d14', borderColor: '#2c4a38', borderWidth: 1,
      titleColor: '#e5b94e', bodyColor: '#e8efe9', padding: 10,
      usePointStyle: true,
    },
  },
  scales: {
    x: { ticks: { color: '#93a89a', maxRotation: 0, autoSkipPadding: 16 },
      grid: { color: CHART_GRID } },
    y: { beginAtZero: true, ticks: { color: '#93a89a', precision: 0 },
      grid: { color: CHART_GRID } },
  },
};

let opsChart = null, opsBuilt = false;

function renderOps() {
  const el = document.getElementById('tab-ops');
  if (!ops) {
    el.innerHTML = '<div class="card muted">Loading…</div>';
    opsBuilt = false; opsChart = null;
    return;
  }
  // The skeleton is built once so the period <select> keeps its state and
  // the chart survives the 30-second live refresh.
  if (!opsBuilt) {
    el.innerHTML =
      '<div id="ops-live"></div>'
      + '<div class="card"><h2 style="display:inline-block">Daily activity</h2> '
      + daysSelect('ops-days', opsDays, DAY_OPTIONS)
      + '<div class="chartbox"><canvas id="ops-chart"></canvas></div>'
      + '<details class="raw" id="ops-raw"><summary>Show the numbers</summary>'
      + '<table style="margin-top:10px" id="ops-table"></table></details>'
      + '<div class="muted" style="font-size:12px;margin-top:8px">'
      + 'Live numbers refresh every 30 seconds.</div></div>';
    opsBuilt = true; opsChart = null;
    document.getElementById('ops-days').onchange = e => {
      opsDays = parseInt(e.target.value);
      loadOps();
    };
  }
  renderOpsLive();
  renderOpsChart();
}

function renderOpsLive() {
  const n = ops.now, t = ops.totals;
  const played = t.players_played, never = t.players - t.players_played;
  const chips = (n.connected_players ?? []).map(p =>
    '<span class="chip">' + esc(p.nickname) + ' · <b>'
    + STATE_LABELS[p.state] + '</b></span>').join('')
    || '<span class="muted">Nobody connected right now.</span>';
  document.getElementById('ops-live').innerHTML =
    '<div class="cards">'
    + '<div class="stat"><div class="n">' + n.connected + '</div>'
    + '<div class="l">Players connected now</div><div class="sub">'
    + 'Playing vs human: <b>' + n.playing_human + '</b><br>'
    + 'Playing vs PC: <b>' + n.playing_pc + '</b><br>'
    + 'Watching: <b>' + n.watching + '</b> · Idle: <b>' + n.idle + '</b></div></div>'
    + '<div class="stat"><div class="n">'
    + (n.games_playing_human + n.games_playing_pc) + '</div>'
    + '<div class="l">Games in progress</div><div class="sub">'
    + 'Human: <b>' + n.games_playing_human + '</b> · PC: <b>'
    + n.games_playing_pc + '</b></div></div>'
    + '<div class="stat"><div class="n">' + n.tournaments_running + '</div>'
    + '<div class="l">Tournaments running</div><div class="sub">'
    + 'Lobby: <b>' + n.lobby_players + '</b> waiting</div></div>'
    + '<div class="stat"><div class="n">' + t.players + '</div>'
    + '<div class="l">Total players</div><div class="sub">'
    + 'Played a game: <b>' + played + '</b> ('
    + (t.players ? Math.round(100 * played / t.players) : 0) + '%)<br>'
    + 'Never played: <b>' + never + '</b><br>'
    + 'Games all-time: <b>' + t.games_total + '</b> · Tournaments: <b>'
    + t.tournaments_total + '</b></div></div>'
    + '</div>'
    + '<div class="card"><h2>Connected players</h2>' + chips + '</div>';
}

function renderOpsChart() {
  const desc = ops.daily ?? [];
  document.getElementById('ops-table').innerHTML =
    '<tr><th>Day</th>'
    + OPS_SERIES.map(s => '<th class="num">' + s[1] + '</th>').join('')
    + '</tr>'
    + (desc.map(d => '<tr><td>' + d.day + '</td>'
        + OPS_SERIES.map(s => '<td class="num">' + (d[s[0]] ?? 0) + '</td>')
          .join('')
        + '</tr>').join('')
      || '<tr><td colspan="' + (OPS_SERIES.length + 1)
         + '" class="muted">No data.</td></tr>');

  const canvas = document.getElementById('ops-chart');
  if (typeof Chart === 'undefined' || !canvas) {
    // Chart library unreachable: fall back to the raw table, opened.
    document.getElementById('ops-raw').open = true;
    return;
  }
  const asc = desc.slice().reverse();
  const labels = asc.map(d => d.day.slice(5));
  if (opsChart && opsChart.data.datasets.length !== OPS_SERIES.length) {
    opsChart.destroy();   // series list changed under a long-lived page
    opsChart = null;
  }
  if (opsChart) {
    opsChart.data.labels = labels;
    OPS_SERIES.forEach(([key], i) => {
      opsChart.data.datasets[i].data = asc.map(d => d[key] ?? 0);
    });
    opsChart.update();
    return;
  }
  opsChart = new Chart(canvas, {
    type: 'line',
    data: {
      labels,
      datasets: OPS_SERIES.map(([key, label, color]) => ({
        label, data: asc.map(d => d[key] ?? 0),
        borderColor: color, backgroundColor: color, pointBackgroundColor: color,
        borderWidth: 2, tension: 0.3, pointRadius: 2, pointHoverRadius: 5,
        fill: false,
      })),
    },
    options: CHART_OPTS,
  });
}

setInterval(() => { if (currentTab === 'ops') loadOps(); }, 30000);

// --- Player stats ------------------------------------------------------
let pstatsBuilt = false;

async function loadPstats() {
  try {
    pstats = await api('/player-stats?days=' + pstatsDays);
    renderPstats();
  } catch (e) {
    document.getElementById('tab-pstats').innerHTML =
      '<div class="card msg err">Failed to load player stats: '
      + esc(e.message) + '</div>';
    pstatsBuilt = false;
  }
}

const wld = (w, l, d) =>
  '<b>' + w + '</b> / <i>' + l + '</i> / <s>' + d + '</s>';

function renderPstats() {
  const el = document.getElementById('tab-pstats');
  if (!pstatsBuilt) {
    el.innerHTML =
      '<div class="card"><h2 style="display:inline-block">Player stats</h2> '
      + daysSelect('ps-days', pstatsDays, PSTATS_DAY_OPTIONS)
      + '<div class="muted" id="ps-summary" style="font-size:13px;margin-top:8px">'
      + '</div>'
      + '<table style="margin-top:10px" id="ps-table"></table></div>';
    pstatsBuilt = true;
    document.getElementById('ps-days').onchange = e => {
      pstatsDays = parseInt(e.target.value);
      loadPstats();
    };
  }
  const list = pstats?.players ?? [];
  const active = pstats?.active_players ?? list.length;
  document.getElementById('ps-summary').innerHTML =
    '<b>' + active + '</b> player' + (active === 1 ? '' : 's')
    + ' played at least one game '
    + (pstatsDays === 1
        ? 'today (since midnight)'
        : 'since ' + esc(pstats?.from_day ?? ''))
    + (list.length < active
        ? ' · showing the top ' + list.length + ' by games played'
        : '')
    + ' · W / L / D = won / lost / drawn';
  document.getElementById('ps-table').innerHTML =
    '<tr><th class="rank"></th><th>Player</th><th class="num">Total</th>'
    + '<th class="num">Human</th><th class="num">W / L / D</th>'
    + '<th class="num">PC</th><th class="num">W / L / D</th></tr>'
    + (list.map((p, i) =>
        '<tr><td class="rank">' + (i + 1) + '</td>'
        + '<td>' + esc(p.nickname || '(no nickname)')
        + '<div class="muted" style="font-size:12px">' + esc(p.uid.slice(0, 8))
        + '… · rating ' + p.rating + '</div></td>'
        + '<td class="num"><b style="color:var(--gold)">' + p.total + '</b></td>'
        + '<td class="num">' + p.human_games + '</td>'
        + '<td class="num wld">' + wld(p.human_won, p.human_lost, p.human_draw)
        + '</td>'
        + '<td class="num">' + p.pc_games + '</td>'
        + '<td class="num wld">' + wld(p.pc_won, p.pc_lost, p.pc_draw)
        + '</td></tr>').join('')
      || '<tr><td colspan="7" class="muted">No games in this period.</td></tr>');
}

let msgTarget = null;
let blockTarget = null;

function pickerHtml(kind) {
  const sel = kind === 'msg' ? msgTarget : blockTarget;
  return '<label>Player</label>'
    + '<input id="' + kind + '-search" placeholder="Search nickname…" autocomplete="off">'
    + '<div id="' + kind + '-results"></div>'
    + '<div class="msg" id="' + kind + '-picked">'
    + (sel ? 'Selected: ' + esc(sel.nickname) + ' (' + sel.id.slice(0, 8) + '…)' : '')
    + '</div>';
}

function wirePicker(kind) {
  const input = document.getElementById(kind + '-search');
  let timer = null;
  input.oninput = () => {
    clearTimeout(timer);
    timer = setTimeout(async () => {
      const q = input.value.trim();
      const box = document.getElementById(kind + '-results');
      if (!q) { box.innerHTML = ''; return; }
      const players = await api('/players?search=' + encodeURIComponent(q));
      box.innerHTML = players.map(p =>
        '<button class="small" style="margin:3px 4px 3px 0" data-id="' + p.id
        + '" data-nick="' + esc(p.nickname) + '">' + esc(p.nickname)
        + ' · ' + p.rating + '</button>').join('') ||
        '<span class="muted">No players found.</span>';
      box.querySelectorAll('button').forEach(b => b.onclick = () => {
        const target = { id: b.dataset.id, nickname: b.dataset.nick };
        if (kind === 'msg') { msgTarget = target; renderMsgs(); }
        else { blockTarget = target; renderPlayers(); }
      });
    }, 350);
  };
}

function inboxHtml() {
  const items = feedback.items ?? [];
  const rows = items.map(f =>
    '<tr><td style="white-space:nowrap">'
    + esc(f.nickname || '(unknown)')
    + '<div class="muted" style="font-size:12px">'
    + (f.created_at ?? '').slice(0, 16).replace('T', ' ') + '</div></td>'
    + '<td>' + esc(f.text) + '</td>'
    + '<td><span class="pill ' + (f.handled_at ? 'on">handled' : 'off">open')
    + '</span></td>'
    + '<td style="white-space:nowrap">'
    + '<button class="small" data-reply="' + f.uid + '" data-nick="'
    + esc(f.nickname || '') + '">Reply</button> '
    + '<button class="small" data-fb="' + f.id + '" data-handled="'
    + (f.handled_at ? 'false' : 'true') + '">'
    + (f.handled_at ? 'Reopen' : 'Mark handled') + '</button></td></tr>').join('');
  return '<div class="card"><h2 style="display:inline-block">Inbox</h2> '
    + '<select id="fb-scope" style="width:auto;margin-left:12px">'
    + '<option value="open"' + (feedbackScope === 'open' ? ' selected' : '')
    + '>Open only</option>'
    + '<option value="all"' + (feedbackScope === 'all' ? ' selected' : '')
    + '>All (last 100)</option></select>'
    + '<div class="muted" style="font-size:13px;margin-top:6px">'
    + 'What players sent through "Write to the admins". '
    + '<b>' + (feedback.open_count ?? 0) + '</b> open.</div>'
    + '<table style="margin-top:10px">'
    + '<tr><th>From</th><th>Message</th><th>Status</th><th></th></tr>'
    + (rows || '<tr><td colspan="4" class="muted">Nothing here.</td></tr>')
    + '</table></div>';
}

function wireInbox(el) {
  document.getElementById('fb-scope').onchange = async e => {
    feedbackScope = e.target.value;
    feedback = await api('/feedback?scope=' + feedbackScope);
    renderMsgs();
  };
  el.querySelectorAll('button[data-fb]').forEach(b => b.onclick = async () => {
    await api('/feedback/' + b.dataset.fb, { method: 'PATCH',
      body: JSON.stringify({ handled: b.dataset.handled === 'true' }),
      headers: { 'Content-Type': 'application/json' } });
    feedback = await api('/feedback?scope=' + feedbackScope);
    renderMsgs();
    updateInboxBadge();
  });
  // Reply = compose a private message to that player, prefilled below.
  el.querySelectorAll('button[data-reply]').forEach(b => b.onclick = () => {
    msgTarget = { id: b.dataset.reply, nickname: b.dataset.nick };
    renderMsgs();
    const aud = document.getElementById('m-aud');
    aud.value = 'private';
    document.getElementById('m-picker').hidden = false;
    document.getElementById('m-text').scrollIntoView(
      { behavior: 'smooth', block: 'center' });
    document.getElementById('m-text').focus();
  });
}

function updateInboxBadge() {
  const link = document.querySelector('#nav a[data-tab="msgs"]');
  if (!link) return;
  const open = feedback.open_count ?? 0;
  link.textContent = open > 0 ? 'Messages (' + open + ')' : 'Messages';
}

function renderMsgs() {
  const el = document.getElementById('tab-msgs');
  const rows = messages.map(m =>
    '<tr><td>' + m.type + '<div class="muted" style="font-size:12px">'
    + m.language + ' · until ' + (m.expires_at ?? '').slice(0, 10) + '</div></td>'
    + '<td style="max-width:380px">' + esc((m.html_text ?? '').slice(0, 120))
    + (m.image_url ? ' <span class="muted">[image]</span>' : '')
    + (m.link_url ? ' <span class="muted">[link]</span>' : '') + '</td>'
    + '<td><span class="pill ' + (m.enabled ? 'on">on' : 'off">off') + '</span></td>'
    + '<td><button class="small" data-id="' + m.id + '" data-en="' + !m.enabled + '">'
    + (m.enabled ? 'Disable' : 'Enable') + '</button></td></tr>').join('');
  el.innerHTML =
    inboxHtml()
    + '<div class="card"><h2>Messages to players</h2><table>'
    + '<tr><th>Type</th><th>Content</th><th>Status</th><th></th></tr>'
    + (rows || '<tr><td colspan="4" class="muted">No messages yet.</td></tr>')
    + '</table></div>'
    + '<div class="card"><h2>New message</h2>'
    + '<div class="row"><div><label>Language</label><select id="m-lang">'
    + '<option value="en">English</option><option value="fr">French</option></select></div>'
    + '<div><label>Audience</label><select id="m-aud">'
    + '<option value="public">All players</option>'
    + '<option value="private"' + (msgTarget ? ' selected' : '') + '>One player</option>'
    + '</select></div></div>'
    + '<div id="m-picker"' + (msgTarget ? '' : ' hidden') + '>' + pickerHtml('msg') + '</div>'
    + '<label>Text (HTML allowed)</label><textarea id="m-text" rows="3"></textarea>'
    + '<div class="row"><div><label>Link URL (optional)</label><input id="m-link"></div>'
    + '<div><label>Visible for (days)</label><input type="number" id="m-days" value="30"></div></div>'
    + '<label>Image (optional)</label><input type="file" accept="image/*" id="m-image">'
    + '<button class="primary" id="m-send">Send message</button>'
    + '<div class="msg" id="m-msg"></div></div>';
  wireInbox(el);
  el.querySelectorAll('table button[data-id]').forEach(b => b.onclick = async () => {
    await api('/messages/' + b.dataset.id, { method: 'PATCH',
      body: JSON.stringify({ enabled: b.dataset.en === 'true' }),
      headers: { 'Content-Type': 'application/json' } });
    await refresh();
  });
  document.getElementById('m-aud').onchange = e => {
    if (e.target.value === 'public') { msgTarget = null; }
    document.getElementById('m-picker').hidden = e.target.value !== 'private';
  };
  wirePicker('msg');
  document.getElementById('m-send').onclick = sendMsg;
}

async function sendMsg() {
  const msg = document.getElementById('m-msg');
  msg.className = 'msg'; msg.textContent = 'Sending…';
  try {
    const isPrivate = document.getElementById('m-aud').value === 'private';
    if (isPrivate && !msgTarget) throw new Error('Pick a player first.');
    const text = document.getElementById('m-text').value.trim();
    const file = document.getElementById('m-image').files[0];
    if (!text && !file) throw new Error('Text or an image is required.');
    const body = {
      language: document.getElementById('m-lang').value,
      target_uid: isPrivate ? msgTarget.id : null,
      html_text: text || null,
      link_url: document.getElementById('m-link').value.trim() || null,
      days: parseInt(document.getElementById('m-days').value) || 30,
    };
    if (file) body.image_url = await uploadFile(file);
    await api('/messages', { method: 'POST', body: JSON.stringify(body),
      headers: { 'Content-Type': 'application/json' } });
    msgTarget = null;
    await refresh();
    document.getElementById('m-msg').textContent = 'Message sent.';
  } catch (e) { msg.className = 'msg err'; msg.textContent = e.message; }
}

function renderPlayers() {
  const el = document.getElementById('tab-players');
  const rows = blocks.map(b =>
    '<tr><td>' + esc(b.nickname || '(unknown)')
    + '<div class="muted" style="font-size:12px">' + b.uid.slice(0, 8) + '…</div></td>'
    + '<td><span class="pill ' + (b.level === 'full' ? 'off">full' : 'on">soft') + '</span></td>'
    + '<td>' + esc(b.reason ?? '') + '</td>'
    + '<td>' + (b.expires_at ? b.expires_at.slice(0, 10) : 'permanent') + '</td>'
    + '<td><button class="small" data-uid="' + b.uid + '">Unblock</button></td></tr>').join('');
  el.innerHTML =
    '<div class="card"><h2>Active blocks</h2><table>'
    + '<tr><th>Player</th><th>Level</th><th>Reason</th><th>Expires</th><th></th></tr>'
    + (rows || '<tr><td colspan="5" class="muted">No active blocks.</td></tr>')
    + '</table></div>'
    + '<div class="card"><h2>Block a player</h2>'
    + pickerHtml('block')
    + '<div class="row"><div><label>Level</label><select id="b-level">'
    + '<option value="soft">Soft — can watch, cannot play</option>'
    + '<option value="full">Full — locked out</option></select></div>'
    + '<div><label>Duration (days, empty = permanent)</label>'
    + '<input type="number" id="b-days"></div></div>'
    + '<label>Reason (optional)</label><input id="b-reason">'
    + '<button class="primary" id="b-block">Block player</button>'
    + '<div class="msg" id="b-msg"></div></div>';
  el.querySelectorAll('table button[data-uid]').forEach(b => b.onclick = async () => {
    await api('/unblock', { method: 'POST',
      body: JSON.stringify({ uid: b.dataset.uid }),
      headers: { 'Content-Type': 'application/json' } });
    await refresh();
  });
  wirePicker('block');
  document.getElementById('b-block').onclick = blockPlayer;
}

async function blockPlayer() {
  const msg = document.getElementById('b-msg');
  msg.className = 'msg'; msg.textContent = 'Blocking…';
  try {
    if (!blockTarget) throw new Error('Pick a player first.');
    const days = parseInt(document.getElementById('b-days').value);
    await api('/blocks', { method: 'POST',
      body: JSON.stringify({
        uid: blockTarget.id,
        level: document.getElementById('b-level').value,
        days: Number.isFinite(days) && days > 0 ? days : null,
        reason: document.getElementById('b-reason').value.trim() || null,
      }),
      headers: { 'Content-Type': 'application/json' } });
    blockTarget = null;
    await refresh();
    document.getElementById('b-msg').textContent = 'Player blocked.';
  } catch (e) { msg.className = 'msg err'; msg.textContent = e.message; }
}

const val = id => document.getElementById(id).value.trim();
const intVal = id => parseInt(document.getElementById(id).value);
const numVal = id => parseFloat(document.getElementById(id).value);
const versionList = id => val(id).split(',')
  .map(v => v.trim()).filter(v => v.length > 0);

// Each card saves only its own keys, so one bad field can't take the
// others with it.
async function saveSettings(cardId, build) {
  const msg = document.getElementById(cardId);
  msg.className = 'msg'; msg.textContent = 'Saving…';
  try {
    await api('/settings', { method: 'PATCH',
      body: JSON.stringify(build()),
      headers: { 'Content-Type': 'application/json' } });
    settings = await api('/settings');
    msg.className = 'msg'; msg.textContent = 'Saved.';
  } catch (e) {
    msg.className = 'msg err';
    let text = e.message;
    try { text = JSON.parse(e.message).error ?? text; } catch (_) {}
    msg.textContent = text;
  }
}

function renderSettings() {
  const el = document.getElementById('tab-settings');
  const units = settings.adUnits ?? { android: {}, ios: {} };
  el.innerHTML =
    // --- App releases -------------------------------------------------
    '<div class="card"><h2>App releases</h2>'
    + '<div class="muted" style="font-size:13px;margin-bottom:6px">'
    + 'Players running a version that is not listed are forced to update, '
    + 'and sent to the store URL. Leave a list empty to turn the gate off '
    + 'for that platform — never remove the version you have shipped.'
    + '</div>'
    + '<div class="row">'
    + '<div><label>Allowed Android versions (comma separated)</label>'
    + '<input id="s-andv" value="'
    + esc((settings.allowedAndroidVersions ?? []).join(', ')) + '"></div>'
    + '<div><label>Allowed iOS versions (comma separated)</label>'
    + '<input id="s-iosv" value="'
    + esc((settings.allowedIosVersions ?? []).join(', ')) + '"></div></div>'
    + '<div class="row">'
    + '<div><label>Android store URL</label><input id="s-andurl" value="'
    + esc(settings.androidAppUrl ?? '') + '"></div>'
    + '<div><label>iOS store URL</label><input id="s-iosurl" value="'
    + esc(settings.iosAppUrl ?? '') + '"></div></div>'
    + '<button class="primary" id="s-save-rel">Save releases</button>'
    + '<div class="msg" id="s-msg-rel"></div></div>'
    // --- Gameplay -----------------------------------------------------
    + '<div class="card"><h2>Gameplay</h2>'
    + '<div class="row4">'
    + '<div><label>Turn time (seconds)</label>'
    + '<input type="number" id="s-turn" min="3" max="600" value="'
    + Math.round((settings.turnMs ?? 15000) / 1000) + '"></div>'
    + '<div><label>Time bank (minutes)</label>'
    + '<input type="number" id="s-bank" min="1" max="120" step="0.5" value="'
    + ((settings.bankMs ?? 300000) / 60000) + '"></div>'
    + '<div><label>Leaderboard min. games</label>'
    + '<input type="number" id="s-lbmin" min="0" max="1000" value="'
    + (settings.leaderboardMinGames ?? 1) + '"></div>'
    + '<div></div></div>'
    + '<div class="muted" style="font-size:12px;margin-top:4px">'
    + 'Clock settings apply to new online games only.</div>'
    + '<button class="primary" id="s-save-play">Save gameplay</button>'
    + '<div class="msg" id="s-msg-play"></div></div>'
    // --- Advertising --------------------------------------------------
    + '<div class="card"><h2>Advertising</h2>'
    + '<div class="row"><div>'
    + '<label>Interstitial frequency (show every Nth event)</label>'
    + '<input type="number" id="s-freq" min="1" value="'
    + (settings.interstitialFrequency ?? 15) + '"></div>'
    + '<div><label>&nbsp;</label>'
    + '<label style="margin-top:14px"><input type="checkbox" id="s-enabled"'
    + (settings.adsEnabled ? ' checked' : '')
    + '> AdMob ads enabled</label></div></div>'
    + '<div class="row">'
    + '<div><label>Android banner unit ID</label><input id="s-and-ban" value="'
    + esc(units.android?.banner ?? '') + '"></div>'
    + '<div><label>Android interstitial unit ID</label>'
    + '<input id="s-and-int" value="'
    + esc(units.android?.interstitial ?? '') + '"></div></div>'
    + '<div class="row">'
    + '<div><label>iOS banner unit ID</label><input id="s-ios-ban" value="'
    + esc(units.ios?.banner ?? '') + '"></div>'
    + '<div><label>iOS interstitial unit ID</label>'
    + '<input id="s-ios-int" value="'
    + esc(units.ios?.interstitial ?? '') + '"></div></div>'
    + '<button class="primary" id="s-save-ads">Save advertising</button>'
    + '<div class="msg" id="s-msg-ads"></div></div>';

  document.getElementById('s-save-rel').onclick = () =>
    saveSettings('s-msg-rel', () => ({
      allowedAndroidVersions: versionList('s-andv'),
      allowedIosVersions: versionList('s-iosv'),
      androidAppUrl: val('s-andurl'),
      iosAppUrl: val('s-iosurl'),
    }));
  document.getElementById('s-save-play').onclick = () =>
    saveSettings('s-msg-play', () => ({
      turnMs: Math.round(numVal('s-turn') * 1000),
      bankMs: Math.round(numVal('s-bank') * 60000),
      leaderboardMinGames: intVal('s-lbmin'),
    }));
  document.getElementById('s-save-ads').onclick = () =>
    saveSettings('s-msg-ads', () => ({
      interstitialFrequency: intVal('s-freq'),
      adsEnabled: document.getElementById('s-enabled').checked,
      adUnits: {
        android: { banner: val('s-and-ban'), interstitial: val('s-and-int') },
        ios: { banner: val('s-ios-ban'), interstitial: val('s-ios-int') },
      },
    }));
}

renderNav();
showTab(tabForPath(location.pathname));

refresh().catch(e => document.querySelector('main').innerHTML =
  '<div class="card msg err">Failed to load: ' + esc(e.message) + '</div>');
</script>
</body>
</html>`;

// Every console page has its own URL so a refresh (or a bookmark) lands
// back on the same tab. The shell is identical for all of them; the client
// picks the tab from location.pathname.
const PAGE_ROUTES = new Set([
  "/admin",
  "/admin/",
  "/admin/operations",
  "/admin/player-stats",
  "/admin/campaigns",
  "/admin/customers",
  "/admin/messages",
  "/admin/players",
  "/admin/settings",
]);

export default {
  async fetch(request, env) {
    if (!checkAuth(request, env)) {
      return unauthorized();
    }
    const url = new URL(request.url);
    if (url.pathname.startsWith("/admin/api")) {
      return handleApi(request, env, url.pathname.slice("/admin/api".length));
    }
    if (!PAGE_ROUTES.has(url.pathname)) {
      return Response.redirect(new URL("/admin", url).toString(), 302);
    }
    return new Response(PAGE, {
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
      },
    });
  },
};
