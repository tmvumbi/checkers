// Cloudflare Worker for dame.cd — the public site
// (landing page, privacy policy, terms of use), the app-link verification
// files, and a deep-link fallback page for invite links.
// Deployed on the route dame.cd/* .

const PLAY_STORE_URL =
  "https://play.google.com/store/apps/details?id=cd.dame";
// Placeholder listing — swap for the real App Store URL at iOS launch.
const APP_STORE_URL =
  "https://apps.apple.com/app/checkers-tournaments/id6806184531";
const CONTACT_EMAIL = "tresormvumbi@gmail.com";
const APP_ADS_TXT =
  "google.com, pub-3437010247383226, DIRECT, f08c47fec0942fa0\n";

const ANDROID_CERTIFICATES = [
  // Local debug certificate (development installs).
  "99:D5:F9:DB:83:5C:52:CE:4C:D3:AD:03:72:9D:B0:10:22:3A:E0:B8:B7:0A:9E:F4:12:7B:2E:50:00:3B:B4:EA",
  // Upload/release certificate used for locally signed release bundles.
  "3E:5A:90:05:CC:D6:22:35:79:18:CF:96:B9:D5:07:F1:5E:87:7A:57:6C:59:6C:E7:0F:24:04:8D:AF:76:92:07",
  // Google Play App Signing certificate used by installs from the store.
  "29:AE:72:9F:8E:5D:66:E1:0C:FC:54:96:58:31:00:07:3D:F8:6A:BC:84:D2:E5:5E:22:ED:54:27:87:37:1B:AB",
];

const ASSETLINKS = [
  {
    relation: ["delegate_permission/common.handle_all_urls"],
    target: {
      namespace: "android_app",
      package_name: "cd.dame",
      sha256_cert_fingerprints: ANDROID_CERTIFICATES,
    },
  },
];

const AASA = {
  applinks: {
    apps: [],
    details: [
      {
        appIDs: ["TKDDB59257.cd.dame"],
        components: [{ "/": "/party/*" }, { "/": "/tournament*" }],
      },
    ],
  },
};

// The 2x2 board mark, drawn inline so pages need no image assets.
const LOGO_SVG = (size) => `
<svg width="${size}" height="${size}" viewBox="0 0 96 96" role="img"
  aria-label="Checkers logo" xmlns="http://www.w3.org/2000/svg">
  <rect x="0" y="0" width="96" height="96" rx="18" fill="#EFE0C4"/>
  <rect x="48" y="0" width="48" height="48" rx="0" fill="#5B4128"/>
  <rect x="0" y="48" width="48" height="48" fill="#5B4128"/>
  <path d="M78 0h18v18a18 18 0 0 0-18-18Z" fill="#5B4128"/>
  <circle cx="72" cy="24" r="15" fill="#FFC801" stroke="#B78200"
    stroke-width="4"/>
  <circle cx="24" cy="72" r="15" fill="#F6F1E7" stroke="#C9BFA8"
    stroke-width="4"/>
</svg>`;

const SITE_CSS = `
:root{--bg1:#12261B;--bg2:#071109;--gold:#FFC801;--soft:#e8efe9;
  --muted:rgba(232,239,233,.72);--line:rgba(255,255,255,.14);
  --card:rgba(255,255,255,.05)}
*{box-sizing:border-box;margin:0}
body{font-family:-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  background:linear-gradient(var(--bg1),var(--bg2)) fixed;color:var(--soft);
  line-height:1.6;-webkit-font-smoothing:antialiased}
a{color:var(--gold)}
.wrap{max-width:880px;margin:0 auto;padding:0 22px}
header.site{display:flex;align-items:center;gap:12px;padding:18px 0}
header.site a.brand{display:flex;align-items:center;gap:12px;
  text-decoration:none;color:var(--soft)}
header.site .word{font-weight:800;letter-spacing:4px;font-size:18px}
.langs{margin-left:auto;font-size:14px}
.langs a{color:var(--muted);text-decoration:none;padding:4px 8px;
  border-radius:6px}
.langs a.on{color:var(--gold);background:var(--card);font-weight:700}
footer.site{border-top:1px solid var(--line);margin-top:56px;
  padding:26px 0 40px;font-size:14px;color:var(--muted)}
footer.site nav{display:flex;gap:18px;flex-wrap:wrap;margin-bottom:10px}
footer.site a{color:var(--muted);text-decoration:none}
footer.site a:hover{color:var(--gold)}
.btn{display:inline-flex;align-items:center;gap:10px;padding:14px 22px;
  border-radius:12px;text-decoration:none;font-weight:700;font-size:16px;
  border:2px solid rgba(255,255,255,.85);color:#fff}
.btn.play{background:#263F6D}
.btn.apple{background:#7240B0}
.btn svg{flex:none}
h1,h2,h3{color:var(--gold);line-height:1.25}
`;

