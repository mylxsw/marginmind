import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_design/mm_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_support.dart' show FakeSecrets;
import 'helpers.dart';

void main() {
  test('settings load, change and persist', () async {
    SharedPreferences.setMockInitialValues({'settings.appearance': 'dark'});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);

    final settings = container.read(settingsProvider);
    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.locale, isNull);

    await container.read(settingsProvider.notifier).setLanguage(LanguagePreference.zh);
    await container.read(settingsProvider.notifier).setAppearance(AppearancePreference.system);
    expect(container.read(settingsProvider).locale, const Locale('zh'));
    expect(prefs.getString('settings.language'), 'zh');
    expect(prefs.getString('settings.appearance'), 'system');
    await container.read(settingsProvider.notifier).setReaderStyle(MMReaderStyle.paper);
    expect(prefs.getString('settings.readerStyle'), 'paper');
    container.invalidate(settingsProvider);
    expect(container.read(settingsProvider).readerStyle, MMReaderStyle.paper);
  });

  test('unknown stored values fall back to defaults', () async {
    SharedPreferences.setMockInitialValues({'settings.appearance': 'sepia', 'settings.language': 'fr'});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    expect(container.read(settingsProvider).appearance, AppearancePreference.system);
    expect(container.read(settingsProvider).language, LanguagePreference.system);
  });

  group('settings window', () {
    Future<ProviderContainer> openSettings(WidgetTester tester, {bool? showsGallery}) async {
      final container = await pumpApp(tester, overrides: [assistantSecretsProvider.overrideWithValue(FakeSecrets())]);
      final context = tester.element(find.byType(MMWindowScaffold));
      showSettings(context, showsGallery: showsGallery);
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('hides the gallery in release builds; Esc closes', (tester) async {
      await openSettings(tester, showsGallery: false);
      expect(find.text('General'), findsNWidgets(2), reason: 'the sidebar row and the page title');
      expect(find.text('Component Gallery'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsWindow), findsNothing);
    });

    testWidgets('opens the gallery in debug builds', (tester) async {
      final container = await openSettings(tester); // tests run in debug mode
      await tester.tap(find.text('Component Gallery'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsWindow), findsNothing);
      expect(container.read(navigationProvider), isA<GalleryRoute>());
    });

    testWidgets('tabs: general, reading, models and web search', (tester) async {
      final container = await openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('settings-tab-models')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-models')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-tab-webSearch')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-web-search')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-tab-general')));
      await tester.pumpAndSettle();
      // Flutter 3.47 asserts (debug + semantics only) when a sheet closes
      // after a pop-up opened over it; choices come last for that reason.
      await tester.tap(find.byKey(const ValueKey('settings-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('简体中文').last);
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).language, LanguagePreference.zh);
      await tester.tap(find.byKey(const ValueKey('settings-tab-reading')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-reader-style')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('纸质').last);
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).readerStyle, MMReaderStyle.paper);
    });

    testWidgets('a centered 780×560 dialog: glass sidebar beside a titled page', (tester) async {
      await openSettings(tester);
      final window = tester.getRect(find.byKey(const ValueKey('settings-window')));
      expect(window.size, SettingsWindow.size);
      expect(window.center, const Offset(640, 410));
      final sidebar = tester.getRect(find.byKey(const ValueKey('settings-sidebar')));
      expect(sidebar.width, SettingsWindow.sidebarWidth);
      expect(sidebar.left - window.left, closeTo(8, .6));
      expect(find.byType(BackdropFilter), findsWidgets);
      expect(
        find.descendant(of: find.byKey(const ValueKey('settings-sidebar')), matching: find.text('Settings')),
        findsOneWidget,
      );
      Text title() => tester.widget<Text>(find.byKey(const ValueKey('settings-title')));
      expect(title().data, 'General');
      await tester.tap(find.byKey(const ValueKey('settings-tab-webSearch')));
      await tester.pumpAndSettle();
      expect(title().data, 'Web Search');
      final selected = tester.widget<MMSidebarItem>(find.byKey(const ValueKey('settings-tab-webSearch')));
      expect(selected.selected, isTrue);
      expect(tester.getRect(find.byKey(const ValueKey('settings-close'))).right, lessThan(window.right - 8));
    });

    testWidgets('shrinks with the window, never below its minimum', (tester) async {
      await pumpApp(tester, overrides: [assistantSecretsProvider.overrideWithValue(FakeSecrets())]);
      final context = tester.element(find.byType(MMWindowScaffold));
      Future<Size> sizeIn(Size window) async {
        showMMDialog<void>(
          context: context,
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(size: window),
            child: const SettingsWindow(showsGallery: false),
          ),
        );
        await tester.pumpAndSettle();
        final size = tester.getSize(find.byKey(const ValueKey('settings-window')));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        return size;
      }

      expect(await sizeIn(const Size(700, 500)), const Size(652, 452));
      expect(await sizeIn(const Size(900, 470)), const Size(780, 440), reason: 'the margins go first');
      expect(await sizeIn(const Size(600, 400)), const Size(600, 400), reason: 'never larger than the window');
    });

    testWidgets('opaque sidebar when transparency is reduced', (tester) async {
      await pumpApp(tester, overrides: [assistantSecretsProvider.overrideWithValue(FakeSecrets())]);
      final context = tester.element(find.byType(MMWindowScaffold));
      showMMDialog<void>(
        context: context,
        builder: (_) => const MMAppearance(reduceTransparency: true, child: SettingsWindow(showsGallery: false)),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byKey(const ValueKey('settings-sidebar')), matching: find.byType(BackdropFilter)),
        findsNothing,
      );
    });

    testWidgets('the close button closes', (tester) async {
      await openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('settings-close')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsWindow), findsNothing);
    });
  });
}
