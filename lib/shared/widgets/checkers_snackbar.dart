import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/constants/app_colors.dart';

/// Brand-styled notification toast. `Get.snackbar` defaults to a translucent
/// grey that is unreadable over the felt background, so every notification
/// goes through this helper instead.
void showCheckersSnackbar(String message) {
  Get.showSnackbar(
    GetSnackBar(
      messageText: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
      backgroundColor: AppColors.darkBlue,
      borderColor: AppColors.gold,
      borderWidth: 1.5,
      borderRadius: 12,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 3),
      animationDuration: const Duration(milliseconds: 250),
    ),
  );
}