// ---------------------------------------------------------------------
// Site copy, English and French. Legal pages are fully written in both
// languages (store and AdMob reviews accept either, players get both).
// ---------------------------------------------------------------------

const NAV_STRINGS = {
  en: { privacy: "Privacy Policy", terms: "Terms of Use", contact: "Contact" },
  fr: {
    privacy: "Politique de confidentialité",
    terms: "Conditions d’utilisation",
    contact: "Contact",
  },
};

function sitePage(lang, path, title, body, extraCss = "") {
  const nav = NAV_STRINGS[lang];
  const langLink = (code) =>
    `<a href="${path}?lang=${code}"${lang === code ? ' class="on"' : ""}>` +
    `${code.toUpperCase()}</a>`;
  const q = `?lang=${lang}`;
  return `<!doctype html>
<html lang="${lang}"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<meta name="description" content="Checkers — draughts &amp; checkers,
 together. Play the machine, play the world, join tournaments.">
<link rel="icon" type="image/svg+xml"
 href="data:image/svg+xml,${encodeURIComponent(LOGO_SVG(64))}">
<style>${SITE_CSS}${extraCss}</style>
</head><body>
<div class="wrap">
<header class="site">
  <a class="brand" href="/${q}">${LOGO_SVG(34)}
    <span class="word">CHECKERS</span></a>
  <nav class="langs">${langLink("en")} ${langLink("fr")}</nav>
</header>
${body}
<footer class="site">
  <nav>
    <a href="/privacy${q}">${nav.privacy}</a>
    <a href="/terms${q}">${nav.terms}</a>
    <a href="mailto:${CONTACT_EMAIL}">${nav.contact}</a>
  </nav>
  <div>&copy; 2026 Checkers &middot; dame.cd</div>
</footer>
</div></body></html>`;
}

const ANDROID_ICON = `<svg width="20" height="20" viewBox="0 0 24 24"
 fill="currentColor" xmlns="http://www.w3.org/2000/svg"><path d="M3.6 2.3
 13.3 12l-9.7 9.7c-.4-.2-.6-.6-.6-1.1V3.4c0-.5.2-.9.6-1.1Zm11.2 8.2L5.9
 1.6l10.8 6.1-1.9 2.8ZM17.9 8.5l2.9 1.6c1 .6 1 1.6 0 2.2l-2.9 1.6-2.2-2.7
 2.2-2.7ZM5.9 22.4l8.9-8.9 1.9 2.8-10.8 6.1Z"/></svg>`;
const APPLE_ICON = `<svg width="20" height="20" viewBox="0 0 24 24"
 fill="currentColor" xmlns="http://www.w3.org/2000/svg"><path d="M16.7
 12.8c0-2.4 2-3.6 2.1-3.7-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9-.8
 0-1.9-.9-3.2-.8-1.6 0-3.1 1-4 2.4-1.7 3-.4 7.4 1.2 9.8.8 1.2 1.8 2.5
 3.1 2.4 1.2-.1 1.7-.8 3.2-.8s1.9.8 3.2.8c1.3 0 2.2-1.2 3-2.4.9-1.4
 1.3-2.7 1.3-2.8-.1 0-2.6-1-2.7-3.9ZM14.4 5.6c.7-.8 1.1-1.9 1-3.1-1
 0-2.2.7-2.9 1.5-.6.7-1.2 1.9-1 3 1.1.1 2.2-.6 2.9-1.4Z"/></svg>`;

