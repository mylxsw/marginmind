import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

final now = DateTime.utc(2026);
Card card(String id, [CardKind kind = CardKind.topic]) => Card(id: id, kind: kind, title: id, createdAt: now);

void main() {
  test('deleting an attached note keeps its children and sibling reading order', () {
    final content = StudySetContent(
      cards: [card('parent'), card('note', CardKind.note), card('nested', CardKind.note), card('topic'), card('last')],
      nodes: const [
        MapNode(cardId: 'parent', order: 0),
        MapNode(cardId: 'note', parentId: 'parent', order: 0),
        MapNode(cardId: 'nested', parentId: 'note', order: 0),
        MapNode(cardId: 'topic', parentId: 'note', order: 1),
        MapNode(cardId: 'last', parentId: 'parent', order: 1),
      ],
    );
    final editor = StudySetEditor(newId: () => 'unused', now: () => now);
    final next = editor.removeAttachedNote(content, 'note');
    expect(next.card('note'), isNull);
    expect(next.card('parent'), isNotNull);
    expect(next.childrenOf('parent').map((n) => n.cardId), ['nested', 'topic', 'last']);
    expect(editor.removeAttachedNote(content, 'parent'), same(content));
  });

  test('deleting a shared note placement preserves the other map and note text', () {
    final content = StudySetContent(
      cards: [card('parent'), card('note', CardKind.note)],
      maps: const [
        MindMap.main,
        MindMap(id: 'other', title: 'Other'),
      ],
      nodes: const [
        MapNode(cardId: 'parent', order: 0),
        MapNode(cardId: 'note', parentId: 'parent', order: 0),
        MapNode(cardId: 'parent', mapId: 'other', order: 0),
        MapNode(cardId: 'note', mapId: 'other', parentId: 'parent', order: 0),
      ],
    );
    final next = StudySetEditor(newId: () => 'unused', now: () => now).removeAttachedNote(content, 'note');
    expect(next.node('note'), isNull);
    expect(next.node('note', mapId: 'other'), isNotNull);
    expect(next.card('note')!.title, 'note');
  });

  test('notes attach to their node and topics under notes retain reading order', () {
    final content = StudySetContent(
      cards: [card('parent'), card('note', CardKind.note), card('nested', CardKind.note), card('topic'), card('last')],
      nodes: const [
        MapNode(cardId: 'parent', parentId: null, order: 0),
        MapNode(cardId: 'note', parentId: 'parent', order: 0),
        MapNode(cardId: 'nested', parentId: 'note', order: 0),
        MapNode(cardId: 'topic', parentId: 'note', order: 1),
        MapNode(cardId: 'last', parentId: 'parent', order: 1),
      ],
    );
    final original = content.toJson();
    final result = MapNoteAttachments(content);
    expect(result.owners, {'note': 'parent', 'nested': 'parent'});
    expect(result.notes['parent']!.map((c) => c.id), ['note', 'nested']);
    expect(result.nodes.map((n) => n.cardId), ['parent', 'topic', 'last']);
    expect(result.nodes.where((n) => n.cardId != 'parent').map((n) => n.parentId), everyElement('parent'));
    expect(result.nodes.where((n) => n.cardId != 'parent').map((n) => n.order), [0, 1]);
    expect(content.toJson(), original, reason: 'presentation must not migrate stored data');
  });

  test('root notes and connection anchors keep their independent identity', () {
    final content = StudySetContent(
      cards: [card('parent'), card('note', CardKind.note), card('root', CardKind.note)],
      nodes: const [
        MapNode(cardId: 'parent', parentId: null, order: 0),
        MapNode(cardId: 'note', parentId: 'parent', order: 0),
        MapNode(cardId: 'root', parentId: null, order: 1),
      ],
      relations: const [MapRelation(id: 'relation', fromId: 'note', toId: 'root')],
    );
    expect(MapNoteAttachments(content).owners, isEmpty);
    expect(MapNoteAttachments(content.copyWith(relations: [])).owners, {'note': 'parent'});
  });

  test('attachments follow each map placement without borrowing another map parent', () {
    final content = StudySetContent(
      cards: [card('a'), card('b'), card('note', CardKind.note)],
      maps: const [
        MindMap.main,
        MindMap(id: 'other', title: 'Other'),
      ],
      nodes: const [
        MapNode(cardId: 'a', parentId: null, order: 0),
        MapNode(cardId: 'note', parentId: 'a', order: 0),
        MapNode(cardId: 'b', mapId: 'other', parentId: null, order: 0),
        MapNode(cardId: 'note', mapId: 'other', parentId: 'b', order: 0),
      ],
    );
    expect(MapNoteAttachments(content).owners['note'], 'a');
    expect(MapNoteAttachments(content, mapId: 'other').owners['note'], 'b');
  });
}
