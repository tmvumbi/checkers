import 'dart:async';

import 'package:checkers/data/models/block_status.dart';
import 'package:checkers/services/auth_service.dart';
import 'package:checkers/services/block_service.dart';
import 'package:checkers/services/custom_ad_service.dart';
import 'package:checkers/services/device_identity_service.dart';
import 'package:checkers/services/presence_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// The services below talk to the backend only through small interfaces, so
// any backend implementation plugs in via InitialBinding.

class _Auth extends Mock implements AuthService {}

class _Devices extends Mock implements DeviceIdentityService {}

class _FakeBlockBackend implements BlockBackend {
  _FakeBlockBackend(this.response);

  final Map<String, dynamic> response;
  List<Map<String, String>>? lastDevices;

  @override
  Future<Map<String, dynamic>> syncDeviceBlocks(
    List<Map<String, String>> devices,
  ) async {
    lastDevices = devices;
    return response;
  }
}

class _FakePresenceBackend implements PresenceBackend {
  final List<String> beats = [];
  int leaves = 0;

  @override
  Future<void> heartbeat({required String busyMode}) async =>
      beats.add(busyMode);

  @override
  Future<void> leave() async => leaves++;
}

class _FakeCustomAdBackend implements CustomAdBackend {
  Map<String, dynamic>? ad;
  final List<String> prints = [];

  @override
  Future<Map<String, dynamic>?> getActiveAd() async => ad;

  @override
  Future<void> recordPrint(String campaignId) async => prints.add(campaignId);

  @override
  Future<void> recordClick(String campaignId) async {}
}

const _user = AuthUser(uid: 'u1', isAnonymous: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BlockService.sync sends device ids and maps the block', () async {
    final devices = _Devices();
    when(devices.identifiers).thenAnswer(
      (_) async => [
        {'kind': 'android_ssaid', 'value': 'abc'},
      ],
    );
    final backend = _FakeBlockBackend({'level': 'full', 'permanent': true});
    final service = BlockService(
      deviceIdentityService: devices,
      backend: backend,
    );

    final status = await service.sync();

    expect(backend.lastDevices, [
      {'kind': 'android_ssaid', 'value': 'abc'},
    ]);
    expect(status.level, BlockLevel.full);
    expect(service.status.value.canWatch, isFalse);
  });

  test('PresenceService beats while signed in and stops on sign-out', () async {
    final auth = _Auth();
    final changes = StreamController<AuthUser?>.broadcast();
    when(() => auth.userChanges).thenAnswer((_) => changes.stream);
    when(() => auth.currentUser).thenReturn(_user);
    final backend = _FakePresenceBackend();
    final service = PresenceService(backend: backend, authService: auth)
      ..onInit();

    await Future<void>.delayed(Duration.zero);
    expect(backend.beats, ['idle']);

    service.setBusyMode('playing');
    await Future<void>.delayed(Duration.zero);
    expect(backend.beats.last, 'playing');

    changes.add(null);
    await Future<void>.delayed(Duration.zero);
    service.onClose();
    await changes.close();
  });

  test('CustomAdService loads the active ad only when signed in', () async {
    final auth = _Auth();
    when(() => auth.userChanges).thenAnswer((_) => const Stream.empty());
    when(() => auth.currentUser).thenReturn(null);
    final backend = _FakeCustomAdBackend()
      ..ad = {
        'id': 'c1',
        'banner_url': 'https://cdn/banner.png',
        'target_url': 'https://example.com',
        'pieces': {'white_king': 'https://cdn/wk.png'},
      };
    final service = CustomAdService(backend: backend, authService: auth);

    await service.refresh();
    expect(service.activeAd.value, isNull);

    when(() => auth.currentUser).thenReturn(_user);
    await service.refresh();
    expect(service.activeAd.value?.id, 'c1');
    expect(service.activeAd.value?.pieceUrls['white_king'], isNotNull);

    service.recordPrint('c1');
    await Future<void>.delayed(Duration.zero);
    expect(backend.prints, ['c1']);
  });
}