const LANDING_CSS = `
.hero{text-align:center;padding:46px 0 30px}
.hero h1{font-size:44px;letter-spacing:10px;margin:22px 0 6px}
.hero .tag{font-size:20px;color:var(--soft)}
.stores{display:flex;gap:14px;justify-content:center;flex-wrap:wrap;
  margin:30px 0 8px}
.stores small{display:block;font-size:11px;font-weight:400;opacity:.8;
  text-align:left;line-height:1.2}
.features{display:grid;gap:14px;margin-top:44px;
  grid-template-columns:repeat(auto-fit,minmax(190px,1fr))}
.card{background:var(--card);border:1px solid var(--line);
  border-radius:14px;padding:18px}
.card h3{font-size:16px;margin-bottom:6px}
.card p{font-size:14px;color:var(--muted)}
.rules{text-align:center;margin-top:34px;color:var(--muted);font-size:14px}
.rules b{color:var(--gold)}
.openapp{display:inline-block;margin-top:14px;color:var(--muted);
  font-size:14px;text-decoration:underline}
.openapp:hover{color:var(--gold)}
`;

const LANDING_STRINGS = {
  en: {
    title: "Checkers — draughts & checkers, together",
    tag: "Draughts &amp; checkers, together.",
    getOn: "Get it on",
    onThe: "Download on the",
    openApp: "Already installed? Open the app",
    features: [
      ["Play the machine",
       "Three difficulty levels, from a friendly first game to a Hard " +
       "engine that will make you work for every piece."],
      ["Play the world",
       "Live online games with real clocks, Elo ratings and a " +
       "Top&nbsp;30 leaderboard. Invite friends with a link or find an " +
       "opponent in seconds."],
      ["Tournaments",
       "Automatic tournaments every half hour: group stage, knockout " +
       "bracket, and a podium. Opt in for a reminder before kick-off."],
      ["Watch &amp; replay",
       "Watch any live game with clocks and captured pieces on screen, " +
       "or step through finished games move by move."],
    ],
    rules: "Three rule sets: <b>International</b> 10&times;10 with " +
      "flying kings, <b>Brazilian</b> 8&times;8, and <b>American</b> " +
      "checkers &mdash; in English and French.",
  },
  fr: {
    title: "Checkers — le jeu de dames, ensemble",
    tag: "Le jeu de dames, ensemble.",
    getOn: "Disponible sur",
    onThe: "Télécharger sur l’",
    openApp: "Déjà installée ? Ouvrir l’application",
    features: [
      ["Jouer contre l’ordinateur",
       "Trois niveaux de difficulté, d’une première " +
       "partie tranquille à un mode Difficile qui vous fera " +
       "mériter chaque pion."],
      ["Jouer avec le monde",
       "Parties en ligne avec pendules, classement Elo et Top&nbsp;30. " +
       "Invitez vos amis par lien ou trouvez un adversaire en quelques " +
       "secondes."],
      ["Tournois",
       "Tournois automatiques toutes les demi-heures : phase de " +
       "groupes, tableau à élimination directe et podium. " +
       "Activez un rappel avant le début."],
      ["Regarder &amp; revoir",
       "Suivez n’importe quelle partie en direct avec pendules et " +
       "pièces capturées, ou rejouez les parties " +
       "terminées coup par coup."],
    ],
    rules: "Trois règlements : dames <b>internationales</b> " +
      "10&times;10 avec dames volantes, <b>brésiliennes</b> " +
      "8&times;8 et <b>américaines</b> &mdash; en français " +
      "et en anglais.",
  },
};

function landingPage(lang) {
  const t = LANDING_STRINGS[lang];
  const cards = t.features
    .map(([h, p]) => `<div class="card"><h3>${h}</h3><p>${p}</p></div>`)
    .join("");
  return sitePage(
    lang,
    "/",
    t.title,
    `
<section class="hero">
  ${LOGO_SVG(112)}
  <h1>CHECKERS</h1>
  <div class="tag">${t.tag}</div>
  <div class="stores">
    <a class="btn play" href="${PLAY_STORE_URL}">${ANDROID_ICON}
      <span><small>${t.getOn}</small>Google Play</span></a>
    <a class="btn apple" href="${APP_STORE_URL}">${APPLE_ICON}
      <span><small>${t.onThe}</small>App Store</span></a>
  </div>
  <a class="openapp" href="dame://home">${t.openApp}</a>
</section>
<section class="features">${cards}</section>
<p class="rules">${t.rules}</p>
`,
    LANDING_CSS,
  );
}

