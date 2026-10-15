# Supabase → Convex cutover runbook

The backend moved from the self-hosted Supabase stack (`api.dame.cd` →
Coolify) to Convex Cloud (team `tresor-mvumbi`, project `checkers`).
Players sign in with Firebase Auth (project `checkers-club`); Convex
verifies the Firebase ID tokens (`convex/auth.config.ts`).

Deployments: dev `silent-donkey-723` (`npx convex dev` in `backend/`),
prod `harmless-loris-857` (https://harmless-loris-857.convex.cloud, HTTP
actions at https://harmless-loris-857.convex.site). Release builds of the
app use prod automatically (`lib/core/config/convex_config.dart`).
A full rehearsal of steps 4–6 against real data ran on dev on 2026-10-15:
every table imported, files copied, ELO and points leaderboards identical
to Supabase.

## 1. Production deployment (one time) — DONE 2026-10-15

Deployed and all env vars set; the admin API secret is in
`~/.config/checkers/convex_admin_api_secret`. Re-run `npx convex deploy`
after backend changes.

```bash
cd backend
npx convex deploy            # creates/updates the prod deployment
npx convex env set --prod RESEND_API_KEY      "$(cat ~/.config/checkers_resend_key)"
npx convex env set --prod PUSH_RELAY_URL      https://checkers-push.tresormvumbi.workers.dev/send
npx convex env set --prod PUSH_RELAY_KEY      "$(cat ~/.config/checkers/push_relay_key)"
npx convex env set --prod ADMIN_API_SECRET    "$(openssl rand -hex 32)"
npx convex env set --prod SUPABASE_LEGACY_URL https://api.dame.cd
npx convex env set --prod SUPABASE_LEGACY_ANON_KEY "$(cat ~/.config/checkers_supabase_anon_key)"
```

Note the prod URLs printed by `deploy` (`https://<name>.convex.cloud` and
`.convex.site`). Never set `MIGRATION_ALLOW_WIPE` on prod.

## 2. Admin console

```bash
npx wrangler secret put CONVEX_SITE_URL  --config wrangler.admin.jsonc   # https://harmless-loris-857.convex.site
npx wrangler secret put ADMIN_API_SECRET --config wrangler.admin.jsonc   # ~/.config/checkers/convex_admin_api_secret
npx wrangler deploy --config wrangler.admin.jsonc
```

`SUPABASE_URL` / `SERVICE_KEY` worker secrets can be deleted afterwards.

## 3. App release 2.0.0

- Release builds already target prod (`ConvexConfig.productionUrl`).
- `pubspec.yaml` version `2.0.0+N`; submit both stores with **manual
  release** and wait for approval.

## 4. Maintenance window

1. Freeze the old app: in Supabase `app_config` set
   `allowed_android_versions` / `allowed_ios_versions` to `["2.0.0"]`
   (old clients now show the update screen and stop writing).
2. Wait for live games to end (`select count(*) from games where status='playing'`).
3. Export and import:
   ```bash
   python3 backend/scripts/export_supabase.py backend/.migration/staging.jsonl
   cd backend
   npx convex import --prod --table migrationStaging --replace backend/.migration/staging.jsonl
   npx convex run --prod migration:start
   npx convex run --prod migration:status     # until "done"
   npx convex run --prod migration:verify
   ```
   Expected differences: `profiles` has extra placeholder rows (players
   referenced by devices/games who never had a profile row);
   `auth_identities` skips links of users without a profile.
4. In the Convex admin console settings, make sure the allowed versions
   include `2.0.0` (the imported config still lists the 1.x versions).
5. Clean up: `npx convex run --prod migration:clearStaging` (repeat until
   it returns < 4000) and delete `backend/.migration/staging.jsonl`.

## 5. Go live

Publish 2.0.0 in both stores. On first launch the app sends the
Supabase session it still holds to `account:claimLegacy`, so every player
(guests included) keeps their profile, ELO, points and history. Google and
Apple users who reinstall are re-linked by their provider identity.

## 6. Decommission (≈90 days later)

- Remove `SUPABASE_LEGACY_*` from Convex, `supabase_flutter`,
  `LegacyAccountHandoff` and `_initLegacySupabaseForHandoff` from the app.
- Stop the Coolify `supabase-checkers` stack, the `api_proxy_worker`
  route and the tunnel route for `checkers-api.contribution.club`.
- `scripts/db_apply.sh`, `scripts/test_*_flow.*` and `supabase/` become
  history; the Convex suite (`npm test` in `backend/`) replaces them.
