import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/reader_margin.dart';
import 'package:marginmind/features/workspace/widgets/highlight_color_button.dart';
import 'package:marginmind/features/workspace/widgets/reader_annotation_tools.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/highlight_palette.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'assistant_quick_actions_test.dart' show screenshot;
import 'helpers.dart';
import 'selection_toolbar_test.dart' show selection;

void main() {
  setUpAll(() async {
    if (Platform.environment['MM_SCREENSHOTS'] == null) return;
    final data = ByteData.sublistView(File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf').readAsBytesSync());
    for (final family in [
      '.AppleSystemUIFont',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'PingFang SC',
    ]) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
    final pub = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
    final icons = Directory('$pub/hosted/pub.dev')
        .listSync()
        .whereType<Directory>()
        .lastWhere((d) => d.path.contains('cupertino_icons-'));
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          Future.value(ByteData.sublistView(File('${icons.path}/assets/CupertinoIcons.ttf').readAsBytesSync())),
        ))
        .load();
  });

  for (final appearance in ['light', 'dark']) {
    testWidgets('inactive brush is neutral; real custom colors apply and are reusable in $appearance', (tester) async {
      final container = await pumpApp(tester, prefs: {'settings.appearance': appearance, 'settings.language': 'zh'});
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final controller = container.read(workspaceProvider('demo-1').notifier);
      final tools = find.byType(ReaderAnnotationTools);
      final brush = find.descendant(of: tools, matching: find.byType(HighlightColorButton));
      final button = find.descendant(of: brush, matching: find.byType(MMToolbarButton));
      expect(tester.widget<MMToolbarButton>(button).selected, isFalse);
      expect(tester.widget<MMToolbarButton>(button).tint, isNull);
      final icon = find.descendant(of: brush, matching: find.byIcon(MMIcons.highlight));
      final paint = tester.widget<RichText>(find.descendant(of: icon, matching: find.byType(RichText)));
      expect((paint.text as TextSpan).style!.color, tester.element(tools).mmColors.label);
      await screenshot(tester, 'inactive-brush-$appearance', target: tools);
      await tester.tap(brush);
      await tester.pumpAndSettle();
      expect(tester.widget<MMToolbarButton>(button).tint, MMAnnotationColor.yellow.color);
      await tester.tap(find.byTooltip('更多颜色'));
      await tester.pumpAndSettle();
      final picker = find.byKey(const ValueKey('highlight-custom-color-picker'));
      expect(picker, findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('highlight-color-hex')), '#12A4B8');
      await tester.pumpAndSettle();
      final expected = MMAnnotationColor.tryParse('#12A4B8')!;
      final preview = tester.widget<Container>(find.byKey(const ValueKey('highlight-color-preview')));
      expect((preview.decoration as BoxDecoration).color, expected.color);
      expect(
        container.read(highlightPaletteProvider).current,
        MMAnnotationColor.yellow,
        reason: 'Editing a draft does not commit any color',
      );
      await screenshot(tester, 'custom-picker-$appearance', target: picker);
      await tester.tap(find.byKey(const ValueKey('highlight-color-apply')));
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).color, expected);
      expect(tester.widget<MMToolbarButton>(button).tint, expected.color);
      expect(container.read(highlightPaletteProvider).usage, isEmpty);
      await screenshot(tester, 'active-custom-brush-$appearance', target: tools);
      await controller.setTool(AnnotationTool.select);
      await tester.pumpAndSettle();
      expect(tester.widget<MMToolbarButton>(button).tint, isNull);
      await controller.onSelectionCommitted('c1', selection);
      await tester.pumpAndSettle();
      final customSwatch = find.byWidgetPredicate((w) => w is MMFloatingToolbarColor && w.color == expected);
      expect(customSwatch, findsOneWidget, reason: 'The current custom color is immediately reusable');
      await tester.tap(customSwatch);
      await tester.pumpAndSettle();
      expect(controller.content.annotations.last.colorIndex, expected.index);
      expect(MMAnnotationColor.fromIndex(controller.content.annotations.last.colorIndex).color, expected.color);
      expect(container.read(highlightPaletteProvider).usage[expected]!.count, 1);
      await controller.undo();
      await settleHud(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }

  testWidgets('color-plane dragging and hue changes are drafts; invalid hex and Escape do not commit', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(HighlightColorButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More Colors'));
    await tester.pumpAndSettle();
    final plane = find.byKey(const ValueKey('highlight-color-saturation-value'));
    final before =
        (tester.widget<Container>(find.byKey(const ValueKey('highlight-color-preview'))).decoration as BoxDecoration)
            .color;
    await tester.tapAt(tester.getCenter(plane));
    await tester.pumpAndSettle();
    final after =
        (tester.widget<Container>(find.byKey(const ValueKey('highlight-color-preview'))).decoration as BoxDecoration)
            .color;
    expect(after, isNot(before));
    await tester.drag(find.byKey(const ValueKey('highlight-color-hue')), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(container.read(highlightPaletteProvider).current, MMAnnotationColor.yellow);
    await tester.enterText(find.byKey(const ValueKey('highlight-color-hex')), '#123');
    await tester.pumpAndSettle();
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('highlight-color-apply'))).onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('highlight-custom-color-picker')), findsNothing);
    expect(container.read(highlightPaletteProvider).current, MMAnnotationColor.yellow);
    expect(container.read(highlightPaletteProvider).usage, isEmpty);
  });

  testWidgets('custom colors render on PDF marks and margin notes; recolor undo restores exact RGB', (tester) async {
    installTestPdfBackend();
    final container = await pumpApp(tester, renderPdf: true);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final custom = MMAnnotationColor.tryParse('#12A4B8')!;
    await controller.highlight('c1', selection, custom);
    await tester.pumpAndSettle();
    final annotation = controller.content.annotations.last;
    final view = tester.widget<MMPdfView>(find.byType(MMPdfView));
    expect(view.highlights.singleWhere((h) => h.id == annotation.id).color, custom.highlight);
    final margin = container.read(readerMarginProvider('demo-1').notifier);
    await margin.start('c1', page: 1, lineY: 500, colorIndex: custom.index);
    margin.text('A custom-colored margin note');
    expect(await margin.finish(), isTrue);
    await tester.pumpAndSettle();
    expect(controller.content.marginNotes.last.colorIndex, custom.index);
    expect(find.text('A custom-colored margin note'), findsWidgets);
    await controller.recolor(annotation.id, MMAnnotationColor.blue);
    await controller.undo();
    await tester.pumpAndSettle();
    expect(controller.content.annotation(annotation.id)!.colorIndex, custom.index);
    await settleHud(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });
}
