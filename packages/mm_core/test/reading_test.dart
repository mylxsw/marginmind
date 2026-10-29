import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:test/test.dart';

final date = DateTime.utc(2026);
Document doc(String id) => Document(id: id, title: id, fileName: '$id.pdf', pageCount: 3, importedAt: date);
MarginNote note({String id = 'n', String? nodeId, String? mapId, AnnotationAnchor? anchor}) => MarginNote(
  id: id,
  documentId: 'a',
  page: 1,
  anchor: anchor,
  lineY: anchor == null ? 500 : null,
  text: 'thought',
  colorIndex: 2,
  nodeId: nodeId,
  mapId: mapId,
  createdAt: date,
  updatedAt: date,
);
TranslationCache cache(Map<String, String> paragraphs, {String model = 'model'}) =>
    TranslationCache(documentId: 'a', targetLang: 'zh', paragraphs: paragraphs, model: model, createdAt: date);
ComparePair pair() => ComparePair(id: 'pair', leftDocumentId: 'a', right: PdfCompareTarget('b'));
void main() {
  var sequence = 0;
  final editor = StudySetEditor(newId: () => 'id${sequence++}', now: () => date);
  StudySetContent seed() => StudySetContent(documents: [doc('a'), doc('b')]);
  test('all reading data survives JSON, copying, and missing fields', () {
    final insets = CropInsets(left: 10, top: 20, right: 30, bottom: 40);
    final crop = DocumentCrop(
      all: insets,
      odd: insets.copyWith(left: 30),
      pages: {2: insets},
      scope: CropScope.oddEven,
    );
    final anchor = AnnotationAnchor(
      pages: [
        const AnnotationPage(page: 1, rects: [PageRect(10, 20, 30, 5)]),
      ],
      quote: 'quote',
    );
    final point = AlignPoint(left: PdfReadingPosition(page: 1, y: 400), right: PdfReadingPosition(page: 2, y: 300));
    final c = seed().copyWith(
      documents: [
        doc('a').copyWith(crop: crop),
        doc('b'),
      ],
      marginNotes: [note(anchor: anchor).copyWith(nodeId: 'card', mapId: 'main')],
      comparePairs: [
        pair().copyWith(alignPoints: [point]),
        ComparePair(id: 'ai', leftDocumentId: 'a', right: AiCompareTarget('zh')),
      ],
      translationCaches: [
        cache({'fp': '译文'}),
      ],
    );
    final encoded = jsonDecode(jsonEncode(c.toJson())) as Map;
    expect(StudySetContent.fromJson(encoded.cast()).toJson(), c.toJson());
    expect(c.copyWith().toJson(), c.toJson());
    expect(StudySetContent.fromJson({}).marginNotes, isEmpty);
    expect(Document.fromJson(doc('a').toJson()).crop, isNull);
    expect(c.documents.first.copyWith(crop: null).crop, isNull);
    expect(crop.forPage(1).left, 30);
    expect(crop.forPage(2).left, 10);
    expect(crop.copyWith(odd: null).forPage(1).left, 10);
    expect(crop.copyWith(enabled: false).forPage(1).left, 0);
    expect(crop.copyWith(scope: CropScope.page).forPage(1).left, 0);
    expect(crop.copyWith(scope: CropScope.page).forPage(2).left, 10);
    expect(crop.copyWith(scope: CropScope.all, mode: CropMode.manual).forPage(1).left, 10);
    expect(point.copyWith().toJson(), point.toJson());
    expect(point.copyWith(left: point.left.copyWith(page: 2, y: 20), right: point.right).left.page, 2);
    expect(anchor.copyWith().toJson(), anchor.toJson());
    expect(anchor.copyWith(quote: 'q', pages: anchor.pages).quote, 'q');
    expect((pair().right as PdfCompareTarget).copyWith().documentId, 'b');
    expect(PdfCompareTarget('a').copyWith(documentId: 'b').documentId, 'b');
    expect(AiCompareTarget('zh').copyWith().targetLang, 'zh');
    expect(AiCompareTarget('zh').copyWith(targetLang: 'en').targetLang, 'en');
    expect(pair().copyWith(leftDocumentId: 'c', right: AiCompareTarget('en'), sync: false).sync, false);
    expect(cache({}).copyWith(model: 'other').model, 'other');
    expect(note().copyWith(page: 2, lineY: 2.0, text: 'x', colorIndex: 3).page, 2);
    expect(note(anchor: anchor).copyWith(anchor: null, lineY: 10.0).lineY, 10);
    insets.validateSize(600, 800);
    expect(insets.copyWith(top: 1, right: 2, bottom: 3).bottom, 3);
  });
  test('invalid geometry and ambiguous targets are rejected in release too', () {
    expect(() => CropInsets(left: double.nan), throwsArgumentError);
    expect(() => CropInsets(left: 600).validateSize(600, 800), throwsArgumentError);
    expect(() => DocumentCrop(all: CropInsets(), pages: {0: CropInsets()}), throwsArgumentError);
    expect(() => DocumentCrop(all: CropInsets()).forPage(0), throwsArgumentError);
    expect(() => PdfReadingPosition(page: 0, y: 0), throwsArgumentError);
    expect(() => AnnotationAnchor(pages: [], quote: ''), throwsArgumentError);
    expect(
      () => MarginNote(id: 'n', documentId: 'a', page: 1, text: '', colorIndex: 0, createdAt: date, updatedAt: date),
      throwsArgumentError,
    );
    expect(() => note().copyWith(lineY: -1.0), throwsArgumentError);
    expect(() => note().copyWith(mapId: 'other'), throwsArgumentError);
    expect(() => note().copyWith(colorIndex: 6), throwsArgumentError);
    expect(() => ComparePair(id: 'p', leftDocumentId: 'a', right: PdfCompareTarget('a')), throwsArgumentError);
    expect(() => CompareTarget.fromJson({'kind': 'unknown'}), throwsFormatException);
    expect(() => PdfCompareTarget(''), throwsArgumentError);
    expect(() => AiCompareTarget(' '), throwsArgumentError);
    expect(() => cache({'fp': ''}), throwsArgumentError);
    final pages = <int, CropInsets>{1: CropInsets()};
    final crop = DocumentCrop(all: CropInsets(), pages: pages);
    pages.clear();
    expect(crop.pages.length, 1);
    expect(() => crop.pages.clear(), throwsUnsupportedError);
    expect(() => cache({}).paragraphs['x'] = 'y', throwsUnsupportedError);
  });
  test('margin link shares edits; either deletion preserves the other entity', () {
    final anchor = AnnotationAnchor(
      pages: [
        const AnnotationPage(page: 1, rects: [PageRect(1, 10, 20, 1)]),
      ],
      quote: 'source',
    );
    var c = editor.upsertMarginNote(seed(), note(anchor: anchor));
    c = editor.attachMarginNote(c, 'n');
    final linked = c.marginNotes.single;
    expect(c.card(linked.nodeId!)!.body, 'source');
    expect(editor.attachMarginNote(c, 'n'), same(c));
    c = editor.rename(c, linked.nodeId!, 'edited');
    expect(c.marginNotes.single.text, 'edited');
    expect(c.card(linked.nodeId!)!.title, 'edited');
    final withoutNode = editor.removeFromMap(c, linked.nodeId!);
    expect(withoutNode.marginNotes.single.nodeId, isNull);
    expect(withoutNode.marginNotes.single.text, 'edited');
    final withoutNote = editor.removeMarginNote(c, 'n');
    expect(withoutNote.cards.single.title, 'edited');
    expect(withoutNote.annotations.single.quote, 'source');
    expect(editor.upsertMarginNote(c, linked.copyWith(text: ' ')).marginNotes, isEmpty);
    expect(editor.upsertMarginNote(seed(), note().copyWith(text: ' ')).marginNotes, isEmpty);
    final line = editor.attachMarginNote(editor.upsertMarginNote(seed(), note()), 'n');
    expect(line.cards.single.kind, CardKind.note);
    final otherMap = StudySetEditor(newId: () => 'unused', now: () => date, mapId: 'other');
    expect(() => otherMap.attachMarginNote(editor.upsertMarginNote(seed(), note()), 'n'), throwsArgumentError);
    expect(() => editor.attachMarginNote(seed(), 'missing'), throwsArgumentError);
    expect(() => editor.upsertMarginNote(seed(), note(nodeId: 'missing')), throwsArgumentError);
    expect(() => editor.upsertMarginNote(c, note(id: 'other', nodeId: linked.nodeId)), throwsArgumentError);
    expect(() => editor.upsertMarginNote(seed(), note().copyWith(page: 4)), throwsArgumentError);
  });
  test('map deletion and a shared card detach only the owning map link', () {
    final other = StudySetEditor(newId: () => 'other-card', now: () => date, mapId: 'other');
    var c = seed().copyWith(
      maps: [
        MindMap.main,
        const MindMap(id: 'other', title: 'Other'),
      ],
    );
    c = other.attachMarginNote(other.upsertMarginNote(c, note()), 'n');
    final cardId = c.marginNotes.single.nodeId!;
    c = editor.placeCard(c, cardId);
    final snapshot = c.toJson();
    final removed = other.removeFromMap(c, cardId);
    expect(removed.marginNotes.single.nodeId, isNull);
    expect(removed.card(cardId), isNotNull);
    expect(removed.node(cardId), isNotNull);
    final withoutMap = editor.removeMap(c, 'other');
    expect(withoutMap.marginNotes.single.nodeId, isNull);
    expect(withoutMap.card(cardId), isNotNull);
    expect(c.toJson(), snapshot, reason: 'undo can restore the original immutable content');
    final withPair = editor.upsertComparePair(c, pair());
    expect(editor.removeDocument(withPair, 'b').comparePairs, isEmpty);
    final moved = MarginNote(
      id: 'n',
      documentId: 'b',
      page: 1,
      lineY: 20,
      text: 'Moved',
      colorIndex: 0,
      createdAt: date,
      updatedAt: date,
    );
    expect(() => editor.upsertMarginNote(c, moved), throwsArgumentError);
  });
  test('repository merges concurrent paragraphs, validates references and deletes cleanly', () async {
    final repo = InMemoryStudySetContentRepository({'s': seed()});
    final events = <StudySetContent>[];
    final sub = repo.watch('s').listen(events.add);
    await Future<void>.delayed(Duration.zero);
    await repo.setDocumentCrop('s', 'a', DocumentCrop(all: CropInsets(left: 10)));
    await repo.upsertMarginNote('s', note());
    await repo.upsertComparePair('s', pair());
    await Future.wait([
      repo.mergeTranslationParagraphs('s', cache({'a': '甲'})),
      repo.mergeTranslationParagraphs('s', cache({'b': '乙'})),
    ]);
    expect((await repo.load('s')).translationCaches.single.paragraphs, {'a': '甲', 'b': '乙'});
    await expectLater(repo.mergeTranslationParagraphs('s', cache({'c': '丙'}, model: 'other')), throwsArgumentError);
    await expectLater(repo.setDocumentCrop('s', 'missing', null), throwsArgumentError);
    await expectLater(
      repo.setDocumentCrop('s', 'a', DocumentCrop(all: CropInsets(), pages: {4: CropInsets()})),
      throwsArgumentError,
    );
    final p = AlignPoint(left: PdfReadingPosition(page: 1, y: 300), right: PdfReadingPosition(page: 1, y: 400));
    await expectLater(repo.upsertComparePair('s', pair().copyWith(alignPoints: [p, p])), throwsArgumentError);
    await repo.upsertComparePair('s', pair().copyWith(alignPoints: [p]));
    final deleted = editor.removeDocument(await repo.load('s'), 'a');
    expect(deleted.marginNotes, isEmpty);
    expect(deleted.comparePairs, isEmpty);
    expect(deleted.translationCaches, isEmpty);
    await repo.removeMarginNote('s', 'n');
    await repo.removeComparePair('s', 'pair');
    await repo.removeTranslationCache('s', 'a', 'zh');
    await repo.setDocumentCrop('s', 'a', null);
    final result = await repo.load('s');
    expect(result.marginNotes, isEmpty);
    expect(result.comparePairs, isEmpty);
    expect(result.translationCaches, isEmpty);
    expect(result.document('a')!.crop, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(events.length, greaterThan(5));
    await sub.cancel();
  });
}
