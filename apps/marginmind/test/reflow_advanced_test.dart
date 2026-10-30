import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/reader_compare.dart';
import 'package:marginmind/features/workspace/reader_margin.dart';
import 'package:marginmind/features/workspace/reader_paragraphs.dart';
import 'package:marginmind/features/workspace/reader_translation.dart';
import 'package:marginmind/features/workspace/reflow_document.dart';
import 'package:marginmind/features/workspace/reflow_geometry.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/features/workspace/widgets/reflow_tools.dart';
import 'package:marginmind/features/workspace/widgets/reader_margin_notes.dart';
import 'package:marginmind/features/workspace/widgets/reflow_translation_view.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_reflow/mm_reflow.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';

import 'helpers.dart';
import 'reflow_fixtures.dart';
import 'reader_translation_test.dart' show TestTranslator, model, frames;

Book fixture([String title = 'Book']) => Book(
  title,
  [
    const EpubParser().parseHtml(
      'main',
      '<p>${'First paragraph with text. ' * 8}</p><p>${'Second paragraph with text. ' * 8}</p>'
          '<p>${'Third paragraph with text. ' * 8}</p>',
    ),
  ],
  {},
  [],
);

void main() {
  testWidgets('review count includes flagged and unresolved annotations once plus unresolved ink', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(repo, book: fixture());
    final book = await ReflowDocument.load(repo, 'demo-1', doc);
    final chapter = book.chapters.first;
    final valid = chapter.anchor(0, 5, revision: book.revision);
    final missing = TextAnchor('gone', 0, 7, 'removed', revision: 'old');
    InkStroke ink(String id, TextAnchor anchor) => InkStroke(
      id: id,
      documentId: doc.id,
      textAnchor: ParagraphInkAnchor(
        anchor: anchor,
        blockId: chapter.blocks.first.id,
        capturedWidth: 600,
        originX: 0,
        originY: 0,
      ),
      tool: InkTool.pen,
      colorIndex: 0,
      width: 2,
      points: [InkPoint(1, 1)],
    );
    await repo.update(
      'demo-1',
      (content) => content.copyWith(
        annotations: [
          for (final (id, anchor, flagged) in [
            ('flagged', valid, true),
            ('both', missing, true),
            ('missing', missing, false),
            ('resolved', valid, false),
          ])
            Annotation(
              id: id,
              documentId: doc.id,
              textAnchors: [anchor],
              quote: id,
              colorIndex: 0,
              createdAt: DateTime(2026),
              needsReview: flagged,
            ),
        ],
        inkStrokes: [ink('stale-ink', missing), ink('valid-ink', valid)],
      ),
    );
    final c = await pumpApp(tester, content: repo);
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final workspace = c.read(workspaceProvider('demo-1').notifier);
    workspace.openDocument(doc.id);
    workspace.showReaderPanel(ReaderPanelMode.annotations);
    await tester.pumpAndSettle();
    expect(find.text('Needs Review (4)'), findsOneWidget);
    for (final id in ['flagged', 'both', 'missing']) {
      expect(find.byKey(ValueKey('annotation-$id')), findsOneWidget);
    }
    expect(find.text('resolved'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('annotation-both')));
    await tester.pumpAndSettle();
    expect(find.text('Can’t find the original text'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('ink follows the leaf origin, scales uniformly by width, splits sparse gestures', () async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(repo, book: fixture());
    final book = await ReflowDocument.load(repo, 'demo-1', doc);
    final chapter = book.chapters.first;
    final layout = ChapterLayout.layout(chapter, LayoutSpec(width: 600, pageHeight: 500), revision: book.revision);
    final reflow = ChapterLayout.layout(
      chapter,
      LayoutSpec(width: 300, pageHeight: 500, fontSize: 26),
      revision: book.revision,
    );
    var n = 0;
    for (final tool in InkTool.values) {
      final strokes = paragraphInk(
        layout,
        [layout.pieces[0].rect.center, layout.pieces[2].rect.center],
        documentId: doc.id,
        newId: () => '${n++}',
        tool: tool,
        colorIndex: 0,
        width: 2,
      );
      expect(strokes.length, greaterThanOrEqualTo(3));
      for (final stroke in strokes) {
        final anchor = stroke.textAnchor!;
        final t = paragraphInkTransform(reflow, anchor)!;
        final piece = reflow.pieces.firstWhere((p) => p.block.id == anchor.blockId);
        expect(t.scale, closeTo(piece.rect.width / anchor.capturedWidth, .001));
        expect(t.origin, piece.rect.topLeft);
        expect(ParagraphInkAnchor.fromJson(anchor.toJson()).anchor.toJson(), anchor.anchor.toJson());
      }
    }
    expect(captureAnchors(layout, layout.pieces.first.rect), hasLength(1));
    expect(captureAnchors(layout, layout.pieces.first.rect, page: 0), isNotEmpty);
    expect(packReflowNotes([(y: 10.0, height: 80.0), (y: 15.0, height: 80.0)], 140, 8).map((p) => p.card), [
      true,
      false,
    ]);
    expect(packReflowNotes([(y: 10.0, height: 80.0), (y: 15.0, height: 80.0)], 200, 8).last.top, 98);
    layout.dispose();
    expect(
      paragraphInkTransform(
        layout,
        paragraphInk(
          reflow,
          [reflow.pieces.first.rect.center],
          documentId: doc.id,
          newId: () => 'x',
          tool: InkTool.pen,
          colorIndex: 0,
          width: 2,
        ).first.textAnchor!,
      ),
      isNull,
    );
    reflow.dispose();
  });

  test('paragraph identities contain revision, source offset and spine order', () async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(repo, book: fixture());
    final book = await ReflowDocument.load(repo, 'demo-1', doc);
    final paragraphs = reflowParagraphs(book);
    expect(paragraphs.map((p) => p.index), [0, 1, 2]);
    final p = paragraphAt(paragraphs, book.position('main', paragraphs[1].textAnchor!.start + 10))!;
    expect(p.index, 1);
    expect(translationGroup(p), 2);
    expect(sameSourcePosition(paragraphPosition(p), paragraphPosition(p)), isTrue);
    expect(paragraphAt(paragraphs, TextReadingPosition(revision: 'old', chapterId: 'main', offset: 0)), isNull);
    expect(paragraphAt(paragraphs, PdfPosition(1)), isNull);
    final altered = ReflowDocument(doc.copyWith(revision: 'new'), book.chapters, book.toc, book.resources, book.read);
    expect(reflowParagraphs(altered).first.fingerprint, isNot(paragraphs.first.fingerprint));
  });

  testWidgets('pen, eraser, image capture, source return and undo work on a reflow surface', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(repo, book: fixture());
    Uint8List? png;
    final c = await pumpApp(
      tester,
      content: repo,
      overrides: [
        reflowCaptureProvider.overrideWithValue((boundary, rect, ratio) async {
          png = await captureReflowRegion(boundary, rect, ratio);
          return png;
        }),
      ],
    );
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final workspace = c.read(workspaceProvider('demo-1').notifier);
    workspace.openDocument(doc.id);
    await tester.pumpAndSettle();
    final s = c.read(reflowSessionProvider(('demo-1', doc.id)));
    final surface = find.byKey(const ValueKey('reflow-surface'));
    final first = tester.getTopLeft(surface) + s.layout!.pieces.first.rect.center;
    workspace.setTool(AnnotationTool.ink);
    await tester.pumpAndSettle();
    final pen = await tester.startGesture(first, kind: PointerDeviceKind.mouse);
    await pen.moveBy(const Offset(30, 5));
    await pen.up();
    await tester.pumpAndSettle();
    expect(workspace.content.inkStrokes, isNotEmpty);
    final before = workspace.content.inkStrokes.first.toJson();
    await c.read(settingsProvider.notifier).setReading(doc.format, const ReadingSettings(size: 6));
    await tester.pumpAndSettle();
    expect(workspace.content.inkStrokes.first.toJson(), before);
    workspace.setInkTool(MMPdfInkTool.eraser);
    await tester.pumpAndSettle();
    final stroke = workspace.content.inkStrokes.first;
    final t = paragraphInkTransform(s.layout!, stroke.textAnchor!)!;
    final hit =
        tester.getTopLeft(surface) +
        s.layout!.toPage(t.origin + Offset(stroke.points.first.x, stroke.points.first.y) * t.scale, s.page);
    final eraser = await tester.startGesture(hit, kind: PointerDeviceKind.mouse);
    await eraser.moveBy(const Offset(25, 0));
    await eraser.up();
    await tester.pumpAndSettle();
    expect(workspace.content.inkStrokes, isEmpty);
    await workspace.undo();
    await tester.pumpAndSettle();
    expect(workspace.content.inkStrokes, isNotEmpty);
    workspace.setTool(AnnotationTool.area);
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(surface) + s.layout!.pieces.first.rect.topLeft;
    final area = await tester.startGesture(top, kind: PointerDeviceKind.mouse);
    await area.moveBy(const Offset(140, 50));
    await area.up();
    await tester.pumpAndSettle();
    await frames(tester);
    expect(png, isNotNull);
    final image = (await tester.runAsync(() => ui.instantiateImageCodec(png!)))!;
    final frame = (await tester.runAsync(image.getNextFrame))!;
    expect(frame.image.width, 140);
    expect(frame.image.height, 50);
    frame.image.dispose();
    image.dispose();
    final annotation = workspace.content.annotations.single;
    expect(annotation.capture!.width, 140);
    expect(annotation.textAnchors, isNotEmpty);
    final card = workspace.content.cardForAnnotation(annotation.id)!;
    expect(card.kind, CardKind.image);
    expect(repo.images[card.imageFileName], png);
    workspace.revealCard(card.id);
    await tester.pumpAndSettle();
    expect(s.position!.offset, annotation.textAnchors.first.start);
    await workspace.undo();
    await tester.pumpAndSettle();
    expect(workspace.content.annotations, isEmpty);
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen capture spans two visible chapters and preserves both sources', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(
      repo,
      book: Book(
        'Two chapters',
        [
          const EpubParser().parseHtml('one', '<p>First visible source paragraph.</p>'),
          const EpubParser().parseHtml('two', '<p>Second visible source paragraph.</p>'),
        ],
        {},
        [],
      ),
    );
    final c = await pumpApp(tester, content: repo);
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final w = c.read(workspaceProvider('demo-1').notifier);
    w.openDocument(doc.id);
    await c.read(settingsProvider.notifier).setReading(doc.format, const ReadingSettings(paged: false));
    await tester.pumpAndSettle();
    w.setTool(AnnotationTool.area);
    await tester.pumpAndSettle();
    Finder surface(String chapter) => find.byWidgetPredicate((w) => w is ReflowTools && w.layout.chapter.id == chapter);
    final first = tester.widget<ReflowTools>(surface('one'));
    final second = tester.widget<ReflowTools>(surface('two'));
    final start = tester.getTopLeft(surface('one')) + first.layout.pieces.first.rect.topLeft;
    final end = tester.getTopLeft(surface('two')) + second.layout.pieces.first.rect.bottomRight;
    final area = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await area.moveTo(end);
    await area.up();
    await tester.pumpAndSettle();
    await frames(tester);
    expect(w.content.annotations.single.textAnchors.map((a) => a.chapterId), ['one', 'two']);
    expect(w.content.cards.single.kind, CardKind.image);
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });

  testWidgets('margin column reserves space, collapses overflow and follows reflow', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(repo, book: fixture());
    final c = await pumpApp(tester, content: repo, size: const Size(1800, 1100));
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final w = c.read(workspaceProvider('demo-1').notifier);
    w.openDocument(doc.id);
    w.setLayout(MMSplitMode.primary);
    await tester.pumpAndSettle();
    final s = c.read(reflowSessionProvider(('demo-1', doc.id)));
    final chapter = s.book!.chapters.first;
    final anchor = chapter.anchor(0, chapter.blocks.first.end, revision: doc.revision!);
    final margin = c.read(readerMarginProvider('demo-1').notifier);
    margin.toggle(doc.id);
    await tester.pumpAndSettle();
    final gutter = find.byKey(const ValueKey('reflow-margin-column'));
    final sourceY =
        tester.getTopLeft(find.byKey(const ValueKey('reflow-surface'))).dy + s.layout!.pieces.first.rect.center.dy;
    await tester.tapAt(Offset(tester.getRect(gutter).center.dx, sourceY));
    await tester.pumpAndSettle();
    expect(c.read(readerMarginProvider('demo-1')).draft!.anchor!.textAnchors.single.quote, chapter.blocks.first.text);
    await margin.close();
    margin.toggle(doc.id);
    await tester.pumpAndSettle();
    for (var i = 0; i < 40; i++) {
      await w.saveMarginNote(
        MarginNote(
          id: 'n$i',
          documentId: doc.id,
          anchor: AnnotationAnchor(textAnchors: [anchor], quote: anchor.quote),
          text: 'Note $i',
          colorIndex: 0,
          createdAt: testNow,
          updatedAt: testNow,
        ),
      );
    }
    c.read(readerMarginProvider('demo-1').notifier).toggle(doc.id);
    await tester.pumpAndSettle();
    expect(find.byType(MarginNoteCard), findsWidgets);
    expect(find.byWidgetPredicate((w) => w.key.toString().contains('margin-marker')), findsOneWidget);
    final cardBox = tester.getRect(find.byType(MarginNoteCard).first);
    final source = tester.getRect(find.byKey(const ValueKey('reflow-surface')));
    expect(cardBox.left, greaterThanOrEqualTo(source.right));
    await w.attachMarginNote('n0');
    await tester.pumpAndSettle();
    expect(w.content.marginNotes.firstWhere((n) => n.id == 'n0').nodeId, isNotNull);
    tester.view.physicalSize = const Size(800, 820);
    await tester.pumpAndSettle();
    final marker = find.byWidgetPredicate((w) => w.key.toString().contains('margin-marker'));
    expect(marker, findsOneWidget);
    await tester.tap(marker);
    await tester.pumpAndSettle();
    expect(find.byType(MarginNoteCard), findsNWidgets(40));
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });

  testWidgets('two reflow documents persist paragraph pairs, sync both ways and swap', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final left = await storeBook(repo, book: fixture('Left'));
    final right = await storeBook(repo, id: 'right', book: fixture('Right'));
    final c = await pumpApp(tester, content: repo, size: const Size(1800, 1100));
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final w = c.read(workspaceProvider('demo-1').notifier);
    w.openDocument(left.id);
    await tester.pumpAndSettle();
    final compare = c.read(readerCompareProvider('demo-1').notifier);
    final entering = compare.select(right.id);
    await tester.pumpAndSettle();
    await entering;
    await tester.pumpAndSettle();
    final pair = c.read(readerCompareProvider('demo-1'))!;
    expect(pair.sourceAlignPoints, hasLength(3));
    expect(reverseComparePair(reverseComparePair(pair)).toJson(), pair.toJson());
    final l = c.read(reflowSessionProvider(('demo-1', left.id))),
        r = c.read(reflowSessionProvider(('demo-1', right.id)));
    final leftFont = l.spec!.fontSize;
    final rightFont = r.spec!.fontSize;
    await tester.tap(find.byKey(ValueKey('compare-settings-${right.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reading-larger')));
    await tester.pumpAndSettle();
    expect(r.spec!.fontSize, greaterThan(rightFont));
    expect(l.spec!.fontSize, leftFont);
    await tester.tapAt(const Offset(10, 1000));
    await tester.pumpAndSettle();
    final target = pair.sourceAlignPoints[1];
    compare.userInput(0);
    await l.jump(target.left as TextReadingPosition);
    compare.changed(0);
    await tester.pumpAndSettle();
    expect(sameSourcePosition(r.position!, target.right), isTrue);
    compare.userInput(1);
    await r.jump(pair.sourceAlignPoints.last.right as TextReadingPosition);
    compare.changed(1);
    await tester.pumpAndSettle();
    expect(sameSourcePosition(l.position!, pair.sourceAlignPoints.last.left), isTrue);
    await compare.toggleSync();
    compare.userInput(0);
    await l.jump(pair.sourceAlignPoints.first.left as TextReadingPosition);
    compare.changed(0);
    await tester.pumpAndSettle();
    expect(sameSourcePosition(r.position!, pair.sourceAlignPoints.last.right), isTrue);
    await compare.align();
    await tester.pumpAndSettle();
    expect(c.read(readerCompareProvider('demo-1'))!.sync, isTrue);
    await compare.swap();
    await tester.pumpAndSettle();
    expect(c.read(readerCompareProvider('demo-1'))!.leftDocumentId, right.id);
    await compare.exit();
    await tester.pumpAndSettle();
    expect(c.read(readerCompareProvider('demo-1')), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reflow and PDF comparison uses paragraph regions in both directions', (tester) async {
    installTestPdfBackend();
    TestPdfRender.produceImages = true;
    addTearDown(() {
      TestPdfRender.produceImages = false;
      TestPdfText.pages = {};
    });
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(repo, book: fixture());
    await repo.update(
      'demo-1',
      (c) => c.copyWith(
        documents: [
          ...c.documents,
          Document(id: 'pdf', title: 'PDF', fileName: 'sample.pdf', pageCount: 3, importedAt: testNow),
        ],
      ),
    );
    final pdfParagraphs = [
      for (var i = 0; i < 3; i++)
        TranslationParagraph(
          documentId: 'pdf',
          page: i + 1,
          index: i,
          text: 'PDF paragraph $i',
          fingerprint: 'pdf-$i',
          rects: [PageRect(70, 650, 500, 600)],
        ),
    ];
    final c = await pumpApp(
      tester,
      content: repo,
      renderPdf: true,
      size: const Size(1800, 1100),
      overrides: [translationParagraphsProvider(('demo-1', 'pdf')).overrideWith((ref) async => pdfParagraphs)],
    );
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await frames(tester);
    final w = c.read(workspaceProvider('demo-1').notifier);
    w.openDocument(doc.id);
    await frames(tester);
    final compare = c.read(readerCompareProvider('demo-1').notifier);
    final entering = compare.select('pdf');
    await frames(tester);
    await entering;
    await frames(tester);
    final pair = c.read(readerCompareProvider('demo-1'))!;
    expect((pair.sourceAlignPoints[1].right as PdfPosition).y, 650);
    final source = c.read(reflowSessionProvider(('demo-1', doc.id)));
    compare.userInput(0);
    await source.jump(pair.sourceAlignPoints[1].left as TextReadingPosition);
    compare.changed(0);
    await frames(tester);
    expect(compare.pdf('pdf').readingPosition!.page, 2);
    compare.userInput(1);
    final moving = compare.pdf('pdf').jumpToReadingPosition(PdfReadingPosition(page: 3, y: 650));
    await frames(tester);
    await moving;
    compare.changed(1);
    await frames(tester);
    expect(sameSourcePosition(source.position!, pair.sourceAlignPoints[2].left), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });

  testWidgets('reflow translation requests only a viewed paragraph and saves completed values', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(repo, book: fixture());
    final translators = <TestTranslator>[];
    final c = await pumpApp(
      tester,
      content: repo,
      size: const Size(1800, 1100),
      overrides: [
        assistantDefaultModelProvider.overrideWithValue(model),
        paragraphTranslatorProvider.overrideWithValue((_) async {
          final t = TestTranslator();
          translators.add(t);
          return t;
        }),
      ],
    );
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final w = c.read(workspaceProvider('demo-1').notifier);
    w.openDocument(doc.id);
    await tester.pumpAndSettle();
    final opening = c.read(readerCompareProvider('demo-1').notifier).openAi('zh');
    await frames(tester);
    await opening;
    await frames(tester);
    expect(find.byType(ReflowTranslationView), findsOneWidget);
    expect(translators.single.calls, hasLength(1));
    final controller = c.read(readerTranslationProvider('demo-1').notifier);
    final paragraphs = c.read(readerTranslationProvider('demo-1')).paragraphs;
    final first = translators.single;
    first.pending.values.single.complete(ParagraphTranslation('译文', tokens: 2));
    await frames(tester);
    expect((await repo.load('demo-1')).translationCaches.single.paragraphs, hasLength(1));
    final next = paragraphPosition(paragraphs[1]) as TextReadingPosition;
    await tester.tap(find.byKey(const ValueKey('translation-paragraph-1')));
    await frames(tester);
    expect(sameSourcePosition(c.read(reflowSessionProvider(('demo-1', doc.id))).position!, next), isTrue);
    expect(translators, hasLength(2));
    expect(translators.last.calls, [1]);
    final late = translators.last;
    controller.textSourceChanged(paragraphPosition(paragraphs[2]) as TextReadingPosition);
    await frames(tester);
    expect(late.closed, isTrue);
    late.pending.values.single.complete(ParagraphTranslation('late', tokens: 2));
    await frames(tester);
    expect((await repo.load('demo-1')).translationCaches.single.paragraphs.values, isNot(contains('late')));
    await c.read(readerCompareProvider('demo-1').notifier).exit();
    await frames(tester);
    for (final t in translators) {
      for (final pending in t.pending.values) {
        if (!pending.isCompleted) pending.complete(ParagraphTranslation('ignored', tokens: 1));
      }
    }
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('translation scrolling follows paragraph identities in both directions', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(
      repo,
      book: Book(
        'Long source',
        [
          const EpubParser().parseHtml(
            'main',
            List.generate(40, (i) => '<p>Paragraph $i ${'source words ' * 30}</p>').join(),
          ),
        ],
        {},
        [],
      ),
    );
    final book = await ReflowDocument.load(repo, 'demo-1', doc);
    final paragraphs = reflowParagraphs(book);
    await repo.update(
      'demo-1',
      (content) => content.copyWith(
        translationCaches: [
          TranslationCache(
            documentId: doc.id,
            targetLang: 'zh',
            model: 'cached',
            createdAt: testNow,
            paragraphs: {for (final p in paragraphs) p.fingerprint: '译文 ${p.index} ${'translated text ' * 25}'},
          ),
        ],
      ),
    );
    final c = await pumpApp(
      tester,
      content: repo,
      size: const Size(1800, 1000),
      overrides: [assistantDefaultModelProvider.overrideWithValue(null)],
    );
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final w = c.read(workspaceProvider('demo-1').notifier);
    w.openDocument(doc.id);
    await tester.pumpAndSettle();
    final opening = c.read(readerCompareProvider('demo-1').notifier).openAi('zh');
    await tester.pumpAndSettle();
    await opening;
    await tester.pumpAndSettle();
    final session = c.read(reflowSessionProvider(('demo-1', doc.id)));
    final translated = find.descendant(of: find.byType(ReflowTranslationView), matching: find.byType(CustomScrollView));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: tester.getCenter(translated), scrollDelta: const Offset(0, 500)),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<CustomScrollView>(translated).controller!.offset, greaterThan(0));
    expect(session.position!.offset, greaterThan(0));
    final slider = find.byKey(const ValueKey('reflow-progress'));
    final bounds = tester.getRect(slider);
    await tester.tapAt(Offset(bounds.left + bounds.width * .75, bounds.center.dy));
    await tester.pumpAndSettle();
    expect(book.progress(session.position!), greaterThan(.5));
    final p = paragraphAt(paragraphs, session.position!)!;
    final target = find.byKey(ValueKey('translation-paragraph-${p.index}'));
    expect(target, findsOneWidget);
    expect(tester.getRect(target).top, lessThan(tester.getRect(translated).top + 50));
    expect(c.read(readerTranslationProvider('demo-1')).done, 40);
    expect(tester.takeException(), isNull);
  });
}
