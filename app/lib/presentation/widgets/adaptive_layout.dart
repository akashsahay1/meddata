import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared layout rules for screens used on both phones and desktop windows.
/// The available width, rather than OS, determines the presentation so a
/// narrow desktop window remains usable and a wide tablet has room to expand.
class AdaptiveLayout {
  AdaptiveLayout._();

  static const double desktopBreakpoint = 900;
  static const double contentMaxWidth = 1200;
  static const double formMaxWidth = 480;
  static const double desktopFormMaxWidth = 760;
  static const double desktopPageMaxWidth = 960;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopBreakpoint;

  static double pageGutter(BuildContext context) =>
      isDesktop(context) ? 32 : 18;

  /// Phones open another page; desktop opens a bounded window over the page
  /// already in use. Look at the Flutter view so a form opened from another
  /// narrow window still gets the desktop presentation.
  static Route<T> route<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    double maxWidth = desktopPageMaxWidth,
  }) {
    final view = View.of(context);
    final double width = view.physicalSize.width / view.devicePixelRatio;
    if (width < desktopBreakpoint) {
      return MaterialPageRoute<T>(builder: builder);
    }

    return DialogRoute<T>(
      context: context,
      // Closing a form must go through its Back/Cancel action or PopScope.
      barrierDismissible: false,
      builder: (BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: maxWidth,
          height: 900,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) =>
                MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: constraints.biggest,
                    padding: EdgeInsets.zero,
                    viewPadding: EdgeInsets.zero,
                  ),
                  child: Shortcuts(
                    shortcuts: const <ShortcutActivator, Intent>{
                      SingleActivator(LogicalKeyboardKey.escape):
                          DismissIntent(),
                    },
                    child: Actions(
                      actions: <Type, Action<Intent>>{
                        DismissIntent: CallbackAction<DismissIntent>(
                          onInvoke: (_) => Navigator.of(context).maybePop(),
                        ),
                      },
                      child: Builder(builder: builder),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
  }
}
