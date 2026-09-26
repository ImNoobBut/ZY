import 'package:flutter/material.dart';

class AppTheme {
  static const backgroundTop = Color(0xFF0F1424);
  static const backgroundBottom = Color(0xFF1A1830);
  /// Frosted glass tint for list cards — not for modal sheets (too transparent).
  static const card = Color(0x14FFFFFF);
  /// Opaque elevated surface for bottom sheets / dialogs.
  static const sheet = Color(0xFF1E1C32);
  static const sheetBarrier = Color(0xCC0A0C14);
  static const accent = Color(0xFF8C7AE6);
  static const accentSoft = Color(0xFF668CEB);
  static const primaryText = Color(0xF2FFFFFF);
  static const secondaryText = Color(0xA6FFFFFF);
  static const tertiaryText = Color(0x73FFFFFF);
  static const destructive = Color(0xFFE66673);

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: backgroundTop,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: primaryText,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: primaryText,
        displayColor: primaryText,
      ),
      listTileTheme: const ListTileThemeData(textColor: primaryText),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(primaryText),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : tertiaryText,
        ),
      ),
    );
  }

  static BoxDecoration nightBackground() => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [backgroundTop, backgroundBottom],
        ),
      );
}
