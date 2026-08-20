import 'package:get/get.dart';

import '../controller/tournament_invite_controller.dart';

class TournamentInviteBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<TournamentInviteController>(TournamentInviteController.new);
  }
}
