import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/annotation_palette.dart';
import 'package:marginmind/features/workspace/widgets/highlight_color_button.dart';
import 'package:marginmind/features/workspace/widgets/highlight_custom_color_picker.dart';
import 'package:marginmind/features/workspace/widgets/map_selection_bar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/highlight_palette.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'workspace_test.dart' show openFirstSet;

StudySetContent fixture() {
  var id = 0;
  final content = demoContent();
  return StudySetEditor(newId: () => 'color-${id++}', now: () => testNow)
      .createExcerpt(
        content,
        documentId: content.documents.first.id,
        page: 25,
        rects: const [],
        quote: 'Another excerpt',
        colorIndex: MMAnnotationColor.green.index,
        parentId: 'c3',
      )
      .$1;
}

void mapColorToolbarTests({bool native = false}) {
  final button = find.byKey(const ValueKey('node-bar-color'));
  final palette = find.byKey(const ValueKey('highlight-color-palette'));
  Finder swatch(MMAnnotationColor color) =>
      find.byWidgetPredicate((w) => w is MMFloatingToolbarColor && w.color == color);

  testWidgets('the shared custom picker keeps touch presets reachable in a narrow viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    MMAnnotationColor? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (_, child) => MMInput(touchPlatform: true, child: child!),
        home: Scaffold(
          body: Center(
            child: HighlightCustomColorPicker(
              current: MMAnnotationColor.yellow,
              onSelected: (color) => picked = color,
              onCancel: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(swatch(MMAnnotationColor.purple));
    await tester.tap(swatch(MMAnnotationColor.purple));
    expect(picked, MMAnnotationColor.purple);
  }, semanticsEnabled: !native);

  testWidgets('one button expands below the map toolbar; presets batch recolor and undo once', (tester) async {
    final content = fixture();
    final excerpts = content.cards.where((c) => c.kind == CardKind.excerpt).map((c) => c.id).toSet();
    final container = await openFirstSet(tester, content: InMemoryStudySetContentRepository({'demo-1': content}));
    final provider = workspaceProvider('demo-1');
    final controller = container.read(provider.notifier);
    controller.selectCards(excerpts);
    await showWholeMap(tester);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(MapSelectionBar), matching: find.byType(HighlightColorButton)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(MapSelectionBar), matching: find.byType(MMFloatingToolbarColor)),
      findsNothing,
    );
    expect(palette, findsNothing);
    final main = tester.getRect(find.byType(MapSelectionBar));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(palette, findsOneWidget);
    expect(tester.getRect(palette).top, greaterThan(main.bottom));
    expect(find.descendant(of: palette, matching: find.byType(MMFloatingToolbarColor)), findsNWidgets(6));
    expect(
      tester
          .widgetList<MMFloatingToolbarColor>(
            find.descendant(of: palette, matching: find.byType(MMFloatingToolbarColor)),
          )
          .where((w) => w.selected),
      isEmpty,
      reason: 'mixed colors have no false active swatch',
    );
    final more = find.descendant(of: palette, matching: find.byType(AnnotationMoreColorsButton));
    expect(tester.getCenter(more).dx, greaterThan(tester.getCenter(swatch(MMAnnotationColor.purple)).dx));
    expect(container.read(provider).selectedCardIds, excerpts);
    await tester.tap(swatch(MMAnnotationColor.blue));
    await tester.pumpAndSettle();
    expect(palette, findsNothing);
    expect(controller.content.annotations.map((a) => a.colorIndex).toSet(), {MMAnnotationColor.blue.index});
    expect(container.read(highlightPaletteProvider).usage[MMAnnotationColor.blue]!.count, 1);
    await controller.undo();
    await tester.pumpAndSettle();
    expect(
      controller.content.annotations.map((a) => a.colorIndex).toList(),
      content.annotations.map((a) => a.colorIndex).toList(),
    );
    await settleHud(tester);
  }, semanticsEnabled: !native);

  testWidgets('map uses the PDF custom picker; exact RGB survives undo/redo, reuse and cancellation', (tester) async {
    final content = fixture();
    final container = await openFirstSet(tester, content: InMemoryStudySetContentRepository({'demo-1': content}));
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.selectCards(content.cards.where((c) => c.kind == CardKind.excerpt).map((c) => c.id));
    await showWholeMap(tester);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AnnotationMoreColorsButton));
    await tester.pumpAndSettle();
    expect(find.byType(HighlightCustomColorPicker), findsOneWidget);
    final custom = MMAnnotationColor.tryParse('#12A4B8')!;
    await tester.enterText(find.byKey(const ValueKey('highlight-color-hex')), custom.hex);
    await tester.pumpAndSettle();
    expect(
      controller.content.annotations.map((a) => a.colorIndex).toList(),
      content.annotations.map((a) => a.colorIndex).toList(),
    );
    expect(container.read(highlightPaletteProvider).usage, isEmpty);
    await tester.tap(find.byKey(const ValueKey('highlight-color-apply')));
    await tester.pumpAndSettle();
    expect(controller.content.annotations.map((a) => a.colorIndex).toSet(), {custom.index});
    expect(
      container.read(highlightPaletteProvider).current,
      custom,
      reason: 'the shared palette remembers the applied custom color',
    );
    await controller.undo();
    await tester.pumpAndSettle();
    expect(
      controller.content.annotations.map((a) => a.colorIndex).toList(),
      content.annotations.map((a) => a.colorIndex).toList(),
    );
    await controller.redo();
    await tester.pumpAndSettle();
    expect(
      controller.content.annotations.every((a) => MMAnnotationColor.fromIndex(a.colorIndex).hex == custom.hex),
      isTrue,
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.widget<MMFloatingToolbarColor>(swatch(custom)).selected, isTrue);
    await tester.tap(find.byType(AnnotationMoreColorsButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('highlight-color-hex')), '#AB1288');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.content.annotations.map((a) => a.colorIndex).toSet(), {custom.index});
    expect(container.read(highlightPaletteProvider).usage[custom]!.count, 1);
    controller.selectCards(['c3', 'c4']);
    await tester.pumpAndSettle();
    expect(button, findsNothing, reason: 'uncolorable topics do not show an ineffective action');
    await settleHud(tester);
  }, semanticsEnabled: !native);
}

void main() => mapColorToolbarTests();
