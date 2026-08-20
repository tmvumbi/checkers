import 'package:get/get.dart';

import '../controller/tournament_lobby_controller.dart';

class TournamentLobbyBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<TournamentLobbyController>(TournamentLobbyController.new);
  }
}
