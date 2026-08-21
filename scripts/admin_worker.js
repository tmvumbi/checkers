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
nav button { background: none; border: none; color: var(--muted);
  font-size: 15px; font-weight: 600; padding: 8px 14px; cursor: pointer;
  border-radius: 8px; }
nav button.on { color: var(--gold); background: var(--panel2); }
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
</style>
</head>
<body>
<header>
  <h1>Checkers &mdash; Ads Admin</h1>
  <nav>
    <button data-tab="dash" class="on">Dashboard</button>
    <button data-tab="camps">Campaigns</button>
    <button data-tab="custs">Customers</button>
  </nav>
</header>
<main>
  <section id="tab-dash"></section>
  <section id="tab-camps" hidden></section>
  <section id="tab-custs" hidden></section>
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

async function refresh() {
  [customers, campaigns, stats] = await Promise.all([
    api('/customers'), api('/campaigns'), api('/stats?days=30')]);
  renderDash(); renderCamps(); renderCusts();
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

function renderCamps() {
  const el = document.getElementById('tab-camps');
  const custOpts = customers.map(c =>
    '<option value="' + c.id + '">' + esc(c.name) + '</option>').join('');
  const rows = campaigns.map(c => {
    const t = totals(c.id);
    return '<tr><td><img class="thumb" src="' + esc(c.banner_url) + '"></td>'
      + '<td>' + esc(c.name) + '<div class="muted" style="font-size:12px">'
      + esc(c.ad_customers?.name ?? '') + ' · ' + c.starts_at + ' → '
      + (c.ends_at ?? 'open') + (c.max_daily_prints ? ' · cap ' + c.max_daily_prints + '/day' : '')
      + '</div></td>'
      + '<td><span class="pill ' + (c.active ? 'on">active' : 'off">off') + '</span></td>'
      + '<td>' + t.prints + ' / ' + t.clicks + '</td>'
      + '<td><button class="small" onclick="toggleCamp(\\'' + c.id + '\\',' + !c.active + ')">'
      + (c.active ? 'Deactivate' : 'Activate') + '</button></td></tr>';
  }).join('');
  el.innerHTML =
    '<div class="card"><h2>Campaigns</h2><table><tr><th></th><th>Campaign</th>'
    + '<th>Status</th><th>Prints / Clicks</th><th></th></tr>'
    + (rows || '<tr><td colspan="5" class="muted">No campaigns yet.</td></tr>')
    + '</table></div>'
    + '<div class="card"><h2>New campaign</h2>'
    + '<div class="row"><div><label>Name</label><input id="c-name"></div>'
    + '<div><label>Customer</label><select id="c-cust">' + custOpts + '</select></div></div>'
    + '<div class="row"><div><label>Starts</label><input type="date" id="c-start"></div>'
    + '<div><label>Ends (empty = open)</label><input type="date" id="c-end"></div></div>'
    + '<div class="row"><div><label>Target URL</label><input id="c-url" placeholder="https://…"></div>'
    + '<div><label>Max daily prints (empty = unlimited)</label><input type="number" id="c-cap"></div></div>'
    + IMG_FIELDS.map(([k, label]) =>
        '<label>' + label + '</label><input type="file" accept="image/*" data-field="' + k + '">'
      ).join('')
    + '<label><input type="checkbox" id="c-active" checked> Active</label>'
    + '<button class="primary" onclick="createCamp()">Create campaign</button>'
    + '<div class="msg" id="c-msg"></div></div>';
  document.getElementById('c-start').value = new Date().toISOString().slice(0, 10);
}

async function uploadFile(file) {
  const r = await fetch(apiBase + '/upload?name=' + encodeURIComponent(file.name), {
    method: 'POST', headers: { 'Content-Type': file.type }, body: file });
  if (!r.ok) throw new Error(await r.text());
  return (await r.json()).url;
}

async function createCamp() {
  const msg = document.getElementById('c-msg');
  msg.className = 'msg'; msg.textContent = 'Uploading…';
  try {
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
      if (input.files[0]) body[field] = await uploadFile(input.files[0]);
    }
    if (!body.banner_url) throw new Error('Banner image is required.');
    await api('/campaigns', { method: 'POST', body: JSON.stringify(body),
      headers: { 'Content-Type': 'application/json' } });
    msg.textContent = 'Campaign created.';
    await refresh();
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

document.querySelectorAll('nav button').forEach(b => b.onclick = () => {
  document.querySelectorAll('nav button').forEach(x => x.classList.remove('on'));
  b.classList.add('on');
  for (const t of ['dash', 'camps', 'custs'])
    document.getElementById('tab-' + t).hidden = t !== b.dataset.tab;
});

refresh().catch(e => document.querySelector('main').innerHTML =
  '<div class="card msg err">Failed to load: ' + esc(e.message) + '</div>');
</script>
</body>
</html>`;

export default {
  async fetch(request, env) {
    if (!checkAuth(request, env)) {
      return unauthorized();
    }
    const url = new URL(request.url);
    if (url.pathname.startsWith("/admin/api")) {
      return handleApi(request, env, url.pathname.slice("/admin/api".length));
    }
    return new Response(PAGE, {
      headers: { "Content-Type": "text/html; charset=utf-8" },
    });
  },
};
