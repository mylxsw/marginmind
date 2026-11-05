import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/document_export.dart';
import 'package:marginmind/features/workspace/widgets/document_export_sheet.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_book/mm_book.dart' as book;
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

final _date = DateTime.utc(2026);

const _labels = DocumentExportLabels(markedSuffix: '（标注版）', cleanSuffix: '（副本）', notesHeading: '批注');

class _Files implements DocumentRepository {
  _Files(this.files);
  final Map<String, List<int>> files;
  final reads = <String>[];
  @override
  Future<List<int>> readDocumentFile(String studySetId, String fileName) async {
    reads.add(fileName);
    final data = files[fileName];
    if (data == null) throw StateError('missing');
    return data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A stored book, written the way document import stores one.
({Document document, Map<String, List<int>> files}) _storedBook({
  DocumentFormat format = DocumentFormat.epub,
  String sourceFile = 'documents/a.epub',
  String sourceText = 'source-bytes',
  String? text,
}) {
  final chapter = book.BookChapter('c', [
    book.BookBlock(
      id: 'p',
      kind: book.BlockKind.paragraph,
      start: 0,
      runs: [book.InlineRun(text ?? 'Hello marked world')],
    ),
  ]);
  final parsed = book.Book('Book', [chapter], {}, const []);
  final revision = parsed.revision;
  final base = 'books/d/$revision';
  final json = parsed.toJson();
  final files = <String, List<int>>{sourceFile: utf8.encode(sourceText)};
  final spine = <Map<String, Object?>>[];
  for (final c in json['spine'] as List) {
    final encoded = utf8.encode(jsonEncode(c));
    final hash = _sha(encoded);
    final path = '$base/chapters/$hash.json';
    files[path] = encoded;
    spine.add({'id': (c as Map)['id'], 'path': path, 'sha256': hash});
  }
  final manifest = '$base/manifest.json';
  files[manifest] = utf8.encode(jsonEncode({...json, 'spine': spine, 'resources': const []}));
  return (
    document: Document(
      id: 'd',
      title: 'Book',
      fileName: manifest,
      sourceFileName: sourceFile,
      contentManifest: manifest,
      revision: revision,
      format: format,
      layout: DocumentLayout.reflow,
      pageCount: 0,
      importedAt: _date,
    ),
    files: files,
  );
}

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

Annotation _textMark(String revision, String quote, int start, {AnnotationKind kind = AnnotationKind.highlight}) =>
    Annotation(
      id: quote,
      documentId: 'd',
      textAnchors: [TextAnchor('c', start, start + quote.length, quote, revision: revision)],
      quote: quote,
      colorIndex: 0,
      createdAt: _date,
      kind: kind,
    );

MarginNote _textNote(String revision, String quote, int start) => MarginNote(
  id: 'n',
  documentId: 'd',
  anchor: AnnotationAnchor(
    textAnchors: [TextAnchor('c', start, start + quote.length, quote, revision: revision)],
    quote: quote,
  ),
  text: 'my note',
  colorIndex: 0,
  createdAt: _date,
  updatedAt: _date,
);

Document _pdf() => Document(
  id: 'd',
  title: 'Paper',
  fileName: 'documents/a.pdf',
  sourceFileName: 'documents/a.pdf',
  pageCount: 9,
  importedAt: _date,
);

Annotation _pdfMark(String id, int page, {AnnotationKind kind = AnnotationKind.highlight, int color = 0}) => Annotation(
  id: id,
  documentId: 'd',
  pages: [
    AnnotationPage(page: page, rects: const [PageRect(1, 20, 10, 10)]),
  ],
  quote: 'q',
  colorIndex: color,
  createdAt: _date,
  kind: kind,
);

StudySetContent _marked() => StudySetContent(
  documents: [_pdf()],
  annotations: [
    _pdfMark('a', 1),
    _pdfMark('b', 2, color: 1),
    _pdfMark('u', 3, kind: AnnotationKind.underline),
  ],
  marginNotes: [
    MarginNote(
      id: 'n',
      documentId: 'd',
      page: 4,
      lineY: 10,
      text: 'n',
      colorIndex: 0,
      createdAt: _date,
      updatedAt: _date,
    ),
  ],
  inkStrokes: [InkStroke(id: 'i', documentId: 'd', page: 5, tool: InkTool.pen, colorIndex: 0, width: 1)],
);

/// Records options instead of touching PDFium, which widget tests do not load.
class _FakeExporter extends DocumentExporter {
  _FakeExporter(StudySetContent content, Document document, {this.fail = false, this.allowed = true})
    : super(repository: _Files({}), studySetId: 's', content: content, document: document, labels: _labels);
  final bool fail, allowed;
  final written = <DocumentExportOptions>[];
  @override
  Future<bool> canWriteMarks() async => allowed;
  @override
  Future<DocumentExportFile> write(
    DocumentExportOptions options, {
    void Function(double progress)? onProgress,
    bool Function()? cancelled,
  }) async {
    written.add(options);
    if (fail) throw StateError('disk full');
    return (name: 'out.pdf', bytes: Uint8List.fromList([1]));
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required DocumentExporter exporter,
  required StudySetContent content,
  required Document document,
  Future<bool> Function(String, Uint8List)? save,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: MMTheme.light(),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MMHudHost(
        child: Scaffold(
          body: DocumentExportSheet(
            content: content,
            document: document,
            exporter: exporter,
            save: save ?? (_, _) async => true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('sheet', () {
    testWidgets('offers one tap per choice, with options out of the way', (tester) async {
      final content = _marked();
      final exporter = _FakeExporter(content, _pdf());
      await _pump(tester, exporter: exporter, content: content, document: _pdf());
      expect(find.text('包含全部标注'), findsOneWidget);
      expect(find.text('高亮 2 · 下划线 1 · 批注 1 · 画笔 1'), findsOneWidget);
      expect(find.text('只保留高亮和下划线'), findsOneWidget);
      expect(find.text('不带标注'), findsOneWidget);
      expect(find.text('更多选项'), findsOneWidget);
      expect(find.byType(MMSwitch), findsNothing);
      expect(find.byKey(const ValueKey('document-export-save')), findsNothing);
    });

    testWidgets('a choice exports straight away', (tester) async {
      final content = _marked();
      final exporter = _FakeExporter(content, _pdf());
      String? saved;
      await _pump(
        tester,
        exporter: exporter,
        content: content,
        document: _pdf(),
        save: (name, _) async {
          saved = name;
          return false;
        },
      );
      await tester.tap(find.byKey(const ValueKey('document-export-marks')));
      await tester.pumpAndSettle();
      expect(saved, 'out.pdf');
      expect(exporter.written.single.notes, isFalse);
      expect(exporter.written.single.highlights, isTrue);
    });

    testWidgets('a document without marks has a single, plain action', (tester) async {
      final content = StudySetContent(documents: [_pdf()]);
      await _pump(tester, exporter: _FakeExporter(content, _pdf()), content: content, document: _pdf());
      expect(find.text('导出这份文档'), findsOneWidget);
      expect(find.text('包含全部标注'), findsNothing);
      expect(find.text('只保留高亮和下划线'), findsNothing);
    });

    testWidgets('marks with nothing else to leave out skip the redundant choice', (tester) async {
      final content = StudySetContent(documents: [_pdf()], annotations: [_pdfMark('a', 1)]);
      await _pump(tester, exporter: _FakeExporter(content, _pdf()), content: content, document: _pdf());
      expect(find.text('只保留高亮和下划线'), findsNothing);
    });

    testWidgets('more options reveal switches, colors and pages', (tester) async {
      final content = _marked();
      final exporter = _FakeExporter(content, _pdf());
      await _pump(tester, exporter: exporter, content: content, document: _pdf());
      await tester.tap(find.byKey(const ValueKey('document-export-more')));
      await tester.pumpAndSettle();
      expect(find.byType(MMSwitch), findsNWidgets(4));
      expect(find.text('包含全部标注'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('document-export-color-1')));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('document-export-option-notes')),
          matching: find.byType(MMSwitch),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('有标注的页'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('document-export-save')));
      await tester.pumpAndSettle();
      final options = exporter.written.single;
      expect(options.hiddenColors, {1});
      expect(options.notes, isFalse);
      expect(options.pages, {1, 3, 5});
    });

    testWidgets('turning off the last color turns off highlights', (tester) async {
      final content = _marked();
      final exporter = _FakeExporter(content, _pdf());
      await _pump(tester, exporter: exporter, content: content, document: _pdf());
      await tester.tap(find.byKey(const ValueKey('document-export-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('document-export-color-0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('document-export-color-1')));
      await tester.pump();
      expect(find.byKey(const ValueKey('document-export-color-0')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('document-export-save')));
      await tester.pumpAndSettle();
      expect(exporter.written.single.highlights, isFalse);
      expect(exporter.written.single.hiddenColors, isEmpty);
    });

    testWidgets('an invalid page range blocks export and explains itself', (tester) async {
      final content = _marked();
      final exporter = _FakeExporter(content, _pdf());
      await _pump(tester, exporter: exporter, content: content, document: _pdf());
      await tester.tap(find.byKey(const ValueKey('document-export-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('指定页'));
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('document-export-save'));
      expect(tester.widget<MMButton>(save).onPressed, isNull);
      await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey('document-export-pages')), matching: find.byType(EditableText)),
        '99',
      );
      await tester.pump();
      expect(find.textContaining('1 到 9'), findsOneWidget);
      expect(tester.widget<MMButton>(save).onPressed, isNull);
      await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey('document-export-pages')), matching: find.byType(EditableText)),
        '2-3',
      );
      await tester.pump();
      expect(find.textContaining('1 到 9'), findsNothing);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(exporter.written.single.pages, {2, 3});
    });

    testWidgets('a protected PDF offers only the clean copy and says why', (tester) async {
      final content = _marked();
      await _pump(tester, exporter: _FakeExporter(content, _pdf(), allowed: false), content: content, document: _pdf());
      expect(find.text('包含全部标注'), findsNothing);
      expect(find.text('导出这份文档'), findsOneWidget);
      expect(find.textContaining('不允许添加标注'), findsOneWidget);
    });

    testWidgets('a failure stays in the sheet and the choice can be retried', (tester) async {
      final content = _marked();
      final exporter = _FakeExporter(content, _pdf(), fail: true);
      await _pump(tester, exporter: exporter, content: content, document: _pdf());
      await tester.tap(find.byKey(const ValueKey('document-export-everything')));
      await tester.pumpAndSettle();
      expect(find.text('导出失败，请重试。'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('document-export-everything')));
      await tester.pumpAndSettle();
      expect(exporter.written, hasLength(2));
    });

    testWidgets('states what a reflowable copy cannot keep', (tester) async {
      final stored = _storedBook(format: DocumentFormat.azw3, sourceFile: 'documents/a.azw3');
      final revision = stored.document.revision!;
      final content = StudySetContent(
        documents: [stored.document],
        annotations: [_textMark(revision, 'marked', 6), _textMark('old', 'gone', 0)],
        inkStrokes: [
          InkStroke(
            id: 'i',
            documentId: 'd',
            textAnchor: ParagraphInkAnchor(
              anchor: TextAnchor('c', 0, 5, 'Hello', revision: revision),
              blockId: 'p',
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
      await _pump(
        tester,
        exporter: _FakeExporter(content, stored.document),
        content: content,
        document: stored.document,
      );
      expect(find.text('高亮 1 · 导出为 EPUB'), findsOneWidget);
      expect(find.textContaining('位置需要确认'), findsOneWidget);
      expect(find.textContaining('画笔只能写入 PDF'), findsOneWidget);
    });
  });

  group('exporter', () {
    test('a clean copy of a book is its original file, untouched', () async {
      final stored = _storedBook();
      final files = _Files(stored.files);
      final exporter = DocumentExporter(
        repository: files,
        studySetId: 's',
        content: StudySetContent(documents: [stored.document]),
        document: stored.document,
        labels: _labels,
      );
      final file = await exporter.write(DocumentExportOptions.preset(DocumentExportPreset.clean));
      expect(file.name, 'Book（副本）.epub');
      expect(utf8.decode(file.bytes), 'source-bytes');
    });

    test('a marked book becomes an EPUB with those marks at their offsets', () async {
      final stored = _storedBook(format: DocumentFormat.mobi, sourceFile: 'documents/a.mobi');
      final revision = stored.document.revision!;
      final exporter = DocumentExporter(
        repository: _Files(stored.files),
        studySetId: 's',
        content: StudySetContent(
          documents: [stored.document],
          annotations: [_textMark(revision, 'marked', 6)],
          marginNotes: [_textNote(revision, 'world', 13)],
        ),
        document: stored.document,
        labels: _labels,
      );
      final file = await exporter.write(const DocumentExportOptions());
      expect(file.name, 'Book（标注版）.epub');
      final chapter = ZipDecoder().decodeBytes(file.bytes).files.firstWhere((f) => f.name.endsWith('chapter0.xhtml'));
      final xhtml = utf8.decode(chapter.content);
      expect(xhtml, contains('>marked</mark>'));
      expect(xhtml, contains('my note'));
    });

    test('a marked Markdown file stays Markdown', () async {
      final stored = _storedBook(
        format: DocumentFormat.markdown,
        sourceFile: 'documents/a.md',
        sourceText: '# Hi\n\nHello **marked** world\n',
        text: 'Hello marked world',
      );
      final revision = stored.document.revision!;
      final exporter = DocumentExporter(
        repository: _Files(stored.files),
        studySetId: 's',
        content: StudySetContent(
          documents: [stored.document],
          annotations: [_textMark(revision, 'marked', 6)],
          marginNotes: [_textNote(revision, 'world', 13)],
        ),
        document: stored.document,
        labels: _labels,
      );
      final file = await exporter.write(const DocumentExportOptions());
      expect(file.name, 'Book（标注版）.md');
      final text = utf8.decode(file.bytes);
      expect(text, contains('**<mark>marked</mark>** world[^1]'));
      expect(text, contains('[^1]: my note'));
    });

    test('a web capture without a source file still has a clean copy', () async {
      final stored = _storedBook();
      final web = Document(
        id: 'd',
        title: 'Page',
        fileName: stored.document.fileName,
        contentManifest: stored.document.contentManifest,
        revision: stored.document.revision,
        format: DocumentFormat.epub,
        layout: DocumentLayout.reflow,
        pageCount: 0,
        importedAt: _date,
      );
      final file = await DocumentExporter(
        repository: _Files(stored.files),
        studySetId: 's',
        content: StudySetContent(documents: [web]),
        document: web,
        labels: _labels,
      ).write(DocumentExportOptions.preset(DocumentExportPreset.clean));
      expect(file.name, 'Page（副本）.epub');
      expect(ZipDecoder().decodeBytes(file.bytes).files.first.name, 'mimetype');
    });

    test('a missing source file surfaces as a failure', () async {
      final stored = _storedBook();
      final exporter = DocumentExporter(
        repository: _Files({}),
        studySetId: 's',
        content: StudySetContent(documents: [stored.document]),
        document: stored.document,
        labels: _labels,
      );
      expect(() => exporter.write(DocumentExportOptions.preset(DocumentExportPreset.clean)), throwsStateError);
    });
  });
}
