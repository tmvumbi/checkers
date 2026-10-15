import 'package:get/get.dart';

import 'convex/convex_gateway.dart';

/// Player feedback inbox (emailed to the team and listed in the admin
/// console).
abstract class FeedbackService {
  /// Submits [text] as the signed-in player [uid]. Throws on failure.
  Future<void> submit({required String uid, required String text});
}

class ConvexFeedbackService implements FeedbackService {
  ConvexFeedbackService({ConvexGateway? gateway}) : _gatewayOverride = gateway;

  final ConvexGateway? _gatewayOverride;
  ConvexGateway get _convex => _gatewayOverride ?? Get.find<ConvexGateway>();

  /// The backend attributes feedback to the authenticated caller.
  @override
  Future<void> submit({required String uid, required String text}) async {
    await _convex.mutation('feedback:submit', {'text': text});
  }
}