const DOC_CSS = `
main.doc{padding-top:8px}
main.doc h1{font-size:30px;margin-bottom:2px}
main.doc .date{color:var(--muted);font-size:14px;margin-bottom:26px}
main.doc h2{font-size:19px;margin:28px 0 8px}
main.doc p,main.doc li{color:var(--soft);font-size:15px}
main.doc ul{padding-left:22px;margin:8px 0}
main.doc li{margin:5px 0}
`;

const PRIVACY_BODY = {
  en: `
<h1>Privacy Policy</h1>
<div class="date">Effective August 22, 2026</div>

<p>This policy describes what the Checkers mobile app ("the app", "we")
collects, why, and the choices you have. Checkers is published at
dame.cd; you can reach us any time at
<a href="mailto:${CONTACT_EMAIL}">${CONTACT_EMAIL}</a>.</p>

<h2>What we collect</h2>
<ul>
<li><b>Account.</b> You can play as a guest (an anonymous account created
on your device) or sign in with Google or Apple, in which case we receive
the identifier and email address those services share for sign-in. We
never see your passwords.</li>
<li><b>Profile.</b> The nickname you choose and, optionally, a profile
photo. The app encourages you not to use your real name or photo.</li>
<li><b>Gameplay.</b> Games you play (moves, results, timestamps), your
rating, tournament results, and — while the app is open — your online
presence, so friends can invite you.</li>
<li><b>Messages.</b> Anything you send us through "Write to the Admins"
in the app.</li>
<li><b>Push notifications.</b> If you allow notifications, we store a
device push token, its platform, and the last time the app connected so
Firebase Cloud Messaging can deliver tournament reminders and occasional
service or game announcements. You can disable notifications in your
device settings.</li>
<li><b>Usage analytics.</b> We use Google Firebase Analytics to
understand which features are used, via anonymous usage events.</li>
</ul>

<h2>Advertising</h2>
<p>The app shows ads through Google AdMob, which may collect device
identifiers to serve and measure ads as described in
<a href="https://policies.google.com/technologies/partner-sites">Google&#39;s
privacy documentation</a>. On iOS the system asks for tracking permission
first, and where required a consent dialog lets you choose between
personalized and non-personalized ads; you can revisit that choice from
the app&#39;s settings at any time. Some banners are sponsorships served by
us directly — for those we count only anonymous impressions and taps,
with no personal targeting.</p>

<h2>Where your data lives</h2>
<p>Game and account data is stored on our own servers. Sign-in, analytics,
push delivery and advertising are provided by Google and Apple as
described above; we do not sell your personal data to anyone.</p>

<h2>Retention and deletion</h2>
<p>You can delete your account in the app under
<b>More &rarr; Delete Account</b>. This permanently removes your account,
profile and rating. Completed games are retained in anonymized form (your
identity is detached from them) to keep opponents&#39; histories and archives
coherent. You can also email us to request access to or deletion of your
data.</p>

<h2>Children</h2>
<p>Checkers is a game of skill suitable for a general audience and is not
directed at children under 13. We do not knowingly collect personal data
from children; if you believe a child has provided us personal data,
contact us and we will delete it.</p>

<h2>Changes</h2>
<p>If this policy changes, the new version will be published on this page
with an updated effective date.</p>
`,
  fr: `
<h1>Politique de confidentialité</h1>
<div class="date">En vigueur le 22 août 2026</div>

<p>Cette politique décrit ce que l’application mobile Checkers
(« l’application », « nous »)
collecte, pourquoi, et les choix dont vous disposez. Checkers est
publiée sur dame.cd ; vous pouvez nous
écrire à tout moment à
<a href="mailto:${CONTACT_EMAIL}">${CONTACT_EMAIL}</a>.</p>

<h2>Ce que nous collectons</h2>
<ul>
<li><b>Compte.</b> Vous pouvez jouer en invité (un compte anonyme
créé sur votre appareil) ou vous connecter avec Google ou
Apple ; nous recevons alors l’identifiant et l’adresse
e-mail que ces services partagent pour la connexion. Nous ne voyons
jamais vos mots de passe.</li>
<li><b>Profil.</b> Le pseudo que vous choisissez et, en option, une photo
de profil. L’application vous encourage à ne pas utiliser
votre vrai nom ni votre photo.</li>
<li><b>Jeu.</b> Les parties que vous jouez (coups, résultats,
horodatages), votre classement, vos résultats de tournois et
— pendant que l’application est ouverte — votre
présence en ligne, pour que vos amis puissent vous inviter.</li>
<li><b>Messages.</b> Tout ce que vous nous envoyez via
« Écrire aux admins » dans
l’application.</li>
<li><b>Notifications push.</b> Si vous autorisez les notifications, nous
conservons un jeton de notification, la plateforme de l’appareil et la
date de sa dernière connexion afin que Firebase Cloud Messaging puisse
envoyer des rappels de tournoi et, occasionnellement, des annonces liées
au service ou au jeu. Vous pouvez désactiver les notifications dans les
réglages de votre appareil.</li>
<li><b>Statistiques d’usage.</b> Nous utilisons Google Firebase
Analytics pour comprendre quelles fonctionnalités sont
utilisées, via des événements anonymes.</li>
</ul>

<h2>Publicité</h2>
<p>L’application affiche des publicités via Google AdMob, qui
peut collecter des identifiants d’appareil pour diffuser et mesurer
les annonces, comme décrit dans
<a href="https://policies.google.com/technologies/partner-sites">la
documentation de Google</a>. Sur iOS, le système demande
d’abord l’autorisation de suivi, et lorsque c’est requis
une fenêtre de consentement vous laisse choisir entre
publicités personnalisées et non personnalisées ;
vous pouvez modifier ce choix à tout moment dans les
réglages de l’application. Certaines bannières sont des
partenariats que nous diffusons directement — nous ne comptons
alors que des affichages et des clics anonymes, sans ciblage
personnel.</p>

<h2>Où vos données sont hébergées</h2>
<p>Les données de jeu et de compte sont stockées sur nos
propres serveurs. La connexion, les statistiques, les notifications et
la publicité sont fournies par Google et Apple comme décrit
ci-dessus ; nous ne vendons vos données personnelles à
personne.</p>

<h2>Conservation et suppression</h2>
<p>Vous pouvez supprimer votre compte dans l’application via
<b>Plus &rarr; Supprimer le compte</b>. Cela supprime
définitivement votre compte, votre profil et votre classement. Les
parties terminées sont conservées sous forme anonymisée
(votre identité en est détachée) afin de garder
cohérents les historiques de vos adversaires et les archives. Vous
pouvez aussi nous écrire pour demander l’accès à
vos données ou leur suppression.</p>

<h2>Enfants</h2>
<p>Checkers est un jeu d’adresse destiné à un public
général et ne s’adresse pas aux enfants de moins de 13
ans. Nous ne collectons pas sciemment de données personnelles
d’enfants ; si vous pensez qu’un enfant nous en a
fournies, contactez-nous et nous les supprimerons.</p>

<h2>Modifications</h2>
<p>Si cette politique évolue, la nouvelle version sera
publiée sur cette page avec sa date d’entrée en
vigueur.</p>
`,
};

