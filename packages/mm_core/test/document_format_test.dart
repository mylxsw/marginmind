import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 29);
  const anchor = TextAnchor('main', 0, 4, '你好😀', prefix: '前', suffix: '后', revision: 'v1');
  final position = TextReadingPosition(revision: 'v1', chapterId: 'main', offset: 4);
  final doc = Document(
    id: 'book',
    title: 'Book',
    fileName: 'books/book/v1/manifest.json',
    sourceFileName: 'documents/source.epub',
    contentManifest: 'books/book/v1/manifest.json',
    revision: 'v1',
    format: DocumentFormat.epub,
    layout: DocumentLayout.reflow,
    pageCount: 0,
    importedAt: now,
    readingPosition: position,
  );
  late StudySetEditor editor;
  setUp(() {
    var id = 0;
    editor = StudySetEditor(newId: () => 'id-${id++}', now: () => now);
  });

  test('legacy document and annotation JSON retain PDF coordinates and defaults', () {
    final json = {
      'id': 'pdf',
      'title': 'PDF',
      'fileName': 'documents/old.pdf',
      'pageCount': 10,
      'lastPage': 7,
      'importedAt': now.toIso8601String(),
    };
    final pdf = Document.fromJson(json);
    expect(pdf.format, DocumentFormat.pdf);
    expect(pdf.layout, DocumentLayout.fixed);
    expect(pdf.lastPage, 7);
    final old = Annotation.fromJson({
      'id': 'a',
      'documentId': 'pdf',
      'page': 7,
      'rects': [const PageRect(1, 9, 4, 2).toJson()],
      'quote': 'old',
      'colorIndex': 2,
      'createdAt': now.toIso8601String(),
    });
    expect(old.page, 7);
    expect(old.rects.single, const PageRect(1, 9, 4, 2));
    expect(old.toJson().containsKey('textAnchors'), isFalse);
    expect(Annotation.fromJson(old.toJson()).pages.single.page, 7);
  });

  test('all formats have capabilities independent of UI and runtime', () {
    for (final extension in DocumentFormat.extensions) {
      expect(DocumentFormat.fromFileName('UPPER.${extension.toUpperCase()}'), isNot(DocumentFormat.unknown));
    }
    expect(DocumentFormat.fromFileName('file.exe'), DocumentFormat.unknown);
    final pdf = DocumentCapabilities.resolve(
      format: DocumentFormat.pdf,
      layout: DocumentLayout.fixed,
      runtime: const DocumentRuntime(ocr: true),
    );
    expect([pdf.crop, pdf.ocr, pdf.zoom, pdf.thumbnails], everyElement(isTrue));
    final flow = doc.capabilities();
    expect([
      flow.selectText,
      flow.annotate,
      flow.excerpt,
      flow.marginNotes,
      flow.parallel,
      flow.translate,
      flow.ink,
      flow.capture,
      flow.search,
      flow.outline,
      flow.bookmarks,
      flow.readingSettings,
    ], everyElement(isTrue));
    expect([flow.crop, flow.ocr, flow.zoom, flow.thumbnails, flow.recapture], everyElement(isFalse));
    final image = DocumentCapabilities.resolve(
      format: DocumentFormat.epub,
      layout: DocumentLayout.fixed,
      contentFeatures: const DocumentContentFeatures(text: false, outline: false),
    );
    expect([
      image.selectText,
      image.search,
      image.annotate,
      image.excerpt,
      image.translate,
      image.outline,
      image.crop,
    ], everyElement(isFalse));
    expect([image.capture, image.ink, image.zoom, image.thumbnails], everyElement(isTrue));
    for (final browser in [false, true]) {
      expect(
        DocumentCapabilities.resolve(
          format: DocumentFormat.web,
          layout: DocumentLayout.reflow,
          runtime: DocumentRuntime(browser: browser),
        ).recapture,
        browser,
      );
    }
    final unknown = DocumentCapabilities.resolve(format: DocumentFormat.unknown, layout: DocumentLayout.fixed);
    expect([unknown.search, unknown.capture, unknown.marginNotes, unknown.bookmarks], everyElement(isFalse));
  });

  test('document, origin and position codecs reject unknown discriminators', () {
    final origin = DocumentOrigin(
      url: 'https://example.com/article',
      capturedAt: now,
      snapshotFile: 'web/book/v1/snapshot.html',
    );
    final encoded = doc
        .copyWith(
          origin: origin,
          title: 'Renamed',
          revision: 'v2',
          contentManifest: 'books/book/v2/manifest.json',
          fileName: 'books/book/v2/manifest.json',
        )
        .toJson();
    expect(Document.fromJson(encoded).toJson(), encoded);
    expect(DocumentOrigin.fromJson(origin.toJson()).url, origin.url);
    expect(() => DocumentOrigin(url: 'javascript:bad', capturedAt: now), throwsArgumentError);
    expect(() => DocumentOrigin(url: 'https://user:pass@example.com', capturedAt: now), throwsArgumentError);
    expect(ReadingPosition.fromJson(PdfPosition(3).toJson()), isA<PdfPosition>());
    expect(() => PdfPosition(0), throwsArgumentError);
    expect(ReadingPosition.fromJson(position.toJson()).toJson(), position.toJson());
    expect(() => LastReadingPosition(documentTitle: 'Book', position: position).page, throwsStateError);
    expect(LastReadingPosition(documentTitle: 'PDF', position: PdfPosition(2)).page, 2);
    expect(() => TextReadingPosition(revision: '', chapterId: '', offset: -1), throwsArgumentError);
    expect(() => ReadingPosition.fromJson({'type': 'future'}), throwsFormatException);
    expect(() => Document.fromJson({...doc.toJson(), 'format': 'future'}), throwsArgumentError);
    expect(() => TextAnchor.fromJson({...anchor.toJson(), 'end': 99}), throwsArgumentError);
    expect(() => TextAnchor.fromJson({...anchor.toJson(), 'normalizationVersion': 2}), throwsArgumentError);
    expect(TextAnchor.fromJson(anchor.toJson()).toJson(), anchor.toJson());
  });

  test('text annotation edits, clipboard, exports and document removal preserve all anchors', () {
    var c = StudySetContent.empty.copyWith(documents: [doc]);
    const second = TextAnchor('next', 0, 1, '后', revision: 'v1');
    final result = editor.createExcerpt(
      c,
      documentId: doc.id,
      textAnchors: [anchor, second],
      quote: '你好😀\n后',
      colorIndex: 1,
    );
    c = result.$1;
    final a = c.annotations.single;
    expect(() => Annotation.fromJson({...a.toJson(), 'targetType': 'future'}), throwsFormatException);
    expect(() => a.page, throwsStateError);
    expect(() => a.rects, throwsStateError);
    expect(a.copyWith(colorIndex: 3).textAnchors, [anchor, second]);
    c = StudySetContent.fromJson(c.toJson());
    expect(c.annotations.single.textAnchors.map((a) => a.chapterId), ['main', 'next']);
    c = editor.restyleAnnotation(c, a.id, lineStyle: AnnotationLineStyle.wavy, colorIndex: 4);
    expect(c.annotations.single.kind, AnnotationKind.underline);
    final face = buildReviewFace(c.cards.single, c);
    expect(face.back.source!.textAnchor!.chapterId, 'main');
    expect(face.front.prompt, ReviewPrompt.cloze);
    expect(
      face.back.source,
      ReviewSource(documentId: doc.id, documentTitle: doc.title, textAnchor: c.annotations.single.textAnchors.first),
    );
    expect(face.back.source.hashCode, isA<int>());
    final entries = MapClipboard.decode(MapClipboard.encode(MapClipboard.copy(c, [result.$2.id])))!;
    final pasted = editor.paste(c, entries).$1;
    expect(pasted.annotations.last.textAnchors.length, 2);
    expect(MapExporter(c, rootTitle: 'Root').markdown(), contains('Book'));
    expect(MapExporter(c, rootTitle: 'Root').opml(), contains('main'));
    final missing = editor.paste(StudySetContent.empty, entries).$1;
    expect(missing.cards.single.kind, CardKind.note);
    expect(editor.removeDocument(pasted, doc.id).annotations, isEmpty);
    expect(() => a.textAnchors.add(anchor), throwsUnsupportedError);
    expect(
      () => Annotation(
        id: 'bad',
        documentId: 'book',
        pages: [],
        textAnchors: [anchor],
        quote: 'x',
        colorIndex: 0,
        createdAt: now,
      ),
      throwsArgumentError,
    );
    expect(
      () => Annotation(id: 'bad', documentId: 'book', quote: 'x', colorIndex: 0, createdAt: now),
      throwsArgumentError,
    );
  });

  test('text research, margin notes, ink, bookmark, outline and undo round trip', () {
    var c = StudySetContent.empty.copyWith(documents: [doc]);
    final target = TextTarget(documentId: doc.id, textAnchors: [anchor]);
    expect(NoteTarget.fromJson(target.toJson()).toJson(), target.toJson());
    expect(SourceAnchor(target: target).canLocate(c.documents, c.nodes), isTrue);
    final captured = AnnotationAnchor(textAnchors: [anchor], quote: anchor.quote);
    expect(AnnotationAnchor.fromJson(captured.copyWith(quote: 'Quote').toJson()).quote, 'Quote');
    final note = MarginNote(
      id: 'margin',
      documentId: doc.id,
      anchor: captured,
      text: 'Note',
      colorIndex: 0,
      createdAt: now,
      updatedAt: now,
    );
    c = editor.upsertMarginNote(c, note);
    c = editor.attachMarginNote(c, note.id);
    final inkAnchor = ParagraphInkAnchor(anchor: anchor, blockId: 'block', capturedWidth: 320, originX: 0, originY: 2);
    c = editor.addInkStroke(
      c,
      InkStroke(
        id: 'ink',
        documentId: doc.id,
        textAnchor: inkAnchor,
        tool: InkTool.pen,
        colorIndex: 0,
        width: 2,
        points: [const InkPoint(1, 2)],
      ),
    );
    c = editor.toggleTextBookmark(c, doc.id, position, title: 'End');
    c = editor.setReadingPosition(c, doc.id, position);
    c = editor.setDocumentOutline(c, doc.id, [PdfOutlineEntry(id: 'entry', title: 'Contents', position: position)]);
    final roundtrip = StudySetContent.fromJson(c.toJson());
    expect(roundtrip.toJson(), c.toJson());
    expect(roundtrip.inkStrokes.single.textAnchor!.anchor.quote, anchor.quote);
    expect(() => roundtrip.inkStrokes.single.page, throwsStateError);
    expect(() => roundtrip.marginNotes.single.page, throwsStateError);
    expect(() => roundtrip.bookmarks.single.page, throwsStateError);
    expect(() => roundtrip.documentOutlines.single.items.single.page, throwsStateError);
    expect(editor.toggleTextBookmark(c, doc.id, position).bookmarks, isEmpty);
    expect(
      StudySetEditor.restore(StudySetContent.empty.copyWith(documents: [doc]), c).documents.single.readingPosition,
      position,
    );
    expect(editor.removeDocument(c, doc.id).inkStrokes, isEmpty);
    expect(
      () => ParagraphInkAnchor(anchor: anchor, blockId: '', capturedWidth: 0, originX: 0, originY: 0),
      throwsArgumentError,
    );
  });

  test('source positions sort by spine and UTF-16 offset without fake PDF pages', () {
    final later = TextReadingPosition(revision: 'v1', chapterId: 'next', offset: 0);
    expect(compareReadingPositions(position, later, chapters: ['main', 'next']), lessThan(0));
    expect(
      compareReadingPositions(position, TextReadingPosition(revision: 'v1', chapterId: 'main', offset: 8)),
      lessThan(0),
    );
    expect(compareReadingPositions(PdfPosition(2), PdfPosition(1)), greaterThan(0));
    expect(compareReadingPositions(position, later), 0);
    final entries = [
      PdfOutlineEntry(id: 'later', title: 'Z', position: later),
      PdfOutlineEntry(id: 'first', title: 'A', position: position),
    ];
    expect(OutlineTree.sort(entries, ReaderEntrySort.pageAscending, chapters: ['main', 'next']).first.id, 'first');
    expect(OutlineTree.sort(entries, ReaderEntrySort.pageDescending, chapters: ['main', 'next']).first.id, 'later');
  });

  test('comparison and translation accept stable text positions', () {
    final pair = ComparePair(
      id: 'pair',
      leftDocumentId: 'book',
      right: PdfCompareTarget('other'),
      sourceAlignPoints: [SourceAlignPoint(left: position, right: PdfPosition(2))],
    );
    expect(
      ComparePair.fromJson(pair.copyWith(sync: false).toJson()).sourceAlignPoints.single.left.toJson(),
      position.toJson(),
    );
    final paragraph = TranslationParagraph(
      documentId: 'book',
      textAnchor: anchor,
      index: 0,
      text: anchor.quote,
      fingerprint: 'v1',
    );
    expect(paragraph.textAnchor, anchor);
    expect(() => paragraph.page, throwsStateError);
    expect(() => TranslationParagraph(documentId: 'book', index: 0, text: '', fingerprint: ''), throwsArgumentError);
  });

  test('document package validates paths, snapshots, immutability and memory store', () async {
    final source = doc.sourceFileName!;
    final manifest = doc.fileName;
    final files = {
      source: [1, 2],
      manifest: utf8.encode('{}'),
    };
    final package = DocumentPackage(document: doc, files: files);
    files[source]!.add(3);
    expect(package.files[source], [1, 2]);
    expect(() => package.files[source]![0] = 9, throwsUnsupportedError);
    final store = InMemoryStudySetContentRepository();
    await store.importDocumentPackage('set', package);
    expect(await store.readDocumentFile('set', source), [1, 2]);
    expect((await store.load('set')).documents.single.id, doc.id);
    await expectLater(store.importDocumentPackage('set', package, cancelled: () => true), throwsStateError);
    await expectLater(
      store.importDocumentPackage(
        'set',
        DocumentPackage(
          document: doc,
          files: {
            ...package.files,
            source: [9],
          },
        ),
      ),
      throwsStateError,
    );
    await expectLater(store.readDocumentFile('set', 'documents/missing.pdf'), throwsStateError);
    for (final path in [
      '../secret',
      'documents/../secret',
      'books/x/../../bad',
      'books//x',
      'web/x.tmp',
      '/documents/file',
    ]) {
      expect(() => validateDocumentPath(path), throwsArgumentError);
    }
    expect(() => DocumentPackage(document: doc, files: {manifest: []}), throwsArgumentError);
  });
}
