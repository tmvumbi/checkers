import 'package:checkers/data/models/ad_config.dart';
import 'package:checkers/services/ad_service.dart';
import 'package:checkers/services/tracking_consent_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTrackingConsent extends TrackingConsentService {
  @override
  Future<TrackingConsentStatus> requestAuthorizationIfNeeded() async {
    return TrackingConsentStatus.notSupported;
  }
}

class _FakeInterstitial extends LoadedInterstitialAd {
  _FakeInterstitial(this.onShown);

  final void Function() onShown;
  VoidCallback? _onDismissed;

  @override
  void setFullScreenCallbacks({
    required VoidCallback onDismissed,
    required VoidCallback onFailedToShow,
  }) {
    _onDismissed = onDismissed;
  }

  @override
  Future<void> show() async {
    onShown();
    _onDismissed?.call();
  }

  @override
  Future<void> dispose() async {}
}

const _config = AppAdConfig(
  enabled: true,
  interstitialFrequency: 15,
  android: AppPlatformAdConfig(
    bannerAdUnitId: 'banner-android',
    interstitialAdUnitId: 'interstitial-android',
  ),
  ios: AppPlatformAdConfig(),
);

GoogleAdService _service({
  required void Function() onInterstitialShown,
  AppAdConfig config = _config,
}) {
  return GoogleAdService(
    trackingConsentService: _FakeTrackingConsent(),
    initializeAds: () async {},
    gatherConsent: () async => true,
    loadPrivacyOptionsRequirement: () async => false,
    presentPrivacyOptions: () async {},
    loadAdConfig: () async => config,
    loadInterstitialAd: (adUnitId, request) async =>
        _FakeInterstitial(onInterstitialShown),
    loadPreferences: SharedPreferences.getInstance,
    disableAdsForLocalTesting: false,
    useTestAdUnits: false,
    targetPlatform: TargetPlatform.android,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppAdConfig', () {
    test('parses full remote json', () {
      final config = AppAdConfig.fromJson({
        'enabled': true,
        'interstitialFrequency': 15,
        'android': {'bannerAdUnitId': 'b-a', 'interstitialAdUnitId': 'i-a'},
        'ios': {'bannerAdUnitId': 'b-i'},
      });
      expect(config.enabled, isTrue);
      expect(config.interstitialFrequency, 15);
      expect(config.android.bannerAdUnitId, 'b-a');
      expect(config.android.interstitialAdUnitId, 'i-a');
      expect(config.ios.bannerAdUnitId, 'b-i');
      expect(config.ios.interstitialAdUnitId, isNull);
    });

    test('malformed json disables ads and keeps the 15-event default', () {
      final config = AppAdConfig.fromJson('nope');
      expect(config.enabled, isFalse);
      expect(config.interstitialFrequency, 15);
      expect(
        AppAdConfig.fromJson({
          'interstitialFrequency': -3,
        }).interstitialFrequency,
        15,
      );
    });
  });

  group('GoogleAdService', () {
    test('banner unit id resolves from remote config when enabled', () async {
      final service = _service(onInterstitialShown: () {});
      await service.initialize();
      expect(service.bannerAdUnitId, 'banner-android');
      expect(service.canShowBannerAds.value, isTrue);
    });

    test('interstitial shows on every 15th event only', () async {
      var shown = 0;
      final service = _service(onInterstitialShown: () => shown++);
      await service.initialize();

      for (var event = 1; event <= 14; event++) {
        expect(await service.recordPcGameFinished(), isFalse);
      }
      expect(shown, 0);
      await service.recordBottomNavigationTransition();
      expect(shown, 1);

      for (var event = 16; event <= 29; event++) {
        expect(await service.recordPcGameFinished(), isFalse);
      }
      expect(shown, 1);
      expect(await service.recordPcGameFinished(), isTrue);
      expect(shown, 2);
    });

    test('disabled config never shows ads', () async {
      var shown = 0;
      final service = _service(
        onInterstitialShown: () => shown++,
        config: const AppAdConfig.disabled(),
      );
      await service.initialize();
      expect(service.bannerAdUnitId, isNull);
      for (var event = 1; event <= 30; event++) {
        await service.recordPcGameFinished();
      }
      expect(shown, 0);
    });
  });
}
