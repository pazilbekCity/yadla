import 'package:flutter/material.dart';

/// Calm, mature, low-fatigue visual theme for Yadla in both Day (light) and
/// Night (dark) modes. Uses soft slate, warm ivory, and muted desaturated
/// accents suitable for adult learners.
class YadlaTheme {
  const YadlaTheme._();

  // Day (Light) palette — warm alabaster & deep slate
  static const Color _lightBackground = Color(0xFFF4F5F7);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceContainer = Color(0xFFECEFF4);
  static const Color _lightPrimary = Color(0xFF334E68);
  static const Color _lightPrimaryContainer = Color(0xFFDCE4EE);
  static const Color _lightOnPrimaryContainer = Color(0xFF1E3246);
  static const Color _lightSecondary = Color(0xFF52606D);
  static const Color _lightSecondaryContainer = Color(0xFFE6E9EF);
  static const Color _lightOnSecondaryContainer = Color(0xFF243B53);
  static const Color _lightOutline = Color(0xFFCBD2D9);
  static const Color _lightOutlineVariant = Color(0xFFDDE2E9);
  static const Color _lightTextPrimary = Color(0xFF1F2933);
  static const Color _lightTextSecondary = Color(0xFF52606D);

  // Night (Dark) palette — restful deep slate & muted steel
  static const Color _darkBackground = Color(0xFF11161F);
  static const Color _darkSurface = Color(0xFF1A2230);
  static const Color _darkSurfaceContainer = Color(0xFF222C3C);
  static const Color _darkPrimary = Color(0xFF8DA8C7);
  static const Color _darkPrimaryContainer = Color(0xFF26384F);
  static const Color _darkOnPrimaryContainer = Color(0xFFD9E4F2);
  static const Color _darkSecondary = Color(0xFF9FB3C8);
  static const Color _darkSecondaryContainer = Color(0xFF242F40);
  static const Color _darkOnSecondaryContainer = Color(0xFFD9E2EC);
  static const Color _darkOutline = Color(0xFF3E4C59);
  static const Color _darkOutlineVariant = Color(0xFF2B3748);
  static const Color _darkTextPrimary = Color(0xFFE4E7EB);
  static const Color _darkTextSecondary = Color(0xFF9AA5B1);

  static ThemeData light() {
    const colorScheme = ColorScheme.light(
      primary: _lightPrimary,
      onPrimary: Colors.white,
      primaryContainer: _lightPrimaryContainer,
      onPrimaryContainer: _lightOnPrimaryContainer,
      secondary: _lightSecondary,
      onSecondary: Colors.white,
      secondaryContainer: _lightSecondaryContainer,
      onSecondaryContainer: _lightOnSecondaryContainer,
      surface: _lightSurface,
      onSurface: _lightTextPrimary,
      onSurfaceVariant: _lightTextSecondary,
      surfaceContainerHighest: _lightSurfaceContainer,
      outline: _lightOutline,
      outlineVariant: _lightOutlineVariant,
      error: Color(0xFFA63A3A),
      onError: Colors.white,
    );

    return _buildTheme(colorScheme, scaffoldBackground: _lightBackground);
  }

  static ThemeData dark() {
    const colorScheme = ColorScheme.dark(
      primary: _darkPrimary,
      onPrimary: Color(0xFF102A43),
      primaryContainer: _darkPrimaryContainer,
      onPrimaryContainer: _darkOnPrimaryContainer,
      secondary: _darkSecondary,
      onSecondary: Color(0xFF102A43),
      secondaryContainer: _darkSecondaryContainer,
      onSecondaryContainer: _darkOnSecondaryContainer,
      surface: _darkSurface,
      onSurface: _darkTextPrimary,
      onSurfaceVariant: _darkTextSecondary,
      surfaceContainerHighest: _darkSurfaceContainer,
      outline: _darkOutline,
      outlineVariant: _darkOutlineVariant,
      error: Color(0xFFE07A7A),
      onError: Color(0xFF2D1212),
    );

    return _buildTheme(colorScheme, scaffoldBackground: _darkBackground);
  }

  static ThemeData _buildTheme(
    ColorScheme colorScheme, {
    required Color scaffoldBackground,
  }) {
    final isDark = colorScheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: BorderSide(color: colorScheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),
    );
  }
}
