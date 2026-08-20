import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/ad_config.dart';
import 'tracking_consent_service.dart';

/// Google AdMob integration (kopo parity, minus subscriptions): adaptive
/// banners plus an interstitial every Nth recorded event (bottom-nav
/// transitions and finished PC games; checkers shows one every 15th).
abstract class AdService extends GetxService {
  RxBool get canShowBannerAds;
  RxBool get isPrivacyOptionsRequired;
  String? get bannerAdUnitId;
  bool get shouldRequestNonPersonalizedAds;

  Future<void> initialize();
  Future<void> recordBottomNavigationTransition();
  Future<bool> recordPcGameFinished();
  Future<void> showPrivacyOptions();
}

abstract class LoadedInterstitialAd {
  void setFullScreenCallbacks({
    required VoidCallback onDismissed,
    required VoidCallback onFailedToShow,
  });

  Future<void> show();
  Future<void> dispose();
}

typedef AdInitializer = Future<void> Function();
typedef ConsentGatherer = Future<bool> Function();
typedef PrivacyOptionsPresenter = Future<void> Function();
typedef PrivacyOptionsRequirementLoader = Future<bool> Function();
typedef AdConfigLoader = Future<AppAdConfig> Function();
typedef InterstitialAdLoader =
    Future<LoadedInterstitialAd?> Function(String adUnitId, AdRequest request);
typedef SharedPreferencesLoader = Future<SharedPreferences> Function();

class GoogleAdService extends AdService {
  GoogleAdService({
    TrackingConsentService? trackingConsentService,
    AdInitializer? initializeAds,
    ConsentGatherer? gatherConsent,
    PrivacyOptionsRequirementLoader? loadPrivacyOptionsRequirement,
    PrivacyOptionsPresenter? presentPrivacyOptions,
    AdConfigLoader? loadAdConfig,
    InterstitialAdLoader? loadInterstitialAd,
    SharedPreferencesLoader? loadPreferences,
    bool disableAdsForLocalTesting = const bool.fromEnvironment(
      'CHECKERS_DISABLE_ADS',
      defaultValue: false,
    ),
    bool useTestAdUnits = kDebugMode,
    TargetPlatform? targetPlatform,
  }) : _trackingConsentService =
           trackingConsentService ?? Get.find<TrackingConsentService>(),
       _initializeAds = initializeAds ?? _initializeMobileAds,
       _gatherConsent = gatherConsent ?? _gatherUserConsent,
       _loadPrivacyOptionsRequirement =
           loadPrivacyOptionsRequirement ?? _isPrivacyOptionsRequiredNow,
       _presentPrivacyOptions =
           presentPrivacyOptions ?? _showPrivacyOptionsForm,
       _loadAdConfig = loadAdConfig ?? _loadSupabaseAdConfig,
       _loadInterstitialAd = loadInterstitialAd ?? _loadGoogleInterstitialAd,
       _loadPreferences = loadPreferences ?? SharedPreferences.getInstance,
       _disableAdsForLocalTesting = disableAdsForLocalTesting,
       _useTestAdUnits = useTestAdUnits,
       _targetPlatform = targetPlatform;

  static const String _interstitialEventCountStorageKey =
      'ad_interstitial_event_count';

  static const String _androidTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/9214589741';
  static const String _iosTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/2435281174';
  static const String _androidTestInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _iosTestInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/4411468910';

  final TrackingConsentService _trackingConsentService;
  final AdInitializer _initializeAds;
  final ConsentGatherer _gatherConsent;
  final PrivacyOptionsRequirementLoader _loadPrivacyOptionsRequirement;
  final PrivacyOptionsPresenter _presentPrivacyOptions;
  final AdConfigLoader _loadAdConfig;
  final InterstitialAdLoader _loadInterstitialAd;
  final SharedPreferencesLoader _loadPreferences;
  final bool _disableAdsForLocalTesting;
  final bool _useTestAdUnits;
  final TargetPlatform? _targetPlatform;

  @override
  final RxBool canShowBannerAds = false.obs;

  @override
  final RxBool isPrivacyOptionsRequired = false.obs;

