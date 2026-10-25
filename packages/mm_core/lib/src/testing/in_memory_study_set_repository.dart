import 'dart:async';

import '../study_set/folder.dart';
import '../study_set/study_set.dart';
import '../study_set/study_set_repository.dart';

/// Keeps the library in memory. Every change re-emits the full list, which
/// matches how drift's reactive queries will behave.
class InMemoryStudySetRepository implements StudySetRepository {
  InMemoryStudySetRepository({
    List<StudySet> sets = const [],
    List<Folder> folders = const [],
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _sets = [...sets],
       _folders = [...folders],
       _clock = clock ?? DateTime.now,
       _nextId = idGenerator ?? _counter();

  final List<StudySet> _sets;
  final List<Folder> _folders;
  final DateTime Function() _clock;
  final String Function() _nextId;
  final _changes = StreamController<void>.broadcast();

  static String Function() _counter() {
    var i = 0;
    return () => 'set-${++i}';
  }

  @override
  Stream<List<StudySet>> watchAll() {
    StreamSubscription<void>? sub;
    late final StreamController<List<StudySet>> out;
    out = StreamController<List<StudySet>>(
      onListen: () {
        out.add(List.unmodifiable(_sets));
        sub = _changes.stream.listen((_) => out.add(List.unmodifiable(_sets)));
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  @override
  Stream<List<Folder>> watchFolders() async* {
    yield List.unmodifiable(_folders);
  }

  @override
  Future<StudySet> create(NewStudySet input) async {
    final now = _clock();
    final set = StudySet(
      id: _nextId(),
      title: input.title.trim(),
      colorIndex: input.colorIndex,
      folderId: input.folderId,
      createdAt: now,
      lastOpenedAt: now,
    );
    _sets.insert(0, set);
    _changes.add(null);
    return set;
  }

  @override
  Future<void> setStarred(String id, {required bool starred}) async {
    _update(id, (s) => s.copyWith(starred: starred));
  }

  @override
  Future<void> markOpened(String id) async {
    _update(id, (s) => s.copyWith(lastOpenedAt: _clock()));
  }

  @override
  Future<void> rename(String id, String title) async => _update(id, (s) => s.copyWith(title: title.trim()));

  @override
  Future<void> setColor(String id, int colorIndex) async => _update(id, (s) => s.copyWith(colorIndex: colorIndex));

  @override
  Future<void> delete(String id) async {
    _sets.removeWhere((s) => s.id == id);
    _changes.add(null);
  }

  void _update(String id, StudySet Function(StudySet) change) {
    final i = _sets.indexWhere((s) => s.id == id);
    if (i < 0) throw StateError('Unknown study set: $id');
    _sets[i] = change(_sets[i]);
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}
