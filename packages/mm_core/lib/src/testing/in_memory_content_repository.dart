import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../content/research_repository.dart';

import '../content/study_set_content.dart';
import '../content/study_set_content_repository.dart';

/// Content kept in memory; files are "imported" by remembering their path.
class InMemoryStudySetContentRepository
    implements StudySetContentRepository, ResearchSessionRepository, ResearchSnapshotRepository {
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

  /// Bytes imported with [importImageBytes], by returned file name.
  final images = <String, List<int>>{};

  @override
  Future<String> importImageBytes(String studySetId, List<int> bytes) async {
    final name = 'images/${Object.hashAll(bytes).toUnsigned(32).toRadixString(16)}.png';
    images[name] = List.unmodifiable(bytes);
    return name;
  }

  final _sessions = <(String, String), ResearchSession>{};
  @override
  Future<List<ResearchSession>> listResearchSessions(String studySetId) async => [
    for (final entry in _sessions.entries)
      if (entry.key.$1 == studySetId) entry.value.reconcile(await load(studySetId)),
  ];

  @override
  Future<void> deleteResearchSession(String studySetId, String sessionId) async {
    _sessions.remove((studySetId, sessionId));
  }

  final _snapshots = <(String, String), String>{};

  @override
  Future<ResearchSession?> loadResearchSession(String studySetId, String sessionId) async =>
      _sessions[(studySetId, sessionId)]?.reconcile(await load(studySetId));

  @override
  Future<void> saveResearchSession(String studySetId, ResearchSession session) async {
    _sessions[(studySetId, session.id)] = ResearchSession.fromJson(
      (jsonDecode(jsonEncode(session.toJson())) as Map).cast(),
    );
  }

  @override
  Future<String> writeResearchSnapshot(String studySetId, String markdown) async {
    final name = 'research/snapshots/${sha256.convert(utf8.encode(markdown))}.md';
    _snapshots[(studySetId, name)] = markdown;
    return name;
  }

  @override
  Future<String> readResearchSnapshot(String studySetId, String fileName) async =>
      _snapshots[(studySetId, fileName)] ?? (throw StateError('Missing snapshot'));

  @override
  String resolveFile(String studySetId, String fileName) => fileName;
}