  AppAdConfig _config = const AppAdConfig.disabled();
  bool _canRequestAds = false;
  bool _shouldRequestNonPersonalizedAds = false;
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isLoadingInterstitial = false;
  bool _isShowingInterstitial = false;
  LoadedInterstitialAd? _interstitialAd;
  Completer<void>? _initializationCompleter;

  @override
  String? get bannerAdUnitId {
    if (_disableAdsForLocalTesting || !_canRequestAds || !_config.enabled) {
      return null;
    }
    return _adUnitIdsForPlatform().bannerAdUnitId;
  }

  @override
  bool get shouldRequestNonPersonalizedAds => _shouldRequestNonPersonalizedAds;

  AdRequest get _adRequest => AdRequest(
    nonPersonalizedAds: _shouldRequestNonPersonalizedAds ? true : null,
  );

  String? get _interstitialAdUnitId {
    if (_disableAdsForLocalTesting || !_canRequestAds || !_config.enabled) {
      return null;
    }
    return _adUnitIdsForPlatform().interstitialAdUnitId;
  }

  int get _interstitialFrequency {
    final frequency = _config.interstitialFrequency;
    return frequency > 0 ? frequency : 15;
  }

  @override
  void onInit() {
    super.onInit();
    unawaited(initialize());
  }

  @override
  void onClose() {
    unawaited(_interstitialAd?.dispose());
    _interstitialAd = null;
    super.onClose();
  }

  @override
  Future<void> initialize() async {
    if (_disableAdsForLocalTesting) {
      _isInitialized = true;
      _refreshBannerAvailability();
      return;
    }
    if (_isInitialized) {
      return;
    }
    if (_isInitializing) {
      return _initializationCompleter?.future;
    }

    _isInitializing = true;
    _initializationCompleter = Completer<void>();
    try {
      final trackingStatus = await _trackingConsentService
          .requestAuthorizationIfNeeded();
      _shouldRequestNonPersonalizedAds =
          trackingStatus.shouldRequestNonPersonalizedAds;
      await _initializeAds();
      _canRequestAds = await _gatherConsent();
      isPrivacyOptionsRequired.value = await _loadPrivacyOptionsRequirement();
      _config = await _loadAdConfig();
      _isInitialized = true;
      _refreshBannerAvailability();
      await _preloadInterstitial();
    } catch (error) {
      _config = const AppAdConfig.disabled();
      _canRequestAds = false;
      isPrivacyOptionsRequired.value = false;
      _isInitialized = true;
      _refreshBannerAvailability();
      debugPrint('Ad initialization failed; ads are disabled: $error');
    } finally {
      _isInitializing = false;
      if (_initializationCompleter?.isCompleted == false) {
        _initializationCompleter?.complete();
      }
      _initializationCompleter = null;
    }
  }

  @override
  Future<void> recordBottomNavigationTransition() {
    return _recordInterstitialEvent();
  }

  @override
  Future<bool> recordPcGameFinished() {
    return _recordInterstitialEvent();
  }

  @override
  Future<void> showPrivacyOptions() {
    if (_disableAdsForLocalTesting) {
      return Future<void>.value();
    }
    return _presentPrivacyOptions();
  }

  Future<bool> _recordInterstitialEvent() async {
    await initialize();
    if (_disableAdsForLocalTesting) {
      return false;
    }
    final adUnitId = _interstitialAdUnitId;
    if (adUnitId == null) {
      return false;
    }

    final preferences = await _loadPreferences();
    final nextCount =
        (preferences.getInt(_interstitialEventCountStorageKey) ?? 0) + 1;
    await preferences.setInt(_interstitialEventCountStorageKey, nextCount);

    if (nextCount % _interstitialFrequency != 0) {
      unawaited(_preloadInterstitial());
      return false;
    }
    return _showInterstitialIfReady();
  }

  Future<void> _preloadInterstitial() async {
    final adUnitId = _interstitialAdUnitId;
    if (_disableAdsForLocalTesting ||
        adUnitId == null ||
        _interstitialAd != null ||
        _isLoadingInterstitial ||
        _isShowingInterstitial) {
      return;
    }

    _isLoadingInterstitial = true;
    try {
      _interstitialAd = await _loadInterstitialAd(adUnitId, _adRequest);
    } finally {
      _isLoadingInterstitial = false;
    }
  }

