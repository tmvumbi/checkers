import 'package:get/get.dart';

import 'convex/convex_gateway.dart';

/// Reads the public remote config (`app_config` row `public`): version gate,
/// AdMob settings, clocks, points rules. Readable before sign-in.
abstract class AppConfigService {
  /// The config object, or an empty map when none is published.
  Future<Map<String, dynamic>> fetchPublicConfig();
}

class ConvexAppConfigService implements AppConfigService {
  ConvexAppConfigService({ConvexGateway? gateway}) : _gatewayOverride = gateway;

  final ConvexGateway? _gatewayOverride;
  ConvexGateway get _convex => _gatewayOverride ?? Get.find<ConvexGateway>();

  @override
  Future<Map<String, dynamic>> fetchPublicConfig() async {
    // Read at start-up before anything else: never hold the landing
    // screen hostage to a slow network (callers fail open).
    final config = await _convex
        .query('config:getPublic')
        .timeout(const Duration(seconds: 5));
    return config is Map ? config.cast<String, dynamic>() : const {};
  }
}
