import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:test/test.dart';

final time = DateTime.utc(2026, 10, 26);
const hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const snapshot = 'research/snapshots/$hash.md';
final pdf = PdfTarget(
  documentId: 'doc',
  pages: [
    const AnnotationPage(page: 2, rects: [PageRect(1, 20, 30, 4)]),
  ],
  quote: 'quote',
  context: 'context',
);
final source = ResearchSource(
  id: 'source',
  url: 'https://example.com/?a=1&b=2',
  canonicalUrl: 'https://example.com',
  kind: 'web',
  title: 'A & B',
  authors: ['Author'],
  fetchedAt: time,
  publishedAt: time,
  doi: 'doi',
  videoId: 'video',
  versions: [const SourceVersion(version: 1, snapshotFile: snapshot, hash: hash)],
);
final evidence = Evidence(
  id: 'e',
  sourceId: 'source',
  sourceVersion: 1,
  quote: 'captured',
  locator: const EvidenceLocator.paragraph('p1'),
  acquisition: EvidenceAcquisition.auto,
  capturedAt: time,
);
ResearchNote note({String id = 'note', String? sessionId = 'session'}) => ResearchNote(
  id: id,
  title: 'Finding <1>',
  body: '**body**\nsecond line',
  question: 'why?',
  citations: [const EvidenceRef('e')],
  origin: NoteOrigin.ai,
  sessionId: sessionId,
  createdAt: time,
  updatedAt: time,
);
StudySetContent base() => StudySetContent(
  documents: [Document(id: 'doc', title: 'Book', fileName: 'documents/a.pdf', pageCount: 4, importedAt: time)],
);
void main() {
  late StudySetEditor editor;
  setUp(() {
    var id = 0;
    editor = StudySetEditor(newId: () => 'id-${id++}', now: () => time);
  });
  StudySetContent saved() => editor.saveResearchNote(
    base(),
    note(),
    targets: [pdf],
    evidence: [evidence],
    sources: [source],
    createCard: true,
  );

  test('format 7 entities round trip with optional and locator variants', () {
    var c = saved();
    final card = c.cards.single;
    expect(card.title, isEmpty); // Only a reference, never a copy of body.
    c = editor.setCardWidth(c, card.id, 320);
    c = editor.setMapDensity(c, MapDensity.compact);
    c = editor.setNoteFormat(c, 'note', TextFormat.markdown);
    c = editor.setCardTextFormat(c, card.id, TextFormat.markdown);
    c = editor.addInkStroke(
      c,
      InkStroke(
        id: 'stroke',
        documentId: 'doc',
        page: 2,
        tool: InkTool.pen,
        colorIndex: 1,
        width: 2,
        points: [const InkPoint(3, 4), const InkPoint(5, 6)],
      ),
    );
    c = editor.addInkStroke(
      c,
      InkStroke(
        id: 'ellipse',
        documentId: 'doc',
        page: 1,
        tool: InkTool.ellipse,
        colorIndex: 0,
        width: 1,
        ellipse: const PageRect(0, 10, 10, 0),
      ),
    );
    c = editor.addInkStroke(
      c,
      InkStroke(
        id: 'arrow',
        documentId: 'doc',
        page: 1,
        tool: InkTool.arrow,
        colorIndex: 2,
        width: 2,
        points: [const InkPoint(1, 1), const InkPoint(8, 9)],
      ),
    );
    expect(
      () => editor.addInkStroke(
        c,
        InkStroke(
          id: 'bad-arrow',
          documentId: 'doc',
          page: 1,
          tool: InkTool.arrow,
          colorIndex: 2,
          width: 2,
          points: [const InkPoint(1, 1)],
        ),
      ),
      throwsArgumentError,
    );
    c = c.copyWith(
      cards: [
        ...c.cards,
        Card(id: 'image', kind: CardKind.image, createdAt: time, imageFileName: 'images/a.png', imageOrigin: 'paste'),
      ],
    );
    final decoded = StudySetContent.fromJson((jsonDecode(jsonEncode(c.toJson())) as Map).cast());
    expect(decoded.toJson(), c.toJson());
    expect(StudySetEditor.restore(base(), c).toJson(), base().toJson());
    expect(StudySetEditor.restore(c, base()).toJson(), c.toJson());
    expect(decoded.researchNotes.single.edited, isTrue);
    expect(decoded.card(card.id)!.copyWith(title: 'new').researchNoteId, 'note');
    expect(decoded.card('image')!.copyWith(title: 'new').imageOrigin, 'paste');
    for (final locator in [const EvidenceLocator.page(3), const EvidenceLocator.timeRange(1, 2)]) {
      expect(EvidenceLocator.fromJson(locator.toJson()).toJson(), locator.toJson());
    }
    expect(() => EvidenceLocator.fromJson({}), throwsFormatException);
    expect(() => NoteTarget.fromJson({'type': 'other'}), throwsFormatException);
    expect(note().copyWith(title: 'new', body: 'edited', updatedAt: time).body, 'edited');
    expect(editor.setCardWidth(c, card.id, null).node(card.id)!.width, isNull);
    expect(() => editor.setCardWidth(c, card.id, double.nan), throwsArgumentError);
    expect(StudySetContent.fromJson({}).maps.single.density, MapDensity.full);
  });

  test('save, attach, detach, delete and restore are single immutable edits', () {
    final original = base();
    var c = saved();
    final card = c.cards.single;
    expect(original.researchNotes, isEmpty);
    expect(c.noteAttachments.length, 2);
    expect(identical(editor.attachNote(c, 'note', pdf), c), isTrue);
    c = editor.detachNote(c, c.noteAttachments.first.id);
    expect(c.researchNotes.single.id, 'note');
    expect(c.noteAttachments.length, 1);
    final (withChild, child) = editor.addNote(c, text: 'Unrelated', parentId: card.id);
    final deleted = editor.deleteNote(withChild, 'note');
    expect(deleted.researchNotes, isEmpty);
    expect(deleted.noteAttachments, isEmpty);
    expect(deleted.card(card.id), isNull);
    expect(deleted.node(child.id)!.parentId, isNull);
    expect(deleted.evidence.single.quote, 'captured');
    expect(StudySetEditor.restore(withChild, deleted).toJson(), withChild.toJson());
    expect(StudySetEditor.restore(deleted, withChild).toJson(), deleted.toJson());
    expect(() => editor.attachNote(c, 'missing', pdf), throwsArgumentError);
    expect(() => editor.attachNote(c, 'note', const CardTarget(cardId: 'missing')), throwsArgumentError);
    expect(() => editor.attachNote(c, 'note', PdfTarget(documentId: 'doc', pages: [])), throwsArgumentError);
    expect(() => editor.saveResearchNote(original, note()), throwsArgumentError);
    expect(() => editor.saveResearchNote(c, note(), createCard: true, parentId: 'missing'), throwsArgumentError);
    final changedEvidence = Evidence.fromJson({...evidence.toJson(), 'quote': 'changed'});
    expect(() => editor.saveResearchNote(c, note(), evidence: [changedEvidence]), throwsArgumentError);
  });

  test('deleting PDF and nodes retains notes/evidence and clears their targets/ink', () {
    var c = saved();
    c = editor.addInkStroke(
      c,
      InkStroke(
        id: 's',
        documentId: 'doc',
        page: 1,
        tool: InkTool.pen,
        colorIndex: 0,
        width: 1,
        points: [const InkPoint(1, 2)],
      ),
    );
    final noPdf = editor.removeDocument(c, 'doc');
    expect(noPdf.noteAttachments.single.target, isA<CardTarget>());
    expect(noPdf.researchNotes.length, 1);
    expect(noPdf.inkStrokes, isEmpty);
    final gone = editor.removeFromMap(noPdf, noPdf.cards.single.id);
    expect(gone.noteAttachments, isEmpty);
    expect(gone.researchNotes.length, 1);
    expect(gone.evidence.length, 1);
    expect(StudySetEditor.restore(c, gone).toJson(), c.toJson());
    final (otherMap, map) = editor.addMap(c, title: 'other');
    final other = StudySetEditor(newId: editor.newId, now: () => time, mapId: map.id);
    final shared = other.placeCard(otherMap, c.cards.single.id);
    expect(
      editor.removeFromMap(shared, c.cards.single.id).noteAttachments.where((a) => a.target is CardTarget),
      hasLength(1),
    );
  });

  test('ink validates document, page, geometry and resource limits', () {
    InkStroke stroke({String doc = 'doc', int page = 1, double width = 1, List<InkPoint>? points}) => InkStroke(
      id: 's',
      documentId: doc,
      page: page,
      tool: InkTool.pen,
      colorIndex: 0,
      width: width,
      points: points ?? [const InkPoint(1, 2)],
    );
    final c = editor.addInkStroke(base(), stroke());
    expect(editor.addInkStroke(c, stroke()), same(c));
    expect(editor.removeInkStroke(c, 's').inkStrokes, isEmpty);
    for (final invalid in [
      stroke(doc: 'missing'),
      stroke(page: 0),
      stroke(page: 5),
      stroke(width: 0),
      stroke(points: []),
      stroke(points: [InkPoint(double.infinity, 0)]),
      stroke(points: List.filled(InkStroke.maxPoints + 1, const InkPoint(0, 0))),
    ]) {
      expect(() => editor.addInkStroke(base(), invalid), throwsArgumentError);
    }
  });

  test('clipboard v3 copies shared notes, remaps all ids, preserves or downgrades PDF anchors', () {
    final c = saved();
    final entries = MapClipboard.decode(
      MapClipboard.encode(MapClipboard.copy(c, [c.cards.single.id], snapshots: {snapshot: 'body'})),
    )!;
    expect(jsonDecode(MapClipboard.encode(entries))['version'], 3);
    expect(entries.single.snapshots[snapshot], 'body');
    var id = 0;
    final targetEditor = StudySetEditor(newId: () => 'target-${id++}', now: () => time);
    final (target, roots) = targetEditor.paste(StudySetContent.empty, entries, snapshots: {snapshot: snapshot});
    expect(target.cards.single.researchNoteId, target.researchNotes.single.id);
    expect(target.cards.single.id, roots.single);
    expect(target.researchNotes.single.sessionId, isNull);
    expect(target.researchNotes.single.sourceLocationMissing, isTrue);
    expect(target.noteAttachments.single.target, isA<CardTarget>());
    expect(target.researchNotes.single.citations.single.evidenceId, target.evidence.single.id);
    expect(target.evidence.single.sourceId, target.researchSources.single.id);
    expect(target.researchSources.single.id, isNot('source'));
    final (same, _) = targetEditor.paste(c, entries, snapshots: {snapshot: snapshot});
    expect(same.researchNotes, hasLength(2));
    expect(same.researchNotes.last.sourceLocationMissing, isFalse);
    expect(same.noteAttachments.where((a) => a.target is PdfTarget), hasLength(2));
    expect(() => targetEditor.paste(base(), entries), throwsFormatException);
    expect(
      () => targetEditor.paste(base(), [const OutlineEntry(0, '', kind: CardKind.research)]),
      throwsFormatException,
    );
    final (twice, _) = targetEditor.paste(base(), [...entries, ...entries], snapshots: {snapshot: snapshot});
    expect(twice.researchNotes, hasLength(1));
    expect(twice.cards, hasLength(2));
    expect(twice.noteAttachments.where((a) => a.target is CardTarget), hasLength(2));
  });

  test('Markdown and OPML include note body, citations, PDF pages and escaped text', () {
    final c = saved();
    final exporter = MapExporter(c, rootTitle: 'Research');
    final markdown = exporter.markdown();
    expect(markdown, contains('研究笔记：Finding <1>'));
    expect(markdown, contains('  **body**\n  second line'));
    expect(markdown, contains('A & B · https://example.com/?a=1&b=2 · ${time.toIso8601String()}'));
    expect(markdown, contains('出处：Book, p. 2'));
    final opml = exporter.opml();
    expect(opml, contains('text="Finding &lt;1&gt;"'));
    expect(opml, contains('_note="**body**&#10;second line'));
    expect(opml, contains('A &amp; B'));
  });

  test('session history survives undo while saved note ids follow content', () async {
    final repo = InMemoryStudySetContentRepository();
    final session = ResearchSession(
      id: 'session',
      question: 'why',
      intent: 'explore',
      mode: 'web',
      anchor: SourceAnchor(target: pdf),
      contextScope: 'selection',
      keywords: ['one'],
      sourceIds: ['source'],
      history: [
        {'query': 'one'},
      ],
      drafts: [
        {'checked': true},
      ],
      createdAt: time,
      updatedAt: time,
    );
    await repo.saveResearchSession('set', session);
    expect(await repo.loadResearchSession('set', 'none'), isNull);
    final c = saved();
    await repo.update('set', (_) => c);
    expect((await repo.loadResearchSession('set', 'session'))!.savedNoteIds, ['note']);
    await repo.update('set', (_) => base());
    final undone = (await repo.loadResearchSession('set', 'session'))!;
    expect(undone.savedNoteIds, isEmpty);
    expect(undone.history, session.history);
    expect(undone.anchor!.canLocate(base().documents, []), isTrue);
    expect(undone.anchor!.canLocate([], []), isFalse);
    final anchor = SourceAnchor.fromJson(
      const SourceAnchor(
        target: CardTarget(cardId: 'card'),
        mapId: 'main',
      ).toJson(),
    );
    expect(anchor.canLocate([], [const MapNode(cardId: 'card', order: 1)]), isTrue);
    expect(anchor.canLocate([], []), isFalse);
    final file = await repo.writeResearchSnapshot('set', 'body');
    expect(await repo.writeResearchSnapshot('set', 'body'), file);
    expect(await repo.readResearchSnapshot('set', file), 'body');
    expect(() => repo.readResearchSnapshot('set', 'missing'), throwsStateError);
  });
  test('source versions cannot change and deletion detaches the last map placement', () {
    final c = saved();
    final changed = ResearchSource.fromJson({
      ...source.toJson(),
      'versions': [
        {'version': 1, 'snapshotFile': 'other', 'hash': 'other'},
      ],
    });
    expect(() => editor.saveResearchNote(c, note(), sources: [changed]), throwsArgumentError);
    final nextVersion = ResearchSource.fromJson({
      ...source.toJson(),
      'versions': [
        {'version': 2, 'snapshotFile': snapshot, 'hash': hash},
      ],
    });
    final updated = editor.saveResearchNote(c, note(), sources: [nextVersion]);
    expect(updated.researchSources.single.versions.map((v) => v.version), [1, 2]);
    final (withMap, _) = editor.addMap(c, title: 'other');
    final removed = editor.removeMap(withMap, 'main');
    expect(removed.noteAttachments.where((a) => a.target is CardTarget), isEmpty);
    expect(removed.researchNotes, hasLength(1));
    final ellipse = InkStroke(
      id: 'invalid',
      documentId: 'doc',
      page: 1,
      tool: InkTool.ellipse,
      colorIndex: 0,
      width: 1,
      ellipse: const PageRect(2, 1, 0, 3),
    );
    expect(() => editor.addInkStroke(c, ellipse), throwsArgumentError);
  });

  test('snapshots, widths and nested session JSON reject invalid input', () {
    final c = saved();
    final entries = MapClipboard.copy(c, [c.cards.single.id], snapshots: {snapshot: 'body'});
    expect(
      () => editor.paste(base(), entries, snapshots: {snapshot: 'research/snapshots/wrong.md'}),
      throwsFormatException,
    );
    final raw = jsonDecode(MapClipboard.encode(entries));
    raw['nodes'][0]['width'] = -10;
    expect(MapClipboard.decode(jsonEncode(raw)), isNull);
    final values = <Object?>[1];
    final session = ResearchSession(
      id: 's',
      question: '',
      history: [
        {'list': values},
      ],
      createdAt: time,
      updatedAt: time,
    );
    values.add(2);
    expect(session.history.single['list'], [1]);
    expect(() => (session.history.single['list'] as List).add(3), throwsUnsupportedError);
    expect(
      () => ResearchSession(
        id: 's',
        question: '',
        history: [
          {'bad': Object()},
        ],
        createdAt: time,
        updatedAt: time,
      ),
      throwsArgumentError,
    );
  });
}
