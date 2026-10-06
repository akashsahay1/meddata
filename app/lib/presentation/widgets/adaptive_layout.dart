import 'package:flutter/material.dart';

/// Shared layout rules for screens used on both phones and desktop windows.
/// The available width, rather than OS, determines the presentation so a
/// narrow desktop window remains usable and a wide tablet has room to expand.
class AdaptiveLayout {
  AdaptiveLayout._();

  static const double desktopBreakpoint = 900;
  static const double contentMaxWidth = 1200;
  static const double formMaxWidth = 480;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopBreakpoint;

  static double pageGutter(BuildContext context) =>
      isDesktop(context) ? 32 : 18;
}
