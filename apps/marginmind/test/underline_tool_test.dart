import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/reader_annotation_tools.dart';
import 'package:marginmind/features/workspace/widgets/selection_toolbar.dart';
import 'package:marginmind/features/workspace/widgets/annotation_color_button.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/highlight_palette.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'reader_crop_test.dart' show drain;
import 'assistant_quick_actions_test.dart' show screenshot;
import 'helpers.dart';
import 'selection_toolbar_test.dart' show selection;

Future<void> componentScreenshot(WidgetTester tester, String appearance) async {
  final output = Platform.environment['MM_SCREENSHOTS'];
  if (output == null) return;
  final bounds = tester
      .getRect(find.byType(ReaderAnnotationTools))
      .expandToInclude(tester.getRect(find.byKey(const ValueKey('annotation-color-palette'))))
      .inflate(8);
  final image = (await tester.runAsync(
    () => (tester.binding.renderViews.first.debugLayer! as OffsetLayer).toImage(bounds, pixelRatio: 2),
  ))!;
  final data = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  await tester.runAsync(
    () => File('$output/underline-component-$appearance.png').writeAsBytes(data.buffer.asUint8List()),
  );
  image.dispose();
}

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

  test('shared annotation color and underline style restore and survive undo', () async {
    final overrides = await testOverrides();
    var container = ProviderContainer(overrides: overrides);
    final provider = workspaceProvider('demo-1');
    container.listen(provider, (_, _) {});
    await container.read(contentProvider('demo-1').future);
    final controller = container.read(provider.notifier);
    await controller.styleUnderline(color: MMAnnotationColor.tryParse('#12A4B8'), style: AnnotationLineStyle.wavy);
    await controller.setTool(AnnotationTool.underline);
    controller.toggleSyncToMap();
    final before = controller.content.annotations.length;
    expect(await controller.onSelectionCommitted('c1', selection), isA<UnderlinedNotice>());
    final mark = controller.content.annotations.last;
    expect(mark.kind, AnnotationKind.underline);
    expect(mark.lineStyle, AnnotationLineStyle.wavy);
    expect(mark.colorIndex, 0x0112A4B8);
    expect(controller.content.cardForAnnotation(mark.id), isNull);
    await controller.undo();
    expect(controller.content.annotations.length, before);
    await controller.redo();
    expect(controller.content.annotations.last.kind, AnnotationKind.underline);
    expect(container.read(highlightPaletteProvider).current.hex, '#12A4B8');
    expect(container.read(highlightPaletteProvider).usage.values.single.count, 1);
    container.dispose();
    container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    expect(container.read(provider).underlineStyle, AnnotationLineStyle.wavy);
    expect(container.read(provider).color.hex, '#12A4B8');
    expect(container.read(provider).tool, AnnotationTool.underline);
  });

  test('continuous underline honors sync and changing style is undoable', () async {
    final container = ProviderContainer(overrides: await testOverrides());
    addTearDown(container.dispose);
    final provider = workspaceProvider('demo-1');
    container.listen(provider, (_, _) {});
    await container.read(contentProvider('demo-1').future);
    final controller = container.read(provider.notifier);
    await controller.setTool(AnnotationTool.underline);
    await controller.onSelectionCommitted('c1', selection);
    final mark = controller.content.annotations.last;
    expect(controller.content.cardForAnnotation(mark.id), isNotNull);
    await controller.styleUnderline(annotationId: mark.id, style: AnnotationLineStyle.dashed);
    expect(controller.content.annotation(mark.id)?.lineStyle, AnnotationLineStyle.dashed);
    await controller.undo();
    expect(controller.content.annotation(mark.id)?.lineStyle, AnnotationLineStyle.solid);
    await controller.redo();
    expect(controller.content.annotation(mark.id)?.lineStyle, AnnotationLineStyle.dashed);
  });

  testWidgets('underlines linked to a map keep their lines without page-margin icons', (tester) async {
    installTestPdfBackend();
    final container = await pumpApp(tester, renderPdf: true);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    await controller.setTool(AnnotationTool.underline);
    await controller.onSelectionCommitted('c1', selection);
    await drain(tester);
    final mark = controller.content.annotations.last;
    expect(controller.content.cardForAnnotation(mark.id), isNotNull);
    final painted = tester.widget<MMPdfView>(find.byType(MMPdfView)).highlights.where((h) => h.id == mark.id);
    expect(painted, isNotEmpty);
    for (final highlight in painted) {
      expect(highlight.underline, isNotNull);
      expect(highlight.lineStyle, AnnotationLineStyle.solid);
      expect(highlight.marker, isNull);
    }
    expect(find.byKey(ValueKey('pdf-marker-${mark.id}')), findsNothing);
    await settleHud(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  });

  for (final appearance in ['light', 'dark']) {
    testWidgets('color palette stays open, custom color is shared, Esc closes settings in $appearance', (tester) async {
      final container = await pumpApp(tester, prefs: {'settings.appearance': appearance});
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final provider = workspaceProvider('demo-1');
      final top = find.byType(ReaderAnnotationTools);
      await tester.tap(find.descendant(of: top, matching: find.byTooltip('Underline')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AnnotationColorButton));
      await tester.pumpAndSettle();
      final bar = find.byKey(const ValueKey('annotation-color-palette'));
      expect(bar, findsOneWidget);
      expect(container.read(provider).tool, AnnotationTool.underline);
      for (final style in ['Dashed', 'Dotted', 'Wavy', 'Solid']) {
        await tester.tap(find.byTooltip(style));
        await tester.pumpAndSettle();
        expect(bar, findsOneWidget);
        expect(container.read(provider).underlineStyle.name, style.toLowerCase());
      }
      await tester.tap(find.descendant(of: bar, matching: find.byTooltip('Green')));
      await tester.pumpAndSettle();
      expect(container.read(provider).color, MMAnnotationColor.green);
      await tester.tap(find.byTooltip('Dotted'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: bar, matching: find.byTooltip('Blue')));
      await tester.pumpAndSettle();
      await screenshot(tester, 'underline-toolbar-$appearance', target: bar);
      await screenshot(tester, 'underline-entry-$appearance', target: top);
      await componentScreenshot(tester, appearance);
      await tester.tap(find.descendant(of: bar, matching: find.byTooltip('More Colors')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('highlight-color-hex')), '#12A4B8');
      await tester.tap(find.byKey(const ValueKey('highlight-color-apply')));
      await tester.pumpAndSettle();
      expect(container.read(provider).color.hex, '#12A4B8');
      expect(bar, findsOneWidget);
      expect(container.read(provider).color.hex, '#12A4B8');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
      expect(container.read(provider).tool, AnnotationTool.underline);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(container.read(provider).tool, AnnotationTool.select);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('selection underline creates once and edits the same mark without dismissing toolbar', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final provider = workspaceProvider('demo-1');
    final controller = container.read(provider.notifier);
    final before = controller.content.annotations.length;
    await controller.onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-underline')));
    await tester.pumpAndSettle();
    expect(controller.content.annotations.length, before + 1);
    final id = controller.content.annotations.last.id;
    expect(container.read(provider).tool, AnnotationTool.select);
    await tester.tap(find.descendant(of: find.byType(SelectionToolbar), matching: find.byType(AnnotationColorButton)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dotted'));
    await tester.pumpAndSettle();
    expect(controller.content.annotation(id)?.lineStyle, AnnotationLineStyle.dotted);
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('annotation-color-palette')), matching: find.byTooltip('Green')),
    );
    await tester.pumpAndSettle();
    expect(controller.content.annotation(id)?.colorIndex, MMAnnotationColor.green.index);
    expect(controller.content.annotations.length, before + 1);
    expect(find.byType(SelectionToolbar), findsOneWidget);
    await tester.tapAt(const Offset(900, 650));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('annotation-color-palette')), findsNothing);
    expect(container.read(provider).pending, isNull);
    controller.tapHighlight(id, selection.viewportRect!);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Delete Underline'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(SelectionToolbar), matching: find.byType(AnnotationColorButton)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Wavy'));
    await tester.pumpAndSettle();
    expect(controller.content.annotation(id)?.lineStyle, AnnotationLineStyle.wavy);
    expect(controller.content.annotations.length, before + 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await settleHud(tester);
  });

  testWidgets('drag reaches PDF through the non-modal palette and draws the saved line style', (tester) async {
    installTestPdfBackend();
    final container = await pumpApp(tester, renderPdf: true);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final provider = workspaceProvider('demo-1');
    final controller = container.read(provider.notifier);
    controller.toggleSyncToMap();
    final before = controller.content.annotations.length;
    await tester.tap(find.descendant(of: find.byType(ReaderAnnotationTools), matching: find.byTooltip('Underline')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AnnotationColorButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dotted'));
    await tester.pumpAndSettle();
    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    final origin = tester.getTopLeft(find.byType(MMPdfView));
    Offset at(double x) =>
        origin +
        pdf.documentToLocal(pdf.calcRectForRectInsidePage(pageNumber: 1, rect: PdfRect(x, 690, x, 690)).topLeft);
    await tester.dragFrom(at(35), at(150) - at(35), kind: PointerDeviceKind.mouse);
    await drain(tester);
    expect(find.byKey(const ValueKey('annotation-color-palette')), findsNothing);
    expect(container.read(provider).tool, AnnotationTool.underline);
    expect(controller.content.annotations.length, before + 1);
    expect(controller.content.annotations.last.kind, AnnotationKind.underline);
    expect(controller.content.annotations.last.lineStyle, AnnotationLineStyle.dotted);
    final painted = tester
        .widget<MMPdfView>(find.byType(MMPdfView))
        .highlights
        .firstWhere((h) => h.id == controller.content.annotations.last.id);
    expect(painted.color, Colors.transparent);
    expect(painted.lineStyle, AnnotationLineStyle.dotted);
    await settleHud(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('top entry applies existing selection; switching tool closes palette', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final provider = workspaceProvider('demo-1');
    final controller = container.read(provider.notifier);
    controller.toggleSyncToMap();
    await controller.onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(ReaderAnnotationTools), matching: find.byTooltip('Underline')));
    await tester.pumpAndSettle();
    expect(controller.content.annotations.last.quote, selection.text);
    expect(controller.content.annotations.last.kind, AnnotationKind.underline);
    expect(find.byType(SelectionToolbar), findsNothing);
    await tester.tap(find.byIcon(MMIcons.pen));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('annotation-color-palette')), findsNothing);
    expect(container.read(provider).tool, AnnotationTool.ink);
    await settleHud(tester);
  });
}
