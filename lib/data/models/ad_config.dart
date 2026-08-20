/// Remote ad configuration (kopo parity), stored in the `app_config`
/// row's JSON under `ads`.
class AppAdConfig {
  const AppAdConfig({
    required this.enabled,
    required this.interstitialFrequency,
    required this.android,
    required this.ios,
  });

  const AppAdConfig.disabled()
    : enabled = false,
      interstitialFrequency = 15,
      android = const AppPlatformAdConfig(),
      ios = const AppPlatformAdConfig();

  final bool enabled;

  /// Show an interstitial every Nth recorded event (checkers uses 15).
  final int interstitialFrequency;
  final AppPlatformAdConfig android;
  final AppPlatformAdConfig ios;

  factory AppAdConfig.fromJson(Object? rawJson) {
    if (rawJson is! Map) {
      return const AppAdConfig.disabled();
    }
    final json = rawJson.cast<String, dynamic>();
    final frequency = json['interstitialFrequency'];
    return AppAdConfig(
      enabled: json['enabled'] == true,
      interstitialFrequency: frequency is int && frequency > 0 ? frequency : 15,
      android: AppPlatformAdConfig.fromJson(json['android']),
      ios: AppPlatformAdConfig.fromJson(json['ios']),
    );
  }
}

class AppPlatformAdConfig {
  const AppPlatformAdConfig({this.bannerAdUnitId, this.interstitialAdUnitId});

  final String? bannerAdUnitId;
  final String? interstitialAdUnitId;

  factory AppPlatformAdConfig.fromJson(Object? rawJson) {
    if (rawJson is! Map) {
      return const AppPlatformAdConfig();
    }
    final json = rawJson.cast<String, dynamic>();
    return AppPlatformAdConfig(
      bannerAdUnitId: _readOptionalString(json, 'bannerAdUnitId'),
      interstitialAdUnitId: _readOptionalString(json, 'interstitialAdUnitId'),
    );
  }

  static String? _readOptionalString(Map<String, dynamic> json, String field) {
    final value = json[field];
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }
}
