import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Meddata design system (green + orange), sourced from the product design
/// handoff. Light-first: a calm off-white canvas, deep-green headers/surfaces,
/// and an orange accent reserved for primary actions.
class AppColors {
  AppColors._();

  // Brand greens
  static const Color greenDarkest = Color(0xFF0A302E); // headings, dark cards
  static const Color green = Color(0xFF0E4D4A); // primary, headers, brand
  static const Color greenMid = Color(0xFF12615C); // avatars, accents

  // Accent orange
  static const Color orange = Color(0xFFFF6B2C); // primary CTAs, FAB, brand
  static const Color orangeHover = Color(0xFFF2551E);
  static const Color orangeLight = Color(0xFFFF8A5C);

  // Surfaces
  static const Color canvas = Color(0xFFEEF2F1); // app background
  static const Color page = Color(0xFFDCE4E2);
  static const Color card = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E9E8);
  static const Color divider = Color(0xFFEEF2F1);

  // Text
  static const Color ink = Color(0xFF0A302E); // primary text
  static const Color muted = Color(0xFF66807D); // secondary text/labels
  static const Color onDarkMuted = Color(0xFF9BC6C1); // muted text on green
  static const Color onDarkFaint = Color(0xFF7FA8A3);

  // Status
  static const Color statusGreen = Color(0xFF12A47C); // in stock
  static const Color statusAmber = Color(0xFFEA8C1F); // low stock
  static const Color statusRed = Color(0xFFE5484D); // expiring / expired

  // Status tint backgrounds (~12-14% of the hue)
  static const Color statusGreenBg = Color(0x1F12A47C);
  static const Color statusAmberBg = Color(0x24EA8C1F);
  static const Color statusRedBg = Color(0x1FE5484D);

  // Dark-mode surfaces (adapted from the light design)
  static const Color darkBg = Color(0xFF0A1918);
  static const Color darkCard = Color(0xFF11302E);
}

/// Shared corner radii used across the design.
class AppRadii {
  AppRadii._();
  static const double input = 12;
  static const double button = 16;
  static const double card = 18;
  static const double cardLg = 22;
  static const double pill = 999;
  static const double fab = 18;
}

class AppTheme {
  AppTheme._();

  static const String fontFamily = 'GoogleSansFlex';

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final Color bg = isDark ? AppColors.darkBg : AppColors.canvas;
    final Color surface = isDark ? AppColors.darkCard : AppColors.card;
    final Color ink = isDark ? Colors.white : AppColors.ink;
    final Color muted = isDark ? AppColors.onDarkMuted : AppColors.muted;
    final Color line = isDark ? const Color(0xFF20423F) : AppColors.border;

    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.green,
      onPrimary: Colors.white,
      secondary: AppColors.orange,
      onSecondary: Colors.white,
      error: AppColors.statusRed,
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
    );

    final TextTheme base = Typography.blackMountainView.apply(
      bodyColor: ink,
      displayColor: ink,
      fontFamily: fontFamily,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      fontFamily: fontFamily,
      dividerColor: line,
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      textTheme: base,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: line),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: TextStyle(color: muted, fontWeight: FontWeight.w700),
        floatingLabelStyle:
            const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700),
        hintStyle: TextStyle(color: muted, fontWeight: FontWeight.w500),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide(color: line, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide(color: line, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: const BorderSide(color: AppColors.green, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: const BorderSide(color: AppColors.statusRed, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          textStyle: const TextStyle(
              fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          backgroundColor: surface,
          minimumSize: const Size.fromHeight(54),
          side: BorderSide(color: line, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          textStyle: const TextStyle(
              fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.green,
          textStyle:
              const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
      ),
      iconTheme: IconThemeData(color: ink),
      listTileTheme: ListTileThemeData(iconColor: AppColors.green, textColor: ink),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.statusGreenBg,
        side: BorderSide.none,
        labelStyle: const TextStyle(
            color: AppColors.statusGreen, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.greenDarkest,
        contentTextStyle: const TextStyle(
            color: Colors.white, fontFamily: fontFamily, fontWeight: FontWeight.w700),
        actionTextColor: AppColors.orangeLight,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? Colors.white : AppColors.muted),
        trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? AppColors.green : AppColors.border),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.orange,
      ),
    );
  }
}