const TERMS_BODY = {
  en: `
<h1>Terms of Use</h1>
<div class="date">Effective August 22, 2026</div>

<p>These terms govern your use of the Checkers mobile app and its online
services ("the service"). By playing, you accept them. Questions:
<a href="mailto:${CONTACT_EMAIL}">${CONTACT_EMAIL}</a>.</p>

<h2>The service</h2>
<p>Checkers lets you play draughts and checkers against the computer or
other people, join tournaments, watch games, and appear on a leaderboard.
Online play requires an internet connection; features may change or be
withdrawn as the service evolves.</p>

<h2>Your account</h2>
<p>You may play as a guest or link a Google or Apple account. You are
responsible for activity on your account. Guest accounts live on your
device: if you sign out or lose the device without linking, the account
and its rating cannot be recovered.</p>

<h2>Fair play</h2>
<p>Rated games, tournaments and challenges are contests between people.
You agree not to use engine assistance or any other outside help in games
against other players, not to abuse bugs, not to deliberately lose games
to manipulate ratings, and not to disrupt other players&#39; games. We may
investigate suspicious play.</p>

<h2>Conduct and content</h2>
<p>Nicknames, photos and messages must not be offensive, impersonate
others, or infringe anyone&#39;s rights. We may remove content and restrict
or terminate accounts that break these rules — including limited blocks
(play disabled, watching allowed) or full blocks for serious or repeated
violations.</p>

<h2>Advertising and sponsorships</h2>
<p>The service is free and supported by advertising, which may include
third-party ads (Google AdMob) and sponsored content served by us. See
the <a href="/privacy?lang=en">Privacy Policy</a> for the choices you
have.</p>

<h2>Intellectual property</h2>
<p>The app, its design and its content (except your own profile content)
belong to us or our licensors. We grant you a personal, non-transferable
licence to use the app for playing. You keep the rights to content you
submit and grant us a licence to display it inside the service (for
example your nickname on the leaderboard or in watched games).</p>

<h2>Disclaimers</h2>
<p>The service is provided "as is", without warranties of any kind. We do
not guarantee uninterrupted availability, that ratings or results are
error-free, or that stored data can never be lost. To the maximum extent
permitted by law, our liability for any claim related to the service is
limited to the amount you paid to use it (the app is free).</p>

<h2>Termination</h2>
<p>You can stop using the service and delete your account at any time in
the app. We may suspend or terminate accounts that violate these
terms.</p>

<h2>Changes</h2>
<p>We may update these terms; the current version is always published on
this page with its effective date. Continuing to use the service after a
change means you accept the updated terms.</p>
`,
  fr: `
<h1>Conditions d’utilisation</h1>
<div class="date">En vigueur le 22 août 2026</div>

<p>Ces conditions régissent votre utilisation de l’application
mobile Checkers et de ses services en ligne
(« le service »). En jouant, vous les acceptez.
Questions :
<a href="mailto:${CONTACT_EMAIL}">${CONTACT_EMAIL}</a>.</p>

<h2>Le service</h2>
<p>Checkers vous permet de jouer aux dames contre l’ordinateur ou
d’autres personnes, de participer à des tournois, de regarder
des parties et de figurer au classement. Le jeu en ligne nécessite
une connexion Internet ; les fonctionnalités peuvent
évoluer ou être retirées.</p>

<h2>Votre compte</h2>
<p>Vous pouvez jouer en invité ou lier un compte Google ou Apple.
Vous êtes responsable de l’activité de votre compte. Les
comptes invités résident sur votre appareil : si vous
vous déconnectez ou perdez l’appareil sans avoir lié de
compte, le compte et son classement ne peuvent pas être
récupérés.</p>

<h2>Fair-play</h2>
<p>Les parties classées, les tournois et les défis sont des
compétitions entre personnes. Vous vous engagez à ne pas
utiliser d’assistance logicielle ni aucune aide extérieure
dans les parties contre d’autres joueurs, à ne pas exploiter
de bugs, à ne pas perdre volontairement pour manipuler le
classement et à ne pas perturber les parties des autres. Nous
pouvons enquêter sur les comportements suspects.</p>

<h2>Comportement et contenus</h2>
<p>Les pseudos, photos et messages ne doivent pas être offensants,
usurper l’identité d’autrui ni enfreindre les droits de
quiconque. Nous pouvons retirer des contenus et restreindre ou fermer
les comptes qui enfreignent ces règles — y compris par des
blocages partiels (jeu désactivé, visionnage autorisé)
ou complets en cas de violations graves ou répétées.</p>

<h2>Publicité et partenariats</h2>
<p>Le service est gratuit et financé par la publicité, qui
peut inclure des annonces de tiers (Google AdMob) et des contenus
sponsorisés que nous diffusons. Consultez la
<a href="/privacy?lang=fr">politique de confidentialité</a> pour
connaître vos choix.</p>

<h2>Propriété intellectuelle</h2>
<p>L’application, son design et ses contenus (hors contenus de
votre profil) nous appartiennent ou appartiennent à nos
concédants. Nous vous accordons une licence personnelle et non
transférable pour utiliser l’application. Vous conservez les
droits sur les contenus que vous soumettez et nous accordez une licence
pour les afficher dans le service (par exemple votre pseudo au
classement ou dans les parties regardées).</p>

<h2>Garanties</h2>
<p>Le service est fourni « en l’état »,
sans garantie d’aucune sorte. Nous ne garantissons ni une
disponibilité ininterrompue, ni l’absence d’erreurs dans
les classements ou résultats, ni qu’aucune donnée ne
puisse jamais être perdue. Dans la mesure maximale permise par la
loi, notre responsabilité pour toute réclamation liée au
service est limitée au montant que vous avez payé pour
l’utiliser (l’application est gratuite).</p>

<h2>Résiliation</h2>
<p>Vous pouvez cesser d’utiliser le service et supprimer votre
compte à tout moment dans l’application. Nous pouvons
suspendre ou fermer les comptes qui violent ces conditions.</p>

<h2>Modifications</h2>
<p>Nous pouvons mettre à jour ces conditions ; la version en
vigueur est toujours publiée sur cette page avec sa date
d’effet. Continuer à utiliser le service après une
modification vaut acceptation.</p>
`,
};

