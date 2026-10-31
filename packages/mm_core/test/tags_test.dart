import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  late StudySetEditor editor;
  late StudySetContent content;
  setUp(() {
    var id = 0;
    editor = StudySetEditor(newId: () => '${++id}', now: () => DateTime.utc(2026));
    final (first, parent) = editor.addTopic(StudySetContent.empty, title: 'Parent');
    final (second, _) = editor.addNote(first, text: 'Child text', parentId: parent.id);
    content = second;
  });

  test('normalizes tags, deduplicates case, removes tags and preserves shared content', () {
    final tagged = editor.setTags(content, '2', ['  Science ', '', 'science', '知识', '知识']);
    expect(tagged.card('2')!.tags, ['Science', '知识']);
    expect(content.card('2')!.tags, isEmpty);
    expect(() => tagged.card('2')!.tags.add('x'), throwsUnsupportedError);
    expect(editor.setTags(tagged, 'missing', ['x']), same(tagged));
    expect(editor.setTags(tagged, '2', ['Science', '知识']), same(tagged));
    final (mapped, map) = editor.addMap(tagged, title: 'Other');
    final other = StudySetEditor(newId: editor.newId, now: editor.now, mapId: map.id);
    final placed = other.placeCard(mapped, '2');
    expect(placed.tags(mapId: map.id), ['Science', '知识']);
    expect(editor.setTags(placed, '2', []).tags(mapId: map.id), isEmpty);
    expect(editor.rename(tagged, '2', 'Renamed').card('2')!.tags, ['Science', '知识']);
    expect(StudySetContent.fromJson(tagged.toJson()).toJson(), tagged.toJson());
    expect(StudySetContent.fromJson(content.toJson()).card('2')!.tags, isEmpty);
  });

  test('search matches tags or text, combines exact tag filter, traverses hidden descendants', () {
    var tagged = editor.setTags(content, '1', ['Science']);
    tagged = editor.setTags(tagged, '2', ['science', '知识']);
    tagged = editor.setCollapsed(tagged, '1', collapsed: true);
    expect(tagged.tags(), ['Science', '知识']);
    expect(tagged.tagCounts(), {'Science': 2, '知识': 1});
    expect(tagged.search('SCI').map((c) => c.id), ['1', '2']);
    expect(tagged.search('', tag: 'SCIENCE').map((c) => c.id), ['1', '2']);
    expect(tagged.search('child', tag: '知识').map((c) => c.id), ['2']);
    expect(tagged.search('parent', tag: '知识'), isEmpty);
    expect(tagged.search('', tag: 'sci'), isEmpty);
    expect(tagged.search(''), isEmpty);
    expect(tagged.search('知识', mapId: 'missing'), isEmpty);
  });

  test('clipboard and undo snapshots preserve tags', () {
    final tagged = editor.setTags(content, '2', ['知识']);
    final entries = MapClipboard.decode(MapClipboard.encode(MapClipboard.copy(tagged, ['2'])))!;
    final (pasted, ids) = editor.paste(tagged, entries);
    expect(pasted.card(ids.single)!.tags, ['知识']);
    final restored = StudySetEditor.restore(content, pasted);
    expect(restored.card('2')!.tags, isEmpty);
  });

  test('tags and search include summary topics and nested descendants in map order', () {
    final made = editor.createSummary(content, ['2'], label: 'Summary');
    final summary = made.value!;
    final (withChild, child) = editor.addTopic(made.content, title: 'Explanation', parentId: summary.cardId);
    final nested = editor.createSummary(withChild, [child.id], label: 'Nested summary');
    final (withNote, note) = editor.addNote(nested.content, text: 'Tagged passage', parentId: nested.value!.cardId);
    var tagged = editor.setTags(withNote, summary.cardId!, ['Science']);
    tagged = editor.setTags(tagged, note.id, ['science']);
    tagged = editor.setCollapsed(tagged, '1', collapsed: true);
    expect(tagged.tags(), ['Science']);
    expect(tagged.tagCounts(), {'Science': 2});
    expect(tagged.pathOf(note.id), ['Parent', 'Summary', 'Nested summary']);
    expect(tagged.search('', tag: 'SCIENCE').map((c) => c.id), [summary.cardId, note.id]);
    expect(tagged.search('passage', tag: 'science').single.id, note.id);
    expect(tagged.search('summary').map((c) => c.id), [summary.cardId, nested.value!.cardId]);
    expect(tagged.tags(mapId: 'other'), isEmpty);
    expect(tagged.search('', tag: 'Science', mapId: 'other'), isEmpty);

    final broken = tagged.copyWith(nodes: tagged.nodes.where((n) => n.cardId != '2').toList());
    expect(broken.tags(), isEmpty, reason: 'a removed summary range must not expose detached descendants');
    expect(broken.search('', tag: 'Science'), isEmpty);
  });
}
