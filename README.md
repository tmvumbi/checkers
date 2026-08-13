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
  service interfaces + Supabase implementations, EN/FR translations.
- **Rules engine** ([lib/engine/](lib/engine/)): pure-Dart bitboard engine,
  perft-validated. AI: negamax + alpha-beta + iterative deepening +
  transposition table + quiescence, in a background isolate.
- **Server-authoritative online play**: the same rules run as JavaScript
  inside Postgres (plv8, [supabase/engine/engine.js](supabase/engine/engine.js)) —
  clients are read-only; every move goes through security-definer RPCs.
  The two engines are locked together by a generated test-vector suite.
- **Backend**: self-hosted Supabase (Coolify), public API at
  `https://checkers-api.contribution.club`.

## Development

```sh
flutter pub get
flutter test                                     # unit + widget tests
dart run tool/generate_vectors.dart              # regenerate engine vectors
deno test --allow-read supabase/engine/engine_test.ts   # JS/Dart engine parity
flutter test integration_test -d <device>        # e2e (live backend)
```

Database migrations live in [supabase/migrations/](supabase/migrations/) and
are applied with `scripts/db_apply.sh <file>`; after editing
`supabase/engine/engine.js`, run `scripts/build_engine_sql.sh` to regenerate
the plv8 migration. Server-flow smoke tests: `scripts/test_online_flow.sh`
and `scripts/test_social_flow.sh`.
