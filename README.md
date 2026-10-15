# Checkers

Draughts/checkers for mobile (Flutter), modeled on the architecture and look
& feel of the kopo card game. Play against the computer (3 difficulty
levels) or online — public matchmaking, friend invites, shareable links —
with live spectating and an ELO Top 30.

See [PRD.md](PRD.md) for the full product spec.

## Rules variants

| Preset | Board | Backward pawn capture | Flying kings |
|---|---|---|---|
| International (default) | 10x10 | yes | yes |
| Brazilian | 8x8 | yes | yes |
| American | 8x8 | no | no |

Both toggles are individually configurable for PC games. Draw rules follow
FMJD (threefold repetition, 25-move king rule, 16/5-move endgame rules) for
the international family and the 40-move rule for American. Online clocks:
15 s per move plus a 5-minute bank; an empty bank loses on time.

## Architecture

- **Flutter + GetX** (kopo conventions): `lib/modules/<feature>/{binding,controller,view}`,
  service interfaces + Convex implementations (registered in
  `lib/bindings/initial_binding.dart`), EN/FR translations.
- **Rules engine** ([lib/engine/](lib/engine/)): pure-Dart bitboard engine,
  perft-validated. AI: negamax + alpha-beta + iterative deepening +
  transposition table + quiescence, in a background isolate.
- **Server-authoritative online play**: the same rules run as JavaScript
  in Convex mutations ([supabase/engine/engine.js](supabase/engine/engine.js),
  copied to `backend/convex/lib/engine.js` by `scripts/build_engine_convex.sh`) —
  clients only read and call functions; every move is validated server-side.
  The two engines are locked together by a generated test-vector suite.
- **Backend**: [Convex](https://convex.dev) in [backend/](backend/)
  (schema, queries/mutations, crons, admin HTTP API). Sign-in is Firebase
  Auth (guest, Google, Apple); Convex verifies the Firebase ID tokens. The
  Flutter client is [dartvex](https://pub.dev/packages/dartvex).
  Migration from the former self-hosted Supabase stack:
  [backend/MIGRATION.md](backend/MIGRATION.md).

## Development

```sh
flutter pub get
flutter test                                     # unit + widget tests
dart run tool/generate_vectors.dart              # regenerate engine vectors
(cd backend && npm install && npm test)          # Convex functions + engine parity
flutter test integration_test -d <device>        # e2e (live dev backend)
```

Backend development: `cd backend && npx convex dev` pushes `convex/` to the
dev deployment on every change (the app targets it by default; override
with `--dart-define=CONVEX_URL=...`). After editing
`supabase/engine/engine.js`, run `scripts/build_engine_convex.sh`.
`supabase/` and the `scripts/test_*_flow` scripts describe the legacy stack
that stays up until the account-handoff window closes.
