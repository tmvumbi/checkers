import 'package:get/get.dart';

import '../modules/edit_profile/binding/edit_profile_binding.dart';
import '../modules/edit_profile/view/edit_profile_view.dart';
import '../modules/game_board/binding/game_board_binding.dart';
import '../modules/game_board/view/game_board_view.dart';
import '../modules/home/binding/home_binding.dart';
import '../modules/home/view/home_view.dart';
import '../modules/how_to_play/view/how_to_play_view.dart';
import '../modules/invite_players/binding/invite_players_binding.dart';
import '../modules/invite_players/view/invite_players_view.dart';
import '../modules/landing/binding/landing_binding.dart';
import '../modules/landing/view/landing_view.dart';
import '../modules/online_lobby/binding/online_lobby_binding.dart';
import '../modules/online_lobby/view/online_lobby_view.dart';
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
    GetPage<dynamic>(
      name: AppRoutes.gameBoard,
      page: GameBoardView.new,
      binding: GameBoardBinding(),
    ),
    GetPage<dynamic>(name: AppRoutes.howToPlay, page: HowToPlayView.new),
    GetPage<dynamic>(
      name: AppRoutes.onlineLobby,
      page: OnlineLobbyView.new,
      binding: OnlineLobbyBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.invitePlayers,
      page: InvitePlayersView.new,
      binding: InvitePlayersBinding(),
    ),
  ];
}
