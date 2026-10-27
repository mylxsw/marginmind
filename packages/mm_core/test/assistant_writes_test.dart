import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  var sequence = 0;
  final time = DateTime(2026, 10, 27);
  late AssistantWrites writes;
  late StudySetContent content;
  setUp(() {
    sequence = 0;
    writes = AssistantWrites(studySetId: 'set', newId: () => 'id-${sequence++}', now: () => time);
    content = StudySetEditor(
      newId: () => 'parent',
      now: () => time,
    ).addTopic(StudySetContent.empty, title: 'Parent').$1;
  });
  MapEditProposal proposal(
    List<MapEditOperation> ops, {
    String id = 'proposal',
    int? revision,
    String set = 'set',
    String map = 'main',
  }) => MapEditProposal(
    id: id,
    studySetId: set,
    mapId: map,
    baseRevision: revision ?? assistantMapRevision(content, map),
    operations: ops,
  );
  const topic = MapEditOperation(id: 'topic', kind: MapEditKind.addTopic, parentId: 'main', title: 'Topic');
  const note = MapEditOperation(
    id: 'note',
    kind: MapEditKind.addNote,
    parentId: 'new:topic',
    title: 'Note',
    body: 'Body',
  );
  const quiz = MapEditOperation(
    id: 'quiz',
    kind: MapEditKind.addReviewCard,
    parentId: 'new:topic',
    question: 'Question?',
    answer: 'Answer',
  );
  const move = MapEditOperation(id: 'move', kind: MapEditKind.move, nodeId: 'parent', parentId: 'new:topic');
  const rename = MapEditOperation(id: 'rename', kind: MapEditKind.rename, nodeId: 'parent', title: 'Renamed');

  test('all operations compose, serialize, review, copy and remain idempotent', () {
    final p = proposal([topic, note, quiz, move, rename]);
    final after = writes.apply(content, p, p.operations.map((o) => o.id).toSet());
    expect(after.card('parent')!.title, 'Renamed');
    expect(after.node('parent')!.parentId, after.cards[1].id);
    final card = after.cards.last;
    expect(card.title, 'Question?');
    expect(card.body, 'Answer');
    expect(after.search('answer').single.id, card.id);
    final export = MapExporter(after, rootTitle: 'Map');
    expect(export.markdown(), contains('Answer'));
    expect(export.opml(), contains('_note="Answer"'));
    expect(after.dueCount(time), 2);
    final face = buildReviewFace(card, after);
    expect(face.front.title, 'Question?');
    expect(face.back.notes.first.text, 'Answer');
    final restored = StudySetContent.fromJson(jsonDecode(jsonEncode(after.toJson())));
    expect(restored.toJson(), after.toJson());
    expect(writes.apply(restored, p, {'topic'}), same(restored));
    final entries = MapClipboard.decode(MapClipboard.encode(MapClipboard.copy(after, [card.id])))!;
    expect(entries.single.body, 'Answer');
    final pasted = StudySetEditor(newId: () => 'copy-${sequence++}', now: () => time).paste(after, entries);
    expect(pasted.$1.cards.last.body, 'Answer');
    final undone = StudySetEditor.restore(content, after);
    expect(undone.cards.length, 1);
    expect(undone.assistantReceipts.single.proposalId, p.id);
    expect(StudySetEditor.restore(after, undone).toJson(), after.toJson());
  });

  test('each operation runs alone', () {
    for (final op in [
      topic,
      const MapEditOperation(id: 'n', kind: MapEditKind.addNote, parentId: 'parent', title: 'N', body: 'B'),
      const MapEditOperation(id: 'q', kind: MapEditKind.addReviewCard, parentId: 'parent', question: 'Q', answer: 'A'),
      const MapEditOperation(id: 'm', kind: MapEditKind.move, nodeId: 'parent', parentId: 'main'),
      rename,
    ]) {
      final after = writes.apply(content, proposal([op]), {op.id});
      expect(after.assistantReceipts.single.operationIds, [op.id]);
    }
  });
  test('missing targets and unchecked dependencies skip with reasons', () {
    final p = proposal([
      topic,
      note,
      const MapEditOperation(id: 'missing', kind: MapEditKind.rename, nodeId: 'gone', title: 'x'),
    ]);
    final after = writes.apply(content, p, {'note', 'missing'});
    expect(after.cards, content.cards);
    expect(after.assistantReceipts.single.skipped.keys, ['note', 'missing']);
    expect(after.assistantReceipts.single.operationIds, isEmpty);
  });
  test('invalid selection, scope, revisions, fields and cycles never change content', () {
    expect(() => writes.apply(content, proposal([topic], set: 'other'), {'topic'}), throwsArgumentError);
    expect(() => writes.apply(content, proposal([topic], map: 'gone'), {'topic'}), throwsStateError);
    expect(() => writes.apply(content, proposal([topic], revision: 0), {'topic'}), throwsStateError);
    expect(() => writes.apply(content, proposal([topic, topic]), {'topic'}), throwsArgumentError);
    expect(() => writes.apply(content, proposal([topic]), {'unknown'}), throwsArgumentError);
    expect(() => writes.apply(content, proposal([topic]), {}), throwsArgumentError);
    expect(() => writes.apply(content, proposal([note, topic]), {'note'}), throwsArgumentError);
    expect(
      () => writes.apply(content, proposal([const MapEditOperation(id: 'bad', kind: MapEditKind.addTopic)]), {'bad'}),
      throwsFormatException,
    );
    expect(
      () => writes.apply(
        content,
        proposal([
          topic,
          const MapEditOperation(id: 'cycle', kind: MapEditKind.move, nodeId: 'new:topic', parentId: 'new:topic'),
        ]),
        {'topic', 'cycle'},
      ),
      throwsArgumentError,
    );
    expect(content.cards.length, 1);
  });
  test('other-map targets skip and cross-map move never attaches', () {
    final editor = StudySetEditor(newId: () => 'foreign', now: () => time, mapId: 'other');
    content = editor
        .addTopic(
          content.copyWith(
            maps: [
              ...content.maps,
              const MindMap(id: 'other', title: 'Other'),
            ],
          ),
          title: 'Foreign',
        )
        .$1;
    final p = proposal([
      const MapEditOperation(id: 'm', kind: MapEditKind.move, nodeId: 'parent', parentId: 'foreign'),
    ]);
    expect(writes.apply(content, p, {'m'}).assistantReceipts.single.skipped, contains('m'));
  });
  test('AI note dual attachment, deletion, undo and validation', () {
    content = StudySetEditor(
      newId: () => 'doc',
      now: () => time,
    ).addDocument(content, title: 'PDF', fileName: 'a.pdf', pageCount: 3).$1;
    final anchor = SourceAnchor(
      target: PdfTarget(
        documentId: 'doc',
        pages: [AnnotationPage(page: 2, rects: [])],
      ),
    );
    final request = SaveNoteRequest(title: 'AI', mapId: 'main', parentId: 'parent', anchor: anchor);
    final after = writes.saveNote(content, noteId: 'n', conversationId: 'c', body: 'Body', request: request);
    expect(after.noteAttachments.length, 2);
    expect(after.researchNote('n')!.conversationId, 'c');
    expect(after.researchNote('n')!.origin, NoteOrigin.ai);
    expect(writes.saveNote(after, noteId: 'n', conversationId: 'c', body: 'Body', request: request), same(after));
    final editor = StudySetEditor(newId: () => 'x', now: () => time);
    final deleted = editor.deleteNote(after, 'n');
    expect(deleted.noteAttachments, isEmpty);
    expect(deleted.cards.length, content.cards.length);
    expect(StudySetEditor.restore(after, deleted).toJson(), after.toJson());
    for (final invalid in [
      const SaveNoteRequest(title: ''),
      const SaveNoteRequest(title: 'x'),
      const SaveNoteRequest(title: 'x', parentId: 'parent'),
      const SaveNoteRequest(title: 'x', mapId: 'gone'),
      const SaveNoteRequest(title: 'x', mapId: 'main', parentId: 'gone'),
      const SaveNoteRequest(
        title: 'x',
        anchor: SourceAnchor(
          target: CardTarget(cardId: 'gone'),
          mapId: 'main',
        ),
      ),
      SaveNoteRequest(
        title: 'x',
        anchor: SourceAnchor(
          target: PdfTarget(
            documentId: 'doc',
            pages: [AnnotationPage(page: 4, rects: [])],
          ),
        ),
      ),
    ]) {
      expect(
        () => writes.saveNote(content, noteId: 'bad', conversationId: 'c', body: 'b', request: invalid),
        throwsArgumentError,
      );
    }
    for (final dest in [
      const SaveNoteRequest(title: 'x', mapId: 'main'),
      SaveNoteRequest(title: 'x', anchor: anchor),
      const SaveNoteRequest(
        title: 'x',
        anchor: SourceAnchor(
          target: CardTarget(cardId: 'parent'),
          mapId: 'main',
        ),
      ),
    ]) {
      expect(
        writes
            .saveNote(content, noteId: 'single', conversationId: 'c', body: 'b', request: dest)
            .noteAttachments
            .length,
        1,
      );
    }
  });
}
