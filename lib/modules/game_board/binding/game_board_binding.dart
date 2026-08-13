import 'package:get/get.dart';

import '../controller/game_board_controller.dart';

class GameBoardBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<GameBoardController>(GameBoardController.new);
  }
}
