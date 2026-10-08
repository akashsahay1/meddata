import 'dart:io';

import 'package:flutter/foundation.dart';

/// Which platform features this build can use.
class AppPlatform {
  AppPlatform._();

  /// Windows / macOS / Linux desktop build.
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// A Windows desktop build (used for Windows-specific layout choices).
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// A camera for barcode scanning / taking photos (phones only; on a PC a
  /// USB barcode scanner types into the barcode field instead).
  static bool get supportsCamera =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// The in-app Razorpay checkout (a WebView) works on phones only; desktop
  /// pays in the browser.
  static bool get supportsInAppCheckout => supportsCamera;

  /// Human-readable platform name (support messages, device list).
  static String get name {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }
}
