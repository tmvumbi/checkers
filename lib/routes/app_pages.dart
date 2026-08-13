import 'package:get/get.dart';

import '../modules/edit_profile/binding/edit_profile_binding.dart';
import '../modules/edit_profile/view/edit_profile_view.dart';
import '../modules/home/binding/home_binding.dart';
import '../modules/home/view/home_view.dart';
import '../modules/landing/binding/landing_binding.dart';
import '../modules/landing/view/landing_view.dart';
import 'app_routes.dart';

abstract final class AppPages {
  static final List<GetPage<dynamic>> pages = [
    GetPage<dynamic>(
      name: AppRoutes.landing,
      page: LandingView.new,
      binding: LandingBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.editProfile,
      page: EditProfileView.new,
      binding: EditProfileBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.home,
      page: HomeView.new,
      binding: HomeBinding(),
    ),
  ];
}
