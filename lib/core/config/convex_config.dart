/// Convex deployment the app talks to (project `checkers`, team
/// tresor-mvumbi). Override per build with `--dart-define=CONVEX_URL=...`;
/// release builds must point at the production deployment.
abstract final class ConvexConfig {
  static const String url = String.fromEnvironment(
    'CONVEX_URL',
    defaultValue: 'https://silent-donkey-723.convex.cloud',
  );
}
