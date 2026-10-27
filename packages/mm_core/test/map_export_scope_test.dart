import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  test('branch snapshot includes folded descendants and only internal marks', () {
    var seq = 0;
    final e = StudySetEditor(newId: () => 'c${seq++}', now: () => DateTime.utc(2026));
    final (a, root) = e.addTopic(StudySetContent.empty, title: 'Branch');
    final (b, child) = e.addTopic(a, title: 'Child', parentId: root.id);
    final (c, other) = e.addTopic(b, title: 'Other');
    final (linked, _) = e.addRelation(c, child.id, other.id, label: 'External');
    final scoped = MapExporter.scope(linked, MindMap.defaultId, root.id);
    expect(scoped.nodes.map((n) => n.cardId), [root.id, child.id]);
    expect(scoped.nodes.first.parentId, isNull);
    expect(scoped.relations, isEmpty);
    for (final text in [
      MapExporter(scoped, rootTitle: 'Branch').markdown(),
      MapExporter(scoped, rootTitle: 'Branch').opml(),
    ]) {
      expect(text, contains('Child'));
      expect(text, isNot(contains('Other')));
    }
    expect(identical(MapExporter.scope(linked, MindMap.defaultId, null), linked), isTrue);
    expect(() => MapExporter.scope(linked, 'other', root.id), throwsArgumentError);
    expect(linked.nodes, hasLength(3));
  });
}
