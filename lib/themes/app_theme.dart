import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_fonts.dart';
import '../core/constants/app_sizes.dart';

abstract final class AppTheme {
  static ThemeData get light =>
      _buildTheme(ColorScheme.fromSeed(seedColor: AppColors.seed));

  static ThemeData get dark => _buildTheme(
    ColorScheme.fromSeed(
      seedColor: AppColors.darkSeed,
      brightness: Brightness.dark,
    ),
  );

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    return ThemeData(
      colorScheme: colorScheme,
      fontFamily: AppFonts.inter,
      fontFamilyFallback: const [AppFonts.iosevkaCharon],
      extensions: const [
        CheckersThemeExtension(
          brandGold: AppColors.gold,
          inviteGreen: AppColors.inviteGreen,
          logoGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.purple, AppColors.darkPurple],
          ),
          primaryButtonGradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.darkBlue, AppColors.blue],
          ),
          tableGradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.tableTop, AppColors.tableBottom],
          ),
        ),
      ],
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radius),
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: AppFonts.iosevkaCharon,
          fontSize: 44,
          fontWeight: FontWeight.w400,
          letterSpacing: 6,
        ),
        headlineMedium: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
        labelLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w400),
      ),
    );
  }
}

@immutable
class CheckersThemeExtension extends ThemeExtension<CheckersThemeExtension> {
  const CheckersThemeExtension({
    required this.brandGold,
    required this.inviteGreen,
    required this.logoGradient,
    required this.primaryButtonGradient,
    required this.tableGradient,
  });

  final Color brandGold;
  final Color inviteGreen;
  final LinearGradient logoGradient;
  final LinearGradient primaryButtonGradient;
  final LinearGradient tableGradient;

  @override
  CheckersThemeExtension copyWith({
    Color? brandGold,
    Color? inviteGreen,
    LinearGradient? logoGradient,
    LinearGradient? primaryButtonGradient,
    LinearGradient? tableGradient,
  }) {
    return CheckersThemeExtension(
      brandGold: brandGold ?? this.brandGold,
      inviteGreen: inviteGreen ?? this.inviteGreen,
      logoGradient: logoGradient ?? this.logoGradient,
      primaryButtonGradient:
          primaryButtonGradient ?? this.primaryButtonGradient,
      tableGradient: tableGradient ?? this.tableGradient,
    );
  }

  @override
  CheckersThemeExtension lerp(
    ThemeExtension<CheckersThemeExtension>? other,
    double t,
  ) {
    if (other is! CheckersThemeExtension) {
      return this;
    }

    return CheckersThemeExtension(
      brandGold: Color.lerp(brandGold, other.brandGold, t) ?? brandGold,
      inviteGreen: Color.lerp(inviteGreen, other.inviteGreen, t) ?? inviteGreen,
      logoGradient:
          LinearGradient.lerp(logoGradient, other.logoGradient, t) ??
          logoGradient,
      primaryButtonGradient:
          LinearGradient.lerp(
            primaryButtonGradient,
            other.primaryButtonGradient,
            t,
          ) ??
          primaryButtonGradient,
      tableGradient:
          LinearGradient.lerp(tableGradient, other.tableGradient, t) ??
          tableGradient,
    );
  }
}
