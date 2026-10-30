import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/reader_margin.dart';
import 'package:marginmind/features/workspace/widgets/reader_sidebar.dart';
import 'package:marginmind/features/workspace/widgets/web_source.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';
import 'reader_crop_test.dart' show drain;

void main() {
  setUp(installTestPdfBackend);

  testWidgets('unresolved PDF marks form the first group, jump to chapter start and only offer Delete', (tester) async {
    final original = demoContent();
    Annotation mark(String id, int page, bool review) => Annotation(
      id: id,
      documentId: 'c1',
      page: page,
      rects: const [PageRect(30, 700, 190, 680)],
      quote: id,
      colorIndex: 0,
      createdAt: testNow,
      needsReview: review,
    );
    final document = original
        .document('c1')!
        .copyWith(
          origin: DocumentOrigin(
            url: 'https://example.com/article',
            capturedAt: testNow,
            mode: WebCaptureMode.original,
          ),
        );
    final repository = InMemoryStudySetContentRepository({
      'demo-1': original.copyWith(
        documents: [
          for (final d in original.documents)
            if (d.id == 'c1') document else d,
        ],
        annotations: [mark('Normal passage', 1, false), mark('Missing passage', 3, true)],
        marginNotes: [],
        documentOutlines: [
          const DocumentOutline(
            documentId: 'c1',
            items: [PdfOutlineEntry(id: 'chapter', title: 'Chapter two', page: 2)],
          ),
        ],
      ),
    });
    final container = await pumpApp(tester, renderPdf: true, content: repository, size: const Size(1800, 1000));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    workspace.setLayout(MMSplitMode.primary);
    workspace.showReaderPanel(ReaderPanelMode.annotations);
    await drain(tester);
    final sidebar = find.byType(ReaderSidebar);
    Finder row(String id) => find.descendant(of: sidebar, matching: find.byKey(ValueKey('annotation-$id')));
    expect(tester.getTopLeft(row('Missing passage')).dy, lessThan(tester.getTopLeft(row('Normal passage')).dy));
    expect(find.descendant(of: sidebar, matching: find.text('Needs Review (1)')), findsOneWidget);
    expect(find.descendant(of: row('Missing passage'), matching: find.text('Chapter two')), findsOneWidget);
    final separator = find.descendant(of: sidebar, matching: find.byType(Divider));
    expect(tester.widgetList<Divider>(separator).any((d) => d.thickness == .5), isTrue);
    expect(
      find.descendant(of: find.byKey(const ValueKey('reader-page-badge')), matching: find.byType(WebSourceAttribution)),
      findsOneWidget,
    );
    await tester.tap(row('Missing passage'));
    await drain(tester);
    expect(container.read(readerPdfProvider('demo-1')).currentPage, 2);
    expect(find.text('Can’t find the original text'), findsOneWidget);
    await tester.tap(row('Missing passage'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    await tester.tap(find.text('Delete'));
    await drain(tester);
    expect(workspace.content.annotation('Missing passage'), isNull);
    expect(find.text('Needs Review (1)'), findsNothing);
    expect(workspace.content.annotation('Normal passage'), isNotNull);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
  });

  for (final expanded in [false, true]) {
    testWidgets('sidebar reveals quote and line notes with the margin ${expanded ? 'expanded' : 'collapsed'}', (
      tester,
    ) async {
      final quoteNote = MarginNote(
        id: 'quote-note',
        documentId: 'c1',
        page: 2,
        anchor: AnnotationAnchor(
          pages: const [
            AnnotationPage(page: 2, rects: [PageRect(30, 700, 190, 680)]),
          ],
          quote: 'Selected passage',
        ),
        text: 'Remember this passage',
        colorIndex: 0,
        createdAt: testNow,
        updatedAt: testNow,
      );
      final lineNote = MarginNote(
        id: 'line-note',
        documentId: 'c1',
        page: 3,
        lineY: 400,
        text: 'Compare with the previous page',
        colorIndex: 2,
        createdAt: testNow,
        updatedAt: testNow,
      );
      final repository = InMemoryStudySetContentRepository({
        'demo-1': demoContent().copyWith(annotations: [], marginNotes: [lineNote, quoteNote]),
      });
      final container = await pumpApp(tester, renderPdf: true, content: repository, size: const Size(1800, 1000));
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await drain(tester);
      final workspace = container.read(workspaceProvider('demo-1').notifier);
      workspace.setLayout(MMSplitMode.primary);
      workspace.showReaderPanel(ReaderPanelMode.annotations);
      await workspace.highlight(
        'c1',
        const MMPdfSelection(page: 1, rects: [PageRect(30, 700, 190, 680)], text: 'A highlighted passage'),
        MMAnnotationColor.yellow,
      );
      final session = container.read(readerMarginProvider('demo-1').notifier);
      if (expanded) session.expand('c1');
      await drain(tester);
      final pdf = container.read(readerPdfProvider('demo-1'));
      expect(pdf.isReady, isTrue);
      Finder row(String id) =>
          find.descendant(of: find.byType(ReaderSidebar), matching: find.byKey(ValueKey('margin-note-$id')));

      await tester.tap(row(quoteNote.id));
      await drain(tester);
      expect(pdf.currentPage, 2);
      expect(container.read(readerMarginProvider('demo-1')).popup, {quoteNote.id});
      expect(find.byKey(ValueKey('margin-card-${quoteNote.id}')), findsOneWidget);
      expect(find.byKey(const ValueKey('margin-popover')), expanded ? findsNothing : findsOneWidget);

      // Navigating away from an editor saves its text before revealing the next note.
      await session.start('c1', existing: quoteNote);
      await drain(tester);
      session.text('Saved before navigating');
      await tester.tap(row(lineNote.id));
      await drain(tester);
      expect(workspace.content.marginNotes.firstWhere((n) => n.id == quoteNote.id).text, 'Saved before navigating');
      expect(pdf.currentPage, 3);
      expect(container.read(readerMarginProvider('demo-1')).draft, isNull);
      expect(container.read(readerMarginProvider('demo-1')).popup, {lineNote.id});
      expect(find.byKey(ValueKey('margin-card-${lineNote.id}')), findsOneWidget);
      expect(
        tester
            .getRect(find.byKey(ValueKey('margin-card-${lineNote.id}')))
            .overlaps(tester.getRect(find.byType(MMPdfView))),
        isTrue,
        reason: 'the note is visible in the viewport, not merely built offscreen',
      );
      expect(tester.widget<MMInteractive>(row(lineNote.id)).selected, isTrue);
      await tester.tap(find.descendant(of: find.byType(ReaderSidebar), matching: find.text('A highlighted passage')));
      await drain(tester);
      expect(pdf.currentPage, 1);
      expect(container.read(readerMarginProvider('demo-1')).popup, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drain(tester);
    });
  }
}
