# App review follow-up — 15 October 2026

## Latest Apple rejection

App: Checkers Tournaments (`cd.dame`, App Store ID 6806184531).
The latest message is dated 21 September 2026 and concerns version 1.2.0 (6),
reviewed on iPhone 17 Pro Max with iOS 27.0.

- Guideline 5.1.1(iv): after declining App Tracking Transparency, a second
  prompt asks for tracking/cookie consent. Apple's screenshot identifies
  this as Google's UMP personalized advertising consent form.
- Guideline 2.1(a): Sign in with Apple and Play as Guest return an error.

Review record:
https://appstoreconnect.apple.com/apps/6806184531/distribution/reviewsubmissions/details/e89f472b-4eeb-4ad1-8929-8f8c03acfa9a

## Changes

`GoogleAdService` now stops before invoking UMP or Google Mobile Ads on iOS
unless ATT returns `authorized`. Denied, restricted, pending, and unsupported
states leave ads and the advertising privacy-options entry disabled. Google
Mobile Ads initialization also waits until UMP permits ad requests.

This means users declining tracking receive no Google ads in that session.
Normal gameplay remains available. Android continues to use UMP consent.

The home profile now keeps a live subscription instead of accepting only the
first cached Convex result. This fixes a blank nickname immediately after
saving a new profile. The subscription is cancelled when the home controller
closes.

The existing 2.0.0 release replaces the old authentication backend with
Firebase Auth and Convex. The production Firebase Apple provider was verified
enabled via the read-only Identity Toolkit configuration API. The user confirmed
on 15 October that native Apple sign-in was already verified and explicitly
authorized submission. This verification is user-reported, not agent-executed.

## Validation

- 38 focused tests pass across ads, authentication, session restoration,
  profile editing, home tabs, account deletion, and profile subscription cleanup.
- Static analysis of all changed Dart files reports no issues.
- A live isolated iPhone 17 Pro Max simulator check against production Convex
  confirmed guest sign-in, saved nickname retrieval, and account deletion.
- The first full UI run reached home but timed out on its nickname assertion.
  The simulator had an outstanding native notification-permission dialog;
  that optional permission was declined. A diagnostic rerun also identified
  the stale profile-cache behavior above; the saved backend nickname itself
  was correct. All diagnostic guest accounts were deleted.
- After the profile subscription fix, the unchanged full UI smoke test passed
  against production on iOS 26.3: guest login, profile creation with visible
  nickname, home navigation, and account deletion. Ads were disabled for this
  authentication test; ATT/UMP branching was verified by the focused tests.

## Android submission

Submitted production release 2.0.0 (7), using the existing signed release bundle.
English and French release notes describe the online-service update and
preserved player profiles/history. Google Play confirms “Changes in review”; automated quick checks are running
and will forward the release when successful. Managed publishing is ON, so
approval does not automatically publish the update. Device support is unchanged.

https://play.google.com/console/u/0/developers/7505188716074533803/app/4972353064259469829/publishing

Android build 7 is the pre-existing release artifact. The privacy and profile
refresh changes in this follow-up are packaged in iOS build 8.

## References

https://developer.apple.com/app-store/user-privacy-and-data-use/
https://developers.google.com/admob/flutter/privacy
https://docs.cloud.google.com/identity-platform/docs/reference/rest/v2/projects.defaultSupportedIdpConfigs/get

## iOS artifact

Signed App Store IPA export succeeded for `cd.dame`, version 2.0.0, build 8.
Artifact: `build/review-2026-10-15/checkers-2.0.0-8.ipa` (about 35 MiB).
The original build 7 IPA is preserved alongside it. Build 8 was successfully
uploaded through Xcode at 18:43 SAST on 15 October 2026; Apple processing
completed, and build 8 was attached to App Store version 2.0.0. The Flutter exporter reports
an existing default launch-image placeholder warning; export still succeeds.

The upload reported a missing `objective_c.framework` dSYM warning. Apple
accepted the binary; this warning affects crash symbolication for that dependency.

## iOS review notes

Version 2.0.0 replaces the previous authentication backend. Guest sign-in,
profile creation, navigation, and account deletion have been tested against
the production service on an iPhone 17 Pro Max simulator (iOS 26.3).

Build 8 also changes advertising consent: if the user chooses Ask App Not to
Track, or tracking permission is otherwise unavailable, the app does not
initialize Google Mobile Ads, show Google's UMP consent form, or request
Google ads. The advertising privacy-options menu is hidden in that state.

To access the app without credentials: choose Play as Guest, enter a nickname,
and save. Account deletion is under More → Delete account. Google and Apple
sign-in remain optional.

The app owner has also confirmed successful native Sign in with Apple testing.

## Reproduction

```sh
flutter test --no-pub test/modules/auth_flow_test.dart test/modules/home_tabs_test.dart test/modules/edit_profile_photo_test.dart test/services/account_deletion_service_test.dart test/services/ad_service_test.dart test/services/convex_session_test.dart
flutter test integration_test/account_deletion_e2e_test.dart -d <isolated-iOS-simulator> --dart-define=CONVEX_URL=https://harmless-loris-857.convex.cloud --dart-define=CHECKERS_DISABLE_ADS=true --no-pub
flutter build ipa --release --build-name=2.0.0 --build-number=8 --export-options-plist=build/review-2026-10-15/ExportOptions.plist --no-pub
```


## iOS submission confirmed

Resubmitted on 15 October 2026 at 18:52 SAST. App Store Connect confirms
**Waiting for Review** for **iOS App 2.0.0 (8)** under submission
`e89f472b-4eeb-4ad1-8929-8f8c03acfa9a`.

Review notes address both September rejection reasons and include the owner's
confirmation of successful Apple sign-in testing. Manual release remains
selected; approval will not automatically publish the app.
