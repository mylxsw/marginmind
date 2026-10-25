import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:test/test.dart';

void main() {
  test('create, star and open re-emit the list', () async {
    var t = DateTime(2026, 1, 1);
    final repo = InMemoryStudySetRepository(clock: () => t);
    final emissions = <List<StudySet>>[];
    final sub = repo.watchAll().listen(emissions.add);

    final created = await repo.create(const NewStudySet(title: '  新学习集 ', colorIndex: 2));
    expect(created.title, '新学习集');

    await repo.setStarred(created.id, starred: true);
    t = DateTime(2026, 1, 2);
    await repo.markOpened(created.id);
    await Future<void>.delayed(Duration.zero);

    expect(emissions.length, 4);
    expect(emissions.last.single.starred, isTrue);
    expect(emissions.last.single.lastOpenedAt, DateTime(2026, 1, 2));

    await sub.cancel();
    await repo.dispose();
  });

  test('unknown ids throw', () async {
    final repo = InMemoryStudySetRepository();
    expect(() => repo.setStarred('nope', starred: true), throwsStateError);
  });
}
