import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/block_status.dart';
import 'device_identity_service.dart';

/// Syncs this install's device identifiers with the backend and tracks the
/// signed-in player's effective block (direct or device-inherited).
class BlockService extends GetxService {
  BlockService({
    DeviceIdentityService? deviceIdentityService,
    SupabaseClient? client,
  }) : _deviceIdentityService =
           deviceIdentityService ?? DeviceIdentityService(),
       _client = client;

  final DeviceIdentityService _deviceIdentityService;
  final SupabaseClient? _client;

  SupabaseClient get client => _client ?? Supabase.instance.client;

  final Rx<BlockStatus> status = BlockStatus.none.obs;

  /// Registers the device and refreshes [status]. Fails open (returns the
  /// last known status) so a network hiccup never locks anyone out; the
  /// server-side triggers remain the real enforcement.
  Future<BlockStatus> sync() async {
    try {
      final devices = await _deviceIdentityService.identifiers();
      final response = await client.rpc<dynamic>(
        'sync_device_blocks',
        params: {'p_devices': devices},
      );
      status.value = BlockStatus.fromJson(
        (response as Map).cast<String, dynamic>(),
      );
    } catch (_) {}
    return status.value;
  }
}
