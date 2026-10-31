import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/map_generation_context.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'reflow_fixtures.dart';

class DigestReader implements StudySetReader {
  DigestReader(this.texts);
  final Map<int, String> texts;
  @override
  Future<List<ReadPage>> readPages(
    String documentId,
    int from,
    int to,
    ReadScope scope,
    CancellationToken cancel,
  ) async {
    expect(scope.allowsPage(documentId, from), isTrue);
    return [if (texts[from] case final text?) ReadPage(documentId, from, text)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Document pdf({int lastPage = 1}) => Document(
  id: 'private-doc',
  title: 'PDF',
  fileName: 'documents/doc.pdf',
  pageCount: 4,
  lastPage: lastPage,
  importedAt: DateTime.utc(2026),
);
Annotation annotation(String id, int page) => Annotation(
  id: id,
  documentId: 'private-doc',
  page: page,
  rects: [],
  quote: 'quote',
  colorIndex: 0,
  createdAt: DateTime.utc(2026),
);
final outline = DocumentOutline(
  documentId: 'private-doc',
  items: [
    const PdfOutlineEntry(id: 'c1', title: 'One', page: 1),
    const PdfOutlineEntry(id: 'c2', title: 'Two', page: 3),
  ],
);
Future<DocumentDigest> digest(
  DocumentDigestBuilder builder,
  StudySetContent snapshot, {
  List<String> chapters = const [],
  bool include = true,
  CancellationToken? cancel,
}) => builder.build(
  snapshot,
  studySetId: 'demo-1',
  documentId: snapshot.documents.single.id,
  mapId: 'private-map',
  draftPrefix: 'run-',
  chapters: chapters,
  includeAnnotations: include,
  cancellation: cancel,
);
void main() {
  test('two chapters, annotation aliases and localized incremental fingerprints', () async {
    final builder = DocumentDigestBuilder(DigestReader({1: 'one', 2: 'two', 3: 'three', 4: 'four'}));
    final first = StudySetContent(
      documents: [pdf(lastPage: 2)],
      documentOutlines: [outline],
      annotations: [annotation('private-mark', 3)],
    );
    final before = await digest(builder, first);
    expect(before.chapters, hasLength(2));
    expect(before.chapters.first.input.textByPage.keys, [1, 2]);
    expect(before.chapters.last.input.textByPage.keys, [3, 4]);
    expect(before.chapters.last.input.context.annotations, {'A1': 'private-mark'});
    expect(jsonEncode(before.chapters.last.input.annotations), isNot(contains('private-')));
    final after = await digest(
      builder,
      first.copyWith(
        documents: [pdf(lastPage: 4)],
        annotations: [annotation('private-mark', 3), annotation('second-mark', 4)],
      ),
    );
    expect(after.source.fingerprint, isNot(before.source.fingerprint));
    expect(after.chapters.first.fingerprint, before.chapters.first.fingerprint);
    expect(after.chapters.last.fingerprint, isNot(before.chapters.last.fingerprint));
    final readOnly = await digest(builder, first.copyWith(documents: [pdf(lastPage: 4)]));
    expect(readOnly.source.fingerprint, before.source.fingerprint);
    expect(readOnly.source.readThrough, 4);
    final selected = await digest(builder, first, chapters: ['c2'], include: false);
    expect(selected.chapters, hasLength(1));
    expect(selected.chapters.single.input.annotations, isEmpty);
    expect(selected.source.chapters, ['c2']);
  });
  test('page fallback preserves the entire long page and emoji', () async {
    final text = '${'a' * 30000}😀${'b' * 40000}';
    final result = await digest(DocumentDigestBuilder(DigestReader({1: text})), StudySetContent(documents: [pdf()]));
    expect(result.chapters, hasLength(1));
    expect(result.chapters.expand((c) => c.input.textByPage.values).join(), text);
    expect(result.chapters.map((c) => c.input.chapterId).toSet().length, result.chapters.length);
    for (final c in result.chapters) {
      expect(utf8.decode(utf8.encode(c.input.textByPage.values.join())), c.input.textByPage.values.join());
    }
  });
  test('48-page chapter preserves every page and annotation in a complete section', () async {
    final text = '章' * 1500;
    final doc = Document(
      id: 'private-doc',
      title: 'Long chapter',
      fileName: 'documents/long.pdf',
      pageCount: 48,
      importedAt: DateTime.utc(2026),
    );
    final snapshot = StudySetContent(
      documents: [doc],
      documentOutlines: [
        DocumentOutline(
          documentId: doc.id,
          items: [const PdfOutlineEntry(id: 'long', title: 'Long', page: 1)],
        ),
      ],
      annotations: [for (var p = 1; p <= 48; p++) annotation('mark-$p', p)],
    );
    final plan = await digest(DocumentDigestBuilder(DigestReader({for (var p = 1; p <= 48; p++) p: text})), snapshot);
    expect(plan.chapters, hasLength(1));
    expect(plan.chapters.expand((c) => c.input.textByPage.values).join(), text * 48);
    expect(plan.chapters.single.input.textByPage.keys, List.generate(48, (i) => i + 1));
    expect(plan.chapters.single.input.context.annotations, hasLength(48));
    expect(plan.chapters.single.input.annotations, hasLength(48));
  });
  test('escaped text, huge marks, comments and instructions are never clipped', () async {
    final text = ('中文"\\\n\u0000😀' * 15000);
    final doc = pdf();
    final snapshot = StudySetContent(
      documents: [doc],
      annotations: [
        Annotation(
          id: 'a',
          documentId: doc.id,
          page: 1,
          rects: [],
          quote: text,
          colorIndex: 0,
          createdAt: DateTime.utc(2026),
        ),
      ],
      marginNotes: [
        MarginNote(
          id: 'n',
          documentId: doc.id,
          page: 1,
          lineY: 0.2,
          text: text,
          colorIndex: 0,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ],
    );
    final plan = await digest(DocumentDigestBuilder(DigestReader({1: text})), snapshot);
    expect(plan.chapters.expand((c) => c.input.textByPage.values).join(), text);
    expect(plan.chapters, hasLength(1));
    final input = plan.chapters.single.input;
    expect(jsonDecode(input.annotations['A1']!)['quote'], text);
    expect(input.annotations['comment1'], text);
    expect(input.context.annotations, {'A1': 'a'});
    final instructions = '详细要求' * 1000;
    final withInstructions = await DocumentDigestBuilder(DigestReader({1: text})).build(
      snapshot,
      studySetId: 'demo-1',
      documentId: doc.id,
      mapId: 'map',
      draftPrefix: 'test-',
      instructions: instructions,
    );
    expect(withInstructions.chapters.single.input.instructions, instructions);
  });
  test('outline loader, nested selection, invalid requests and OCR result', () async {
    final reader = DigestReader({1: 'one', 2: 'two', 3: 'three', 4: 'four'});
    final builder = DocumentDigestBuilder(
      reader,
      loadOutline: (_, _) async => DocumentOutline(
        documentId: 'private-doc',
        items: [
          const PdfOutlineEntry(
            id: 'parent',
            title: 'Parent',
            page: 1,
            children: [PdfOutlineEntry(id: 'child', title: 'Child', page: 2)],
          ),
          const PdfOutlineEntry(id: 'next', title: 'Next', page: 4),
        ],
      ),
    );
    final snapshot = StudySetContent(documents: [pdf()]);
    final selected = await digest(builder, snapshot, chapters: ['parent']);
    expect(selected.chapters.expand((c) => c.input.textByPage.keys), [1, 2, 3]);
    await expectLater(digest(builder, snapshot, chapters: ['unknown']), throwsA(isA<ResearchFailure>()));
    await expectLater(
      digest(DocumentDigestBuilder(DigestReader({})), snapshot),
      throwsA(isA<MapDigestNeedsText>().having((e) => e.message, 'message', '需要识别文字')),
    );
    await expectLater(
      digest(builder, snapshot, cancel: CancellationToken()..cancel()),
      throwsA(isA<ResearchFailure>()),
    );
  });
  test('PDF notes stay in chapter and do not send structural IDs', () async {
    final builder = DocumentDigestBuilder(DigestReader({1: 'one', 2: 'two', 3: 'three', 4: 'four'}));
    final base = StudySetContent(documents: [pdf()], documentOutlines: [outline]);
    final note = MarginNote(
      id: 'private-note',
      documentId: 'private-doc',
      page: 3,
      lineY: 0.2,
      text: 'Comment',
      colorIndex: 0,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final before = await digest(builder, base), after = await digest(builder, base.copyWith(marginNotes: [note]));
    expect(after.chapters.first.fingerprint, before.chapters.first.fingerprint);
    expect(after.chapters.last.fingerprint, isNot(before.chapters.last.fingerprint));
    expect(jsonEncode(after.chapters.last.input.annotations), contains('Comment'));
    expect(jsonEncode(after.chapters.last.input.annotations), isNot(contains('private-')));
    expect(after.source.fingerprint, isNot(before.source.fingerprint));
  });
  test('document and excerpt attached notes affect only their owning chapter', () async {
    final builder = DocumentDigestBuilder(DigestReader({1: 'one', 2: 'two', 3: 'three', 4: 'four'}));
    final mark = annotation('private-mark', 3);
    final note = ResearchNote(
      id: 'note',
      title: 'Note',
      body: 'Attached comment',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final base = StudySetContent(
      documents: [pdf(lastPage: 2)],
      documentOutlines: [outline],
      annotations: [mark],
      cards: [Card(id: 'card', kind: CardKind.excerpt, annotationId: mark.id, createdAt: DateTime.utc(2026))],
      researchNotes: [note],
    );
    final before = await digest(builder, base);
    for (final target in <NoteTarget>[
      PdfTarget(
        documentId: 'private-doc',
        pages: [const AnnotationPage(page: 3, rects: [])],
      ),
      const CardTarget(cardId: 'card'),
    ]) {
      final after = await digest(
        builder,
        base.copyWith(
          noteAttachments: [NoteAttachment(id: 'attachment', noteId: 'note', target: target)],
        ),
      );
      expect(after.chapters.first.fingerprint, before.chapters.first.fingerprint);
      expect(after.chapters.last.fingerprint, isNot(before.chapters.last.fingerprint));
      expect(after.chapters.last.input.annotations.values.join(), contains('Attached comment'));
      expect(jsonEncode(after.chapters.last.input.annotations), isNot(contains('private-')));
    }
  });
  test('EPUB, MOBI, Markdown, web canonical chapters and text anchors', () async {
    for (final format in [DocumentFormat.epub, DocumentFormat.mobi, DocumentFormat.markdown, DocumentFormat.web]) {
      final repo = InMemoryStudySetContentRepository();
      final a = const EpubParser().parseHtml('a', '<h1>First</h1><p>First text.</p>');
      final b = const EpubParser().parseHtml('b', '<h1>Second</h1><p>Second text.</p>');
      final doc = await storeBook(
        repo,
        format: format,
        book: Book(
          'Book',
          [a, b],
          {},
          [],
          toc: [BookTocEntry('one', 'One', 'a', 0), BookTocEntry('two', 'Two', 'b', 0)],
        ),
      );
      final anchor = TextAnchor('b', 0, 6, 'Second', revision: doc.revision!);
      final snapshot = StudySetContent(
        documents: [doc],
        annotations: [
          Annotation(
            id: 'private-text-mark',
            documentId: doc.id,
            textAnchors: [anchor],
            quote: 'Second',
            colorIndex: 0,
            createdAt: DateTime.utc(2026),
          ),
        ],
        marginNotes: [
          MarginNote(
            id: 'text-note',
            documentId: doc.id,
            anchor: AnnotationAnchor(textAnchors: [anchor], quote: 'Second'),
            text: 'Text comment',
            colorIndex: 0,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );
      final builder = DocumentDigestBuilder(DigestReader({}), repository: repo);
      final result = await digest(builder, snapshot);
      expect(result.chapters, hasLength(2));
      expect(result.chapters.last.input.annotations.values.join(), contains('Text comment'));
      expect(result.chapters.last.input.context.pages.values.single, isEmpty);
      final selected = await digest(builder, snapshot, chapters: ['two']);
      expect(selected.chapters.single.input.textByPage.values.single, b.canonicalText);
      await expectLater(digest(DocumentDigestBuilder(DigestReader({})), snapshot), throwsA(isA<ResearchFailure>()));
    }
  });
}
