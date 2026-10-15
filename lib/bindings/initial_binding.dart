import 'package:firebase_core/firebase_core.dart';
import 'package:get/get.dart';

import '../services/ad_service.dart';
import '../services/account_deletion_service.dart';
import '../services/analytics_service.dart';
import '../services/app_config_service.dart';
import '../services/app_rating_service.dart';
import '../services/auth_service.dart';
import '../services/block_service.dart';
import '../services/checkers_ai_service.dart';
import '../services/custom_ad_service.dart';
import '../services/feedback_service.dart';
import '../services/invite_listener_service.dart';
import '../services/online_game_service.dart';
import '../services/party_link_service.dart';
import '../services/player_message_service.dart';
import '../services/presence_service.dart';
import '../services/profile_photo_service.dart';
import '../services/profile_service.dart';
import '../services/push_notification_service.dart';
import '../services/social_service.dart';
import '../services/tournament_service.dart';
import '../services/tracking_consent_service.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AnalyticsService>(
      () => Firebase.apps.isEmpty
          ? NoopAnalyticsService()
          : FirebaseAnalyticsService(),
      fenix: true,
    );
    // Backend implementations (Convex; the ConvexGateway and ConvexSession
    // they use are registered in main()). Swapping the backend means
    // swapping this block only.
    Get.lazyPut<AuthService>(FirebaseAuthService.new, fenix: true);
    Get.lazyPut<AppConfigService>(ConvexAppConfigService.new, fenix: true);
    Get.lazyPut<FeedbackService>(ConvexFeedbackService.new, fenix: true);
    Get.lazyPut<SocialService>(ConvexSocialService.new, fenix: true);
    Get.lazyPut<PresenceBackend>(ConvexPresenceBackend.new, fenix: true);
    Get.lazyPut<BlockBackend>(ConvexBlockBackend.new, fenix: true);
    Get.lazyPut<CustomAdBackend>(ConvexCustomAdBackend.new, fenix: true);
    Get.lazyPut<PushDeviceBackend>(ConvexPushDeviceBackend.new, fenix: true);
    Get.lazyPut<AccountDeletionService>(
      ConvexAccountDeletionService.new,
      fenix: true,
    );
    Get.lazyPut<ProfileService>(ConvexProfileService.new, fenix: true);
    Get.lazyPut<ProfilePhotoService>(
      ConvexProfilePhotoService.new,
      fenix: true,
    );
    Get.lazyPut<AiService>(PersistentIsolateAiService.new, fenix: true);
    Get.lazyPut<OnlineGameService>(ConvexOnlineGameService.new, fenix: true);
    Get.lazyPut<TournamentService>(ConvexTournamentService.new, fenix: true);
    Get.put<PresenceService>(PresenceService(), permanent: true);
    Get.put<PlayerMessageService>(
      ConvexPlayerMessageService(),
      permanent: true,
    );
    Get.put<BlockService>(BlockService(), permanent: true);
    Get.lazyPut<AppRatingService>(RateMyAppRatingService.new, fenix: true);
    Get.put<TrackingConsentService>(
      AppTrackingTransparencyService(),
      permanent: true,
    );
    Get.put<AdService>(GoogleAdService(), permanent: true);
    Get.put<CustomAdService>(CustomAdService(), permanent: true);
    Get.put<InviteListenerService>(InviteListenerService(), permanent: true);
    if (Firebase.apps.isNotEmpty) {
      Get.put<PushNotificationService>(
        PushNotificationService(),
        permanent: true,
      );
    }
    Get.put<PartyLinkService>(PartyLinkService(), permanent: true);
  }
}
