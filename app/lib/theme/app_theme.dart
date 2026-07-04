import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Strictly monochrome design system. No color anywhere — only black, white,
/// and greys. Status is shown via text/borders/weight, never hue.
class AppColors {
  AppColors._();

  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color grey100 = Color(0xFFF5F5F5);
  static const Color grey300 = Color(0xFFE0E0E0);
  static const Color grey500 = Color(0xFF9E9E9E);
  static const Color grey700 = Color(0xFF616161);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.black : AppColors.white;
    final Color fg = isDark ? AppColors.white : AppColors.black;
    final Color surface = isDark ? const Color(0xFF121212) : AppColors.white;
    final Color subtle = isDark ? AppColors.grey700 : AppColors.grey500;
    final Color line = isDark ? AppColors.grey700 : AppColors.grey300;

    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: fg,
      onPrimary: bg,
      secondary: fg,
      onSecondary: bg,
      error: fg, // errors shown in bold text, not red (monochrome)
      onError: bg,
      surface: surface,
      onSurface: fg,
    );

    final TextTheme text = Typography.blackMountainView.apply(
      bodyColor: fg,
      displayColor: fg,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: line,
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      textTheme: text,
      fontFamily: 'Roboto',
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: fg,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: line),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        isDense: true,
        labelStyle: TextStyle(color: subtle),
        hintStyle: TextStyle(color: subtle),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: fg, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: fg,
          foregroundColor: bg,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: fg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: fg),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: fg,
        foregroundColor: bg,
        elevation: 0,
        highlightElevation: 0,
      ),
      iconTheme: IconThemeData(color: fg),
      listTileTheme: ListTileThemeData(iconColor: fg, textColor: fg),
      chipTheme: ChipThemeData(
        backgroundColor: bg,
        side: BorderSide(color: fg),
        labelStyle: TextStyle(color: fg, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: fg,
        contentTextStyle: TextStyle(color: bg),
        actionTextColor: bg,
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (Set<WidgetState> s) => s.contains(WidgetState.selected) ? bg : fg),
        trackColor: WidgetStateProperty.resolveWith(
            (Set<WidgetState> s) => s.contains(WidgetState.selected) ? fg : bg),
        trackOutlineColor: WidgetStateProperty.all(fg),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: fg,
        linearTrackColor: line,
        circularTrackColor: line,
      ),
    );
  }
}
