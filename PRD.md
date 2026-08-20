# Checkers — Product Requirements Document

| | |
|---|---|
| **Status** | Draft v1.0 |
| **Date** | 2026-08-13 |
| **Reference product** | [kopo](../kopo) (`/Users/tresorm/projects/kopo`) — architecture, look & feel, and flows are reused |
| **Platforms** | Android + iOS (Flutter) |
| **Backend** | Supabase (self-hosted, deployed on the existing Coolify instance at `http://192.168.101.240:8000/`) |

---

## 1. Overview

A mobile checkers/draughts game built with Flutter that reuses the **look and feel, architecture, structure, and conventions of the kopo card game** while replacing its card engine with a checkers engine and its Firebase backend with Supabase.

Players can:

- **Play against the PC** with three difficulty levels (Easy / Medium / Hard) powered by a real search-based AI.
- **Play online against people**: join a public matchmaking lobby, or invite a friend (in-app invite or shareable link — same flows as kopo).
- **Watch** live games in real time as a spectator.
- **Compete** on a **Top 30** leaderboard ranked by ELO rating.
- Configure the rules: board size **10x10 (default)** or **8x8**, backward pawn capture (default **on**), flying king (default **on**), surfaced through named variant **presets** plus individual toggles.

Completed online games are recorded permanently in the database (with full move lists, enabling replay later).

### 1.1 Goals

1. Ship a polished 2-player checkers game with the same production quality and UX language as kopo.
2. A computer opponent that is genuinely fun at Easy and genuinely strong at Hard.
3. Reliable online play with a server-authoritative engine (no client can cheat), correct clocks, and graceful disconnect handling.
4. Faithful rules for the three major variants (International, Brazilian, American) with correct auto-draw detection.
5. Prove out the Supabase-on-Coolify stack as a Firebase replacement for future games.

### 1.2 Non-goals (explicitly out of scope for v1)

