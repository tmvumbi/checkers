// The dame.cd gift store: points auctions served by link_worker.js under
// /gifts, /gifts/winners, /gifts/mine and /gifts/<id>. Every route returns
// the same shell; giftStoreClient() runs in the browser, signs players in
// with Firebase Auth (same Google/Apple accounts as the app) and talks to
// the Convex backend (backend/convex/gifts.ts) over a live connection.

export const PROD_CONVEX_URL = "https://harmless-loris-857.convex.cloud";

// Firebase web app "dame.cd website" in project checkers-club (public
// client config, not a secret).
const FIREBASE_CONFIG = {
  apiKey: "AIzaSyAxvUYXcSM_Dn5gqkTCtQBNu2TBkdj6j5g",
  projectId: "checkers-club",
  appId: "1:558217605941:web:6c37e214aed7e5685dd27c",
  messagingSenderId: "558217605941",
};

const FIREBASE_SDK = "https://www.gstatic.com/firebasejs/10.14.1";
const CONVEX_BUNDLE = "https://cdn.jsdelivr.net/npm/convex@1.46.0/dist/browser.bundle.js";

const TITLES = {
  en: "Gift store — Checkers",
  fr: "Boutique cadeaux — Checkers",
};

export const GIFT_STORE_CSS = `
.gs-top{display:flex;flex-wrap:wrap;align-items:center;gap:10px;margin:6px 0 22px}
.gs-tabs{display:flex;gap:4px;flex-wrap:wrap}
.gs-tabs a{color:var(--muted);text-decoration:none;font-weight:700;font-size:15px;
  padding:8px 14px;border-radius:10px}
.gs-tabs a.on{color:var(--gold);background:var(--card)}
.gs-account{margin-left:auto;display:flex;align-items:center;gap:10px;flex-wrap:wrap;
  font-size:14px}
.gs-points{background:rgba(255,200,1,.14);color:var(--gold);font-weight:800;
  padding:5px 12px;border-radius:99px;white-space:nowrap}
.gs-btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;
  padding:10px 16px;border-radius:10px;font-weight:700;font-size:15px;cursor:pointer;
  border:1px solid rgba(255,255,255,.85);color:#fff;background:#263F6D;
  text-decoration:none;font-family:inherit}
.gs-btn.apple{background:#111}
.gs-btn.gold{background:var(--gold);color:#1b1300;border-color:var(--gold)}
.gs-btn.ghost{background:none;border-color:var(--line);color:var(--muted);
  padding:6px 12px;font-size:13px}
.gs-btn:disabled{opacity:.55;cursor:default}
.gs-intro{color:var(--muted);margin:-8px 0 20px;font-size:15px}
.gs-grid{display:grid;gap:16px;grid-template-columns:repeat(auto-fill,minmax(230px,1fr))}
.gs-card{background:var(--card);border:1px solid var(--line);border-radius:14px;
  overflow:hidden;text-decoration:none;color:var(--soft);display:flex;flex-direction:column}
.gs-card:hover{border-color:rgba(255,200,1,.55)}
.gs-cover{aspect-ratio:4/3;background:rgba(255,255,255,.06);display:block;width:100%;
  object-fit:cover}
.gs-card .body{padding:12px 14px 14px;display:flex;flex-direction:column;gap:4px}
.gs-card h3{font-size:16px;color:var(--soft)}
.gs-meta{font-size:13px;color:var(--muted)}
.gs-bid{font-weight:800;color:var(--gold)}
.gs-empty{color:var(--muted);text-align:center;padding:40px 0}
.gs-detail{display:grid;gap:24px;grid-template-columns:minmax(0,1.1fr) minmax(0,1fr)}
@media (max-width:720px){.gs-detail{grid-template-columns:1fr}}
.gs-main{width:100%;aspect-ratio:4/3;object-fit:contain;border-radius:14px;cursor:zoom-in;
  background:rgba(255,255,255,.05);display:block}
.gs-thumbs{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}
.gs-thumbs img{width:64px;height:64px;object-fit:cover;border-radius:8px;cursor:pointer;
  border:2px solid transparent;opacity:.75}
.gs-thumbs img.on{border-color:var(--gold);opacity:1}
.gs-panel{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:18px}
.gs-panel h1{font-size:26px;margin-bottom:4px}
.gs-big{font-size:30px;font-weight:800;color:var(--gold);line-height:1.2}
.gs-row{display:flex;justify-content:space-between;gap:10px;padding:8px 0;
  border-bottom:1px solid var(--line);font-size:15px}
.gs-row:last-child{border-bottom:none}
.gs-row span:first-child{color:var(--muted)}
.gs-form{display:flex;gap:10px;margin-top:14px;flex-wrap:wrap}
.gs-form input{flex:1;min-width:120px;padding:11px 12px;border-radius:10px;font-size:17px;
  border:1px solid var(--line);background:rgba(0,0,0,.25);color:var(--soft);font-family:inherit}
.gs-note{font-size:14px;color:var(--muted);margin-top:10px}
.gs-msg{margin-top:10px;font-size:14px;min-height:20px}
.gs-msg.err{color:#ff8f8f}.gs-msg.ok{color:#7ce09a}
.gs-pill{display:inline-block;padding:2px 10px;border-radius:99px;font-size:12px;font-weight:800}
.gs-pill.leading,.gs-pill.won{background:#1d4d2c;color:#7ce09a}
.gs-pill.outbid,.gs-pill.lost,.gs-pill.cancelled{background:#4d1d1d;color:#ff9b9b}
.gs-desc{white-space:pre-line;margin-top:18px;color:var(--soft)}
.gs-video{margin-top:18px;aspect-ratio:16/9;width:100%;border:0;border-radius:14px}
.gs-list{display:flex;flex-direction:column;gap:10px}
.gs-item{display:flex;gap:12px;align-items:center;background:var(--card);
  border:1px solid var(--line);border-radius:12px;padding:10px;text-decoration:none;color:var(--soft)}
.gs-item img,.gs-item .ph{width:64px;height:64px;border-radius:8px;object-fit:cover;flex:none;
  background:rgba(255,255,255,.06)}
.gs-item .grow{flex:1;min-width:0}
.gs-item b{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.gs-h2{font-size:19px;margin:26px 0 12px}
.gs-box{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:18px;
  text-align:center;color:var(--muted)}
.gs-box p{margin-bottom:12px}
.gs-signin{display:flex;gap:10px;justify-content:center;flex-wrap:wrap}
.gs-lightbox{position:fixed;inset:0;background:rgba(0,0,0,.92);display:flex;
  align-items:center;justify-content:center;z-index:50;cursor:zoom-out}
.gs-lightbox img{max-width:96vw;max-height:92vh;object-fit:contain}
.gs-more{display:block;margin:18px auto 0}
@media (max-width:600px){.gs-account{margin-left:0;width:100%}
  .gs-account .gs-signin{justify-content:flex-start}
  .gs-account .gs-btn{padding:7px 11px;font-size:13px}}
`;

