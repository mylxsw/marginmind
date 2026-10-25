import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 10, 25, 12);
  final sets = DemoLibrary.studySets(now);

  test('default query sorts by most recently opened', () {
    final result = const LibraryQuery().apply(sets);
    expect(result.first.id, 'demo-1');
    expect(result.last.id, 'demo-6');
  });

  test('filters by starred, due and folder', () {
    expect(const LibraryQuery(filter: LibraryFilter.starred).apply(sets).map((s) => s.id), ['demo-1', 'demo-3']);
    expect(const LibraryQuery(filter: LibraryFilter.due).apply(sets), hasLength(3));
    expect(const LibraryQuery(filter: FolderFilter('design')).apply(sets), hasLength(2));
    expect(const LibraryQuery(filter: FolderFilter(null)).apply(sets).single.id, 'demo-6');
  });

  test('recent keeps only the newest few', () {
    final result = const LibraryQuery(filter: RecentFilter(limit: 2)).apply(sets);
    expect(result.map((s) => s.id), ['demo-1', 'demo-2']);
  });

  test('search is case-insensitive and combines with filters', () {
    final upper = [...sets, StudySet(id: 'x', title: 'Deep Work', colorIndex: 0, createdAt: now, lastOpenedAt: now)];
    expect(const LibraryQuery(search: 'deep').apply(upper).single.id, 'x');
    expect(const LibraryQuery(filter: FolderFilter('design'), search: '原则').apply(sets).single.id, 'demo-4');
  });

  test('sorts by card count descending', () {
    final result = const LibraryQuery(sort: LibrarySort.cardCount).apply(sets);
    expect(result.first.id, 'demo-6');
  });

  test('progress is clamped and safe for empty sets', () {
    expect(sets.first.progress, closeTo(26 / 176, 1e-9));
    expect(StudySet(id: 'e', title: 'e', colorIndex: 0, createdAt: now, lastOpenedAt: now).progress, 0);
  });
}
