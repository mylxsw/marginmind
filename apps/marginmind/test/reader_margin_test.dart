import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/reader_margin.dart';
import 'package:marginmind/features/workspace/widgets/reader_margin_notes.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';
import 'reader_crop_test.dart' show drain;

void main() {
  setUp(installTestPdfBackend);
  testWidgets('selection C creates, Escape saves; blank drafts discard and clearing deletes with undo', (tester) async {
    final repository = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final container = await pumpApp(tester, renderPdf: true, content: repository, size: const Size(1800, 1000));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    workspace.setLayout(MMSplitMode.primary);
    await drain(tester);
    final session = container.read(readerMarginProvider('demo-1').notifier);
    const pages = [
      AnnotationPage(page: 1, rects: [PageRect(30, 700, 190, 680)]),
    ];
    await workspace.onSelectionCommitted(
      'c1',
      const MMPdfSelection(text: 'Selected passage', pages: pages, viewportRect: Rect.fromLTWH(100, 150, 160, 20)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selection-margin-note')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await drain(tester);
    final id = container.read(readerMarginProvider('demo-1')).draft!.id;
    expect(find.byKey(const ValueKey('margin-column-1')), findsOneWidget);
    final field = find.byKey(ValueKey('margin-editor-$id'));
    await tester.enterText(field, '  Remember this\nsecond line  ');
    await tester.pumpAndSettle();
    expect(workspace.content.marginNotes, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await drain(tester);
    expect(workspace.content.marginNotes.single.text, 'Remember this\nsecond line');
    expect(workspace.content.marginNotes.single.anchor!.quote, 'Selected passage');
    final pdfController = container.read(readerPdfProvider('demo-1'));
    final beforeScroll = pdfController.readingPosition!;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byKey(ValueKey('margin-card-$id'))),
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pumpAndSettle();
    expect(pdfController.readingPosition!.y, lessThan(beforeScroll.y));
    await session.start('c1', page: 1, lineY: 550);
    await drain(tester);
    await session.finish();
    await drain(tester);
    expect(workspace.content.marginNotes.length, 1);
    await session.start('c1', existing: workspace.content.marginNotes.single);
    await drain(tester);
    await tester.enterText(find.byKey(ValueKey('margin-editor-$id')), ' ');
    await tester.tap(find.byKey(const ValueKey('reader-margin')));
    await drain(tester);
    expect(workspace.content.marginNotes, isEmpty);
    expect(find.text('Comment Deleted'), findsOneWidget);
    await workspace.undo();
    await drain(tester);
    expect(workspace.content.marginNotes.single.text, 'Remember this\nsecond line');
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('line click and map synchronization preserve layout; markers edit and deletion keeps cards', (
    tester,
  ) async {
    final repository = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final container = await pumpApp(tester, renderPdf: true, content: repository, size: const Size(1800, 1000));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    final session = container.read(readerMarginProvider('demo-1').notifier);
    workspace.setLayout(MMSplitMode.primary);
    session.expand('c1');
    await drain(tester);
    final column = find.byKey(const ValueKey('margin-column-1'));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: tester.getTopLeft(column) + const Offset(20, 150));
    await pointer.moveTo(tester.getTopLeft(column) + const Offset(30, 150));
    await tester.pump();
    expect(find.text('+ Comment'), findsOneWidget);
    await tester.tapAt(tester.getTopLeft(column) + const Offset(30, 150));
    await drain(tester);
    var note = container.read(readerMarginProvider('demo-1')).draft!;
    expect(note.anchor, isNull);
    expect(note.lineY, inInclusiveRange(0, 800));
    await tester.enterText(find.byKey(ValueKey('margin-editor-${note.id}')), 'A line note');
    await session.finish();
    await drain(tester);
    final layout = container.read(workspaceProvider('demo-1')).layout;
    final cardId = (await workspace.attachMarginNote(note.id))!;
    await drain(tester);
    note = workspace.content.marginNotes.single;
    expect(workspace.content.card(cardId)!.kind, CardKind.note);
    expect(container.read(workspaceProvider('demo-1')).layout, layout);
    await workspace.rename(cardId, 'From map');
    await drain(tester);
    expect(workspace.content.marginNotes.single.text, 'From map');
    await session.start('c1', existing: workspace.content.marginNotes.single);
    session.text('From margin');
    await session.finish();
    await drain(tester);
    expect(workspace.content.card(cardId)!.title, 'From margin');
    session.toggle('c1');
    await drain(tester);
    expect(find.byKey(const ValueKey('margin-column-1')), findsNothing);
    final marker = find.byKey(ValueKey('margin-marker-${note.id}'));
    expect(marker, findsOneWidget);
    await tester.tap(marker);
    await drain(tester);
    expect(find.byKey(const ValueKey('margin-popover')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('margin-card-${note.id}')));
    await drain(tester);
    expect(find.byKey(ValueKey('margin-editor-${note.id}')), findsOneWidget);
    await session.finish();
    await session.recolor(workspace.content.marginNotes.single, 4);
    await drain(tester);
    expect(workspace.content.marginNotes.single.colorIndex, 4);
    await session.delete(workspace.content.marginNotes.single);
    await drain(tester);
    expect(workspace.content.marginNotes, isEmpty);
    expect(workspace.content.card(cardId), isNotNull);
    await workspace.undo();
    await drain(tester);
    expect(workspace.content.marginNotes.single.nodeId, cardId);
    await workspace.removeCards([cardId]);
    await drain(tester);
    expect(workspace.content.marginNotes.single.nodeId, isNull);
    await pointer.removePointer();
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('narrow pane shows editable markers and expands again when space returns', (tester) async {
    final repository = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final container = await pumpApp(tester, renderPdf: true, content: repository, size: const Size(1400, 1000));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final session = container.read(readerMarginProvider('demo-1').notifier);
    await session.start('c1', page: 1, lineY: 700);
    session.text('Narrow window');
    await drain(tester);
    final id = container.read(readerMarginProvider('demo-1')).draft!.id;
    expect(find.byKey(ValueKey('margin-marker-$id')), findsOneWidget);
    expect(find.byKey(const ValueKey('margin-popover')), findsOneWidget);
    expect(container.read(readerMarginProvider('demo-1')).openDocuments, contains('c1'));
    await session.finish();
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    workspace.setLayout(MMSplitMode.primary);
    await drain(tester);
    expect(find.byKey(const ValueKey('margin-column-1')), findsOneWidget);
    final pdf = container.read(readerPdfProvider('demo-1'));
    final before = pdf.readingPosition!;
    session.toggle('c1');
    await drain(tester);
    expect(pdf.readingPosition!.page, before.page);
    expect(pdf.readingPosition!.y, closeTo(before.y, 1));
    await session.close();
    await drain(tester);
    expect(find.byType(MarginNoteCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('long cards push the next page down and crop offer expands a narrow pane', (tester) async {
    TestPdfRender.produceImages = true;
    TestPdfText.pages = {
      for (var p = 1; p <= 3; p++)
        p: PdfPageRawText('Text', [
          const PdfRect(80, 700, 90, 680),
          const PdfRect(90, 700, 100, 680),
          const PdfRect(100, 700, 110, 680),
          const PdfRect(110, 700, 120, 680),
        ]),
    };
    addTearDown(() {
      TestPdfRender.produceImages = false;
      TestPdfText.pages = {};
      TestPdfRender.renders.clear();
    });
    final container = await pumpApp(tester, renderPdf: true, size: const Size(1400, 1000));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    final session = container.read(readerMarginProvider('demo-1').notifier);
    await session.start('c1', page: 1, lineY: 700);
    session.text('Cropped note');
    await drain(tester);
    final offer = find.byKey(const ValueKey('margin-expand'));
    expect(offer, findsOneWidget);
    expect(find.text('Crop Margins and Show Notes'), findsOneWidget);
    await tester.tap(offer);
    await drain(tester);
    expect(workspace.content.document('c1')!.crop!.enabled, true);
    expect(find.byKey(const ValueKey('margin-column-1')), findsOneWidget);
    workspace.setLayout(MMSplitMode.primary);
    await drain(tester);
    await workspace.setDocumentCrop('c1', null);
    await drain(tester);
    for (var i = 0; i < 3; i++) {
      await session.start('c1', page: 1, lineY: 25 - i.toDouble());
      session.text(List.filled(7, 'Long note that wraps onto more than one line.').join('\n'));
      await session.finish();
    }
    await drain(tester);
    final pdf = container.read(readerPdfProvider('demo-1'));
    final jump = pdf.jumpToReadingPosition(PdfReadingPosition(page: 1, y: 80));
    await tester.pumpAndSettle();
    await jump;
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    final last = workspace.content.marginNotes.last;
    final card = find.byKey(ValueKey('margin-card-${last.id}'));
    final viewOrigin = tester.getTopLeft(find.byType(MMPdfView));
    final nextPageY = viewOrigin.dy + viewer.documentToLocal(viewer.layout.pageLayouts[1].topLeft).dy;
    expect(nextPageY, greaterThan(tester.getBottomLeft(card).dy));
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });
}
