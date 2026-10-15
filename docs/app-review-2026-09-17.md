# App Review — September 17, 2026

## Reported issue

Apple rejected version 1.2.0 (5) under Guideline 4: Sign in with Apple button artwork/design. The review device was iPad Air 11-inch (M3). Evidence: `/Users/tresorm/Downloads/Screenshot-0917-104303.png`.

## Fix — version 1.2.0 (6)

The iOS/iPadOS landing screen now embeds AuthenticationServices' native `ASAuthorizationAppleIDButton` using a Flutter platform view. The system provides the logo, text, and accessibility. It uses the built-in Continue type and white style, a supported 8-point corner radius, and a 64-point height matching other login controls. The existing authentication service remains unchanged. A per-view method channel forwards taps and synchronizes the busy/disabled state; disposal removes handlers. Other platforms use the existing sign_in_with_apple package's standard button.

The public version remains 1.2.0; build number is incremented from 5 to 6. No backend migration or version-gate change is needed.

## Validation

- Targeted auth flow/version tests: 6 passed.
- Native button bridge regression: passed (callback forwarding/replacement, disabled taps ignored, disposal).
- Changed Dart files and regression test: static analysis clean.
- iPad Air 11-inch (M3), iPadOS 26.3: visual check confirms official Apple logo and white button; tapping opens the native Apple Account prompt. This fresh simulator has no Apple Account, so a credential exchange was not performed.
- Guest login, profile creation, home navigation, and account deletion passed on the iPad simulator.
- iPhone 17 Pro Max, iOS 26.3: guest login, profile creation, navigation, and account deletion passed; the updated native button was visually verified.
- Screenshots: `build/review-2026-09-17/ipad-native-apple-button.png` and `build/review-2026-09-17/iphone-native-apple-button.png`.
- Signed archive/export completed. The IPA signature, App Store distribution
  profile, `cd.dame` identifier, version 1.2.0, build 6, and Apple sign-in
  entitlement were verified.
- Signed IPA: `build/releases/checkers-1.2.0+6.ipa`.
- SHA-256: `13c5d72d74ab8c93880763c3ce8f1d221ddbd1d62e54eb429035e9328504bec7`.
- Upload succeeded September 17 at 16:11 SAST; Apple completed processing
  (build ID `e9236d8c-f2a2-423b-8d76-e98fe58f4fd1`).
  Xcode reported a non-blocking missing dSYM warning for `objective_c.framework`.
  The upload completed successfully; this warning affects crash symbolication
  for that dependency.

Apple reference: https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidbutton

## Reviewer notes saved

Resubmission for Guideline 4 — version 1.2.0 (build 6).

We replaced the custom blue “Continue with Apple” button with Apple's native ASAuthorizationAppleIDButton from AuthenticationServices on iOS and iPadOS. It uses Apple's built-in Continue button type and white style, including the system-provided Apple logo, typography, and accessibility. Only its supported corner radius is customized. No custom Apple logo artwork is used on iOS or iPadOS.

The native button opens the existing Sign in with Apple authentication flow. We verified its appearance and activation on an iPad Air 11-inch (M3) simulator running iPadOS 26.3. The button is disabled while authentication is in progress.

To review without a pre-existing account:
1. Open the app and choose “Play as Guest.”
2. Enter a nickname and save the profile.
3. From the home screen, play against the computer, play online, or open tournaments.

Google and Apple sign-in are optional. An internet connection is required to sign in, including as a guest. Account deletion is available under More → Delete account.

The app contains banner and interstitial ads and presents consent and App Tracking Transparency prompts where applicable.

Privacy Policy: https://dame.cd/privacy
Terms of Use: https://dame.cd/terms

## Listing and submission

Existing public descriptions are retained. Release remains manual after approval.
Signing, upload, and resubmission were authorized by the user's September 17
request. The exact reviewer notes above were shared in the conversation before
the final submission. Build 6 replaced rejected build 5; the review item was
updated and resubmitted September 17 at **16:25 SAST**. App Store Connect
confirms **Waiting for Review** for **1.2.0 (6)**.

https://appstoreconnect.apple.com/apps/6806184531/distribution/reviewsubmissions/details/e89f472b-4eeb-4ad1-8929-8f8c03acfa9a
