import 'dart:async';

import '../content/study_set_content.dart';
import '../content/study_set_content_repository.dart';

/// Content kept in memory; files are "imported" by remembering their path.
class InMemoryStudySetContentRepository implements StudySetContentRepository {
  InMemoryStudySetContentRepository([Map<String, StudySetContent>? initial]) : _content = {...?initial};

  final Map<String, StudySetContent> _content;
  final _changes = StreamController<String>.broadcast();

  @override
  Future<StudySetContent> load(String studySetId) async => _content[studySetId] ?? StudySetContent.empty;

  @override
  Stream<StudySetContent> watch(String studySetId) {
    StreamSubscription<String>? sub;
    late final StreamController<StudySetContent> out;
    out = StreamController<StudySetContent>(
      onListen: () {
        out.add(_content[studySetId] ?? StudySetContent.empty);
        sub = _changes.stream.where((id) => id == studySetId).listen((_) => out.add(_content[studySetId]!));
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  @override
  Future<StudySetContent> update(String studySetId, StudySetContent Function(StudySetContent) change) async {
    final next = change(_content[studySetId] ?? StudySetContent.empty);
    _content[studySetId] = next;
    _changes.add(studySetId);
    return next;
  }

  @override
  Future<String> importFile(String studySetId, String sourcePath) async => sourcePath;

  @override
  Future<String> importImage(String studySetId, String sourcePath) async => sourcePath;

  @override
  String resolveFile(String studySetId, String fileName) => fileName;
}
