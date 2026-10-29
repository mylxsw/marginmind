import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/reader_margin.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';
import 'reader_crop_test.dart' show drain;

Future<Color> paintedColor(WidgetTester tester, Finder target, Offset local) async {
  final box = tester.renderObject<RenderBox>(target);
  // Capture the complete reader, including the PDF's separate repaint layer.
  RenderObject boundary = tester.renderObject(find.byType(ReaderPane));
  while (!boundary.isRepaintBoundary) {
    boundary = boundary.parent!;
  }
  final surface = boundary as RenderBox;
  final point = surface.globalToLocal(box.localToGlobal(local));
  final image = (await tester.runAsync(
    () => (surface.debugLayer! as OffsetLayer).toImage(Offset.zero & surface.size),
  ))!;
  try {
    final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    final offset = (point.dy.floor() * image.width + point.dx.floor()) * 4;
    return Color.fromARGB(
      bytes.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  } finally {
    image.dispose();
  }
}

void main() {
  setUp(installTestPdfBackend);

  testWidgets('expanded margin paints paper across its width in every reading palette', (tester) async {
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    TestPdfRender.produceImages = true;
    TestPdfRender.scanImage = true;
    addTearDown(() {
      TestPdfRender.produceImages = false;
      TestPdfRender.scanImage = false;
      TestPdfRender.renders.clear();
    });
    final repository = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final container = await pumpApp(tester, renderPdf: true, content: repository, size: const Size(1800, 1000));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    container.read(workspaceProvider('demo-1').notifier).setLayout(MMSplitMode.primary);
    container.read(readerMarginProvider('demo-1').notifier).expand('c1');
    await drain(tester);
    for (final style in MMReaderStyle.values) {
      await container.read(settingsProvider.notifier).setReaderStyle(style);
      await drain(tester);
      final column = find.byKey(const ValueKey('margin-column-1'));
      expect(column, findsOneWidget);
      final size = tester.getSize(column);
      for (final x in [.1, .5, .9]) {
        expect(
          await paintedColor(tester, column, Offset(size.width * x, 60)),
          sameColor(style.paperColor),
          reason: '${style.name} at $x of the column width',
        );
      }
      final columnRect = tester.getRect(column);
      final seamY = columnRect.intersect(tester.getRect(find.byType(MMPdfView))).center.dy - columnRect.top;
      for (final x in [-2.0, 2.0]) {
        expect(
          await paintedColor(tester, column, Offset(x, seamY)),
          sameColor(style.paperColor),
          reason: '${style.name} keeps both sides of the visible paper seam filled',
        );
      }
      if (style == MMReaderStyle.white) {
        final edge = await paintedColor(tester, column, Offset(size.width + 2, 60));
        final outside = await paintedColor(tester, column, Offset(size.width + 25, 60));
        expect(edge.r, lessThan(outside.r), reason: 'the sheet shadow reaches the outer margin edge');
      }
    }
    debugDisableShadows = true;
    expect(tester.takeException(), isNull);
  });

  testWidgets('margin toolbar count is inline and disappears when the active document has no notes', (tester) async {
    final container = await pumpApp(tester, size: const Size(1800, 1000));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    final session = container.read(readerMarginProvider('demo-1').notifier);
    final button = find.byKey(const ValueKey('reader-margin'));
    Finder count(String value) => find.descendant(of: button, matching: find.text(value));
    expect(find.descendant(of: button, matching: find.byType(Text)), findsNothing);
    await session.start('c1', page: 1, lineY: 500);
    session.text('Saved note');
    await session.finish();
    await tester.pumpAndSettle();
    expect(count('1'), findsOneWidget);
    expect(find.descendant(of: find.byType(ReaderPane), matching: find.byType(Badge)), findsNothing);
    final icon = find.descendant(of: button, matching: find.byIcon(MMIcons.marginNote));
    final text = tester.widget<Text>(count('1'));
    expect(text.style!.fontSize, 10);
    expect(text.style!.fontWeight, FontWeight.w600);
    expect(text.style!.fontFeatures, const [ui.FontFeature.tabularFigures()]);
    expect(text.style!.color, tester.widget<Icon>(icon).color);
    expect(tester.getTopLeft(count('1')).dx - tester.getTopRight(icon).dx, closeTo(2, .01));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(count('1')).style!.color, tester.widget<Icon>(icon).color);
    workspace.openDocument(workspace.content.documents.last.id);
    await tester.pumpAndSettle();
    expect(find.descendant(of: button, matching: find.byType(Text)), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
