import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  testWidgets('F11 reaches the Windows window manager', (tester) async {
    const channel = MethodChannel('window_manager');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'isFullScreen' ? false : null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await pumpApp(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), contains('setFullScreen'));
    expect(calls.singleWhere((c) => c.method == 'setFullScreen').arguments, {'isFullScreen': true});
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  test('Windows and Linux full screen cannot collide with find', () {
    for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(AppShortcuts.fullScreen.trigger, LogicalKeyboardKey.f11);
      expect(AppShortcuts.fullScreen.control, isFalse);
      expect(AppShortcuts.find.trigger, LogicalKeyboardKey.keyF);
      expect(AppShortcuts.find.control, isTrue);
      expect(primaryShortcut(LogicalKeyboardKey.backspace).meta, isFalse);
      expect(primaryShortcut(LogicalKeyboardKey.arrowDown).control, isTrue);
    }
  });
  test('macOS keeps its full screen and library modifiers', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(AppShortcuts.fullScreen.trigger, LogicalKeyboardKey.keyF);
    expect(AppShortcuts.fullScreen.control, isTrue);
    expect(AppShortcuts.fullScreen.meta, isTrue);
    expect(primaryShortcut(LogicalKeyboardKey.backspace).meta, isTrue);
  });
  test('browser owns navigation/find/save chords, native hosts retain them', () {
    for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
      debugDefaultTargetPlatformOverride = platform;
      for (final key in [
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.keyW,
        LogicalKeyboardKey.keyN,
      ]) {
        expect(browserOwnsShortcut(primaryShortcut(key), isWeb: true), isTrue);
        expect(browserOwnsShortcut(primaryShortcut(key), isWeb: false), isFalse);
        expect(browserOwnsShortcut(primaryShortcut(key, alt: true), isWeb: true), isFalse);
      }
    }
  });
}
