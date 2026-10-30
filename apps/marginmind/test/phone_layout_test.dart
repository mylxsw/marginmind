import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/phone_tabs.dart';
import 'package:marginmind/features/library/library_screen.dart';
import 'package:marginmind/features/review/review_screen.dart';
import 'package:marginmind/features/workspace/widgets/map_export_sheet.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/notices.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

/// A phone window: logical size, safe area insets and the platform whose
/// tab bar style it gets.
typedef Phone = ({String name, Size size, EdgeInsets safe, TargetPlatform platform});

const iphone = (
  name: 'iPhone 402×874',
  size: Size(402, 874),
  safe: EdgeInsets.fromLTRB(0, 62, 0, 34),
  platform: TargetPlatform.iOS,
);
const pixel = (
  name: 'Android 411×914',
  size: Size(411, 914),
  safe: EdgeInsets.fromLTRB(0, 50, 0, 24),
  platform: TargetPlatform.android,
);
const phones = <Phone>[iphone, pixel];

Future<ProviderContainer> pumpPhone(WidgetTester tester, Phone phone, {bool isPhone = true}) async {
  final container = await pumpApp(
    tester,
    size: phone.size,
    overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(isPhone)],
  );
  tester.view.padding = FakeViewPadding(
    left: phone.safe.left,
    top: phone.safe.top,
    right: phone.safe.right,
    bottom: phone.safe.bottom,
  );
  await tester.pumpAndSettle();
  return container;
}

Future<ProviderContainer> openStudySet(WidgetTester tester, Phone phone) async {
  final container = await pumpPhone(tester, phone);
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  container.read(workspaceProvider('demo-1').notifier).openDocument('c1');
  await tester.pumpAndSettle();
  return container;
}

Finder tab(PhoneTab tab) => find.byKey(ValueKey('mm-tab-${tab.index}'));

PhoneTab? selectedTab(WidgetTester tester) {
  final bar = tester.widget<MMTabBar>(find.byType(MMTabBar));
  return bar.selected == null ? null : PhoneTab.values[bar.selected!];
}

