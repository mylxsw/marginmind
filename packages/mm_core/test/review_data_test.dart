import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  final time = DateTime.utc(2026, 10, 26);
  var sequence = 0;
  final editor = StudySetEditor(newId: () => 'log-${sequence++}', now: () => time);
  final initial = StudySetContent(
    cards: [
      Card(id: 'a', kind: CardKind.note, title: 'A', createdAt: time),
      Card(id: 'b', kind: CardKind.note, title: 'B', createdAt: time),
    ],
    nodes: const [
      MapNode(cardId: 'a', order: 0),
      MapNode(cardId: 'b', order: 1),
    ],
  );
  const memory = MemoryState(cardId: 'a', stability: 3.5, difficulty: 5, phase: MemoryPhase.review);

  test('each rating appends exactly one log and uses FSRS scheduling', () {
    var c = initial;
    for (final rating in [...Rating.values, Rating.good]) {
      final previous = c;
      final expected = ReviewScheduler.rate('a', c.reviewOf('a'), rating, time, memory: c.memoryOf('a'));
      ReviewScheduler.preview('a', c.reviewOf('a'), time);
      c = editor.rate(c, 'a', rating);
      expect(c.reviewOf('a')!.toJson(), expected.toJson());
      expect(c.reviewLogs.length, previous.reviewLogs.length + 1);
      final log = c.reviewLogs.last;
      expect(log.cardId, 'a');
      expect(log.reviewedAt, time);
      expect(log.rating, rating);
      expect(log.intervalBefore, previous.reviewOf('a')?.intervalDays ?? 0);
      expect(log.intervalAfter, expected.intervalDays);
      expect(c.reviewLogs.take(previous.reviewLogs.length), previous.reviewLogs);
    }
    c = editor.rate(c, 'b', Rating.hard);
    expect(c.reviewOf('b')!.intervalDays, 0);
    expect(c.reviewLogs.map((e) => e.id).toSet().length, 6);
    expect(c.reviewLogsOf('a').length, 5);
    expect(c.reviewLogsOf('missing'), isEmpty);
    expect(() => c.reviewLogsOf('a').clear(), throwsUnsupportedError);
    expect(StudySetContent.fromJson(c.toJson()).toJson(), c.toJson());
    expect(editor.rate(c, 'missing', Rating.good), same(c));
  });

  test('memory state replaces only its card and survives rating, delete and restore', () {
    var c = editor.setMemoryState(initial, memory);
    const other = MemoryState(cardId: 'b', stability: 1, difficulty: 4, phase: MemoryPhase.learning, learningStep: 1);
    c = editor.setMemoryState(c, other);
    const next = MemoryState(cardId: 'a', stability: .5, difficulty: 8, phase: MemoryPhase.relearning, learningStep: 2);
    c = editor.setMemoryState(c, next);
    expect(c.memoryStates.length, 2);
    expect(c.memoryOf('a'), next);
    expect(c.memoryOf('b'), other);
    expect(c.memoryOf('missing'), isNull);
    expect(c.reviews, isEmpty);
    c = editor.rate(c, 'a', Rating.good);
    final removed = editor.removeFromMap(c, 'a');
    expect(removed.memoryOf('a'), c.memoryOf('a'));
    expect(c.memoryOf('a'), isNot(same(next)));
    expect(removed.reviewLogs, c.reviewLogs);
    final restored = StudySetEditor.restore(initial, removed);
    expect(restored.card('a'), isNotNull);
    expect(restored.memoryOf('a'), c.memoryOf('a'));
    expect(restored.reviews, c.reviews);
    expect(restored.reviewLogs, c.reviewLogs);
    expect(StudySetContent.fromJson(restored.toJson()).toJson(), restored.toJson());
    expect(editor.setMemoryState(StudySetContent.empty, memory), same(StudySetContent.empty));
    for (final phase in MemoryPhase.values) {
      final value = MemoryState(cardId: 'a', stability: 2, difficulty: 3, phase: phase);
      expect(MemoryState.fromJson(value.toJson()).toJson(), value.toJson());
    }
  });

  test('suspension defaults false, persists, is undoable and leaves the queue', () {
    expect(initial.card('a')!.suspended, isFalse);
    var c = editor.setSuspended(initial, 'a', suspended: true);
    expect(c.card('a')!.suspended, isTrue);
    expect(c.card('b')!.suspended, isFalse);
    c = editor.setTags(c, 'a', ['tag']);
    expect(c.card('a')!.copyWith(title: 'renamed').suspended, isTrue);
    expect(StudySetContent.fromJson(c.toJson()).card('a')!.suspended, isTrue);
    expect(c.reviewQueue(time).map((e) => e.id), ['b']);
    expect(editor.setSuspended(c, 'a', suspended: true), same(c));
    expect(editor.setSuspended(c, 'missing', suspended: true), same(c));
    expect(editor.setSuspended(c, 'a', suspended: false).card('a')!.suspended, isFalse);
    expect(StudySetEditor.restore(initial, c).card('a')!.suspended, isFalse);
    expect(initial.reviewLogs, isEmpty);
    expect(initial.memoryStates, isEmpty);
  });
}
