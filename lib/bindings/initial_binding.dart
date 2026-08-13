import 'package:get/get.dart';

import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/checkers_ai_service.dart';
import '../services/profile_service.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AnalyticsService>(NoopAnalyticsService.new, fenix: true);
    Get.lazyPut<AuthService>(SupabaseAuthService.new, fenix: true);
    Get.lazyPut<ProfileService>(SupabaseProfileService.new, fenix: true);
    Get.lazyPut<AiService>(IsolateAiService.new, fenix: true);
  }
}
