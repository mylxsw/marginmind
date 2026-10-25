import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('primary modifier is Command on macOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final s = primaryShortcut(LogicalKeyboardKey.keyL, shift: true);
    expect(s.meta, isTrue);
    expect(s.control, isFalse);
    expect(describeShortcut(s), '⇧⌘L');
    expect(describeShortcut(primaryShortcut(LogicalKeyboardKey.keyS, control: true)), '⌃⌘S');
  });

  test('primary modifier is Ctrl elsewhere', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final s = primaryShortcut(LogicalKeyboardKey.digit1);
    expect(s.meta, isFalse);
    expect(s.control, isTrue);
    expect(describeShortcut(s), 'Ctrl+1');
  });

  test('appearance parses the native snapshot', () {
    final a = SystemAppearance.fromMap({'accent': 0xFFAF52DE, 'reduceTransparency': true, 'reduceMotion': false});
    expect(a.accentColor, const Color(0xFFAF52DE));
    expect(a.reduceTransparency, isTrue);
    expect(a.reduceMotion, isFalse);
  });
}
