import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/block_status.dart';
import 'device_identity_service.dart';

/// Backend half of [BlockService].
abstract class BlockBackend {
  /// Records this install's device ids and returns the effective block
  /// `{level, permanent, expires_at}`.
  Future<Map<String, dynamic>> syncDeviceBlocks(
    List<Map<String, String>> devices,
  );
}

class SupabaseBlockBackend implements BlockBackend {
  SupabaseBlockBackend({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? Supabase.instance.client;

  @override
  Future<Map<String, dynamic>> syncDeviceBlocks(
    List<Map<String, String>> devices,
  ) async {
    final response = await client.rpc<dynamic>(
      'sync_device_blocks',
      params: {'p_devices': devices},
    );
    return (response as Map).cast<String, dynamic>();
  }
}

/// Syncs this install's device identifiers with the backend and tracks the
/// signed-in player's effective block (direct or device-inherited).
class BlockService extends GetxService {
  BlockService({
    DeviceIdentityService? deviceIdentityService,
    BlockBackend? backend,
  }) : _deviceIdentityService =
           deviceIdentityService ?? DeviceIdentityService(),
       _backendOverride = backend;

  final DeviceIdentityService _deviceIdentityService;
  final BlockBackend? _backendOverride;

  BlockBackend get _backend => _backendOverride ?? Get.find();

  final Rx<BlockStatus> status = BlockStatus.none.obs;

  /// Registers the device and refreshes [status]. Fails open (returns the
  /// last known status) so a network hiccup never locks anyone out; the
  /// server-side triggers remain the real enforcement.
  Future<BlockStatus> sync() async {
    try {
      final devices = await _deviceIdentityService.identifiers();
      status.value = BlockStatus.fromJson(
        await _backend.syncDeviceBlocks(devices),
      );
    } catch (_) {}
    return status.value;
  }
}
