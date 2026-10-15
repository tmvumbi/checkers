import 'package:flutter/foundation.dart';

/// Convex deployment the app talks to (project `checkers`, team
/// tresor-mvumbi): release builds use production, debug/profile builds the
/// dev deployment. Override either with `--dart-define=CONVEX_URL=...`.
abstract final class ConvexConfig {
  static const String productionUrl = 'https://harmless-loris-857.convex.cloud';
  static const String developmentUrl = 'https://silent-donkey-723.convex.cloud';

  static const String _override = String.fromEnvironment('CONVEX_URL');

  static String get url => _override.isNotEmpty
      ? _override
      : (kReleaseMode ? productionUrl : developmentUrl);
}
