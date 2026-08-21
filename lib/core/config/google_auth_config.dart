/// Google OAuth client configuration (Google Cloud project checkers-club).
///
/// These are public identifiers, not secrets. GoTrue accepts ID tokens whose
/// audience is either the web or the iOS client (GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID
/// on the server lists both).
abstract final class GoogleAuthConfig {
  /// Web OAuth client: the `serverClientId` the native flows request ID
  /// tokens for on Android, and the primary GoTrue audience.
  static const String serverClientId =
      '558217605941-1es9bt24mjd8f9jfpcj9tvd7o8g95ecm.apps.googleusercontent.com';

  /// iOS OAuth client. Passed explicitly instead of relying on
  /// GoogleService-Info.plist being bundled — the app configures Firebase
  /// programmatically (firebase_options.dart), so that plist is not part
  /// of the Xcode resources and the SDK would find no client id.
  static const String iosClientId =
      '558217605941-krshtf5j0ljfd8v6uv076a2s7ri1ct3m.apps.googleusercontent.com';
}
