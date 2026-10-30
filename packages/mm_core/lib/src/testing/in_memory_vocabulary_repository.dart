import 'dart:async';

import '../vocabulary/vocabulary.dart';

/// In-memory vocabulary persistence for tests and previews.
class InMemoryVocabularyRepository implements VocabularyRepository {
  InMemoryVocabularyRepository([List<VocabularyEntry> entries = const []]) : _entries = List.unmodifiable(entries);
  List<VocabularyEntry> _entries;
  final _changes = StreamController<List<VocabularyEntry>>.broadcast();
  @override
  Future<List<VocabularyEntry>> load() async => _entries;
  @override
  Future<void> save(List<VocabularyEntry> entries) async {
    _entries = List.unmodifiable(entries);
    _changes.add(_entries);
  }

  @override
  Stream<List<VocabularyEntry>> watch() => Stream.multi((out) {
    final sub = _changes.stream.listen(out.add, onError: out.addError, onDone: out.close);
    out.add(_entries);
    out.onCancel = sub.cancel;
  });
  Future<void> dispose() => _changes.close();
}
