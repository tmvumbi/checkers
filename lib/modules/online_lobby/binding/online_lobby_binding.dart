import 'package:get/get.dart';

import '../controller/online_lobby_controller.dart';

class OnlineLobbyBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<OnlineLobbyController>(OnlineLobbyController.new);
  }
}
