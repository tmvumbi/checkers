abstract final class AppStrings {
  static const String appName = 'Checkers';

  /// Must be kept in sync with the version in pubspec.yaml.
  static const String currentAppVersion = '1.0.1';

  static const String avatarPlaceholder =
      'assets/images/avatar_placeholder.png';

  static const String partyLinkHost = 'checkers.contribution.club';
  /// Reverse-DNS so the scheme is unique: the bare `checkers://` scheme is
  /// also claimed by unrelated App Store apps (the Checkers restaurant
  /// chain), and iOS picks the winner arbitrarily when schemes collide.
  static const String partyLinkScheme = 'club.contribution.checkers';

  /// Still accepted for links shared before the rename.
  static const String legacyLinkScheme = 'checkers';
}