  Future<bool> _showInterstitialIfReady() async {
    if (_disableAdsForLocalTesting || _isShowingInterstitial) {
      return false;
    }
    final ad = _interstitialAd;
    if (ad == null) {
      unawaited(_preloadInterstitial());
      return false;
    }

    _isShowingInterstitial = true;
    _interstitialAd = null;
    final completedAd = Completer<bool>();
    ad.setFullScreenCallbacks(
      onDismissed: () {
        _isShowingInterstitial = false;
        unawaited(ad.dispose());
        unawaited(_preloadInterstitial());
        if (!completedAd.isCompleted) {
          completedAd.complete(true);
        }
      },
      onFailedToShow: () {
        _isShowingInterstitial = false;
        unawaited(ad.dispose());
        unawaited(_preloadInterstitial());
        if (!completedAd.isCompleted) {
          completedAd.complete(false);
        }
      },
    );
    try {
      await ad.show();
      return completedAd.future;
    } catch (_) {
      _isShowingInterstitial = false;
      await ad.dispose();
      unawaited(_preloadInterstitial());
      if (!completedAd.isCompleted) {
        completedAd.complete(false);
      }
      return false;
    }
  }

  void _refreshBannerAvailability() {
    canShowBannerAds.value = bannerAdUnitId != null;
  }

  AppPlatformAdConfig _adUnitIdsForPlatform() {
    final platform = _targetPlatform ?? defaultTargetPlatform;
    final isAndroid = platform == TargetPlatform.android;
    final isIos = platform == TargetPlatform.iOS;
    if (!isAndroid && !isIos) {
      return const AppPlatformAdConfig();
    }
    if (_useTestAdUnits) {
      return AppPlatformAdConfig(
        bannerAdUnitId: isAndroid
            ? _androidTestBannerAdUnitId
            : _iosTestBannerAdUnitId,
        interstitialAdUnitId: isAndroid
            ? _androidTestInterstitialAdUnitId
            : _iosTestInterstitialAdUnitId,
      );
    }
    return isAndroid ? _config.android : _config.ios;
  }

  static Future<void> _initializeMobileAds() async {
    await MobileAds.instance.initialize();
  }

  static Future<AppAdConfig> _loadSupabaseAdConfig() async {
    final row = await Supabase.instance.client
        .from('app_config')
        .select('config')
        .eq('id', 'public')
        .maybeSingle();
    final config = (row?['config'] as Map?)?.cast<String, dynamic>();
    return AppAdConfig.fromJson(config?['ads']);
  }

  static Future<bool> _gatherUserConsent() async {
    final completer = Completer<bool>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
        completer.complete(await ConsentInformation.instance.canRequestAds());
      },
      (_) async {
        completer.complete(await ConsentInformation.instance.canRequestAds());
      },
    );
    return completer.future;
  }

  static Future<bool> _isPrivacyOptionsRequiredNow() async {
    return await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
  }

  static Future<void> _showPrivacyOptionsForm() async {
    await ConsentForm.showPrivacyOptionsForm((_) {});
  }

  static Future<LoadedInterstitialAd?> _loadGoogleInterstitialAd(
    String adUnitId,
    AdRequest request,
  ) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return null;
    }
    final completer = Completer<LoadedInterstitialAd?>();
    await InterstitialAd.load(
      adUnitId: adUnitId,
      request: request,
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => completer.complete(_GoogleInterstitialAd(ad)),
        onAdFailedToLoad: (_) => completer.complete(null),
      ),
    );
    return completer.future;
  }
}

class _GoogleInterstitialAd extends LoadedInterstitialAd {
  _GoogleInterstitialAd(this._ad);

  final InterstitialAd _ad;

  @override
  void setFullScreenCallbacks({
    required VoidCallback onDismissed,
    required VoidCallback onFailedToShow,
  }) {
    _ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (_) => onDismissed(),
      onAdFailedToShowFullScreenContent: (_, _) => onFailedToShow(),
    );
  }

  @override
  Future<void> show() {
    return _ad.show();
  }

  @override
  Future<void> dispose() {
    return _ad.dispose();
  }
}