const DOC_TITLES = {
  privacy: {
    en: "Privacy Policy — Checkers",
    fr: "Politique de confidentialité — Checkers",
  },
  terms: {
    en: "Terms of Use — Checkers",
    fr: "Conditions d’utilisation — Checkers",
  },
};

function privacyPage(lang) {
  return sitePage(lang, "/privacy", DOC_TITLES.privacy[lang],
    `<main class="doc">${PRIVACY_BODY[lang]}</main>`, DOC_CSS);
}

function termsPage(lang) {
  return sitePage(lang, "/terms", DOC_TITLES.terms[lang],
    `<main class="doc">${TERMS_BODY[lang]}</main>`, DOC_CSS);
}

function pickLang(request, url) {
  const q = url.searchParams.get("lang");
  if (q === "fr" || q === "en") return q;
  const accept = request.headers.get("accept-language") ?? "";
  return /^fr\b|,\s*fr\b/i.test(accept) ? "fr" : "en";
}

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
<p style="font-size:12px;opacity:.45">Opens the Dame app</p>
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

    // Keep the authenticated operations console on the new public domain
    // while its isolated worker retains the credentials and service key.
    if (p === "/admin" || p.startsWith("/admin/")) {
      const adminUrl = new URL(
        p + url.search,
        "https://checkers-admin.tresormvumbi.workers.dev",
      );
      return fetch(new Request(adminUrl, request));
    }

    if (p === "/.well-known/assetlinks.json") return json(ASSETLINKS);
    if (p === "/app-ads.txt") {
      return new Response(APP_ADS_TXT, {
        headers: {
          "content-type": "text/plain; charset=utf-8",
          "cache-control": "public, max-age=3600",
        },
      });
    }
    if (
      p === "/.well-known/apple-app-site-association" ||
      p === "/apple-app-site-association"
    )
      return json(AASA);

    const party = p.match(/^\/party\/([A-Za-z0-9-]+)/);
    if (party)
      return html(
        deepLinkPage(
          "dame://party/" + party[1],
          "You've been invited to a game!"
        )
      );
    if (p === "/tournament" || p.startsWith("/tournament/"))
      return html(
        deepLinkPage(
          "dame://tournament",
          "You've been invited to a tournament!"
        )
      );

    const lang = pickLang(request, url);
    if (p === "/privacy" || p === "/privacy/") {
      return html(privacyPage(lang));
    }
    if (p === "/terms" || p === "/terms/") {
      return html(termsPage(lang));
    }
    return html(landingPage(lang));
  },
};
