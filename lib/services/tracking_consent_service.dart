import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

enum TrackingConsentStatus {
  authorized,
  denied,
  restricted,
  notDetermined,
  notSupported,
}

extension TrackingConsentStatusPolicy on TrackingConsentStatus {
  bool get shouldRequestNonPersonalizedAds =>
      this == TrackingConsentStatus.denied ||
      this == TrackingConsentStatus.restricted;
}

abstract class TrackingConsentService extends GetxService {
  Future<TrackingConsentStatus> requestAuthorizationIfNeeded();
}

/// iOS App Tracking Transparency prompt (kopo parity); other platforms
/// report [TrackingConsentStatus.notSupported].
class AppTrackingTransparencyService extends TrackingConsentService {
  AppTrackingTransparencyService({TargetPlatform? targetPlatform})
    : _targetPlatform = targetPlatform;

  final TargetPlatform? _targetPlatform;
  TrackingConsentStatus? _cachedStatus;

  @override
  Future<TrackingConsentStatus> requestAuthorizationIfNeeded() async {
    if (_cachedStatus case final cachedStatus?) {
      return cachedStatus;
    }

    final platform = _targetPlatform ?? defaultTargetPlatform;
    if (platform != TargetPlatform.iOS || !Platform.isIOS) {
      _cachedStatus = TrackingConsentStatus.notSupported;
      return _cachedStatus!;
    }

    final currentStatus =
        await AppTrackingTransparency.trackingAuthorizationStatus;
    final resolvedStatus = currentStatus == TrackingStatus.notDetermined
        ? await AppTrackingTransparency.requestTrackingAuthorization()
        : currentStatus;
    _cachedStatus = _mapStatus(resolvedStatus);
    return _cachedStatus!;
  }

  TrackingConsentStatus _mapStatus(TrackingStatus status) {
    return switch (status) {
      TrackingStatus.authorized => TrackingConsentStatus.authorized,
      TrackingStatus.denied => TrackingConsentStatus.denied,
      TrackingStatus.restricted => TrackingConsentStatus.restricted,
      TrackingStatus.notDetermined => TrackingConsentStatus.notDetermined,
      TrackingStatus.notSupported => TrackingConsentStatus.notSupported,
    };
  }
}
