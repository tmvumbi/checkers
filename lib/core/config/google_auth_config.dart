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
}
