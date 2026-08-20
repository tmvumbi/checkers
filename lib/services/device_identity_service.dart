import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Collects the stable, high-entropy device identifiers used for block
/// enforcement. Only OS-provided ids (never fingerprints), so false
/// positives are limited to genuinely shared physical devices:
/// - Android: SSAID (`ANDROID_ID`) — stable per device + signing key,
///   survives reinstalls, resets on factory reset.
/// - iOS: a keychain-persisted UUID (survives reinstalls) plus
///   `identifierForVendor` as a secondary signal.
class DeviceIdentityService {
  DeviceIdentityService({
    DeviceInfoPlugin? deviceInfo,
    FlutterSecureStorage? secureStorage,
  }) : _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _keychainKey = 'checkers_device_id';

  // Fleet-wide degenerate values that must never identify a device.
  static const Set<String> _badValues = {
    '9774d56d682e549c',
    'unknown',
    'null',
    '00000000-0000-0000-0000-000000000000',
  };

  final DeviceInfoPlugin _deviceInfo;
  final FlutterSecureStorage _secureStorage;

  List<Map<String, String>>? _cached;

  Future<List<Map<String, String>>> identifiers() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    final result = <Map<String, String>>[];
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        _add(result, 'android_ssaid', info.id);
      } else if (Platform.isIOS) {
        _add(result, 'ios_keychain', await _keychainId());
        final info = await _deviceInfo.iosInfo;
        _add(result, 'ios_idfv', info.identifierForVendor);
      }
    } catch (_) {
      // Identification is best-effort; the uid-level block still applies.
    }
    _cached = result;
    return result;
  }

  Future<String?> _keychainId() async {
    try {
      final existing = await _secureStorage.read(key: _keychainKey);
      if (existing != null && existing.isNotEmpty) {
        return existing;
      }
      final generated = const Uuid().v4();
      await _secureStorage.write(key: _keychainKey, value: generated);
      return generated;
    } catch (_) {
      return null;
    }
  }

  static void _add(List<Map<String, String>> out, String kind, String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.length < 8 ||
        trimmed.length > 128 ||
        _badValues.contains(trimmed.toLowerCase())) {
      return;
    }
    out.add({'kind': kind, 'value': trimmed});
  }
}
