import 'package:flutter/material.dart';

// ========== COLOURS ==========
// Calm, high-contrast palette chosen for easy reading
class AppColors {
  static const background = Color(0xFFF6F3EE); // warm paper
  static const surface = Colors.white;
  static const primary = Color(0xFF1F4E8C); // deep blue
  static const primarySoft = Color(0xFFE4ECF7);
  static const text = Color(0xFF1A1C1E);
  static const textMuted = Color(0xFF4A4F57);
  static const border = Color(0xFFE2DDD3);
  static const danger = Color(0xFFB3261E);
  static const dangerSoft = Color(0xFFFBE9E7);
  static const success = Color(0xFF1B6E43);
  static const successSoft = Color(0xFFE5F3EA);

  // One colour per time of day
  static const morning = Color(0xFFA14F00);
  static const afternoon = Color(0xFF0E6B63);
  static const night = Color(0xFF51399E);
}

// ========== THEME ==========
// Large text and big touch targets for older eyes and hands.
// The phone's own font size setting still scales everything on top.
ThemeData buildAppTheme() {
  const radius = BorderRadius.all(Radius.circular(18));

  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    onPrimary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.danger,
  );

  // Bigger than Material defaults (body text 20 instead of 16).
  // Atkinson Hyperlegible was designed for readers with low vision; it is
  // bundled in assets/fonts so the app never needs the internet.
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: 'AtkinsonHyperlegible',
  );
  const sizes = TextTheme(
    displaySmall: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, height: 1.2),
    headlineMedium: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.2),
    headlineSmall: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.25),
    titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.25),
    titleMedium: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, height: 1.3),
    bodyLarge: TextStyle(fontSize: 20, height: 1.4),
    bodyMedium: TextStyle(fontSize: 18, height: 1.4),
    bodySmall: TextStyle(fontSize: 16, height: 1.4),
    labelLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    labelMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
  );

  final textTheme = base.textTheme
      .merge(sizes)
      .apply(bodyColor: AppColors.text, displayColor: AppColors.text);

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: textTheme,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 76,
      titleTextStyle: textTheme.headlineSmall,
      iconTheme: const IconThemeData(size: 30, color: AppColors.text),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 64),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: textTheme.labelLarge,
        iconSize: 28,
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 60),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        foregroundColor: AppColors.primary,
        textStyle: textTheme.labelLarge,
        iconSize: 26,
        side: const BorderSide(color: AppColors.primary, width: 2),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: textTheme.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      hintStyle: textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
      border: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.border, width: 2),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.border, width: 2),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.primary, width: 2.5),
      ),
    ),
    chipTheme: ChipThemeData(
      labelStyle: textTheme.labelMedium,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      backgroundColor: Colors.white,
      selectedColor: AppColors.primarySoft,
      checkmarkColor: AppColors.primary,
      side: const BorderSide(color: AppColors.border, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.text,
      contentTextStyle: textTheme.bodyLarge?.copyWith(color: Colors.white),
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      titleTextStyle: textTheme.headlineSmall,
      contentTextStyle: textTheme.bodyLarge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1.5),
  );
}
