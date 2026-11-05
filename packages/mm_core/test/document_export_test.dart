import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

final _date = DateTime.utc(2026);

Document _pdf() => Document(
  id: 'd',
  title: 'Book',
  fileName: 'documents/a.pdf',
  sourceFileName: 'documents/a.pdf',
  pageCount: 9,
  importedAt: _date,
);

Document _book({
  DocumentFormat format = DocumentFormat.epub,
  DocumentLayout layout = DocumentLayout.reflow,
  String? source,
}) => Document(
  id: 'd',
  title: 'Book',
  fileName: 'books/d/v1/manifest.json',
  sourceFileName: source ?? 'documents/a.${format.name}',
  contentManifest: 'books/d/v1/manifest.json',
  revision: 'v1',
  format: format,
  layout: layout,
  pageCount: 0,
  importedAt: _date,
);

Annotation _pdfMark(
  String id,
  int page, {
  AnnotationKind kind = AnnotationKind.highlight,
  int color = 0,
  bool review = false,
}) => Annotation(
  id: id,
  documentId: 'd',
  pages: [
    AnnotationPage(page: page, rects: const [PageRect(1, 20, 10, 10)]),
  ],
  quote: 'q',
  colorIndex: color,
  createdAt: _date,
  kind: kind,
  needsReview: review,
);

Annotation _textMark(String id, {String revision = 'v1', AnnotationKind kind = AnnotationKind.highlight}) => Annotation(
  id: id,
  documentId: 'd',
  textAnchors: [TextAnchor('c', 0, 1, 'q', revision: revision)],
  quote: 'q',
  colorIndex: 0,
  createdAt: _date,
  kind: kind,
);

MarginNote _pageNote(String id, int page) => MarginNote(
  id: id,
  documentId: 'd',
  page: page,
  lineY: 10,
  text: 'n',
  colorIndex: 0,
  createdAt: _date,
  updatedAt: _date,
);

MarginNote _textNote(String id, {String revision = 'v1'}) => MarginNote(
  id: id,
  documentId: 'd',
  anchor: AnnotationAnchor(
    textAnchors: [TextAnchor('c', 0, 1, 'q', revision: revision)],
    quote: 'q',
  ),
  text: 'n',
  colorIndex: 0,
  createdAt: _date,
  updatedAt: _date,
);

InkStroke _ink(String id, int page) =>
    InkStroke(id: id, documentId: 'd', page: page, tool: InkTool.pen, colorIndex: 0, width: 1);

StudySetContent _pdfContent() => StudySetContent(
  documents: [_pdf()],
  annotations: [
    _pdfMark('yellow', 1),
    _pdfMark('green', 2, color: 1),
    _pdfMark('under', 3, kind: AnnotationKind.underline),
    _pdfMark('stale', 4, review: true),
    Annotation(
      id: 'other',
      documentId: 'elsewhere',
      pages: [
        AnnotationPage(page: 1, rects: const [PageRect(1, 20, 10, 10)]),
      ],
      quote: 'q',
      colorIndex: 0,
      createdAt: _date,
    ),
  ],
  marginNotes: [_pageNote('n', 5)],
  inkStrokes: [_ink('i', 6)],
);