Future<void> systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  for (final phone in phones) {
    final variant = TargetPlatformVariant.only(phone.platform);

    testWidgets('${phone.name}: tabs switch library, source, map and review without overflow', (tester) async {
      final container = await pumpPhone(tester, phone);
      final nav = container.read(navigationProvider.notifier);
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(selectedTab(tester), PhoneTab.library);
      // Nothing opened yet: the study set tabs wait for one.
      await tester.tap(tab(PhoneTab.map));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryScreen), findsOneWidget);

      // The bar floats above the home indicator inset, over the content.
      final bar = tester.getRect(find.byKey(const ValueKey('mm-tab-bar-glass')));
      expect(bar.bottom, phone.size.height - phone.safe.bottom);
      expect(bar.height, phone.platform == TargetPlatform.android ? MMSizes.tabBarAndroid : MMSizes.tabBar);

      nav.openStudySet('demo-1');
      await tester.pumpAndSettle();
      container.read(workspaceProvider('demo-1').notifier).openDocument('c1');
      await tester.pumpAndSettle();
      expect(selectedTab(tester), PhoneTab.source);
      expect(find.byType(ReaderPane), findsOneWidget);
      // The tabs replace the Source | Map switch.
      expect(find.byKey(const ValueKey('workspace-pane-switch')), findsNothing);
      // The pages run on beneath the bar; the page navigation stays above it.
      expect(tester.getRect(find.byType(ReaderPane)).bottom, phone.size.height);
      expect(tester.getRect(find.byKey(const ValueKey('reader-page-navigation'))).bottom, lessThanOrEqualTo(bar.top));

      await tester.tap(tab(PhoneTab.map));
      await tester.pumpAndSettle();
      expect(selectedTab(tester), PhoneTab.map);
      expect(container.read(workspaceProvider('demo-1')).layout, MMSplitMode.secondary);
      expect(find.byType(MapPane), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'map');

      await tester.tap(tab(PhoneTab.source));
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).layout, MMSplitMode.primary);

      await tester.tap(tab(PhoneTab.review));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(selectedTab(tester), PhoneTab.review);
      expect(tester.takeException(), isNull, reason: 'review');

      await tester.tap(tab(PhoneTab.library));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'library');

      // From the library the tabs go back to the study set opened last.
      await tester.tap(tab(PhoneTab.map));
      await tester.pumpAndSettle();
      expect(container.read(navigationProvider), isA<WorkspaceRoute>());
      expect(selectedTab(tester), PhoneTab.map);

      nav.showStats('demo-1');
      await tester.pumpAndSettle();
      expect(selectedTab(tester), PhoneTab.review);
      expect(tester.takeException(), isNull, reason: 'stats');
      await settleHud(tester);
    }, variant: variant);

    testWidgets('${phone.name}: the assistant and card details rise as a bottom sheet', (tester) async {
      final container = await openStudySet(tester, phone);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      final sheet = find.byKey(const ValueKey('mm-bottom-sheet'));

      controller.showDetails('c3');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('workspace-panel-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-floating-panel')), findsNothing);
      // Over the tabs, at the medium height.
      final medium = tester.getRect(sheet);
      expect(medium.bottom, phone.size.height);
      final room = phone.size.height - phone.safe.top - MMSpacing.s;
      expect(medium.height, moreOrLessEquals(room * MMSizes.bottomSheetMedium, epsilon: 1));
      expect(tester.takeException(), isNull, reason: 'details sheet');

      // Dragging the handle up takes the full height; down returns.
      final handle = find.byKey(const ValueKey('mm-bottom-sheet-handle'));
      await tester.drag(handle, Offset(0, -room * 0.3));
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet).height, moreOrLessEquals(room, epsilon: 1));
      await tester.drag(handle, Offset(0, room * 0.3));
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet).height, moreOrLessEquals(room * MMSizes.bottomSheetMedium, epsilon: 1));

      // The soft keyboard puts the sheet on it at full height.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      final typing = tester.getRect(sheet);
      expect(typing.bottom, phone.size.height - 300);
      expect(typing.height, moreOrLessEquals(phone.size.height - 300 - phone.safe.top - MMSpacing.s, epsilon: 1));
      // The tabs step aside for the keyboard.
      expect(find.byType(MMTabBar), findsNothing);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.byType(MMTabBar), findsOneWidget);

      // Dragging it down closes the panel.
      await tester.drag(handle, Offset(0, room * 0.5));
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).panel, isNull);
      expect(sheet, findsNothing);

      controller.openPanel(RightPanel.assistant);
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'assistant sheet');
      await tester.tapAt(Offset(phone.size.width / 2, phone.safe.top + 20));
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).panel, isNull);
      await settleHud(tester);
    }, variant: variant);

    testWidgets('${phone.name}: system back closes menus, sheets and editing before going up', (tester) async {
      final container = await openStudySet(tester, phone);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      final nav = container.read(navigationProvider.notifier);

      // The panel sheet closes first.
      controller.openPanel(RightPanel.assistant);
      await tester.pumpAndSettle();
      await systemBack(tester);
      expect(container.read(workspaceProvider('demo-1')).panel, isNull);
      expect(container.read(navigationProvider), isA<WorkspaceRoute>());

      // Then the sidebar drawer.
      await tester.tap(find.byTooltip('Show Sidebar'));
      await tester.pumpAndSettle();
      final scrim = find.byKey(const ValueKey('mm-drawer-scrim'));
      expect(
        tester.widget<IgnorePointer>(find.ancestor(of: scrim, matching: find.byType(IgnorePointer)).first).ignoring,
        isFalse,
      );
      await systemBack(tester);
      expect(
        tester.widget<IgnorePointer>(find.ancestor(of: scrim, matching: find.byType(IgnorePointer)).first).ignoring,
        isTrue,
      );
      expect(container.read(navigationProvider), isA<WorkspaceRoute>());

      // A sheet route pops before the page.
      final context = tester.element(find.byType(ReaderPane));
      showConfirmSheet(context, title: 'Sheet', message: 'Body', confirmLabel: 'OK');
      await tester.pumpAndSettle();
      expect(find.text('Sheet'), findsOneWidget);
      // A compact window shows it from the bottom.
      expect(find.byKey(const ValueKey('mm-bottom-sheet')), findsOneWidget);
      await systemBack(tester);
      expect(find.text('Sheet'), findsNothing);
      expect(container.read(navigationProvider), isA<WorkspaceRoute>());

      // Editing ends before navigation.
      controller.beginEditing('c3');
      await tester.pumpAndSettle();
      // Editing from the source brings the map in, alone.
      expect(container.read(workspaceProvider('demo-1')).layout, MMSplitMode.secondary);
      bool editing() {
        final field = FocusManager.instance.primaryFocus?.context;
        return field != null && field.findAncestorWidgetOfExactType<EditableText>() != null;
      }

      expect(editing(), isTrue);
      await systemBack(tester);
      expect(editing(), isFalse);
      expect(container.read(workspaceProvider('demo-1')).editingCardId, isNull);
      expect(container.read(navigationProvider), isA<WorkspaceRoute>());

      // The workspace goes up to the library, review to its study set.
      await systemBack(tester);
      expect(container.read(navigationProvider), isA<LibraryRoute>());
      nav.startReview('demo-1');
      await tester.pumpAndSettle();
      await systemBack(tester);
      expect(container.read(navigationProvider), isA<WorkspaceRoute>());
      nav.showStats('demo-1');
      await tester.pumpAndSettle();
      await systemBack(tester);
      expect(container.read(navigationProvider), isA<WorkspaceRoute>());
      nav.showLibrary();
      await tester.pumpAndSettle();

      // The library leaves back to the system.
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await systemBack(tester);
      expect(calls.map((c) => c.method), contains('SystemNavigator.pop'));
      expect(container.read(navigationProvider), isA<LibraryRoute>());
      await settleHud(tester);
    }, variant: variant);

    testWidgets('${phone.name}: long press opens an action sheet that back and Cancel close', (tester) async {
      await pumpPhone(tester, phone);
      await tester.longPress(find.text('注意力与专注').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mm-action-sheet')), findsOneWidget);
      expect(find.text('Rename…'), findsOneWidget);
      final sheet = tester.getRect(find.byKey(const ValueKey('mm-action-sheet')));
      expect(sheet.bottom, lessThanOrEqualTo(phone.size.height - phone.safe.bottom));
      await systemBack(tester);
      expect(find.byKey(const ValueKey('mm-action-sheet')), findsNothing);
      expect(find.byType(LibraryScreen), findsOneWidget);

      await tester.longPress(find.text('注意力与专注').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mm-action-sheet')), findsNothing);

      // Choosing an item runs it: Rename opens its sheet from the bottom.
      await tester.longPress(find.text('注意力与专注').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename…'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mm-bottom-sheet')), findsOneWidget);
      expect(find.byType(MMSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: variant);

    testWidgets('${phone.name}: an excerpt stays on the source and offers View once', (tester) async {
      final container = await openStudySet(tester, phone);
      final context = tester.element(find.byType(ReaderPane));
      // A long target ends in an ellipsis; View stays in reach.
      showNotice(
        context,
        const ExcerptedNotice('Sample: Forgetting & Spaced Repetition, chapter two', cardId: 'c4'),
        rootTitle: 'Root',
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('View'), findsOneWidget);
      expect(tester.getRect(find.text('View')).right, lessThan(phone.size.width));
      expect(container.read(workspaceProvider('demo-1')).layout, isNot(MMSplitMode.secondary));
      // Above the tabs.
      expect(tester.getRect(find.text('View')).bottom, lessThan(tester.getRect(find.byType(MMTabBar)).top));
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      final state = container.read(workspaceProvider('demo-1'));
      expect(state.layout, MMSplitMode.secondary);
      expect(state.selectedCardId, 'c4');
      expect(selectedTab(tester), PhoneTab.map);
      await settleHud(tester);

      // With the map in view the HUD has nothing to offer.
      showNotice(tester.element(find.byType(MapPane)), const ExcerptedNotice(null, cardId: 'c4'), rootTitle: 'Root');
      await tester.pump();
      expect(find.text('View'), findsNothing);
      await settleHud(tester);
    }, variant: variant);

    testWidgets('${phone.name}: map export opens as a bottom sheet that fits the width', (tester) async {
      final container = await openStudySet(tester, phone);
      await tester.tap(tab(PhoneTab.map));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(MapPane));
      showMapExportSheet(context, context as WidgetRef, 'demo-1');
      await tester.pumpAndSettle();
      expect(find.byType(MapExportSheet), findsOneWidget);
      final sheet = tester.getRect(find.byKey(const ValueKey('mm-bottom-sheet')));
      expect(sheet.width, phone.size.width);
      expect(sheet.bottom, phone.size.height);
      expect(tester.takeException(), isNull);
      await systemBack(tester);
      expect(find.byType(MapExportSheet), findsNothing);
      expect(container.read(navigationProvider), isA<WorkspaceRoute>());
      await settleHud(tester);
    }, variant: variant);

    testWidgets('${phone.name}: settings fill a bottom sheet with the sections on top', (tester) async {
      await pumpPhone(tester, phone);
      await tester.tap(find.byTooltip('Show Sidebar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(MMIcons.settings));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mm-bottom-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-sidebar')), findsNothing);
      final sections = find.byKey(const ValueKey('settings-sections'));
      expect(sections, findsOneWidget);
      expect(tester.getRect(find.byKey(const ValueKey('settings-window'))).width, phone.size.width);
      for (final label in ['Reading', 'Models', 'Web Search', 'Voice Input', 'General']) {
        await tester.tap(find.descendant(of: sections, matching: find.text(label)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
      }
      await systemBack(tester);
      expect(find.byKey(const ValueKey('settings-window')), findsNothing);
    }, variant: variant);

    testWidgets('${phone.name}: review grades with thumb-sized buttons and a tap turns the card', (tester) async {
      final container = await pumpPhone(tester, phone);
      container.read(navigationProvider.notifier).startReview('demo-1');
      await tester.pumpAndSettle();
      expect(find.text('Show Answer'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('review-card-tap')));
      await tester.pumpAndSettle();
      final good = find.byKey(const ValueKey('rate-good'));
      expect(good, findsOneWidget);
      final buttons = [
        for (final r in ['again', 'hard', 'good', 'easy']) tester.getRect(find.byKey(ValueKey('rate-$r'))),
      ];
      for (final b in buttons) {
        expect(b.height, MMSizes.reviewRatingTouch);
      }
      // The four share the width inside the margins.
      expect(buttons.first.left, MMSpacing.l);
      expect(buttons.last.right, phone.size.width - MMSpacing.l);
      expect(tester.takeException(), isNull);
      await tester.tap(good);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await settleHud(tester);
    }, variant: variant);
  }

  testWidgets('an iPad in Split View keeps the Source | Map switch and no tabs', (tester) async {
    final container = await pumpPhone(tester, (
      name: 'iPad ⅓',
      size: const Size(375, 1032),
      safe: const EdgeInsets.fromLTRB(0, 24, 0, 20),
      platform: TargetPlatform.iOS,
    ), isPhone: false);
    expect(find.byType(MMTabBar), findsNothing);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    container.read(workspaceProvider('demo-1').notifier).openDocument('c1');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-pane-switch')), findsOneWidget);
    expect(find.byType(MMTabBar), findsNothing);
    // Compact tablet companion remains separate from its source.
    container.read(workspaceProvider('demo-1').notifier).showDetails('c3');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tablet-workspace-panel')), findsOneWidget);
    await settleHud(tester);
  });

  testWidgets('a phone on its side is not compact: no tabs, as before', (tester) async {
    await pumpPhone(tester, (
      name: 'iPhone landscape',
      size: const Size(874, 402),
      safe: const EdgeInsets.fromLTRB(62, 0, 62, 21),
      platform: TargetPlatform.iOS,
    ));
    expect(find.byType(MMTabBar), findsNothing);
  });

  testWidgets('desktop windows have no tabs and keep their menus', (tester) async {
    final container = await pumpApp(tester);
    expect(find.byType(MMTabBar), findsNothing);
    expect(container.read(phoneProvider), isFalse);
    await tester.tap(find.text('注意力与专注').last, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mm-action-sheet')), findsNothing);
    expect(find.text('Rename…'), findsOneWidget);
  });

  test('system bars contrast with the theme', () {
    final light = systemBarsStyle(Brightness.light);
    expect(light.statusBarIconBrightness, Brightness.dark);
    expect(light.systemNavigationBarIconBrightness, Brightness.dark);
    expect(light.systemNavigationBarColor, Colors.transparent);
    final dark = systemBarsStyle(Brightness.dark);
    expect(dark.statusBarIconBrightness, Brightness.light);
    expect(dark.statusBarBrightness, Brightness.dark);
    expect(dark.systemNavigationBarIconBrightness, Brightness.light);
  });

  test('tabs follow the route', () {
    expect(phoneTabOf(const LibraryRoute()), PhoneTab.library);
    expect(phoneTabOf(const StatsRoute(null)), PhoneTab.library);
    expect(phoneTabOf(const WorkspaceRoute('a')), PhoneTab.source);
    expect(phoneTabOf(const WorkspaceRoute('a'), mapShown: true), PhoneTab.map);
    expect(phoneTabOf(const ReviewRoute('a')), PhoneTab.review);
    expect(phoneTabOf(const StatsRoute('a')), PhoneTab.review);
    expect(phoneTabOf(const GalleryRoute()), isNull);
  });
}
