import 'package:get/get.dart';

import '../core/network/api_result.dart';
import '../data/models/user_profile.dart';
import 'convex/convex_gateway.dart';

abstract class ProfileService {
  Future<ApiResult<UserProfile?>> getProfile(String uid);
  Future<ApiResult<UserProfile>> upsertProfile(UserProfile profile);
}

class ConvexProfileService implements ProfileService {
  ConvexProfileService({ConvexGateway? gateway}) : _gatewayOverride = gateway;

  final ConvexGateway? _gatewayOverride;
  ConvexGateway get _convex => _gatewayOverride ?? Get.find<ConvexGateway>();

  @override
  Future<ApiResult<UserProfile?>> getProfile(String uid) {
    return guardConvex(() async {
      final row = await _convex.query('profiles:get', {'uid': uid});
      return row == null ? null : UserProfile.fromJson(asRow(row));
    });
  }

  /// Saves the caller's identity columns (nickname, photo, anonymity);
  /// stats stay server-owned.
  @override
  Future<ApiResult<UserProfile>> upsertProfile(UserProfile profile) {
    return guardConvex(() async {
      final row = await _convex.mutation('profiles:updateMine', {
        'nickname': profile.nickname,
        'photoUrl': profile.photoUrl,
        'isAnonymous': profile.isAnonymous,
      });
      return UserProfile.fromJson(asRow(row));
    });
  }
}