void main() {
  group('presets', () {
    test('everything keeps each kind of mark', () {
      final plan = DocumentExportPlan.build(
        _pdfContent(),
        _pdf(),
        DocumentExportOptions.preset(DocumentExportPreset.everything),
      );
      expect(plan.annotations.map((a) => a.id), ['yellow', 'green', 'under']);
      expect(plan.notes, hasLength(1));
      expect(plan.strokes, hasLength(1));
      expect(plan.isEmpty, isFalse);
      expect(plan.isUnchangedOriginal, isFalse);
    });

    test('marks only drops notes and ink', () {
      final plan = DocumentExportPlan.build(
        _pdfContent(),
        _pdf(),
        DocumentExportOptions.preset(DocumentExportPreset.marksOnly),
      );
      expect(plan.annotations, hasLength(3));
      expect(plan.notes, isEmpty);
      expect(plan.strokes, isEmpty);
    });

    test('clean is the unchanged original', () {
      final plan = DocumentExportPlan.build(
        _pdfContent(),
        _pdf(),
        DocumentExportOptions.preset(DocumentExportPreset.clean),
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.isUnchangedOriginal, isTrue);
    });
  });

  group('options', () {
    test('hidden colors leave out only those highlights', () {
      final plan = DocumentExportPlan.build(_pdfContent(), _pdf(), const DocumentExportOptions(hiddenColors: {1}));
      expect(plan.annotations.map((a) => a.id), ['yellow', 'under']);
    });

    test('a page selection filters every kind of mark', () {
      final plan = DocumentExportPlan.build(_pdfContent(), _pdf(), const DocumentExportOptions(pages: {2, 5}));
      expect(plan.annotations.map((a) => a.id), ['green']);
      expect(plan.notes, hasLength(1));
      expect(plan.strokes, isEmpty);
    });

    test('a clean page range is not the unchanged original', () {
      final plan = DocumentExportPlan.build(
        _pdfContent(),
        _pdf(),
        DocumentExportOptions.preset(DocumentExportPreset.clean).copyWith(pages: () => {1}),
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.isUnchangedOriginal, isFalse);
    });

    test('copyWith keeps or clears the page selection', () {
      const options = DocumentExportOptions(pages: {1});
      expect(options.copyWith(notes: false).pages, {1});
      expect(options.copyWith(pages: () => null).pages, isNull);
    });

    test('marked pages follow what the options keep', () {
      expect(DocumentExportPlan.markedPages(_pdfContent(), _pdf(), const DocumentExportOptions()), {1, 2, 3, 5, 6});
      expect(
        DocumentExportPlan.markedPages(_pdfContent(), _pdf(), const DocumentExportOptions(notes: false, ink: false)),
        {1, 2, 3},
      );
    });
  });

  group('inventory', () {
    test('counts this document only and sets unconfirmed marks aside', () {
      final inventory = DocumentExportPlan.inventory(_pdfContent(), _pdf());
      expect(inventory.highlights, 2);
      expect(inventory.underlines, 1);
      expect(inventory.marks, 3);
      expect(inventory.notes, 1);
      expect(inventory.ink, 1);
      expect(inventory.unplaced, 1);
      expect(inventory.highlightColors, {0: 1, 1: 1});
      expect(inventory.isEmpty, isFalse);
    });

    test('an unmarked document is empty', () {
      expect(DocumentExportPlan.inventory(StudySetContent(documents: [_pdf()]), _pdf()).isEmpty, isTrue);
    });

    test('marks and notes from another revision of a book are not placed', () {
      final content = StudySetContent(
        documents: [_book()],
        annotations: [
          _textMark('now'),
          _textMark('old', revision: 'v0'),
        ],
        marginNotes: [
          _textNote('now'),
          _textNote('old', revision: 'v0'),
        ],
      );
      final inventory = DocumentExportPlan.inventory(content, _book());
      expect(inventory.marks, 1);
      expect(inventory.notes, 1);
      expect(inventory.unplaced, 2);
    });

    test('a book has no place for ink, and says so', () {
      final book = _book();
      final content = StudySetContent(
        documents: [book],
        inkStrokes: [
          InkStroke(
            id: 'i',
            documentId: 'd',
            textAnchor: ParagraphInkAnchor(
              anchor: const TextAnchor('c', 0, 1, 'q', revision: 'v1'),
              blockId: 'b',
              capturedWidth: 100,
              originX: 0,
              originY: 0,
            ),
            tool: InkTool.pen,
            colorIndex: 0,
            width: 1,
          ),
        ],
      );
      final inventory = DocumentExportPlan.inventory(content, book);
      expect(inventory.ink, 0);
      expect(inventory.unsupportedInk, 1);
    });

    test('fixed-layout books only leave as the original', () {
      final book = _book(layout: DocumentLayout.fixed);
      final content = StudySetContent(documents: [book], annotations: [_textMark('a')]);
      expect(book.exportsMarks, isFalse);
      expect(DocumentExportPlan.inventory(content, book).isEmpty, isTrue);
    });
  });

  group('formats', () {
    test('marked copies keep the file type when a writer exists', () {
      expect(_pdf().markedExportExtension, 'pdf');
      expect(_book().markedExportExtension, 'epub');
      expect(_book(format: DocumentFormat.markdown, source: 'documents/a.md').markedExportExtension, 'md');
      expect(_book(format: DocumentFormat.azw3).markedExportExtension, 'epub');
      expect(_book(format: DocumentFormat.mobi).cleanExportExtension, 'mobi');
    });

    test('a web capture saved as PDF is a PDF', () {
      final web = Document(
        id: 'd',
        title: 'Web',
        fileName: 'documents/w.pdf',
        pageCount: 2,
        importedAt: _date,
        format: DocumentFormat.web,
      );
      expect(web.exportsAsPdf, isTrue);
      expect(web.originalExportFile, 'documents/w.pdf');
    });
  });

  group('parseDocumentPageRanges', () {
    test('reads ranges and lists in common separators', () {
      expect(parseDocumentPageRanges('1-3, 7', 9), {1, 2, 3, 7});
      expect(parseDocumentPageRanges('2–3，5', 9), {2, 3, 5});
      expect(parseDocumentPageRanges(' 4 ', 9), {4});
    });

    test('rejects text it cannot place in the document', () {
      for (final bad in ['', 'abc', '0', '10', '3-1', '1-99', '1-', '99999999']) {
        expect(parseDocumentPageRanges(bad, 9), isNull, reason: bad);
      }
    });
  });

  group('documentExportFileName', () {
    test('removes characters file systems reject', () {
      expect(documentExportFileName('a/b:c\\d', 'pdf', suffix: '（副本）'), 'a-b-c-d（副本）.pdf');
    });

    test('never returns a bare extension', () {
      expect(documentExportFileName(' ', 'pdf'), 'document.pdf');
    });
  });
}
