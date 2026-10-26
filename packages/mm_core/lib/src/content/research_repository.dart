import 'package:meta/meta.dart';

import 'research.dart';
import 'study_set_content.dart';

/// Large research history is persisted independently of undoable content.
@immutable
class ResearchSession {
  ResearchSession({
    required this.id,
    required this.question,
    this.intent = '',
    this.mode = '',
    this.anchor,
    this.contextScope = '',
    List<String> keywords = const [],
    List<String> sourceIds = const [],
    List<Map<String, Object?>> history = const [],
    List<Map<String, Object?>> drafts = const [],
    this.status = 'idle',
    required this.createdAt,
    required this.updatedAt,
    List<String> savedNoteIds = const [],
  }) : history = List.unmodifiable(history.map((e) => _freezeJson(e) as Map<String, Object?>)),
       drafts = List.unmodifiable(drafts.map((e) => _freezeJson(e) as Map<String, Object?>)),
       keywords = List.unmodifiable(keywords),
       sourceIds = List.unmodifiable(sourceIds),
       savedNoteIds = List.unmodifiable(savedNoteIds);
  final String id;
  final String question;
  final String intent;
  final String mode;
  final SourceAnchor? anchor;
  final String contextScope;
  final List<String> keywords;
  final List<String> sourceIds;

  /// JSON query/chat events and checked/edited drafts, owned by research services.
  final List<Map<String, Object?>> history;
  final List<Map<String, Object?>> drafts;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> savedNoteIds;

  /// Derived from current notes, so undo cannot leave stale saved-note records.
  ResearchSession reconcile(StudySetContent content) => ResearchSession.fromJson({
    ...toJson(),
    'savedNoteIds': [
      for (final n in content.researchNotes)
        if (n.sessionId == id) n.id,
    ],
  });
  Map<String, Object?> toJson() => {
    'id': id,
    'question': question,
    'intent': intent,
    'mode': mode,
    if (anchor != null) 'anchor': anchor!.toJson(),
    'contextScope': contextScope,
    'keywords': keywords,
    'sourceIds': sourceIds,
    'history': history,
    'drafts': drafts,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'savedNoteIds': savedNoteIds,
  };
  factory ResearchSession.fromJson(Map<String, Object?> j) => ResearchSession(
    id: j['id'] as String,
    question: j['question'] as String,
    intent: j['intent'] as String? ?? '',
    mode: j['mode'] as String? ?? '',
    anchor: j['anchor'] == null ? null : SourceAnchor.fromJson((j['anchor'] as Map).cast()),
    contextScope: j['contextScope'] as String? ?? '',
    keywords: (j['keywords'] as List? ?? []).cast<String>(),
    sourceIds: (j['sourceIds'] as List? ?? []).cast<String>(),
    history: [for (final e in j['history'] as List? ?? []) (e as Map).cast<String, Object?>()],
    drafts: [for (final e in j['drafts'] as List? ?? []) (e as Map).cast<String, Object?>()],
    status: j['status'] as String? ?? 'idle',
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    savedNoteIds: (j['savedNoteIds'] as List? ?? []).cast<String>(),
  );
}

abstract interface class ResearchSessionRepository {
  Future<ResearchSession?> loadResearchSession(String studySetId, String sessionId);
  Future<void> saveResearchSession(String studySetId, ResearchSession session);
}

abstract interface class ResearchSnapshotRepository {
  /// Returns `research/snapshots/<sha256>.md`. Existing bytes are never replaced.
  Future<String> writeResearchSnapshot(String studySetId, String markdown);
  Future<String> readResearchSnapshot(String studySetId, String fileName);
}

Object? _freezeJson(Object? value) => switch (value) {
  Map value => Map<String, Object?>.unmodifiable(value.map((k, v) => MapEntry(k as String, _freezeJson(v)))),
  List value => List<Object?>.unmodifiable(value.map(_freezeJson)),
  null || String() || num() || bool() => value,
  _ => throw ArgumentError('Expected JSON session data'),
};