/** The page body for every /gifts route. */
export function giftStoreBody(lang, convexUrl) {
  const config = {
    lang,
    convexUrl,
    firebase: FIREBASE_CONFIG,
    firebaseSdk: FIREBASE_SDK,
  };
  // Inline JSON must not be able to close the script element.
  const json = JSON.stringify(config).replace(/</g, "\\u003c");
  return {
    title: TITLES[lang],
    body: `<main id="gs-root"><div class="gs-empty">…</div></main>
<script src="${CONVEX_BUNDLE}"></script>
<script type="module">
// wrangler's esbuild (keepNames) wraps nested functions in __name().
const __name = (fn) => fn;
(${giftStoreClient.toString()})(${json});
</script>`,
  };
}

// ---------------------------------------------------------------------
// Browser code. Serialized with toString(): it must not reference
// anything outside its own body — all inputs arrive in `cfg`.
// ---------------------------------------------------------------------

async function giftStoreClient(cfg) {
  const T = {
    en: {
      tabGifts: "Gifts",
      tabWinners: "Winners",
      tabMine: "My gifts",
      intro:
        "Win real gifts with the points you earn in the app: beat the computer, " +
        "win tournaments, then bid here. The highest bid when the countdown ends wins.",
      signInGoogle: "Sign in with Google",
      signInApple: "Sign in with Apple",
      signOut: "Sign out",
      points: "@n pts",
      noGifts: "No gifts right now — come back soon!",
      noWinners: "No winners yet.",
      highestBid: "Highest bid",
      leader: "Leader",
      startingAt: "Starting bid",
      bids: "Bids",
      bidders: "Bidders",
      endsIn: "Ends in",
      ended: "Ended",
      ending: "Ending…",
      offeredBy: "Offered by @name",
      placeBid: "Place bid",
      raiseBid: "Raise my bid",
      yourBalance: "Your balance: @n points",
      minBid: "Minimum bid: @n points",
      youLead: "You have the highest bid.",
      youOutbid: "You have been outbid — your points are back.",
      bidPlaced: "Bid placed — you are in the lead!",
      wonBy: "Won by @name for @n points",
      cancelled: "This auction was cancelled; bids were refunded.",
      signInToBid: "Sign in with the account you use in the app to bid.",
      noProfile:
        "This account has no player yet. Open the Checkers app, sign in with the same " +
        "Google or Apple account, then come back.",
      guest:
        "Guest players cannot bid. In the app, link your profile to Google or Apple, " +
        "then sign in here with that account.",
      mineSignIn: "Sign in to see your bids and the gifts you won.",
      current: "Current bids",
      won: "Gifts you won",
      noCurrent: "You have no running bids.",
      noWon: "You have not won a gift yet.",
      status: { leading: "Leading", outbid: "Outbid", won: "Won", lost: "Lost", cancelled: "Cancelled" },
      loadMore: "Load more",
      notFound: "This gift is not available.",
      back: "← All gifts",
      wonHelp: "We will contact you to arrange delivery. Questions? Write to us through the app.",
      errors: {
        gift_closed: "This auction has ended.",
        bid_too_low: "Your bid is too low — someone may have just bid more.",
        not_enough_points: "You do not have enough points for this bid.",
        invalid_amount: "Enter a whole number of points.",
        anonymous_not_allowed: "Guest players cannot bid.",
        blocked: "Your account is restricted and cannot bid right now.",
        profile_required: "Open the app first to create your player.",
        not_authenticated: "Please sign in again.",
        gift_not_found: "This gift is not available.",
        signin: "Sign-in failed. Please try again.",
        network: "Network problem — please try again.",
      },
    },
    fr: {
      tabGifts: "Cadeaux",
      tabWinners: "Gagnants",
      tabMine: "Mes cadeaux",
      intro:
        "Gagnez de vrais cadeaux avec les points gagnés dans l’application : battez " +
        "l’ordinateur, remportez des tournois, puis misez ici. La plus haute mise à la " +
        "fin du compte à rebours l’emporte.",
      signInGoogle: "Se connecter avec Google",
      signInApple: "Se connecter avec Apple",
      signOut: "Se déconnecter",
      points: "@n pts",
      noGifts: "Aucun cadeau pour le moment — revenez bientôt !",
      noWinners: "Pas encore de gagnant.",
      highestBid: "Plus haute mise",
      leader: "En tête",
      startingAt: "Mise de départ",
      bids: "Mises",
      bidders: "Participants",
      endsIn: "Fin dans",
      ended: "Terminé",
      ending: "Clôture…",
      offeredBy: "Offert par @name",
      placeBid: "Miser",
      raiseBid: "Augmenter ma mise",
      yourBalance: "Votre solde : @n points",
      minBid: "Mise minimale : @n points",
      youLead: "Vous avez la plus haute mise.",
      youOutbid: "Votre mise a été dépassée — vos points vous sont rendus.",
      bidPlaced: "Mise placée — vous êtes en tête !",
      wonBy: "Remporté par @name pour @n points",
      cancelled: "Cette enchère a été annulée ; les mises ont été remboursées.",
      signInToBid: "Connectez-vous avec le compte utilisé dans l’application pour miser.",
      noProfile:
        "Ce compte n’a pas encore de joueur. Ouvrez l’application Checkers, connectez-vous " +
        "avec le même compte Google ou Apple, puis revenez.",
      guest:
        "Les invités ne peuvent pas miser. Dans l’application, liez votre profil à Google " +
        "ou Apple, puis connectez-vous ici avec ce compte.",
      mineSignIn: "Connectez-vous pour voir vos mises et les cadeaux gagnés.",
      current: "Mises en cours",
      won: "Cadeaux gagnés",
      noCurrent: "Vous n’avez aucune mise en cours.",
      noWon: "Vous n’avez pas encore gagné de cadeau.",
      status: { leading: "En tête", outbid: "Dépassé", won: "Gagné", lost: "Perdu", cancelled: "Annulé" },
      loadMore: "Voir plus",
      notFound: "Ce cadeau n’est pas disponible.",
      back: "← Tous les cadeaux",
      wonHelp:
        "Nous vous contacterons pour organiser la livraison. Une question ? Écrivez-nous " +
        "depuis l’application.",
      errors: {
        gift_closed: "Cette enchère est terminée.",
        bid_too_low: "Votre mise est trop basse — quelqu’un vient peut-être de miser plus.",
        not_enough_points: "Vous n’avez pas assez de points pour cette mise.",
        invalid_amount: "Saisissez un nombre entier de points.",
        anonymous_not_allowed: "Les invités ne peuvent pas miser.",
        blocked: "Votre compte est restreint et ne peut pas miser pour le moment.",
        profile_required: "Ouvrez d’abord l’application pour créer votre joueur.",
        not_authenticated: "Veuillez vous reconnecter.",
        gift_not_found: "Ce cadeau n’est pas disponible.",
        signin: "La connexion a échoué. Veuillez réessayer.",
        network: "Problème de réseau — veuillez réessayer.",
      },
    },
  }[cfg.lang];

  const root = document.getElementById("gs-root");
  const esc = (s) =>
    String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  const fmt = (n) => Number(n).toLocaleString(cfg.lang === "fr" ? "fr-FR" : "en-US");
  const fill = (text, vars) => text.replace(/@(\w+)/g, (_, k) => vars[k] ?? "");
  const q = "?lang=" + cfg.lang;
  const href = (path) => path + q;
  const errorText = (e) => {
    const code = typeof e?.data === "string" ? e.data : null;
    return (code && T.errors[code]) || T.errors.network;
  };

  // --- Backend and auth --------------------------------------------------
  const client = new window.convex.ConvexClient(cfg.convexUrl);
  let authMod = null; // Firebase Auth module, loaded after the first render
  let auth = null;
  let authReady = false;
  let user = null;
  let me = undefined; // undefined = loading, null = no profile
  let meUnsub = null;
  let view = { unsubs: [], render: () => {} };

  async function startAuth() {
    const [{ initializeApp }, mod] = await Promise.all([
      import(cfg.firebaseSdk + "/firebase-app.js"),
      import(cfg.firebaseSdk + "/firebase-auth.js"),
    ]);
    authMod = mod;
    // On dame.cd the worker proxies /__/auth to Firebase, keeping sign-in
    // first-party (Safari blocks the cross-site iframe otherwise).
    const onSite = location.hostname === "dame.cd";
    const app = initializeApp({
      ...cfg.firebase,
      authDomain: onSite ? "dame.cd" : cfg.firebase.projectId + ".firebaseapp.com",
    });
    auth = authMod.getAuth(app);
    auth.languageCode = cfg.lang;
    authMod.getRedirectResult(auth).catch(() => {});
    authMod.onAuthStateChanged(auth, (u) => {
      const changed = (u?.uid ?? null) !== (user?.uid ?? null);
      authReady = true;
      user = u;
      if (meUnsub) meUnsub();
      meUnsub = null;
      if (u) {
        me = undefined;
        client.setAuth(async ({ forceRefreshToken }) => {
          try {
            return await u.getIdToken(forceRefreshToken);
          } catch {
            return null;
          }
        });
        meUnsub = client.onUpdate("gifts:me", {}, (row) => {
          me = row;
          renderAccount();
          (view.onMe ?? view.render)();
        });
      } else {
        me = null;
        client.client.clearAuth();
      }
      renderAccount();
      // Signing in or out changes per-player data: resubscribe the page.
      if (changed) route();
      else (view.onMe ?? view.render)();
    });
  }

  async function signIn(kind) {
    if (!authMod) return;
    const provider =
      kind === "apple" ? new authMod.OAuthProvider("apple.com") : new authMod.GoogleAuthProvider();
    if (kind === "apple") {
      provider.addScope("email");
      provider.addScope("name");
    } else {
      provider.setCustomParameters({ prompt: "select_account" });
    }
    try {
      await authMod.signInWithPopup(auth, provider);
    } catch (e) {
      if (e?.code === "auth/popup-blocked" || e?.code === "auth/operation-not-supported-in-this-environment") {
        await authMod.signInWithRedirect(auth, provider);
      } else if (e?.code !== "auth/popup-closed-by-user" && e?.code !== "auth/cancelled-popup-request") {
        alert(T.errors.signin);
      }
    }
  }

  const signInButtons = () =>
    `<div class="gs-signin">
      <button class="gs-btn" data-signin="google">${esc(T.signInGoogle)}</button>
      <button class="gs-btn apple" data-signin="apple">${esc(T.signInApple)}</button>
    </div>`;

  // --- Layout --------------------------------------------------------------
  root.innerHTML = `
    <div class="gs-top">
      <nav class="gs-tabs">
        <a data-link href="${href("/gifts")}" data-tab="list">${esc(T.tabGifts)}</a>
        <a data-link href="${href("/gifts/winners")}" data-tab="winners">${esc(T.tabWinners)}</a>
        <a data-link href="${href("/gifts/mine")}" data-tab="mine">${esc(T.tabMine)}</a>
      </nav>
      <div class="gs-account" id="gs-account"></div>
    </div>
    <div id="gs-view"></div>`;
  const viewEl = document.getElementById("gs-view");
  const accountEl = document.getElementById("gs-account");

  function renderAccount() {
    if (!authReady) {
      accountEl.innerHTML = "";
      return;
    }
    if (!user) {
      accountEl.innerHTML = signInButtons();
      return;
    }
    const name = me?.nickname || user.displayName || user.email || "";
    accountEl.innerHTML =
      `<span>${esc(name)}</span>` +
      (me ? `<span class="gs-points">${esc(fill(T.points, { n: fmt(me.points) }))}</span>` : "") +
      `<button class="gs-btn ghost" data-signout>${esc(T.signOut)}</button>`;
  }

  document.addEventListener("click", (e) => {
    const signin = e.target.closest("[data-signin]");
    if (signin) return void signIn(signin.dataset.signin);
    if (e.target.closest("[data-signout]")) return void authMod?.signOut(auth);
    const link = e.target.closest("a[data-link]");
    if (link && !e.metaKey && !e.ctrlKey && !e.shiftKey && e.button === 0) {
      e.preventDefault();
      history.pushState({}, "", link.getAttribute("href"));
      route();
    }
  });
  window.addEventListener("popstate", route);

  // --- Countdowns ------------------------------------------------------------
  function remaining(iso) {
    const ms = Date.parse(iso) - Date.now();
    if (ms <= 0) return null;
    const s = Math.floor(ms / 1000);
    const d = Math.floor(s / 86400);
    const h = Math.floor((s % 86400) / 3600);
    const m = Math.floor((s % 3600) / 60);
    const pad = (n) => String(n).padStart(2, "0");
    if (d > 0) return `${d}${cfg.lang === "fr" ? "j" : "d"} ${h}h`;
    if (h > 0) return `${h}h ${pad(m)}m`;
    return `${m}m ${pad(s % 60)}s`;
  }
  const countdown = (iso) => `<span data-ends="${esc(iso)}">${esc(remaining(iso) ?? T.ending)}</span>`;
  setInterval(() => {
    for (const el of document.querySelectorAll("[data-ends]")) {
      el.textContent = remaining(el.dataset.ends) ?? T.ending;
    }
  }, 1000);

  // --- Router ------------------------------------------------------------------
  function route() {
    for (const u of view.unsubs) u();
    const path = location.pathname.replace(/\/+$/, "");
    const parts = path.split("/").filter(Boolean); // ["gifts", ...]
    const tab = parts[1] === "winners" ? "winners" : parts[1] === "mine" ? "mine" : parts[1] ? "detail" : "list";
    for (const a of document.querySelectorAll(".gs-tabs a")) a.classList.toggle("on", a.dataset.tab === tab);
    if (tab === "list") view = listView();
    else if (tab === "winners") view = winnersView();
    else if (tab === "mine") view = mineView();
    else view = detailView(decodeURIComponent(parts[1]));
    view.render();
  }

  const cover = (url) =>
    url ? `<img class="gs-cover" src="${esc(url)}" alt="" loading="lazy">` : `<span class="gs-cover"></span>`;

  // --- Gift list -------------------------------------------------------------------
  function listView() {
    let gifts;
    const v = {
      unsubs: [client.onUpdate("gifts:listOpen", {}, (rows) => ((gifts = rows), v.render()))],
      render() {
        if (gifts === undefined) return void (viewEl.innerHTML = `<div class="gs-empty">…</div>`);
        const cards = gifts
          .map(
            (g) => `<a class="gs-card" data-link href="${href("/gifts/" + g.id)}">
              ${cover(g.images[0]?.url)}
              <div class="body">
                <h3>${esc(g.name)}</h3>
                ${g.offered_by ? `<div class="gs-meta">${esc(fill(T.offeredBy, { name: g.offered_by }))}</div>` : ""}
                <div><span class="gs-meta">${esc(g.highest_bid != null ? T.highestBid : T.startingAt)}:</span>
                  <span class="gs-bid">${fmt(g.highest_bid ?? g.minimum_bid)} pts</span></div>
                <div class="gs-meta">${esc(T.endsIn)} ${countdown(g.ends_at)}</div>
              </div></a>`,
          )
          .join("");
        viewEl.innerHTML =
          `<p class="gs-intro">${esc(T.intro)}</p>` +
          (cards ? `<div class="gs-grid">${cards}</div>` : `<div class="gs-empty">${esc(T.noGifts)}</div>`);
      },
    };
    return v;
  }

  // --- Gift detail ---------------------------------------------------------------
  function detailView(id) {
    let gift;
    let imageIndex = 0;
    let message = null; // { ok, text }
    let pending = false;
    const v = {
      unsubs: [
        client.onUpdate("gifts:get", { id }, (row) => {
          const first = gift === undefined;
          gift = row;
          if (first) v.render();
          else v.renderStatus();
        }),
      ],
      render() {
        if (gift === undefined) return void (viewEl.innerHTML = `<div class="gs-empty">…</div>`);
        if (gift === null) {
          viewEl.innerHTML = `<div class="gs-empty">${esc(T.notFound)}<br><br>
            <a data-link href="${href("/gifts")}">${esc(T.back)}</a></div>`;
          return;
        }
        const images = gift.images;
        const thumbs =
          images.length > 1
            ? `<div class="gs-thumbs">${images
                .map((im, i) => `<img src="${esc(im.url)}" data-thumb="${i}" class="${i === imageIndex ? "on" : ""}" alt="">`)
                .join("")}</div>`
            : "";
        viewEl.innerHTML = `
          <p><a data-link href="${href("/gifts")}">${esc(T.back)}</a></p><br>
          <div class="gs-detail">
            <div>
              ${images.length ? `<img class="gs-main" id="gs-main" src="${esc(images[imageIndex].url)}" alt="">` : ""}
              ${thumbs}
            </div>
            <div>
              <div class="gs-panel">
                <h1>${esc(gift.name)}</h1>
                ${gift.offered_by ? `<div class="gs-meta">${esc(fill(T.offeredBy, { name: gift.offered_by }))}</div>` : ""}
                <div id="gs-status"></div>
              </div>
              <div class="gs-desc">${esc(gift.description)}</div>
              ${gift.youtube_video_id
                ? `<iframe class="gs-video" src="https://www.youtube-nocookie.com/embed/${esc(gift.youtube_video_id)}"
                    allow="encrypted-media; picture-in-picture" allowfullscreen loading="lazy"></iframe>`
                : ""}
            </div>
          </div>`;
        for (const t of viewEl.querySelectorAll("[data-thumb]")) {
          t.onclick = () => {
            imageIndex = Number(t.dataset.thumb);
            document.getElementById("gs-main").src = images[imageIndex].url;
            for (const o of viewEl.querySelectorAll("[data-thumb]")) o.classList.toggle("on", o === t);
          };
        }
        const main = document.getElementById("gs-main");
        if (main) {
          main.onclick = () => {
            const box = document.createElement("div");
            box.className = "gs-lightbox";
            box.innerHTML = `<img src="${esc(images[imageIndex].url)}" alt="">`;
            box.onclick = () => box.remove();
            document.body.appendChild(box);
          };
        }
        v.renderStatus();
      },
      renderStatus() {
        const el = document.getElementById("gs-status");
        if (!el || !gift) return;
        const typed = document.getElementById("gs-amount")?.value;
        const rows = [];
        if (gift.status === "closed") {
          rows.push(`<p class="gs-big" style="font-size:20px;margin-top:12px">
            ${esc(fill(T.wonBy, { name: gift.winner_nickname ?? "", n: fmt(gift.winner_amount ?? 0) }))}</p>`);
          if (gift.my_bid?.status === "won") rows.push(`<p class="gs-note">${esc(T.wonHelp)}</p>`);
        } else if (gift.status === "cancelled") {
          rows.push(`<p class="gs-note">${esc(T.cancelled)}</p>`);
        } else {
          const has = gift.highest_bid != null;
          rows.push(`<div style="margin-top:14px">
            <div class="gs-meta">${esc(has ? T.highestBid : T.startingAt)}</div>
            <div class="gs-big">${fmt(has ? gift.highest_bid : gift.minimum_bid)} pts</div></div>`);
          rows.push(`<div style="margin-top:10px">
            ${has ? `<div class="gs-row"><span>${esc(T.leader)}</span><span>${esc(gift.highest_bidder_nickname)}</span></div>` : ""}
            <div class="gs-row"><span>${esc(T.bids)}</span><span>${fmt(gift.bid_count)}</span></div>
            <div class="gs-row"><span>${esc(T.bidders)}</span><span>${fmt(gift.participant_count)}</span></div>
            <div class="gs-row"><span>${esc(T.endsIn)}</span><b>${countdown(gift.ends_at)}</b></div></div>`);
          rows.push(bidArea());
        }
        el.innerHTML = rows.join("");
        const input = document.getElementById("gs-amount");
        if (input) {
          const n = Number(typed);
          input.value = typed && n >= gift.required_bid ? typed : String(gift.required_bid);
          document.getElementById("gs-bid-form").onsubmit = (e) => {
            e.preventDefault();
            placeBid(Number(input.value));
          };
        }
      },
    };

    v.onMe = () => v.renderStatus();

    function bidArea() {
      const note = message ? `<div class="gs-msg ${message.ok ? "ok" : "err"}">${esc(message.text)}</div>` : "";
      if (!authReady) return `<div class="gs-empty">…</div>`;
      if (!user) return `<div class="gs-box" style="margin-top:16px"><p>${esc(T.signInToBid)}</p>${signInButtons()}</div>`;
      if (me === undefined) return `<div class="gs-empty">…</div>`;
      if (me === null) return `<div class="gs-box" style="margin-top:16px">${esc(T.noProfile)}</div>`;
      if (me.is_anonymous) return `<div class="gs-box" style="margin-top:16px">${esc(T.guest)}</div>`;
      const mine = gift.my_bid;
      const state = gift.leader_is_me
        ? `<p class="gs-msg ok">${esc(T.youLead)}</p>`
        : mine?.status === "outbid"
          ? `<p class="gs-msg err">${esc(T.youOutbid)}</p>`
          : "";
      return `${state}
        <form class="gs-form" id="gs-bid-form">
          <input id="gs-amount" type="number" inputmode="numeric" min="${gift.required_bid}" step="1" required>
          <button class="gs-btn gold" ${pending ? "disabled" : ""}>${esc(gift.leader_is_me ? T.raiseBid : T.placeBid)}</button>
        </form>
        <div class="gs-note">${esc(fill(T.minBid, { n: fmt(gift.required_bid) }))} ·
          ${esc(fill(T.yourBalance, { n: fmt(me.points) }))}</div>
        ${note}`;
    }

    async function placeBid(amount) {
      if (pending) return;
      pending = true;
      message = null;
      v.renderStatus();
      try {
        await client.mutation("gifts:placeBid", {
          giftId: id,
          amount,
          clientBidId: crypto.randomUUID(),
          language: cfg.lang,
        });
        message = { ok: true, text: T.bidPlaced };
      } catch (e) {
        message = { ok: false, text: errorText(e) };
      }
      pending = false;
      v.renderStatus();
    }
    return v;
  }

  // --- Winners ------------------------------------------------------------------------
  function winnersView() {
    const rows = [];
    let cursor = null;
    let done = false;
    let loading = false;
    const v = {
      unsubs: [],
      render() {
        const items = rows
          .map(
            (g) => `<a class="gs-item" data-link href="${href("/gifts/" + g.id)}">
              ${g.images[0] ? `<img src="${esc(g.images[0].url)}" alt="" loading="lazy">` : `<span class="ph"></span>`}
              <div class="grow"><b>${esc(g.name)}</b>
                <div class="gs-meta">${esc(fill(T.wonBy, { name: g.winner_nickname ?? "", n: fmt(g.winner_amount ?? 0) }))}</div>
                <div class="gs-meta">${esc(new Date(g.closed_at).toLocaleDateString(cfg.lang))}</div></div></a>`,
          )
          .join("");
        viewEl.innerHTML =
          (items
            ? `<div class="gs-list">${items}</div>`
            : `<div class="gs-empty">${esc(loading || !done ? "…" : T.noWinners)}</div>`) +
          (!done && rows.length ? `<button class="gs-btn ghost gs-more" id="gs-more">${esc(T.loadMore)}</button>` : "");
        const more = document.getElementById("gs-more");
        if (more) more.onclick = load;
      },
    };
    async function load() {
      if (loading || done) return;
      loading = true;
      try {
        const page = await client.query("gifts:winners", { paginationOpts: { numItems: 10, cursor } });
        rows.push(...page.page);
        cursor = page.continueCursor;
        done = page.isDone;
      } catch {
        done = true;
      }
      loading = false;
      if (view === v) v.render();
    }
    load();
    return v;
  }

  // --- My gifts ---------------------------------------------------------------------
  function mineView() {
    let bids;
    let wins;
    const v = { unsubs: [], render: () => {} };
    if (user) {
      v.unsubs.push(client.onUpdate("gifts:myBids", {}, (rows) => ((bids = rows), v.render())));
      v.unsubs.push(
        client.onUpdate("gifts:myWins", { paginationOpts: { numItems: 50, cursor: null } }, (page) => {
          wins = page.page;
          v.render();
        }),
      );
    }
    const item = (b) => `<a class="gs-item" data-link href="${href("/gifts/" + b.gift_id)}">
        ${b.gift_image_url ? `<img src="${esc(b.gift_image_url)}" alt="" loading="lazy">` : `<span class="ph"></span>`}
        <div class="grow"><b>${esc(b.gift_name)}</b>
          <div class="gs-meta">${fmt(b.amount)} pts${b.status === "won" ? "" : ` · ${esc(T.endsIn)} ${countdown(b.gift_ends_at)}`}</div></div>
        <span class="gs-pill ${esc(b.status)}">${esc(T.status[b.status] ?? b.status)}</span></a>`;
    v.render = () => {
      if (!authReady) return void (viewEl.innerHTML = `<div class="gs-empty">…</div>`);
      if (!user) {
        viewEl.innerHTML = `<div class="gs-box"><p>${esc(T.mineSignIn)}</p>${signInButtons()}</div>`;
        return;
      }
      if (me === null) {
        viewEl.innerHTML = `<div class="gs-box">${esc(T.noProfile)}</div>`;
        return;
      }
      if (bids === undefined || wins === undefined) return void (viewEl.innerHTML = `<div class="gs-empty">…</div>`);
      viewEl.innerHTML =
        `<h2 class="gs-h2">${esc(T.current)}</h2>` +
        (bids.length ? `<div class="gs-list">${bids.map(item).join("")}</div>` : `<p class="gs-meta">${esc(T.noCurrent)}</p>`) +
        `<h2 class="gs-h2">${esc(T.won)}</h2>` +
        (wins.length
          ? `<div class="gs-list">${wins.map(item).join("")}</div><p class="gs-note">${esc(T.wonHelp)}</p>`
          : `<p class="gs-meta">${esc(T.noWon)}</p>`);
    };
    return v;
  }

  renderAccount();
  route();
  startAuth().catch(() => {
    authReady = true;
    renderAccount();
    view.render();
  });
}