- ~~**Advertisement**~~ — *added post-v1 (2026-08-20) at the owner's request; see §5.9.*
- **Subscriptions / IAP** ("Remove Ads" paywall, entitlements, receipt validation) — not ported.
- 3+ player modes (checkers is strictly 2-player; kopo's 4-player seat logic collapses to 2 seats).
- Tournaments, chat, puzzles, opening books, endgame tablebases (possible later).
- Web/desktop builds (the AI bitboard design assumes native 64-bit ints; see §7.3).

---

## 2. Reference product: what is reused from kopo

Kopo's own `AGENTS.md` is the engineering conventions contract and is adopted wholesale (folder layout, GetX conventions, theming rules, i18n rules, service layering, testing layout). The parity table:

| Kopo element | Checkers decision |
|---|---|
| Folder structure (`lib/bindings`, `core`, `data/models`, `modules/<feature>/{binding,controller,view}`, `routes`, `services`, `shared/widgets`, `themes`, `translations`) | **Reuse as-is** |
| GetX: `GetMaterialApp`, `GetPage` + per-screen `Binding` with `Get.lazyPut`, `GetView<Controller>` + `Obx`, typed `Get.arguments` classes | **Reuse as-is** |
| `InitialBinding` global DI, abstract-interface + concrete service pattern, `ApiResult<T>`/`ApiError` sealed result | **Reuse as-is** (Firebase implementations replaced by Supabase implementations) |
| Theme: Material 3 `ColorScheme.fromSeed`, `KopoThemeExtension`-style `ThemeExtension` (brand gold, gradients), Inter + Iosevka Charon fonts, tiny deliberate TextTheme, light-only | **Reuse pattern**; new brand assets (board/pieces instead of cards; new background art in the same "dark table" aesthetic) |
| Shared widgets: gradient button, blurred modal (`showKopoModal`), staggered entrance, animated logo mark, square icon button, flag icon | **Reuse** (renamed to the new app's prefix) |
| Landing screen = splash + language selector + Google/Apple/Guest auth; then Edit Profile (nickname + avatar) on first login | **Reuse flow** on Supabase Auth |
| Home shell: custom floating bottom bar with 4 tabs | **Reuse**: **Play · Watch · Top 30 · "..."** (more) |
| Heart/share menu in Play-tab header (Share App, Rate App, Feedback, About, Terms, Privacy) | **Reuse** (drop "Other games" and "Facebook page" for v1 unless assets exist) |
| Online architecture: server-authoritative state, clients read-only, all mutations via callable functions with transactions, client-claimed + server-validated timeouts, `lastMovePresentation` reveal pattern | **Reuse pattern** on Supabase (Edge Functions + Postgres + Realtime) |
| Invite flows: in-app player directory invite, social/deep-link invite, mid-game bot replacement | **Reuse** (bot replacement becomes "AI takeover" — see §5.2.6) |
| Watch tab: live-game list + search, spectate through the same board view in read-only mode | **Reuse** |
| Leaderboard tab with podium + share-as-image | **Reuse UI**; ranked by **ELO** instead of stars |
| Stars economy | **Replaced by ELO** (see §5.5). No stakes/stars in v1. |
| i18n EN/FR via GetX translations, key constants, no hard-coded strings | **Reuse** |
| Force-update gate from remote config | **Reuse** via `app_config` table |
| Rating prompt (`rate_my_app`), Share App (`share_plus`), screen wakelock, confetti on win | **Reuse** |
| Ads, subscriptions, player-messages admin inbox, other-games catalog, how-to-play video streaming | **Dropped or deferred** (messages system: deferred to v1.1; how-to-play becomes native animated pages, no video) |

---

## 3. Game rules specification

The rules engine implements **FMJD international draughts** as the baseline (all article references are to FMJD *Annex 1 — Official rules for international draughts*), parameterized by board size and rule toggles.

### 3.1 Variant presets and toggles

Game setup exposes **named presets** backed by **two user-visible toggles** + board size:

| Preset | Board | Backward pawn capture | Flying king | Majority capture (hidden rule) |
|---|---|---|---|---|
| **International** (default) | 10x10 | ON | ON | ON |
| **Brazilian** | 8x8 | ON | ON | ON |
| **American** | 8x8 | OFF | OFF | OFF |
| **Custom** | either | any | any | follows backward-capture toggle |

- **Backward pawn capture** (default **permitted**): when ON, men (pawns) may capture both forwards and backwards (FMJD Art. 4.1). When OFF, men capture forwards only.
- **Flying king** (default **permitted**): when ON, a king moves any number of free squares along a diagonal (Art. 3.9) and, when capturing, jumps a piece anywhere on its diagonal and lands on **any** free square beyond it, turning 90° between jumps (Art. 4.3, 4.6). When OFF, a king moves and captures exactly **one square at a time** (in any diagonal direction).
- **Majority capture** is not shown as a toggle in v1: it is ON whenever backward capture is ON, OFF otherwise (this exactly reproduces the three named variants). The engine still implements it as an independent parameter so a third toggle can be exposed later without refactoring.
- Changing a preset sets the toggles; changing a toggle switches the preset label to "Custom".
- **Online matchmaking is segmented by preset** (see §5.2.1). Custom configurations are available vs PC and in friend invites only.

### 3.2 Core rules (all variants unless noted)

- Play on dark squares only. 10x10: 50 playable squares, 20 men per side; 8x8: 32 playable squares, 12 men per side. Initial setup per FMJD Art. 2.7 (10x10: Black on 1–20, White on 31–50).
- **White moves first** in International and Brazilian. American convention (darker color moves first) is normalized in this product to **White moves first in all variants** for consistency; documented in How to Play.
- Men move one square diagonally forward to an empty square (Art. 3.4).
- **Capture is mandatory** in all variants. Multi-jump chains must be played to completion.
- **Majority rule** (when ON): the sequence capturing the **largest number of pieces** must be played (Art. 4.13); a king counts as one piece with no priority; ties are free choice (Art. 4.14). When OFF (American): the player freely chooses among available capture sequences.
- **Multi-capture constraints** (Art. 4.7, 4.8, 4.11): may not jump own pieces; may cross the same empty square twice but may **not jump the same enemy piece twice**; captured pieces are removed **only after the full sequence completes** — a "dead" piece still blocks squares during the sequence (the *Turkish strike* rule — a known implementation trap; explicit test cases required).
- **Promotion**: a man promotes only when its move **ends** on the far row (Art. 3.5). A man that passes over the promotion row mid-capture and lands elsewhere **remains a man** (Art. 4.15). Promotion ends the turn; the new king cannot move until the opponent has moved (Art. 3.8).
- **Win** (Art. 7.2): the opponent has no pieces left, has no legal move (blocked), resigns, or **loses on time** (§5.3).

### 3.3 Draw rules

Two paths to a draw:

**(a) Draw by agreement** (Art. 7.3.1) — lichess-style flow:
1. Either player taps **Offer draw** (flag icon in the in-game menu).
2. The opponent sees a non-blocking banner with **Accept** / **Decline**; making a move implicitly declines and withdraws the offer.
3. Anti-spam: a player may not re-offer within 5 of their own moves; after 3 declined offers the button is disabled for the rest of the game.

**(b) Automatic draw detection** — the server engine declares the draw automatically (with a modal explaining which rule fired). For **International / Brazilian** presets, exact FMJD rules:

| Rule | Trigger |
|---|---|
| Threefold repetition (Art. 6.1) | Same position (pieces + side to move) occurs a 3rd time. Detected via Zobrist-hash history. |
| 25-move rule (Art. 6.2) | 25 successive moves per side with only king moves — no man move, no capture. Counter resets on any man move or capture. |
| 16-move endgame rule (Art. 6.3) | Material is exactly {3 kings} or {2 kings + 1 man} or {1 king + 2 men} vs 1 lone king: at most 16 more moves each; captures do **not** reset this counter. A block/no-pieces loss on the 16th move takes precedence. |
| 5-move endgame rule (Art. 6.4) | {2 kings vs 1 king}, {1 king + 1 man vs 1 king}, or {1 king vs 1 king}: drawn after at most 5 more moves each. |

For the **American** preset: threefold repetition + **40-move rule** (40 consecutive moves per side without a capture or a man move ⇒ draw — the accepted software formulation of the WCDF rule).

For **Custom** configurations: the counters follow the majority-capture setting's family (International family when backward capture is ON, American family otherwise).

Draw detection runs identically in the Dart engine (PC games, client display) and the TS engine (authoritative for online games).

### 3.4 Notation and game storage

- Squares use **FMJD numbering**: 1–50 on 10x10 (Black's back row = 1–5), 1–32 on 8x8. This is the wire and storage format for moves.
- Moves are stored fully disambiguated: `{from, to, captured: [squares], promoted: bool}` per ply (short PDN notation like `27x38` can be ambiguous for multi-captures).
- Completed games are exportable as **PDN** (Portable Draughts Notation), `GameType` 20 = International, 21 = American, 26 = Brazilian; position setup via the standard FEN-like tag. PDN export is a v1.1 nice-to-have; the storage schema must support it from day one (it does — see §7.4.3).

---

## 4. Users and modes

- **Guest (anonymous)**: full access — play PC, play online, appear on leaderboard. Warned (like kopo) that logging out loses the account; can **link** the account to Google/Apple at any time from the More tab.
- **Signed-in (Google / Apple)**: durable account across devices.
- Profiles: nickname (required) + optional avatar (pick → crop → compress → upload), privacy nudge to not use real name/photo — identical flow to kopo's Edit Profile.

---

## 5. Features

### 5.1 Play vs PC

Entry: **Play** tab → **Play with PC** → modal: choose **difficulty** (Easy / Medium / Hard) and **rules** (preset selector + toggles, defaults to last used) → board.

- Human plays White by default; a **side selector** (White / Black / Random) is in the same modal.
- The AI runs **on-device** in a background isolate (§7.3); no network needed — PC games are fully offline.
- The PC opponent is presented with a bot persona (name + avatar) in kopo's style (reuse the bot-profile pattern; new checkers-themed personas).
- AI think time is padded to a minimum ~0.8s so moves feel deliberate; the moving piece animates along its jump path.
- Undo: allowed vs PC (undoes the last human+AI move pair), unlimited. Not available online.
- Game end: win → confetti + banner (kopo pattern); loss/draw → banner with the reason (e.g. "Draw — 25-move rule"). **Play again** button (no auto-restart countdown in v1; checkers games are long, unlike kopo hands).
- **PC games are streamed to the backend when the player is signed in** *(updated 2026-08-14)*: the client mirrors every move (human and AI) to a `vs_pc` game record that the server re-validates with the same engine — so PC games appear live in the Watch tab. The record includes the AI level and whether "allow undoing moves" was enabled; undos roll the server state back via replay. Streamed PC games are **unrated**, carry no clocks, and abandoning one (or starting a new one) closes it server-side. If the device is offline the game simply plays locally without streaming.

#### 5.1.1 Difficulty levels

All levels use the same engine (negamax + alpha-beta + iterative deepening + transposition table + quiescence, §7.3), differentiated by time budget and deliberate imperfection:

| Level | Think budget | Behavior |
|---|---|---|
| **Easy** | ~1 s, depth cap 8 | Full quiescence; occasionally (~20%) plays the 2nd-best move; small eval noise; ~4% bounded blunders. Beatable by a casual player who pays attention. |
| **Medium** | ~3 s | Full engine strength at a moderate budget, always the best move found. Challenge for a club-level player. |
| **Hard** | ~6.5 s, depth cap 40 | Full strength with transposition-table + killer-move ordering inside the search (several extra plies at the same node budget). Target: clearly stronger than almost all human players. |

*(Rebalanced after playtesting on 2026-08-14: the original Easy tier proved
redundant — the original Medium was already beatable — so the ladder shifted
up one notch and Hard gained a deeper search.)*

Noise is deterministic per position (derived from the Zobrist key) so the transposition table stays consistent.

### 5.2 Play online (vs people)

Entry: **Play** tab → **Play with People** → modal with two sections (kopo pattern):
**Join Online Game** and **Invite Friends to Play**.

All online games are **server-authoritative**: the client never writes game state; every action is an Edge Function call validated by the server-side engine against the current position, clock, and turn (§7.4).

#### 5.2.1 Matchmaking lobby

1. Player picks a preset (International 10x10 default / Brazilian / American — no Custom in matchmaking) and taps Join.
2. Edge Function `join_online_game` finds the oldest `waiting` public game with the same preset and a free seat and seats the player transactionally; otherwise creates a new `waiting` game.
3. The lobby screen (reuse kopo's `online_lobby` module) shows both seats, live presence, and a **Leave Lobby** action. An 8s no-data timeout aborts to home.
4. When both seats are filled, the server flips the game to `playing`, assigns colors randomly, initializes clocks, and sets the first turn deadline. Clients navigate to the board.
5. **Play with PC fallback**: if a player waits > 30 s alone, the lobby offers a "Play the PC instead?" shortcut (does not auto-trigger). *(Kopo's "fill with bots" adapted to 2-player.)*

#### 5.2.2 Invite a friend — in-app

Reuse kopo's `invite_players` module and flows:

- A directory of **available players** (online, not busy, active < 3 min) is maintained via presence heartbeats (§7.4.4). Single-select (2-player game), invite → server creates a private game + an invite record with a **60 s TTL**, inviter waits in the lobby.
- The invitee's always-on invite listener (kopo's `PrivateInviteListenerService` pattern, backed by a Supabase Realtime subscription) pops a modal with the inviter's avatar → **Accept** (seated, both go to board) / **Decline**.
- Invite records expire server-side after 60 s.

#### 5.2.3 Invite a friend — shareable link

- "Invite from social media" creates a private game with `allow_social_join`, builds `https://<app-domain>/party/<gameId>` (custom scheme fallback `checkers://party/<gameId>`), and opens the system share sheet (`share_plus`).
- Receiving the link (kopo's `PartyLinkService` pattern with `app_links`): auto-sign-in anonymously if needed → `join_social_game` → lobby. Requires Android App Links + iOS Universal Links assets hosted on the app domain (**open item: domain to be chosen**, see §11).
- Friend-invite games use whatever rules the host configured (Custom allowed). **Private games are unrated** (§5.5).

#### 5.2.4 In-game experience (online)

- Board view is the same widget as PC games; opponent presence indicator (connected/disconnected) shown by their avatar.
- Opponent moves are animated from the server's `last_move` payload (kopo's `lastMovePresentation` pattern).
- Client submits `{from, to, path[]}`; the server validates against the full legal-move set (including majority rule) and rejects otherwise. The client pre-validates with the same Dart engine so illegal moves are impossible in the UI (server check is the authority).
- In-game menu: **Resign** (confirm modal), **Offer draw** (§3.3), sound toggle.
- **Reconnect**: on app resume / network recovery the client re-subscribes and calls `reconnect_game`; the full authoritative state (position, clocks, pending draw offer) is rehydrated from the game row. A player who stays disconnected simply keeps losing clock time (§5.3); there is no bot substitution online in v1 — their flag will fall.

#### 5.2.5 Rematch

When a game finishes, both players see the result banner with a **Rematch** button. If both tap it within 30 s, the server starts a new game with colors swapped (same rules, both clocks reset). If the opponent left, the banner says so and offers Home / Play again (new matchmaking).

#### 5.2.6 Abandonment

- Leaving mid-game (app kill, back-out with confirm) = **resignation** after a grace period: if a player is disconnected and their total remaining time (turn + bank, when it is their turn) runs out, they lose on time; if they are disconnected for > 2 minutes regardless of turn, the server (sweep job) declares the game abandoned in the opponent's favor.
- Rated games ended by resignation/abandonment/timeout count as normal losses for ELO.

### 5.3 Clock specification

Per player, per game:

- **Turn timer: 15 seconds** per move ("delay clock"). It does not accumulate — using less than 15 s gives no credit.
- **Bank: 5 minutes** (300 s). When a player exceeds 15 s on a move, the excess is deducted from their bank.
- **Flag fall**: if a player's bank reaches 0 while they are thinking (i.e. elapsed > 15 s + remaining bank), they **lose immediately on time**.

Mechanics (server-authoritative, kopo's pattern):

- On every accepted move the server stamps `turn_started_at` and computes the mover's new bank: `bank -= max(0, elapsed - 15s)`.
- `turn_deadline_at = turn_started_at + 15s + mover's remaining bank` is stored on the game row; clients render both the 15 s countdown ring and the bank below each avatar, corrected for clock skew via a server-time offset probe.
- Timeout enforcement is **client-claimed, server-validated** (kopo's `claimOnlineTimeout`): any connected client (including a spectator) whose local view passes the deadline calls `claim_timeout`; the server re-checks against its own clock and ends the game. A **pg_cron sweep (every 30 s)** is the backstop when no client is connected.
- Clock values are config constants in `app_config` (server-controlled), so they can be tuned without an app release. v1 ships exactly 15 s + 5 min.

### 5.4 Watch (live spectating)

- The **Watch** tab lists live public games in real time (kopo's `watchableGames` pattern → a Supabase Realtime subscription on a `watchable_games` view/projection): players' avatars, nicknames, ratings, variant badge, move count. Client-side nickname search (kopo parity).
- Tapping opens the **same board view in spectator mode**: no hand/action UI, both clocks visible (hidden for streamed PC games, which have no clocks), moves animate live. Spectators can trigger `claim_timeout` but nothing else.
- **Watcher presence** *(added 2026-08-14)*: spectators heartbeat into `game_watchers`; everyone on the board (players and spectators) sees a live row of up to 5 overlapping watcher avatars plus a "+X" bubble near the bottom. Tapping it opens a modal listing watchers 20 at a time (avatar, nickname, ELO) with load-more. Stale watchers are swept after 90 s.
- Private (friend) games are **not** listed.
- If the watched game ends or disappears, show the result, then a "no longer available" overlay (kopo parity).
- **Replay of completed games** (from the recorded move lists): v1.1 — Watch tab gains a "Recent games" section with a move-by-move replay player.

### 5.5 Top 30 (leaderboard, ELO)

Ranking is by **ELO rating** (replaces kopo's stars):

- Initial rating **1200**. Standard ELO expected-score update; **K = 32** for a player's first 30 rated games, **K = 16** after. Draw = 0.5. Floor at 100.
- **Rated**: public matchmaking games (all three presets share one rating in v1). **Unrated**: PC games, private/friend games, social-link games.
- Ratings are updated **transactionally by the server** when a game reaches a terminal state (win/loss/draw/timeout/abandonment). `rating_before`/`rating_after` are stored on the game record for auditability.
- **Top 30 tab**: reuse kopo's leaderboard UI verbatim — animated podium for the top 3, staggered ranked rows, share-as-image (rasterized share card via `RenderRepaintBoundary`). Rows show nickname, avatar, rating, and games played. Minimum **10 rated games** to appear on the board (keeps fresh 1200s from cluttering the top).
- Data comes from a `get_leaderboard` RPC / view (top 30 by rating among qualified players).

### 5.6 The "..." (More) tab

Reuse kopo's More tab minus monetization:

- **Languages** (EN / FR modal)
- **Edit Profile**
- **Link Account** (anonymous users only)
- **Log Out** (extra warning modal for anonymous users)
- **Delete Account** (confirm modal → server-side deletion of auth user, profile, avatar; completed games are anonymized, not deleted)
- Heart/share menu (Play-tab header, kopo parity): **Share App**, **Rate App**, **Feedback** (text → `feedback` table), **About** (Terms of Use, Privacy Policy links)

Removed vs kopo: Remove Ads, Privacy Options (UMP), Other Games, Facebook page.

### 5.6.1 Admin → player messages (kopo parity)

Admins can send messages to players: **public** broadcasts (per language) or
**private** messages targeted at one uid. Stored in `player_messages`
(Supabase, RLS scopes rows to public + own private; realtime), each row has
HTML text and/or an image, an optional link (opens in an in-app webview), a
publish/expiry window, and an enabled flag. The Play-tab header shows a mail
button with an unread badge only when active messages exist; opening the
Messages page marks them read (read ids persisted locally per language).
Admins insert rows via `scripts/send_player_message.sh`.

### 5.7 How to Play

Native animated explainer (kopo's `how_to_play` module pattern, no video): board & setup, man moves, captures & mandatory capture, majority rule, king moves (flying vs one-step per current settings), promotion, draws, clocks. Content adapts to the currently selected preset. Localized EN/FR.

### 5.8 Recorded games

Every online game (rated and private) is recorded permanently:

- Final result + reason (`checkmate`-equivalent: no pieces / blocked, resignation, timeout, abandonment, draw + which draw rule, draw by agreement).
- Full move list (per-ply `{from, to, captured[], promoted, ms_spent}`), rules config, players, ratings before/after, timestamps.
- This powers: Watch-tab live spectating (moves stream in as they're recorded), future replays, PDN export, and anti-abuse review.

### 5.9 Advertisement (added 2026-08-20, kopo parity)

AdMob via `google_mobile_ads`, mirroring kopo's `AdService` minus subscriptions:

- **Banners** (adaptive, compact): home Watch / Top 30 / More tabs, the game
  board, and the Messages page. They collapse when unavailable.
- **Interstitials**: an event counter increments on bottom-nav transitions and
  finished PC games; every **15th** event shows an interstitial (kopo used 5).
- **Consent**: UMP consent form (GDPR message shared with kopo's, apps added)
  + iOS ATT prompt; EEA users get a "Privacy Options" entry in More.
- **Remote config**: `app_config.config.ads` — `enabled`, `interstitialFrequency`,
  per-platform banner/interstitial unit ids. Kill switch: set `enabled` false.
- Debug builds always use Google's sample ad units; `--dart-define=CHECKERS_DISABLE_ADS=true`
  disables ads entirely (local testing / e2e).
- AdMob apps: Android `ca-app-pub-3437010247383226~1693679988`,
  iOS `ca-app-pub-3437010247383226~4798460676`.

### 5.10 Moderation: player blocking (added 2026-08-20)

Admins block players from the backend (`scripts/block_player.sh`), for N days
or permanently:

- **soft**: the player connects and watches games but cannot play (Play
  actions show a restriction notice; the server rejects any seat).
- **full**: the player only sees a blocked screen with the duration.

Enforcement is device-linked: the app registers stable OS identifiers
(Android SSAID; on iOS a keychain-persisted UUID + identifierForVendor) via
`sync_device_blocks`, and blocking a player flags all their known devices —
so a signed-out or freshly re-registered account on the same device inherits
the block. Only high-entropy OS ids are used (no fingerprinting) and
fleet-wide degenerate values are rejected, keeping false positives to
genuinely shared physical devices. Server-side, `game_players` /
`game_watchers` insert triggers reject blocked uids on every play/watch
path, so client bypasses don't work. `--unblock` revokes the block and its
device flags; block rows are kept for audit.

### 5.11 Tournaments (added 2026-08-20)

A **Tournament** tab sits between Watch and Top 30 with two entry points:
join the lobby, or browse current + completed tournaments (10 per page,
load more; completed rows show the winner's name and photo, running rows
show the current stage).

- **Lobby**: realtime presence with 15s heartbeats; quitting the app,
  starting a game, or losing connectivity drops the player (stale >45s).
  A pg_cron job fires at :00 and :30; with >=4 present it starts a
  tournament with an even number of players (earliest joiners first).
- **Format**: if the field is a power of two (>=4), a straight knockout
  with random pairings each round; semifinal losers play for 3rd place.
  Otherwise an elimination round runs first (random pairs, 3/1/0 points)
  and the largest power of two qualifies, ranked by points, then ELO,
  then lobby join order. Knockout draws resolve by the same order.
- **Games** reuse the standard online machinery (games/game_players,
  clocks, spectating, recording, emotes) and are created already started;
  timeouts advance the bracket automatically via a games trigger
  (`_on_tournament_game_finished` -> `_advance_tournament`).
- **UI**: bracket page with a fixtures view (stage columns, live/winner
  match cards) and a table view (elimination standings + per-stage
  results), podium banner when finished, an in-app "how tournaments
  work" explainer, and auto-navigation into the player's own match.
- **Replays**: finished tournament games open in a replay board
  (prev / play / next through the recorded moves).

---

## 6. UX specification

### 6.1 Navigation map

```
/ (landing: logo, language, Google/Apple/Guest)
├─ /update-required
├─ /edit-profile               (first login, and from More)
└─ /home                       (4 tabs: Play · Watch · Top 30 · ···)
   ├─ Play → PC modal → /game-board (local)
   ├─ Play → People modal → /online-lobby → /game-board (online)
   │                      └→ /invite-players → /online-lobby
   ├─ Watch → /game-board (spectator)
   ├─ /how-to-play
   └─ More → modals + /edit-profile
```

Bottom bar: kopo's custom floating translucent bar — 4 items, gold selected state, icon-only for "...". Labels: **Play**, **Watch**, **Top 30**, (icon).

### 6.2 Board screen

- Full-bleed table background (kopo's casino-table aesthetic, new checkers art: wooden/dark table, board centered).
- Board fills the width in portrait; opponent avatar + clock + captured-piece tray on top, own on the bottom. Spectator mode shows both players top/bottom with no action affordances.
- **Input**: tap a piece → legal destinations highlighted (dots; capture paths highlighted with intermediate squares); tap destination to move. Drag-and-drop also supported. When the majority rule forces specific sequences, only those pieces/paths are selectable; a first-time hint explains "capture is mandatory" (persisted like kopo's drag hint).
- Multi-jump: the piece animates hop-by-hop; captured pieces fade out at sequence end (per the deferred-removal rule).
- Last move highlighted (from/to squares tinted).
- 15 s ring around the active player's avatar; bank time (m:ss) beneath it, turning red under 30 s. Kopo's countdown widget adapted.
- Haptics on piece pickup and capture (light impact); optional sound effects (move, capture, king, win) behind a toggle — **new** relative to kopo (which has no audio); nice-to-have, can slip to v1.1.
- Win: confetti + banner (kopo). Draw/loss: banner with reason.

### 6.3 Theming

- Port kopo's theme wholesale: Material 3 seed scheme, `ThemeExtension` with brand tokens (gold accent, blue primary gradient for buttons, purple logo gradient), Inter + Iosevka Charon, translucent black panels with 2 px white borders, staggered entrance animations, blurred modals.
- New asset set: app logo/mark, board textures (10x10 and 8x8), piece sprites (men + kings, two colors, king distinguished by crown), bot personas, background art. All paths centralized in an `AppStrings`-style constants file.

---

## 7. Technical architecture

### 7.1 Client

- Flutter (same SDK line as kopo), GetX for state/DI/routing/i18n, structure per kopo's `AGENTS.md`.
- Key packages carried over: `get`, `flutter_svg`, `image_picker`, `image_cropper`, `flutter_image_compress`, `share_plus`, `app_links`, `rate_my_app`, `url_launcher`, `shared_preferences`, `wakelock_plus`, `flutter_confetti`, `crypto`.
- Replaced: all `firebase_*` / `cloud_*` packages → `supabase_flutter` (+ `google_sign_in`, `sign_in_with_apple` for native token flows into Supabase Auth).
- Dropped: `google_mobile_ads`, `in_app_purchase`, `app_tracking_transparency`, `video_player`, `flutter_html`, `webview_flutter`.
- Services (abstract + Supabase impl): `AuthService`, `ProfileService`, `ProfilePhotoService`, `OnlineGameService`, `LeaderboardService`, `PresenceService`, `InviteListenerService`, `PartyLinkService`, `AppShareService`, `AppRatingService`, `ExternalUrlService`, `ScreenAwakeService`, `FeedbackService`, plus new `CheckersAiService`.

### 7.2 Rules engine (the critical shared component)

One engine specification, **two implementations kept in lock-step** (kopo's proven pattern):

1. **Dart** (`lib/modules/game_board/models/` — or `lib/engine/`): used for PC games, client-side pre-validation, legal-move highlighting, draw detection display, and the AI.
2. **TypeScript** (Supabase Edge Functions shared module): the **authority** for online games.

Engine responsibilities: board representation, legal move generation (incl. majority-rule sequence enumeration and Turkish-strike semantics), apply/undo, promotion, terminal detection, draw counters (§3.3), Zobrist hashing, serialization.

**Lock-step guarantee**: a shared **JSON test-vector suite** (positions → expected legal move sets, and full scripted games → expected states) lives in the repo and runs in both Dart (`flutter test`) and Deno (`deno test`) CI. Any rule change must update the vectors; both engines must pass. Perft-style move-count tests at several depths for all three presets guard the move generator.

Board representation: bitboards — three 64-bit ints (`white`, `black`, `kings`); 50 playable squares fit natively in Dart VM ints (this is the reason web builds are out of scope).

### 7.3 AI engine (Dart, on-device)

- **Negamax + alpha-beta pruning**, **iterative deepening** under a time budget, **transposition table** (Zobrist, ~2^18–2^20 entries), move ordering (TT move → largest captures → killers → history), **quiescence search** that extends through all forced-capture chains (mandatory capture makes this cheap and essential), forced-move extension (+1 ply when only one legal move).
- **Evaluation**: material (man = 100; king ≈ 300 with flying kings, ≈ 140 without — follows the toggle), advancement/tempo, center control & edge penalty, back-row guard, mobility, runaway-man bonus. Hand-tuned v1; pattern-learned eval (Scan-style) is a possible v2.
- Expected strength on a mid-range phone (Dart ≈ 0.5–2 M nodes/s): depth 6–8 in 0.3 s, 10–14 in 1 s, 14–18 in 3 s — Hard plays far above casual level. References: Chinook (8x8 — game weakly solved, perfect play is a draw), Scan / Kingsrow (10x10 state of the art).
- Runs in a **long-lived background isolate** (TT and killer/history tables stay warm across moves); board state passed as the 3-int encoding; hard time cutoff checked every ~1024 nodes; supports cancellation (user leaves the screen).

> **Implementation note (2026-08-13):** v1 implements server-side move
> validation as the shared JS engine running **inside Postgres via plv8**
> (`checkers_engine()` function) with pl/pgsql RPCs, instead of Edge
> Functions — the fallback anticipated by risk #5, chosen because it is
> fully transactional and needs no separate deployment pipeline on the
> self-hosted stack. The Dart and JS engines are locked together by a
> generated 668-vector test suite run in `flutter test` and `deno test`.

### 7.4 Backend: Supabase on Coolify

A new **Supabase project deployed as a Coolify service** on the existing instance (`http://192.168.101.240:8000/`) — Coolify's one-click Supabase stack (Postgres, GoTrue auth, PostgREST, Realtime, Storage, Edge Functions runtime, Studio). Setup checklist in §10 M0.

> **Public API URL: `https://checkers-api.contribution.club`** — published via the existing Cloudflare Tunnel (`ubuntu-home-server` connector) as a route to `http://localhost:80` (the server's proxy), alongside the other Coolify-hosted services. The Supabase project in Coolify must be configured with this as its API domain. Cloudflare terminates TLS; DNS is auto-managed by the tunnel.

#### 7.4.1 Auth

- **Supabase Auth**: Google (native `google_sign_in` → `signInWithIdToken`), Apple (`sign_in_with_apple` → `signInWithIdToken`, iOS only, required by App Store rules since Google is offered), and **Anonymous sign-in** (enabled in GoTrue).
- Anonymous → permanent upgrade via Supabase **identity linking** (`linkIdentity`) — mirrors kopo's Link Account flow, including the "anonymous account is unrecoverable" logout warning.
- A `profiles` row is upserted on every login (trigger on `auth.users` insert + client-side upsert of nickname/photo).

#### 7.4.2 Postgres schema (core tables)

```sql
profiles        (id uuid PK → auth.users, nickname text, photo_url text,
                 is_anonymous bool, rating int default 1200,
                 rated_games int, wins int, losses int, draws int,
                 created_at, updated_at)

games           (id uuid PK, status game_status,          -- waiting|playing|finished|abandoned
                 preset text, board_size int,             -- rules config
                 backward_capture bool, flying_king bool, majority_capture bool,
                 is_private bool, allow_social_join bool, rated bool,
                 host_uid uuid, created_at, started_at, finished_at,
                 state jsonb,                             -- authoritative: position, side_to_move,
                                                          -- draw counters, zobrist history,
                                                          -- clocks {bank_ms per seat}, turn_started_at,
                 turn_deadline_at timestamptz,
                 last_move jsonb, draw_offer_seat int,
                 result game_result, result_reason text,  -- white|black|draw + reason
                 winner_uid uuid)

game_players    (game_id, seat int,                       -- 0=white, 1=black
                 uid uuid, nickname text, photo_url text, -- snapshots
                 connected bool, rating_before int, rating_after int,
                 PK (game_id, seat))

game_moves      (game_id, ply int, seat int,
                 from_sq int, to_sq int, captured int[], promoted bool,
                 ms_spent int, played_at, PK (game_id, ply))

invites         (id uuid PK, game_id uuid, inviter_uid uuid, invitee_uid uuid,
                 status invite_status,                    -- pending|accepted|declined|expired|cancelled
                 created_at, expires_at)

player_presence (uid uuid PK, nickname, photo_url, rating,
                 busy_mode text,                          -- idle|pc|online
                 last_active_at, updated_at)

app_config      (id text PK,                              -- 'public'
                 config jsonb)                            -- allowed versions, store URLs, share message,
                                                          -- clock constants, feature flags

feedback        (id uuid PK, uid uuid, text text ≤2000, created_at)
```

**RLS (kopo's read-only-client principle)**: authenticated users can `SELECT` games/game_players/game_moves (public games; private ones only for participants), own profile writes limited to an allow-list, `player_presence` self-upsert only, `feedback` insert-only, `app_config` world-readable. **No client `INSERT`/`UPDATE` on games, game_players, game_moves, invites, or `profiles.rating`** — those change only via Edge Functions using the service role.

#### 7.4.3 Edge Functions (Deno/TS — all game mutations)

`join_online_game` · `leave_game` · `submit_move` · `claim_timeout` · `offer_draw` · `respond_draw` (accept/decline) · `resign` · `request_rematch` · `create_private_invites` · `respond_invite` · `create_social_game` · `join_social_game` · `reconnect_game` · `get_leaderboard` · `delete_account`.

Each mutation: load the game row `FOR UPDATE` (Postgres transaction — replaces kopo's RTDB transactions), validate with the shared TS engine (turn, legality, clock), apply, write `state` + `last_move` + append to `game_moves`, stamp `turn_deadline_at`, commit. Terminal states additionally compute ELO and update both `profiles` rows in the same transaction.

**Scheduled jobs (pg_cron)**: timeout/abandonment sweep (30 s), expire stale invites (1 min), clean stale presence (5 min), garbage-collect `waiting` games with no connected players (5 min).

#### 7.4.4 Realtime

- **Game channel**: clients (players + spectators) subscribe to `postgres_changes` on their `games` row (state snapshots — kopo's snapshot-rehydration model) and to `game_moves` inserts (drives move animation and future replay).
- **Watch list**: subscription on a `watchable_games` projection (public + `playing`).
- **Invites**: subscription on `invites` where `invitee_uid = me` (powers the global invite-listener service).
- **Presence**: Supabase Realtime **Presence** on a global lobby channel for the available-players directory, backed by the `player_presence` table heartbeat (30 s) for durability (kopo's dual presence model).
- Clock skew: client measures server-time offset via a lightweight RPC at session start and on resume.

#### 7.4.5 Storage

Bucket `avatars`, path `{uid}/avatar.jpg`, ≤ 1 MB JPEG, owner-write / public-read (kopo's storage rules translated to Storage policies).

### 7.5 Deep links

Android App Links + iOS Universal Links on `https://<app-domain>/party/<gameId>` with `assetlinks.json` / `apple-app-site-association` hosted on the app domain (can be served by a tiny static site on the same Coolify), plus `checkers://party/<id>` scheme fallback, plus a hosted fallback page for desktop clicks. Direct port of kopo's `PartyLinkService` + manifest/entitlement plumbing.

---

## 8. Non-functional requirements

- **i18n**: EN + FR at parity from day one (GetX translations, key constants, no hard-coded strings — kopo rule).
- **Performance**: 60 fps board animations; AI never blocks the UI isolate; move round-trip (submit → opponent render) < 1.5 s on a normal connection.
- **Integrity**: server validates every move and clock claim; RLS denies all client writes to game state; rating changes only server-side.
- **Resilience**: full state rehydration on reconnect; client-claimed + cron-backstopped timeouts; idempotent Edge Functions (move submissions carry the expected ply number — duplicates are rejected cleanly).
- **Force-update gate**: version allow-list in `app_config` checked at landing (kopo pattern).
- **Testing** (kopo conventions: `test/` mirrors `lib/`, mocktail, `Get.reset()`): engine test vectors + perft in both languages (§7.2); AI sanity tests (finds forced 2-for-1s, never selects illegal moves at any level); clock/ELO unit tests server-side; widget tests for board interaction.
- **Analytics**: deferred to v1.1 (kopo's Firebase Analytics is not ported; candidate: self-hosted PostHog on the same Coolify — see Open Questions). The `AnalyticsService` interface + no-op impl ship in v1 so call sites exist.
- **Privacy/legal**: privacy policy + terms hosted on the app domain; account deletion in-app (store requirement); no ads/tracking SDKs in v1 keeps the data-safety forms minimal.

---

## 9. Explicitly excluded (kopo features intentionally not ported)

Ads (AdMob + UMP + ATT), subscriptions/IAP + entitlements + receipt validation, stars economy, 4-player logic, player-messages admin inbox (v1.1 candidate), other-games catalog, how-to-play videos, Facebook page link.

---

## 10. Milestones

| # | Milestone | Contents |
|---|---|---|
| **M0** | Infra bootstrap | ✅ *Done (2026-08-13):* Coolify project `checkers` + service `supabase-checkers` (full stack running healthy); public API live at `https://checkers-api.contribution.club` (Cloudflare Tunnel → Traefik → Kong; verified 200 with anon key on `/auth/v1/health` and `/rest/v1/`); `checkers.contribution.club` tunnel route reserved for deep links. Note: Kong's Coolify domain uses the `http://` scheme deliberately — TLS terminates at Cloudflare and the tunnel delivers plain HTTP to Traefik; an `https://` scheme generates a redirect loop. *Remaining:* Auth providers (Google/Apple/anonymous) configuration in GoTrue; Flutter app skeleton with kopo structure, theme port, landing + auth + edit-profile + home shell with 4 tabs. |
| **M1** | Engine + PC play | Dart engine (all 3 presets + toggles, draw detection) passing the test-vector suite + perft; board UI with tap/drag input, highlights, animations; AI with 3 levels in an isolate; full offline PC game loop with How to Play. **App is playable offline end-to-end.** |
| **M2** | Online core | TS engine port passing the same vectors; schema + RLS + Edge Functions (`join/submit_move/claim_timeout/resign/reconnect/leave`); matchmaking lobby; live online games with clocks (15 s + 5 min bank), timeout losses; recorded moves. |
| **M3** | Social + draws | Draw offer/accept + all auto-draw rules live online; rematch; in-app invites + presence directory; share-link invites + deep links; abandonment handling. |
| **M4** | Watch + Top 30 | Spectator mode + Watch tab live list/search; ELO computation + Top 30 tab with podium + share-as-image; profile stats (W/L/D, rating). |
| **M5** | Polish & release | FR localization pass, sounds/haptics, feedback/rate/share/about, delete account, force-update gate, store assets, fastlane, closed beta. |
| **v1.1** | Fast follows | Game replays (Watch → Recent), PDN export, local PC-game history, analytics, player-messages inbox, sound pack. |

---

## 11. Risks & open questions

| # | Item | Notes |
|---|---|---|
| 1 | **Public domain** | ✅ **Resolved.** API: `checkers-api.contribution.club` (Cloudflare Tunnel route → Coolify Supabase, live and verified). Deep links: `checkers.contribution.club` (tunnel route created; needs a small static site serving `assetlinks.json` / AASA / `/party/*` fallback page when M3 lands). |
| 2 | Dual-engine drift (Dart + TS) | Mitigated by the shared test-vector + perft CI gate (§7.2); this is kopo's known biggest cost — the vector suite is the non-negotiable answer. |
| 3 | Turkish-strike & majority-rule correctness | The two classic draughts implementation bugs; explicit vectors for both, in both engines. |
| 4 | Self-hosted Supabase operational load | Backups (Postgres dumps via Coolify scheduled backups), upgrades, uptime on a single host. Acceptable for beta; revisit before scale. |
| 5 | Edge Functions on self-hosted Supabase | Coolify's stack includes the edge-runtime container, but DX (deploys, logs) is rougher than the hosted platform. Fallback if painful: implement mutations as **PostgREST RPCs (pl/pgsql)** for simple ops and keep only the engine-validated `submit_move` path in the functions runtime. |
| 6 | Single shared ELO across presets | v1 simplification; per-variant ratings possible later (column per preset). |
| 7 | Anonymous users on the leaderboard | Allowed (kopo parity) but enables throwaway smurfing; the 10-rated-games threshold mitigates. Revisit if abused. |
| 8 | Analytics choice | Recommend self-hosted PostHog on the same Coolify in v1.1; interface ships in v1. |
| 9 | Sounds | Kopo has zero audio; sounds for checkers are desirable but new ground (asset sourcing + `audioplayers`). Committed as "M5 if time, else v1.1". |

---

## Appendix A — Rule/config matrix (quick reference)

| Setting | Values | Default |
|---|---|---|
| Board size | 10x10 / 8x8 | **10x10** |
| Backward pawn capture | on / off | **on** |
| Flying king | on / off | **on** (off ⇒ king moves/captures one square) |
| Majority capture | (hidden) follows backward capture | on |
| Preset | International / Brazilian / American / Custom | **International** |
| Turn timer | server config | **15 s** |
| Time bank | server config | **5 min** |
| Rated | matchmaking only | — |

## Appendix B — Terminal states

| Result | Reasons |
|---|---|
| Win/Loss | opponent has no pieces · opponent blocked (no legal move) · resignation · timeout (bank depleted) · abandonment (disconnected > 2 min) |
| Draw | agreement · threefold repetition · 25-move king rule (Int'l/Brazilian) · 16-move endgame rule · 5-move endgame rule · 40-move rule (American) |
