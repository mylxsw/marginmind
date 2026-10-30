import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/reader_margin.dart';
import 'package:marginmind/features/workspace/reflow_document.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/features/workspace/widgets/reader_sidebar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';
import 'reader_crop_test.dart' show drain;
import 'reflow_fixtures.dart';

void main() {
  testWidgets('PDF ink is grouped by page, navigates, and follows erase/undo and document changes', (tester) async {
    installTestPdfBackend();
    InkStroke stroke(String id, String documentId, int page) => InkStroke(
      id: id,
      documentId: documentId,
      page: page,
      tool: InkTool.pen,
      colorIndex: 0,
      width: 2,
      points: const [InkPoint(30, 700), InkPoint(100, 650)],
    );
    final base = demoContent();
    final repository = InMemoryStudySetContentRepository({
      'demo-1': base.copyWith(
        annotations: [],
        inkStrokes: [
          stroke('third', 'c1', 3),
          stroke('first', 'c1', 2),
          stroke('second', 'c1', 2),
          stroke('other', 'c2', 5),
        ],
      ),
    });
    final container = await pumpApp(tester, content: repository, renderPdf: true, size: const Size(1800, 1000));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    workspace.setLayout(MMSplitMode.primary);
    workspace.showReaderPanel(ReaderPanelMode.annotations);
    await drain(tester);
    Finder row(int page) =>
        find.descendant(of: find.byType(ReaderSidebar), matching: find.byKey(ValueKey('ink-page-$page')));
    expect(find.text('Hand-drawn annotations'), findsNWidgets(2));
    expect(find.text('No Annotations'), findsNothing);
    expect(row(5), findsNothing);
    expect(find.descendant(of: row(2), matching: find.text('2 strokes')), findsOneWidget);
    expect(tester.getTopLeft(row(2)).dy, lessThan(tester.getTopLeft(row(3)).dy));
    await tester.tap(row(3));
    await drain(tester);
    expect(container.read(readerPdfProvider('demo-1')).currentPage, 3);
    expect(container.read(readerMarginProvider('demo-1')).popup, isEmpty);

    await workspace.eraseInkStrokes({'first'});
    await drain(tester);
    expect(find.descendant(of: row(2), matching: find.text('1 stroke')), findsOneWidget);
    await workspace.eraseInkStrokes({'second'});
    await drain(tester);
    expect(row(2), findsNothing);
    await workspace.undo();
    await drain(tester);
    expect(row(2), findsOneWidget);
    await workspace.eraseInkStrokes({'second', 'third'});
    await drain(tester);
    expect(find.text('No Annotations'), findsOneWidget);
    workspace.openDocument('c2');
    await drain(tester);
    expect(row(5), findsOneWidget);
    expect(find.text('No Annotations'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
  });

  for (final fixed in [false, true]) {
    testWidgets('${fixed ? 'fixed-layout pages' : 'reflow chapters'} group ink and retain navigation after resizing', (
      tester,
    ) async {
      final repository = InMemoryStudySetContentRepository();
      final parser = const EpubParser();
      final chapters = [
        parser.parseHtml('one', '<p>${'First page. ' * 30}</p><p>Another paragraph.</p>'),
        parser.parseHtml('two', '<p>${'Second page. ' * 30}</p>'),
      ];
      final doc = await storeBook(
        repository,
        format: DocumentFormat.epub,
        book: Book('Ink book', chapters, {}, [], fixedLayout: fixed),
      );
      final source = await ReflowDocument.load(repository, 'demo-1', doc);
      InkStroke stroke(String id, int chapterIndex, int blockIndex) {
        final chapter = source.chapters[chapterIndex];
        final block = chapter.blocks[blockIndex];
        return InkStroke(
          id: id,
          documentId: doc.id,
          textAnchor: ParagraphInkAnchor(
            anchor: chapter.anchor(block.start, block.end, revision: doc.revision!),
            blockId: block.id,
            capturedWidth: 600,
            originX: 0,
            originY: 0,
          ),
          tool: InkTool.pen,
          colorIndex: 0,
          width: 2,
          points: const [InkPoint(30, 10), InkPoint(100, 20)],
        );
      }

      await repository.update(
        'demo-1',
        (c) => c.copyWith(inkStrokes: [stroke('later', 1, 0), stroke('a', 0, 1), stroke('b', 0, 0)]),
      );
      final container = await pumpApp(tester, content: repository, size: const Size(1600, 900));
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final workspace = container.read(workspaceProvider('demo-1').notifier);
      workspace.openDocument(doc.id);
      workspace.setLayout(MMSplitMode.primary);
      workspace.showReaderPanel(ReaderPanelMode.annotations);
      await tester.pumpAndSettle();
      Finder row(String chapter) => find.byKey(ValueKey('ink-chapter-$chapter'));
      expect(find.text('Hand-drawn annotations'), findsNWidgets(2));
      expect(find.text('No Annotations'), findsNothing);
      expect(find.textContaining('2 strokes'), findsOneWidget);
      if (fixed) {
        expect(find.textContaining('Page 1 ·'), findsOneWidget);
        expect(find.textContaining('Page 2 ·'), findsOneWidget);
      }
      expect(tester.getTopLeft(row('one')).dy, lessThan(tester.getTopLeft(row('two')).dy));
      await tester.tap(row('two'));
      await tester.pumpAndSettle();
      final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
      expect(session.position!.chapterId, 'two');
      await container.read(settingsProvider.notifier).setReading(doc.format, const ReadingSettings(size: 5));
      await tester.pumpAndSettle();
      expect(find.text('Hand-drawn annotations'), findsNWidgets(2));
      await tester.tap(row('one'));
      await tester.pumpAndSettle();
      expect(session.position!.chapterId, 'one');
      expect(session.position!.offset, 0, reason: 'navigate to the first ink, independent of insertion order');
      await workspace.eraseInkStrokes({'a'});
      await tester.pumpAndSettle();
      expect(row('one'), findsOneWidget);
      await workspace.eraseInkStrokes({'b'});
      await tester.pumpAndSettle();
      expect(row('one'), findsNothing);
      await workspace.undo();
      await tester.pumpAndSettle();
      expect(row('one'), findsOneWidget);
      await workspace.eraseInkStrokes({'b', 'later'});
      await tester.pumpAndSettle();
      expect(find.text('No Annotations'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
