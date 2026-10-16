import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The macOS app is sandboxed: without this entitlement the photo / file
// picker and "Save" dialogs can't open or write the file the user picked.
void main() {
  for (final String name in <String>['DebugProfile', 'Release']) {
    test('$name entitlements allow user-selected files', () {
      final String plist =
          File('macos/Runner/$name.entitlements').readAsStringSync();
      expect(plist,
          contains('<key>com.apple.security.files.user-selected.read-write</key>'));
    });
  }
}
