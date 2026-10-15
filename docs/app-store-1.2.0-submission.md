# Checkers Tournaments — 1.2.0 (5)

## Release artifacts

- Bundle identifier: `cd.dame`
- App Store ID: `6806184531`
- Distribution team: `TKDDB59257`
- Signed package: `build/releases/checkers-1.2.0+5.ipa`
- Archive: `build/ios/archive/Runner.xcarchive`

The IPA's signature, App Store distribution profile, version, build number,
and Sign in with Apple entitlement were verified locally.

Upload succeeded on September 15, 2026 at 13:04 SAST. App Store Connect
assigned build ID `3d7c845d-d04b-4885-b161-f72781fa42e4`; processing completed.
Build 5 is attached to version 1.2.0. Following explicit user approval,
resubmission succeeded on September 15, 2026 at 13:19 SAST. App Store Connect
confirms **Waiting for Review** for version 1.2.0 (5).
Xcode reported a non-blocking missing dSYM warning for `objective_c.framework`.
This affects symbolication of crashes in that dependency, not upload acceptance.

Clean-install guest sign-in, profile creation, navigation, and account deletion
passed on isolated iPhone 17 Pro Max and iPad Pro 13-inch (M5) simulators running
iOS/iPadOS 26.3. Regression test: `integration_test/account_deletion_e2e_test.dart`.

## Listing

The existing English and French descriptions and screenshots are retained.
No new public app description was written for this bug-fix resubmission.
The version draft is 1.2.0 and release remains manual after approval.

## Reviewer notes saved in the draft

Resubmission for Guideline 2.1(a) — version 1.2.0 (build 5).

We identified an authentication backend outage that prevented guest login and the backend exchange used by Sign in with Apple. The service has been restored. Live backend tests now pass for fresh guest signup, authenticated session validation, profile creation, and app configuration access.

Clean-install guest sign-in, profile creation, home navigation, and account deletion also passed on iPhone 17 Pro Max and iPad Pro 13-inch simulators running iOS/iPadOS 26.3.

This build also fixes account deletion: avatar files are removed through the Storage API before the account is deleted. Deletion with and without an avatar, and retry behavior, have been verified.

To review without a pre-existing account:
1. Open the app and choose “Play as Guest.”
2. Enter a nickname and save the profile.
3. From the home screen, play against the computer, play online, or open tournaments.

Google and Apple sign-in are optional. An internet connection is required to sign in, including as a guest. Account deletion is available under More → Delete account.

The app contains banner and interstitial ads and presents consent and App Tracking Transparency prompts where applicable.

Privacy Policy: https://dame.cd/privacy
Terms of Use: https://dame.cd/terms

## Submission approval

The user reviewed the exact notes and explicitly authorized final submission:
“please go ahead with submission, all is working fine.” This also confirmed
the previously outstanding Apple login check at the user level; the agent
did not independently execute the native Apple credential flow. The approved
notes were submitted unchanged.

Submitted review:
https://appstoreconnect.apple.com/apps/6806184531/distribution/reviewsubmissions/details/e89f472b-4eeb-4ad1-8929-8f8c03acfa9a
