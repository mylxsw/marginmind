import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 26);
  var seq = 0;
  StudySetEditor editor([String mapId = MindMap.defaultId]) =>
      StudySetEditor(newId: () => 'multi-${seq++}', now: () => now, mapId: mapId);

  test('deleting any map preserves shared cards and schedules; last map stays', () {
    final e = editor();
    final (withNote, note) = e.addNote(StudySetContent.empty, text: 'Shared');
    final (withMap, map) = e.addMap(e.rate(withNote, note.id, Rating.good), title: ' Second ');
    final placed = editor(map.id).placeCard(withMap, note.id);
    final renamed = e.renameMap(placed, map.id, ' Renamed ');
    expect(renamed.map(map.id)!.title, 'Renamed');
    final removed = e.removeMap(renamed, MindMap.defaultId);
    expect(removed.maps.single.id, map.id);
    expect(removed.nodes.single.mapId, map.id);
    expect(removed.card(note.id), same(placed.card(note.id)));
    expect(removed.reviews, placed.reviews);
    expect(e.removeMap(removed, map.id), same(removed));
    expect(e.removeMap(renamed, 'missing'), same(renamed));
    expect(StudySetContent.fromJson(removed.toJson()).toJson(), removed.toJson());
    expect(StudySetEditor.restore(renamed, removed).toJson(), renamed.toJson());
  });

  test('review filters before the new-card limit and deduplicates shared cards', () {
    final e = editor();
    var c = StudySetContent.empty;
    for (var i = 0; i < 30; i++) {
      c = e.addNote(c, text: 'main $i').$1;
    }
    final (withMap, map) = e.addMap(c, title: 'Second');
    final second = editor(map.id);
    final (withNew, fresh) = second.addNote(withMap, text: 'second only');
    final shared = c.cards.first;
    c = second.placeCard(withNew, shared.id);
    expect(c.reviewQueue(now, mapId: map.id).map((c) => c.id), [shared.id, fresh.id]);
    expect(c.dueCount(now, mapId: 'missing'), 0);
    c = e.rate(c, shared.id, Rating.good);
    expect(c.reviewQueue(now, mapId: map.id).map((c) => c.id), [fresh.id]);
    final later = now.add(const Duration(days: 100));
    expect(c.reviewQueue(later).where((c) => c.id == shared.id), hasLength(1));
    expect(c.reviewQueue(later, mapId: map.id).map((c) => c.id), [shared.id, fresh.id]);
    expect(c.dueCount(now, mapId: map.id), 1);
  });
}
