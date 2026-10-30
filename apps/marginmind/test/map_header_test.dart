import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marginmind/features/workspace/widgets/map_header.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/map_selection_bar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
  testWidgets('touch multi-selection remains available from the measured header', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: await testOverrides(),
        child: MaterialApp(
          theme: MMTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (_, child) => MMInput(touchPlatform: true, child: MMHudHost(child: child!)),
          home: const Scaffold(body: MapPane(studySetId: 'demo-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(MapPane)));
    final provider = workspaceProvider('demo-1');
    container.read(provider.notifier).selectCard('c3');
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('map-multi-select'));
    expect(find.descendant(of: find.byType(MapHeader), matching: toggle), findsOneWidget);
    await tester.tap(toggle, kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();
    expect(tester.widget<MMToolbarButton>(toggle).selected, isTrue);
    await tester.tap(find.byKey(const ValueKey('c4')), kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();
    expect(container.read(provider).selectedCardIds, {'c3', 'c4'});
    await settleHud(tester);
  });
  testWidgets('a header-only reflow updates canvas clearance in the same frame', (tester) async {
    final geometry = MapHeaderGeometry();
    final controlsWidth = ValueNotifier<double>(180);
    addTearDown(controlsWidth.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 632,
            height: 400,
            child: CustomMultiChildLayout(
              delegate: MapPaneHeaderLayout(geometry, top: MMSpacing.s),
              children: [
                LayoutId(
                  id: MapPaneSlot.canvas,
                  child: LayoutBuilder(builder: (_, _) => Text('${geometry.toolbarTopInset}')),
                ),
                LayoutId(
                  id: MapPaneSlot.header,
                  child: MapHeader(
                    title: const SizedBox(width: 50, height: 16),
                    commands: const SizedBox(width: 300, height: 36),
                    controls: ValueListenableBuilder<double>(
                      valueListenable: controlsWidth,
                      builder: (_, width, _) => SizedBox(width: width, height: 36),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('52.0'), findsOneWidget);
    controlsWidth.value = 300;
    await tester.pump();
    expect(find.text('96.0'), findsOneWidget);
    controlsWidth.value = 180;
    await tester.pump();
    expect(find.text('52.0'), findsOneWidget);
  });
  for (final reduce in [false, true]) {
    testWidgets('map header uses frosted glass and consistent icons (reduce transparency: $reduce)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: await testOverrides(),
          child: MaterialApp(
            theme: MMTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (_, child) => MMAppearance(reduceTransparency: reduce, child: child!),
            home: const Scaffold(body: MapPane(studySetId: 'demo-1')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(MapCommandBar), matching: find.byType(MMLiquidGlass)), findsOneWidget);
      expect(tester.widget(find.byKey(const ValueKey('map-view-glass'))), isA<MMLiquidGlass>());
      for (final surface in [find.byType(MapCommandBar), find.byKey(const ValueKey('map-view-glass'))]) {
        final filters = tester.widgetList<BackdropFilter>(
          find.descendant(of: surface, matching: find.byType(BackdropFilter)),
        );
        expect(filters, hasLength(reduce ? 0 : 1));
        if (!reduce) expect(filters.single.filter, MMLiquidGlass.liquidFilter(24));
      }
      Icon icon(String key) =>
          tester.widget<Icon>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Icon)));
      expect(icon('map-style-button').size, icon('map-command-image').size);
      expect(icon('map-style-button').size, 16);
      await settleHud(tester);
    });
  }
  testWidgets('measured controls share a row below the old breakpoint and wrap only when they cannot fit', (
    tester,
  ) async {
    final geometry = MapHeaderGeometry();
    Future<void> show(double width, {double controlsWidth = 180}) => tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: 400,
            child: CustomMultiChildLayout(
              delegate: MapPaneHeaderLayout(geometry, top: MMSpacing.s),
              children: [
                LayoutId(
                  id: MapPaneSlot.canvas,
                  child: LayoutBuilder(
                    builder: (_, _) => Text('${geometry.toolbarTopInset}', key: const ValueKey('clearance')),
                  ),
                ),
                LayoutId(
                  id: MapPaneSlot.header,
                  child: MapHeader(
                    title: const SizedBox(key: ValueKey('title'), width: 50, height: 16),
                    commands: const SizedBox(key: ValueKey('commands'), width: 300, height: 36),
                    controls: SizedBox(key: const ValueKey('controls'), width: controlsWidth, height: 36),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Rect rect(String id) => tester.getRect(find.byKey(ValueKey(id)));
    for (final width in [600.0, 632.0, 800.0]) {
      await show(width);
      expect(rect('commands').center.dy, rect('controls').center.dy);
      expect(rect('title').right, lessThan(rect('commands').left));
      expect(rect('commands').right, lessThan(rect('controls').left));
      expect(geometry.toolbarTopInset, 52);
      expect(find.text('52.0'), findsOneWidget, reason: 'canvas gets the measured height in the same frame');
    }
    await show(500);
    expect(rect('commands').top, greaterThan(rect('controls').bottom));
    expect(geometry.toolbarTopInset, 96);
    // Larger labels (another language or text size) drive the layout too.
    await show(632, controlsWidth: 300);
    expect(rect('commands').top, greaterThan(rect('controls').bottom));
    await show(800, controlsWidth: 300);
    expect(rect('commands').center.dy, rect('controls').center.dy);
    expect(geometry.toolbarTopInset, 52);
    expect(tester.takeException(), isNull);
  });
}
