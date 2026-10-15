# App Review investigation — September 15, 2026

## Rejection

- App: Checkers Tournaments (`cd.dame`, App Store ID `6806184531`).
- Version/build: `1.1.1 (4)`.
- Submission: `e89f472b-4eeb-4ad1-8929-8f8c03acfa9a`.
- Guideline: 2.1(a), Performance — App Completeness.
- Apple could not enter the app using Sign in with Apple or Play as Guest.
- Review devices: iPhone 17 Pro Max and iPad Air 11-inch (M3), running
  iOS/iPadOS 27.0 according to the review message.
- Evidence: `~/Downloads/Screenshot-0915-133722.png`,
  `Screenshot-0915-133727.png`, and `Screenshot-0915-133731.png`.

## Confirmed findings

The archived build in `build/ios/archive/Runner.xcarchive` and the Xcode
archive dated August 29 both identify themselves as `cd.dame`, version
`1.1.1`, build `4`. Their compiled app contains `https://api.dame.cd`.

The public endpoint currently returns HTTP 530 with Cloudflare Tunnel
error 1033 for all three checks, including requests with the app's API key:

- `/auth/v1/health`
- `/auth/v1/settings`
- `/rest/v1/app_config?id=eq.public&select=id`

The error names `checkers-api.contribution.club`, matching the upstream in
`scripts/api_proxy_worker.js`. Cloudflare documents 1033 as no healthy
tunnel connector available to receive traffic:
https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-1xxx-errors/error-1033/

Both sign-in methods depend on Supabase Auth: guest login calls
`signInAnonymously`, and native Apple login exchanges its credential using
`signInWithIdToken`. This outage is sufficient to cause both reported
failures. Historical server logs have not yet been retrieved, so the exact
outage start time and whether it was the sole problem during review remain
unconfirmed.

The documented Supabase/Coolify host is `linux-pc` at `192.168.101.240`.
SSH timed out and the Coolify endpoint on port 8000 was unreachable from
the Mac on the same subnet. Whether the server is powered off, disconnected,
or has changed IP address has not been confirmed.

## Recovery and validation still required

1. Restore access to the existing server (power, network, or corrected IP).
2. Inspect Supabase and cloudflared service/container state and logs; restore
   the failed existing services. Check their restart policies and the reason
   they became unavailable before making changes.
3. Verify the public health and settings endpoints return JSON successfully,
   and confirm anonymous and Apple authentication are enabled. Check the
   Apple provider audience includes the shipped bundle identifier `cd.dame`.
4. Test guest signup, profile creation, home entry, and a game from a clean
   install on both iPhone and iPad. The existing
   `integration_test/app_e2e_test.dart` covers guest signup/profile/navigation;
   `integration_test/pc_game_e2e_test.dart` covers playing against the computer.
5. Verify native Sign in with Apple end to end on a supported signed device,
   including the backend token exchange. An authentication settings check or
   a mocked unit test does not establish that this flow works.
6. Once verified, prepare an accurate reply to App Review describing the
   restored service and actual devices/builds tested. Determine whether the
   existing build can be resubmitted or a binary change is also necessary.

## Recovery update

The server became reachable after a reboot on September 15. During startup,
the public API progressed from a tunnel error to HTTP 502/404, then recovered.
Docker initially had heavy startup load; the existing services recovered
without an agent-initiated restart or configuration change.

Verified after recovery:

- Public Auth health and settings endpoints return HTTP 200 JSON.
- Anonymous signup is enabled; a newly created guest received a valid session.
- The session successfully accessed `/auth/v1/user`.
- The guest could create and read its profile and read app configuration.
- Apple authentication is enabled with client ID `cd.dame`, matching build 4.
- Checkers Auth, Kong, database, and Storage containers are healthy and use
  the existing `unless-stopped` restart policy.

The native Apple credential flow and complete iPhone/iPad app flows still
need verification. Server-level checks do not replace device testing.

### Additional issue observed during test cleanup

The existing `delete_account` RPC returned HTTP 403 / PostgreSQL `42501`:
“Direct deletion from storage tables is not allowed. Use the Storage API
instead.” Migration `0007_account.sql` deletes directly from
`storage.objects`, which the current Storage service rejects. The temporary
test account was removed separately through the supported Auth Admin API.
This was a separate account-deletion defect, rather than the reported sign-in
rejection. No bypass of Storage protection was applied.

### Account-deletion fix — version 1.2.0 (5)

- Added `AccountDeletionService`: removes the avatar using the existing
  Storage API service before calling the account RPC. Failure keeps the
  session and account available for retry; successful deletion signs out.
- Applied migration `0037_account_deletion_storage_api.sql` to production.
  The RPC no longer deletes from `storage.objects`; it checks for remaining
  avatars before modifying account data. Earlier builds with avatars cannot
  complete deletion until upgraded to the client that performs file cleanup.
- Applied `0038_allow_version_1_2_0.sql`, adding 1.2.0 to both platform
  allowlists while retaining previously allowed versions.
- Updated `pubspec.yaml` to `1.2.0+5` and the displayed app version to 1.2.0.
- Targeted service/widget/auth/profile/version tests passed (25 unique tests).
  Static analysis of the changed Dart implementation and tests passed.
- `python3 scripts/test_account_deletion.py` passed against the public API:
  accounts with and without avatars are removed, repeated Storage cleanup is
  safe, and the RPC refuses to delete an account while its avatar remains.
  Both temporary test accounts and their uploaded files were removed.
- An unsigned iOS release build compiled successfully; its Info.plist confirms
  bundle `cd.dame`, version 1.2.0, build 5. It is not a signed uploadable archive.

## Current disposition

The backend outage has cleared and guest authentication/profile operations
pass. The account-deletion defect is fixed in the backend and new client.
Clean-install guest sign-in, profile creation, navigation, and account deletion
also passed on isolated iPhone 17 Pro Max and iPad Pro 13-inch (M5) simulators
running iOS/iPadOS 26.3. The user subsequently confirmed everything is working
in response to the outstanding Apple sign-in check and approved resubmission.

Version 1.2.0 (5) was signed and successfully uploaded on September 15 at
13:04 SAST. Apple finished processing the build. Build 5 is attached to version
1.2.0. With explicit user approval, final resubmission succeeded at 13:19 SAST;
App Store Connect confirms Waiting for Review. The approved reviewer notes
were submitted unchanged; existing English/French descriptions and screenshots
are retained. Release remains manual after approval.
See `app-store-1.2.0-submission.md` for artifacts and exact notes.
The user reports the Paid Apps Agreement issue is resolved.
