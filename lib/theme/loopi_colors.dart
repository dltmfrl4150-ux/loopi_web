import 'package:flutter/material.dart';

abstract final class LoopiColors {
  static const Color purple = Color(0xFF7C5CFF);
  static const Color purpleDark = Color(0xFF5B3FD6);
  static const Color deepPurple = Color(0xFF4A148C);
  static const Color canvas = Color(0xFFF6F4FB);
  static const Color darkCanvas = Color(0xFF121018);
  static const Color darkSurface = Color(0xFF1C1826);
  static const Color ink = Color(0xFF1C1630);
  static const Color muted = Color(0xFF7A7489);
  static const Color line = Color(0xFFE6E1F2);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color pageBackground(BuildContext context) =>
      isDark(context) ? darkCanvas : canvas;

  static Color card(BuildContext context) =>
      isDark(context) ? darkSurface : Colors.white;

  static Color text(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color textMuted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static Color divider(BuildContext context) =>
      isDark(context) ? Colors.white12 : line;
}
