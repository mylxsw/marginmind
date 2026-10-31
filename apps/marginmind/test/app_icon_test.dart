import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/settings/app_icon.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_design/mm_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';
import 'assistant_quick_actions_test.dart' show screenshot;
import 'vocabulary_screenshots.dart' show loadVocabularyScreenshotFonts;

class FakeIcons extends AppIconService {
  FakeIcons({this.mac = true});
  final bool mac;
  final calls = <AppIconPreference>[];
  bool fail = false;
  Completer<void>? pending;
  @override
  bool get supported => true;
  @override
  bool get dockOnly => mac;
  @override
  Future<void> apply(AppIconPreference icon) async {
    calls.add(icon);
    if (fail) throw PlatformException(code: 'icon_change_failed');
    await pending?.future;
  }
}

/// Reproduces the legacy preferences cache changing before a failed disk write.
class FailedIconWrites extends Fake implements SharedPreferences {
  final Map<String, Object> values = {appIconPreferenceKey: 'leafFolio'};
  @override
  String? getString(String key) => values[key] as String?;
  @override
  int? getInt(String key) => null;
  @override
  double? getDouble(String key) => null;
  @override
  bool? getBool(String key) => null;
  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadVocabularyScreenshotFonts);

  Future<(ProviderContainer, SharedPreferences, FakeIcons)> setup(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    final icons = FakeIcons();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs), appIconServiceProvider.overrideWithValue(icons)],
    );
    addTearDown(container.dispose);
    return (container, prefs, icons);
  }

  test('B is the default, including unknown stored choices', () async {
    final (container, _, icons) = await setup({appIconPreferenceKey: 'removed-icon'});
    expect(container.read(settingsProvider).appIcon, AppIconPreference.paperArc);
    expect(icons.calls, isEmpty);
  });

  test('persist A and C only after native success and restore on provider reload', () async {
    final (container, prefs, icons) = await setup({});
    final controller = container.read(settingsProvider.notifier);
    for (final icon in [AppIconPreference.leafFolio, AppIconPreference.foldedF, AppIconPreference.paperArc]) {
      await controller.setAppIcon(icon);
      expect(container.read(settingsProvider).appIcon, icon);
      expect(prefs.getString(appIconPreferenceKey), icon.name);
    }
    expect(icons.calls, AppIconPreference.values.skip(1).followedBy([AppIconPreference.paperArc]));
    await controller.setAppIcon(AppIconPreference.leafFolio);
    container.invalidate(settingsProvider);
    expect(container.read(settingsProvider).appIcon, AppIconPreference.leafFolio);
  });

  test('native failure preserves the old choice and saved preference', () async {
    final (container, prefs, icons) = await setup({appIconPreferenceKey: 'leafFolio'});
    icons.fail = true;
    await expectLater(
      container.read(settingsProvider.notifier).setAppIcon(AppIconPreference.foldedF),
      throwsA(isA<PlatformException>()),
    );
    expect(container.read(settingsProvider).appIcon, AppIconPreference.leafFolio);
    expect(prefs.getString(appIconPreferenceKey), 'leafFolio');
  });

  test('a failed preference write rolls back the native icon and cached choice', () async {
    final prefs = FailedIconWrites();
    final icons = FakeIcons();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs), appIconServiceProvider.overrideWithValue(icons)],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(settingsProvider.notifier).setAppIcon(AppIconPreference.foldedF),
      throwsStateError,
    );
    expect(icons.calls, [AppIconPreference.foldedF, AppIconPreference.leafFolio]);
    expect(prefs.getString(appIconPreferenceKey), 'leafFolio');
    container.invalidate(settingsProvider);
    expect(container.read(settingsProvider).appIcon, AppIconPreference.leafFolio);
  });

  test('in-flight changes cannot race or overwrite the confirmed choice', () async {
    final (container, prefs, icons) = await setup({});
    icons.pending = Completer<void>();
    final controller = container.read(settingsProvider.notifier);
    final first = controller.setAppIcon(AppIconPreference.leafFolio);
    await controller.setAppIcon(AppIconPreference.foldedF);
    expect(icons.calls, [AppIconPreference.leafFolio]);
    expect(container.read(settingsProvider).appIcon, AppIconPreference.paperArc);
    expect(prefs.containsKey(appIconPreferenceKey), false);
    icons.pending!.complete();
    await first;
    expect(container.read(settingsProvider).appIcon, AppIconPreference.leafFolio);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    test('startup reconciles the ${platform.name} icon without prompting on iOS', () async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final calls = <MethodCall>[];
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(AppIconService.channel, (call) async {
        calls.add(call);
        return call.method == 'get' ? 'foldedF' : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(AppIconService.channel, null));
      SharedPreferences.setMockInitialValues({appIconPreferenceKey: 'leafFolio'});
      final prefs = await SharedPreferences.getInstance();
      await const AppIconService().initialize(prefs);
      if (platform == TargetPlatform.macOS) {
        expect(calls.single.method, 'set');
        expect(calls.single.arguments, {'icon': 'leafFolio'});
      } else {
        expect(calls.single.method, 'get');
        expect(prefs.getString(appIconPreferenceKey), 'foldedF');
      }
    });
  }

  test('a failed Dock restore reconciles the preference with the actual native icon', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AppIconService.channel, (call) async {
      if (call.method == 'set') throw PlatformException(code: 'icon_unavailable');
      return 'paperArc';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(AppIconService.channel, null));
    SharedPreferences.setMockInitialValues({appIconPreferenceKey: 'leafFolio'});
    final prefs = await SharedPreferences.getInstance();
    await expectLater(const AppIconService().initialize(prefs), throwsA(isA<PlatformException>()));
    expect(prefs.getString(appIconPreferenceKey), 'paperArc');
  });

  testWidgets('settings previews switch icons, disable while busy and show a retryable error', (tester) async {
    final icons = FakeIcons();
    final container = await pumpApp(tester, overrides: [appIconServiceProvider.overrideWithValue(icons)]);
    showSettings(tester.element(find.byType(MMWindowScaffold)));
    await tester.pumpAndSettle();
    final a = find.byKey(const ValueKey('settings-icon-leafFolio'));
    final b = find.byKey(const ValueKey('settings-icon-paperArc'));
    final c = find.byKey(const ValueKey('settings-icon-foldedF'));
    expect(tester.widget<MMInteractive>(b).selected, true);
    icons.pending = Completer<void>();
    await tester.tap(a);
    await tester.pump();
    expect(tester.widget<MMInteractive>(c).enabled, false);
    expect(container.read(settingsProvider).appIcon, AppIconPreference.paperArc);
    icons.pending!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<MMInteractive>(a).selected, true);
    icons.pending = null;
    icons.fail = true;
    await tester.tap(c);
    await tester.pumpAndSettle();
    expect(find.text('Could not change the icon. Please try again.'), findsOneWidget);
    expect(tester.widget<MMInteractive>(a).selected, true);
    icons.fail = false;
    await tester.tap(c);
    await tester.pumpAndSettle();
    expect(tester.widget<MMInteractive>(c).selected, true);
    expect(find.text('Could not change the icon. Please try again.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (name, size, phone, appearance, language) in [
    ('desktop-light-zh', const Size(1280, 820), false, 'light', 'zh'),
    ('desktop-dark-en', const Size(1280, 820), false, 'dark', 'en'),
    ('ipad-zh', const Size(834, 1194), false, 'light', 'zh'),
    ('phone-en', const Size(320, 640), true, 'light', 'en'),
  ]) {
    testWidgets('icon picker fits $name', (tester) async {
      await pumpApp(
        tester,
        size: size,
        prefs: {'settings.appearance': appearance, 'settings.language': language},
        overrides: [
          appIconServiceProvider.overrideWithValue(FakeIcons(mac: !phone && !name.startsWith('ipad'))),
          touchPlatformProvider.overrideWithValue(phone || name.startsWith('ipad')),
          phoneProvider.overrideWithValue(phone),
        ],
      );
      showSettings(tester.element(find.byType(MMWindowScaffold)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-icon-paperArc')), findsOneWidget);
      final context = tester.element(find.byKey(const ValueKey('settings-icon-paperArc')));
      await tester.runAsync(
        () => Future.wait([
          for (final icon in AppIconPreference.values) precacheImage(AssetImage(icon.previewAsset), context),
        ]),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'icons-$name', target: find.byKey(const ValueKey('settings-window')));
    });
  }
}
