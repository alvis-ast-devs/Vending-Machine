import 'package:flutter/material.dart';
import 'package:vending_ui/core/theme_settings.dart';

class VendingColors {
  const VendingColors._();

  static VendingPalette _palette = VendingPalette.defaults;

  static Color get background => _palette.background;
  static Color get surface => _palette.surface;
  static Color get surfaceSoft => _palette.surfaceSoft;
  static Color get white => _palette.textPrimary;
  static Color get muted => _palette.textMuted;
  static Color get accent => _palette.accent;
  static Color get warning => _palette.warning;
  static Color get danger => _palette.danger;

  static void apply(VendingPalette palette) {
    _palette = palette;
  }
}

class VendingTheme {
  const VendingTheme._();

  static ThemeData get data {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: VendingColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: VendingColors.accent,
        brightness: Brightness.dark,
        surface: VendingColors.surface,
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: VendingColors.white),
        bodyMedium: TextStyle(color: VendingColors.white),
        bodySmall: TextStyle(color: VendingColors.muted),
        titleLarge: TextStyle(color: VendingColors.white),
        titleMedium: TextStyle(color: VendingColors.white),
        titleSmall: TextStyle(color: VendingColors.white),
      ),
      iconTheme: IconThemeData(color: VendingColors.white),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: VendingColors.accent,
          foregroundColor: VendingColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
