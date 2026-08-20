import 'package:get/get.dart';

import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/app_rating_service.dart';
import '../services/auth_service.dart';
import '../services/block_service.dart';
import '../services/checkers_ai_service.dart';
import '../services/invite_listener_service.dart';
import '../services/online_game_service.dart';
import '../services/party_link_service.dart';
import '../services/player_message_service.dart';
import '../services/presence_service.dart';
import '../services/profile_photo_service.dart';
import '../services/profile_service.dart';
import '../services/tracking_consent_service.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AnalyticsService>(NoopAnalyticsService.new, fenix: true);
    Get.lazyPut<AuthService>(SupabaseAuthService.new, fenix: true);
    Get.lazyPut<ProfileService>(SupabaseProfileService.new, fenix: true);
    Get.lazyPut<ProfilePhotoService>(
      SupabaseProfilePhotoService.new,
      fenix: true,
    );
    Get.lazyPut<AiService>(IsolateAiService.new, fenix: true);
    Get.lazyPut<OnlineGameService>(SupabaseOnlineGameService.new, fenix: true);
    Get.put<PresenceService>(PresenceService(), permanent: true);
    Get.put<PlayerMessageService>(
      SupabasePlayerMessageService(),
      permanent: true,
    );
    Get.put<BlockService>(BlockService(), permanent: true);
    Get.lazyPut<AppRatingService>(RateMyAppRatingService.new, fenix: true);
    Get.put<TrackingConsentService>(
      AppTrackingTransparencyService(),
      permanent: true,
    );
    Get.put<AdService>(GoogleAdService(), permanent: true);
    Get.put<InviteListenerService>(InviteListenerService(), permanent: true);
    Get.put<PartyLinkService>(PartyLinkService(), permanent: true);
  }
}
