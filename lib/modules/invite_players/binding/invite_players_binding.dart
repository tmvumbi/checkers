import 'package:get/get.dart';

import '../controller/invite_players_controller.dart';

class InvitePlayersBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<InvitePlayersController>(InvitePlayersController.new);
  }
}
