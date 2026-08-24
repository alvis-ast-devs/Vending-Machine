import 'package:flutter/material.dart';

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

  factory VendingPalette.fromJson(Map<String, dynamic> json) {
    final background = _parseHex(json['background'], defaults.background);
    return VendingPalette(
      background: background,
      surface: _shiftColor(background, const [10, 11, 13]),
      surfaceSoft: _shiftColor(background, const [20, 22, 26]),
      textPrimary: _parseHex(json['text_primary'], defaults.textPrimary),
      textMuted: _parseHex(json['text_muted'], defaults.textMuted),
      accent: _parseHex(json['accent'], defaults.accent),
      warning: _parseHex(json['warning'], defaults.warning),
      danger: _parseHex(json['danger'], defaults.danger),
    );
  }

  static Color _parseHex(Object? rawValue, Color fallback) {
    final value = rawValue?.toString();
    if (value == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value)) {
      return fallback;
    }
    return Color(int.parse(value.substring(1), radix: 16) | 0xFF000000);
  }

  static Color _shiftColor(Color color, List<int> offsets) {
    final value = color.toARGB32();
    final red = (value >> 16) & 0xFF;
    final green = (value >> 8) & 0xFF;
    final blue = value & 0xFF;
    final perceivedBrightness = red * 0.299 + green * 0.587 + blue * 0.114;
    final direction = perceivedBrightness > 180 ? -1 : 1;

    int shifted(int channel, int offset) {
      return (channel + offset * direction).clamp(0, 255).toInt();
    }

    return Color.fromARGB(
      255,
      shifted(red, offsets[0]),
      shifted(green, offsets[1]),
      shifted(blue, offsets[2]),
    );
  }
}
