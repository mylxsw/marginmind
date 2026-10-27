import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart';

import 'research_intents.dart';

/// A passage the user selected in a source's text, kept until it is saved
/// into a note. Its evidence is immutable from the moment it is taken.
class ResearchClip {
  const ResearchClip({required this.evidence, required this.sourceTitle});

  final Evidence evidence;
  final String sourceTitle;

  Map<String, Object?> toJson() => {'evidence': evidence.toJson(), 'sourceTitle': sourceTitle};

  static ResearchClip? fromJson(Object? json) {
    if (json is! Map) return null;
    try {
      return ResearchClip(
        evidence: Evidence.fromJson((json['evidence'] as Map).cast()),
        sourceTitle: json['sourceTitle'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// What the research panel keeps in its session besides the engine's data
/// (the `type: ui` draft): how it was launched, checked and edited points,
/// clips, sources chosen for an answer, extra context joined later and AI
/// summaries. Persisted with the session, never undoable.
class ResearchDrafts {
  const ResearchDrafts({
    this.method = ResearchMethod.search,
    this.keywords = const [],
    this.kinds = const {},
    this.context = '',
    this.later = false,
    this.checked = const {},
    this.edits = const {},
    this.clips = const [],
    this.chosen = const {},
    this.extra = const [],
    this.summaries = const {},
    this.doneAt,
  });

  static const type = 'ui';

  final ResearchMethod method;
  final List<String> keywords;
  final Set<ResearchSourceKind> kinds;

  /// The context the user confirmed on the launcher.
  final String context;

  /// Saved for later from the launcher; not started yet.
  final bool later;

  /// Answer point keys.
  final Set<String> checked;
  final Map<String, String> edits;
  final List<ResearchClip> clips;

  /// Source ids added to "answer from sources".
  final Set<String> chosen;

  /// Passages joined to the question while it ran.
  final List<String> extra;

  /// AI summaries by `sourceId@version`.
  final Map<String, String> summaries;

  /// When the last request finished (later draft changes do not move it).
  final DateTime? doneAt;

  static ResearchDrafts of(ResearchSession session) {
    final json = session.drafts.where((d) => d['type'] == type).firstOrNull;
    if (json == null) return const ResearchDrafts();
    List<String> strings(Object? v) => [
      for (final e in v as List? ?? const [])
        if (e is String) e,
    ];
    Map<String, String> map(Object? v) => {
      for (final e in (v as Map? ?? const {}).entries)
        if (e.key is String && e.value is String) e.key as String: e.value as String,
    };
    return ResearchDrafts(
      method: ResearchMethod.parse(json['method'] as String? ?? session.mode),
      keywords: strings(json['keywords']),
      kinds: {for (final k in strings(json['kinds'])) ?ResearchSourceKind.values.where((v) => v.name == k).firstOrNull},
      context: json['context'] as String? ?? '',
      later: json['later'] == true,
      checked: strings(json['checked']).toSet(),
      edits: map(json['edits']),
      clips: [for (final c in json['clips'] as List? ?? const []) ?ResearchClip.fromJson(c)],
      chosen: strings(json['chosen']).toSet(),
      extra: strings(json['extra']),
      summaries: map(json['summaries']),
      doneAt: DateTime.tryParse(json['doneAt'] as String? ?? ''),
    );
  }

  Map<String, Object?> toJson() => {
    'type': type,
    'method': method.name,
    'keywords': keywords,
    'kinds': [for (final k in kinds) k.name],
    'context': context,
    'later': later,
    'checked': checked.toList(),
    'edits': edits,
    'clips': [for (final c in clips) c.toJson()],
    'chosen': chosen.toList(),
    'extra': extra,
    'summaries': summaries,
    if (doneAt != null) 'doneAt': doneAt!.toIso8601String(),
  };

  ResearchDrafts copyWith({
    ResearchMethod? method,
    List<String>? keywords,
    Set<ResearchSourceKind>? kinds,
    String? context,
    bool? later,
    Set<String>? checked,
    Map<String, String>? edits,
    List<ResearchClip>? clips,
    Set<String>? chosen,
    List<String>? extra,
    Map<String, String>? summaries,
    DateTime? doneAt,
  }) => ResearchDrafts(
    method: method ?? this.method,
    keywords: keywords ?? this.keywords,
    kinds: kinds ?? this.kinds,
    context: context ?? this.context,
    later: later ?? this.later,
    checked: checked ?? this.checked,
    edits: edits ?? this.edits,
    clips: clips ?? this.clips,
    chosen: chosen ?? this.chosen,
    extra: extra ?? this.extra,
    summaries: summaries ?? this.summaries,
    doneAt: doneAt ?? this.doneAt,
  );
}

/// The session's own data plus the panel's, as one view.
extension ResearchStateDrafts on ResearchSessionState {
  ResearchDrafts get drafts => ResearchDrafts.of(session);

  /// Sources of the session as numbered in the panel (1-based).
  int numberOf(String sourceId) => sources.indexWhere((s) => s.id == sourceId) + 1;

  /// Versions of [sourceId] whose text the user pasted.
  Set<int> pastedVersions(String sourceId) => {
    for (final v in (metadata[sourceId] as Map?)?['pasted'] as List? ?? const [])
      if (v is int) v,
  };

  /// Why reading [sourceId] failed, as the engine's stable code.
  String? readError(String sourceId) => (metadata[sourceId] as Map?)?['error'] as String?;
}
