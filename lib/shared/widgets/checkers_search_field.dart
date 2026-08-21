import 'package:flutter/material.dart';

import '../../themes/app_theme.dart';

/// Compact dark search input used by the player/game lists.
class CheckersSearchField extends StatelessWidget {
  const CheckersSearchField({
    required this.hint,
    required this.onChanged,
    super.key,
  });

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;
    final onPrimary = theme.colorScheme.onPrimary;

    return TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: theme.textTheme.bodyLarge!.copyWith(
        color: onPrimary,
        fontSize: 15,
      ),
      cursorColor: brand.brandGold,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: theme.textTheme.bodyLarge!.copyWith(
          color: onPrimary.withValues(alpha: 0.5),
          fontSize: 15,
        ),
        prefixIcon: Icon(
          Icons.search,
          size: 20,
          color: onPrimary.withValues(alpha: 0.6),
        ),
        filled: true,
        fillColor: theme.colorScheme.shadow.withValues(alpha: 0.3),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: onPrimary.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: brand.brandGold, width: 1.5),
        ),
      ),
    );
  }
}
