import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Medikabiz design system: the logo's navy and green, as on medikabiz.com
/// (owner's choice, 17 Oct 2026). Light-first: a cool off-white canvas, navy
/// headers and brand surfaces, and green for actions and links. Red and amber
/// are kept for things that need attention.
class AppColors {
  AppColors._();

  // Brand navy (headers, side menu, brand surfaces)
  static const Color navyDeep = Color(0xFF04132A); // snackbars, deepest surfaces
  static const Color navy = Color(0xFF071D3B); // headers, brand
  static const Color navyLight = Color(0xFF0E2A52); // raised surfaces on navy

  // Brand green (actions, links, selection)
  // White text on it 6.1:1; as text it stays above 5:1 even on the green,
  // amber and soft tints over the canvas (WCAG AA 4.5:1).
  static const Color primary = Color(0xFF007056);
  static const Color primaryDark = Color(0xFF00604A); // hover / pressed
  static const Color primaryBright = Color(0xFF00B88D); // the logo's green, on navy
  static const Color primarySoft = Color(0xFFDDF5EE); // selected / tinted backgrounds

  // Surfaces
  static const Color canvas = Color(0xFFF3F6F9); // app background
  static const Color page = Color(0xFFE2E8EF);
  static const Color card = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFDCE4EC);
  static const Color divider = Color(0xFFEDF1F5);

  // Text
  static const Color ink = Color(0xFF0B1B33); // primary text
  // Secondary text/labels: 6.0:1 on cards, 5.6:1 on the canvas (WCAG AA).
  static const Color muted = Color(0xFF50617D);
  static const Color onDarkMuted = Color(0xFFB8C5D9); // muted text on navy
  static const Color onDarkFaint = Color(0xFF8FA2BF);

  // Status
  static const Color statusGreen = Color(0xFF12A47C); // in stock
  static const Color statusAmber = Color(0xFFEA8C1F); // low stock
  static const Color statusRed = Color(0xFFE5484D); // expiring / expired

  // Status tint backgrounds (~12-14% of the hue)
  static const Color statusGreenBg = Color(0x1F12A47C);
  static const Color statusAmberBg = Color(0x24EA8C1F);
  static const Color statusRedBg = Color(0x1FE5484D);

  // Dark-mode surfaces
  static const Color darkBg = Color(0xFF06142A);
  static const Color darkCard = Color(0xFF0E2240);
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

  /// Body text (has ₹ and →); headings use [displayFamily].
  static const String fontFamily = 'Figtree';

  /// Headings and big numbers, as on medikabiz.com. It has no ₹, which
  /// comes from [fontFamily] through [displayFallback].
  static const String displayFamily = 'HankenGrotesk';
  static const List<String> displayFallback = <String>[fontFamily];

  /// A heading or large-number style in the display face.
  static TextStyle display({double? size, FontWeight weight = FontWeight.w800, Color? color, double? height}) =>
      TextStyle(
        fontFamily: displayFamily,
        fontFamilyFallback: displayFallback,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: -0.2,
      );

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final Color bg = isDark ? AppColors.darkBg : AppColors.canvas;
    final Color surface = isDark ? AppColors.darkCard : AppColors.card;
    final Color ink = isDark ? Colors.white : AppColors.ink;
    final Color muted = isDark ? AppColors.onDarkMuted : AppColors.muted;
    final Color line = isDark ? const Color(0xFF1E3B66) : AppColors.border;

    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.navy,
      onSecondary: Colors.white,
      error: AppColors.statusRed,
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
    );

    final TextTheme body = Typography.blackMountainView.apply(
      bodyColor: ink,
      displayColor: ink,
      fontFamily: fontFamily,
    );
    // Headings and titles in the display face, as on the website.
    TextStyle? heading(TextStyle? s) =>
        s?.copyWith(fontFamily: displayFamily, fontFamilyFallback: displayFallback);
    final TextTheme base = body.copyWith(
      displayLarge: heading(body.displayLarge),
      displayMedium: heading(body.displayMedium),
      displaySmall: heading(body.displaySmall),
      headlineLarge: heading(body.headlineLarge),
      headlineMedium: heading(body.headlineMedium),
      headlineSmall: heading(body.headlineSmall),
      titleLarge: heading(body.titleLarge),
    );

    // Flutter's buttons and ink default to the plain arrow on desktop; the
    // owner wants the hand on everything clickable (arrow when disabled).
    const WidgetStateMouseCursor click = WidgetStateMouseCursor.clickable;
    const ButtonStyle clickStyle = ButtonStyle(mouseCursor: click);

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
          fontFamily: displayFamily,
          fontFamilyFallback: displayFallback,
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
            const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
        hintStyle: TextStyle(color: muted, fontWeight: FontWeight.w500),
        // The default helper grey is 2.4:1 on the canvas; muted passes AA.
        // w600: small muted text at w500 fails the contrast guideline.
        helperStyle: TextStyle(color: muted, fontWeight: FontWeight.w600),
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
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: const BorderSide(color: AppColors.statusRed, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          // White on the brand green: 6.1:1.
          foregroundColor: Colors.white,
          // Hover/press darken the green (a white overlay would lower the
          // contrast of the white label).
          overlayColor: Colors.black,
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          textStyle: const TextStyle(
              fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w700),
          enabledMouseCursor: SystemMouseCursors.click,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          // Theme-aware: dark ink on light, white on dark. Using the constant
          // AppColors.ink here made outlined buttons (e.g. "Log out") render
          // dark-on-dark and vanish in dark mode.
          foregroundColor: ink,
          backgroundColor: surface,
          minimumSize: const Size.fromHeight(54),
          side: BorderSide(color: line, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          textStyle: const TextStyle(
              fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w700),
          enabledMouseCursor: SystemMouseCursors.click,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          // The brand green is too dark on dark surfaces; use the logo green there.
          foregroundColor: isDark ? AppColors.primaryBright : AppColors.primary,
          textStyle:
              const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700),
          enabledMouseCursor: SystemMouseCursors.click,
        ),
      ),
      filledButtonTheme: const FilledButtonThemeData(style: clickStyle),
      iconButtonTheme: const IconButtonThemeData(style: clickStyle),
      segmentedButtonTheme: const SegmentedButtonThemeData(style: clickStyle),
      menuButtonTheme: const MenuButtonThemeData(style: clickStyle),
      popupMenuTheme: const PopupMenuThemeData(mouseCursor: click),
      tabBarTheme: const TabBarThemeData(mouseCursor: click),
      checkboxTheme: const CheckboxThemeData(mouseCursor: click),
      radioTheme: const RadioThemeData(mouseCursor: click),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        mouseCursor: click,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        // Darken on hover/focus/press, as the elevated buttons do.
        hoverColor: Color(0x14000000),
        focusColor: Color(0x1F000000),
        splashColor: Color(0x1F000000),
        elevation: 0,
        highlightElevation: 0,
      ),
      iconTheme: IconThemeData(color: ink),
      listTileTheme: ListTileThemeData(iconColor: AppColors.primary, textColor: ink),
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
        backgroundColor: AppColors.navyDeep,
        contentTextStyle: const TextStyle(
            color: Colors.white, fontFamily: fontFamily, fontWeight: FontWeight.w700),
        actionTextColor: AppColors.primaryBright,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? Colors.white : AppColors.muted),
        trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? AppColors.primary : AppColors.border),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        mouseCursor: click,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
    );
  }
}
