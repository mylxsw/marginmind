import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/phone_tabs.dart';
import 'package:marginmind/features/library/widgets/study_set_card.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/system_appearance.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';
import 'phone_layout_test.dart' show Phone, openStudySet, phones, pumpPhone, tab;

class _ReducedTransparency extends SystemAppearanceController {
  @override
  SystemAppearance build() => const SystemAppearance(reduceTransparency: true);
}

Rect _capsule(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('mm-tab-bar-glass')));

Rect _toolbarGlass(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('mm-glass-bar')));

/// Whether the tab highlight sits on [tab], finished sliding.
void _expectHighlightOn(WidgetTester tester, PhoneTab tab) {
  final highlight = find.byKey(const ValueKey('mm-tab-highlight'));
  expect(
    tester.widget<AnimatedOpacity>(find.descendant(of: highlight, matching: find.byType(AnimatedOpacity))).opacity,
    1,
  );
  expect(
    tester.getRect(highlight).center.dx,
    closeTo(tester.getRect(find.byKey(ValueKey('mm-tab-${tab.index}'))).center.dx, 0.01),
  );
}

void main() {
  for (final Phone phone in phones) {
    final variant = TargetPlatformVariant.only(phone.platform);

    testWidgets('${phone.name}: the tab bar floats as a glass capsule clear of the safe area', (tester) async {
      await pumpPhone(tester, phone);
      final capsule = _capsule(tester);
      expect(capsule.left, MMSizes.tabBarMargin + phone.safe.left);
      expect(capsule.right, phone.size.width - MMSizes.tabBarMargin - phone.safe.right);
      expect(capsule.bottom, phone.size.height - phone.safe.bottom, reason: 'clear of the home indicator');
      expect(capsule.height, phone.platform == TargetPlatform.android ? MMSizes.tabBarAndroid : MMSizes.tabBar);
      // Every tab keeps a finger-sized hit area.
      for (final t in PhoneTab.values) {
        final size = tester.getSize(tab(t));
        expect(size.height, greaterThanOrEqualTo(48), reason: '$t');
        expect(size.width, greaterThanOrEqualTo(48), reason: '$t');
      }
      expect(find.ancestor(of: tab(PhoneTab.library), matching: find.byType(MMLiquidGlass)), findsOneWidget);
      _expectHighlightOn(tester, PhoneTab.library);
      expect(tester.takeException(), isNull);
    }, variant: variant);

    testWidgets('${phone.name}: the library scrolls beneath the glass toolbar and tab bar', (tester) async {
      await pumpPhone(tester, phone);
      final scroll = find.byType(CustomScrollView).first;
      // The list reaches both window edges, beneath the glass.
      expect(tester.getRect(scroll), Offset.zero & phone.size);
      final toolbar = _toolbarGlass(tester);
      expect(toolbar.top, 0);
      expect(
        find.descendant(of: find.byKey(const ValueKey('mm-glass-bar')), matching: find.byType(TextField)),
        findsOneWidget,
      );
      // The first row starts below the toolbar's glass.
      expect(tester.getRect(find.byType(StudySetCard).first).top, greaterThanOrEqualTo(toolbar.bottom));

      await tester.fling(scroll, const Offset(0, -3000), 3000);
      await tester.pumpAndSettle();
      final last = tester.getRect(find.byType(StudySetCard).last);
      final capsule = _capsule(tester);
      // The last card scrolls up clear of the bar, fully visible.
      expect(last.bottom, lessThanOrEqualTo(capsule.top));
      expect(last.top, greaterThanOrEqualTo(toolbar.bottom));
      // Cards beneath the bar are content: no glass of their own there.
      expect(find.descendant(of: find.byType(StudySetCard), matching: find.byType(BackdropFilter)), findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: variant);

    testWidgets('${phone.name}: reader and map run beneath the bar; their controls keep clear', (tester) async {
      final container = await openStudySet(tester, phone);
      final capsule = _capsule(tester);
      _expectHighlightOn(tester, PhoneTab.source);
      expect(tester.getRect(find.byType(ReaderPane)).bottom, phone.size.height);
      expect(tester.getRect(find.byKey(const ValueKey('pdf-placeholder-c1'))).bottom, phone.size.height);
      expect(
        tester.getRect(find.byKey(const ValueKey('reader-page-navigation'))).bottom,
        lessThanOrEqualTo(capsule.top),
      );
      // The reader's own controls start below the glass toolbar.
      expect(tester.getRect(find.byType(ReaderPane)).top, 0);
      expect(
        tester.getRect(find.byKey(const ValueKey('pdf-placeholder-c1'))).top,
        greaterThanOrEqualTo(_toolbarGlass(tester).bottom),
      );

      await tester.tap(tab(PhoneTab.map));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // The highlight slides from Source toward Map.
      final highlight = tester.getRect(find.byKey(const ValueKey('mm-tab-highlight'))).center.dx;
      expect(highlight, greaterThan(tester.getRect(tab(PhoneTab.source)).center.dx));
      await tester.pumpAndSettle();
      _expectHighlightOn(tester, PhoneTab.map);
      expect(container.read(workspaceProvider('demo-1')).layout, MMSplitMode.secondary);
      expect(tester.getRect(find.byType(MapPane)), Offset.zero & phone.size);
      expect(tester.getRect(find.byTooltip('Zoom In').last).bottom, lessThanOrEqualTo(capsule.top));
      expect(
        tester.getRect(find.byType(MMSegmentedControl<MapViewMode>)).top,
        greaterThanOrEqualTo(_toolbarGlass(tester).bottom),
      );

      // The outline is laid out between the bars.
      container.read(workspaceProvider('demo-1').notifier).setMapView(MapViewMode.outline);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The bottom sheet of the panel is glass too.
      container.read(workspaceProvider('demo-1').notifier).openPanel(RightPanel.details);
      await tester.pumpAndSettle();
      expect(tester.widget(find.byKey(const ValueKey('mm-bottom-sheet'))), isA<MMLiquidGlass>());
      expect(tester.takeException(), isNull);
    }, variant: variant);

    testWidgets('${phone.name}: Reduce transparency makes the chrome opaque', (tester) async {
      final container = await pumpApp(
        tester,
        size: phone.size,
        overrides: [
          touchPlatformProvider.overrideWithValue(true),
          phoneProvider.overrideWithValue(true),
          systemAppearanceProvider.overrideWith(_ReducedTransparency.new),
        ],
      );
      tester.view.padding = FakeViewPadding(top: phone.safe.top, bottom: phone.safe.bottom);
      await tester.pumpAndSettle();
      expect(container.read(systemAppearanceProvider).reduceTransparency, isTrue);
      expect(find.byType(BackdropFilter), findsNothing);
      final c = tester.element(find.byType(MMTabBar)).mmColors;
      final bar = tester.widget<DecoratedBox>(find.byKey(const ValueKey('mm-glass-bar')));
      expect((bar.decoration as BoxDecoration).color, c.windowBackground);
      final fills = tester
          .widgetList<DecoratedBox>(
            find.descendant(of: find.byKey(const ValueKey('mm-tab-bar-glass')), matching: find.byType(DecoratedBox)),
          )
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color);
      expect(fills, contains(c.glassOpaque));
    }, variant: variant);
  }

  testWidgets('a desktop window keeps its toolbar and glass unchanged', (tester) async {
    final container = await pumpApp(tester);
    expect(find.byKey(const ValueKey('mm-glass-bar')), findsNothing);
    expect(find.byType(MMLiquidGlass), findsNothing);
    expect(find.byType(MMTabBar), findsNothing);
    // Toolbar groups keep the plain blur.
    final filters = tester.widgetList<BackdropFilter>(find.byType(BackdropFilter)).map((f) => f.filter);
    expect(filters, isNotEmpty);
    expect(filters, everyElement(isNot(MMLiquidGlass.liquidFilter(24))));
    expect(filters, contains(ImageFilter.blur(sigmaX: 24, sigmaY: 24)));
    // The content starts below the toolbar, not beneath it.
    final toolbar = tester.getRect(find.byType(MMToolbar));
    expect(tester.getRect(find.byType(CustomScrollView).first).top, greaterThanOrEqualTo(toolbar.bottom));

    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mm-glass-bar')), findsNothing);
    // Map controls use floating glass; desktop window chrome stays separate.
    expect(
      find.byType(MMLiquidGlass).evaluate().length,
      find.descendant(of: find.byType(MapPane), matching: find.byType(MMLiquidGlass)).evaluate().length,
    );
    expect(tester.takeException(), isNull);
  });
}
