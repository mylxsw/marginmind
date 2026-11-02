import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/mobile_status_bar.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_design/mm_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  test('status bar defaults to visible and restores either saved choice', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    expect(container.read(settingsProvider).showSystemStatusBar, isTrue);
    for (final visible in [false, true]) {
      await container.read(settingsProvider.notifier).setShowSystemStatusBar(visible);
      container.invalidate(settingsProvider);
      expect(container.read(settingsProvider).showSystemStatusBar, visible);
      expect(prefs.getBool(SettingsController.showSystemStatusBarKey), visible);
    }
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform applies startup, toggles and resume without hiding the bottom bar', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final calls = <MethodCall>[];
      final channel = platform == TargetPlatform.iOS ? SystemChannels.platform : MobileStatusBar.androidChannel;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      Future<void> pump(bool visible) =>
          tester.pumpWidget(MobileStatusBar(enabled: true, visible: visible, child: const SizedBox()));
      await pump(false);
      await pump(true);
      await pump(false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      if (platform == TargetPlatform.iOS) {
        final overlays = calls.where((call) => call.method == 'SystemChrome.setEnabledSystemUIOverlays');
        expect(overlays.map((call) => call.arguments), [
          ['SystemUiOverlay.bottom'],
          ['SystemUiOverlay.top', 'SystemUiOverlay.bottom'],
          ['SystemUiOverlay.bottom'],
          ['SystemUiOverlay.bottom'],
        ]);
      } else {
        expect(calls.map((call) => call.arguments), [false, true, false, false]);
      }
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final size in [const Size(393, 852), const Size(1133, 744), const Size(1280, 820)]) {
    final mobile = size.width < 1200;
    testWidgets('general status bar setting at $size (mobile: $mobile)', (tester) async {
      final container = await pumpApp(
        tester,
        size: size,
        overrides: [touchPlatformProvider.overrideWithValue(mobile), phoneProvider.overrideWithValue(size.width < 600)],
      );
      showSettings(tester.element(find.byType(MMWindowScaffold)));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('settings-show-system-status-bar'));
      expect(toggle, mobile ? findsOneWidget : findsNothing);
      if (mobile) {
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(container.read(settingsProvider).showSystemStatusBar, isFalse);
        expect(tester.widget<MMSwitch>(toggle).value, isFalse);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(container.read(settingsProvider).showSystemStatusBar, isTrue);
      }
    });
  }
}
