import 'package:flutter/material.dart';

/// Represents the color palette for the vending machine UI.
/// In the local-only version, only the default palette is used.
class VendingPalette {
  final Color background;
  final Color surface;
  final Color surfaceSoft;
  final Color textPrimary;
  final Color textMuted;
  final Color accent;
  final Color warning;
  final Color danger;

  const VendingPalette({
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
    required this.warning,
    required this.danger,
  });

  static const defaults = VendingPalette(
    background: Color(0xFF101214),
    surface: Color(0xFF1A1D21),
    surfaceSoft: Color(0xFF24282E),
    textPrimary: Color(0xFFF8FAFC),
    textMuted: Color(0xFF9CA3AF),
    accent: Color(0xFF19D37E),
    warning: Color(0xFFFFC857),
    danger: Color(0xFFFF5D5D),
  );

  /// In local mode, always return the default palette.
  factory VendingPalette.fromJson(Map<String, dynamic> json) {
    return defaults;
  }
}
