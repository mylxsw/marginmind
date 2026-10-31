/// Durable task lifecycle; paragraph progress lives in the segment journal.
enum TranslationJobState { running, review, paused, offline, error, budget, done, stopped }

/// Why a task paused, including recovery after an unclean process exit.
enum TranslationPauseReason { user, quit }

/// Whether a batch requires confirmation or work continues to the end.
enum TranslationMode { batch, all }

/// Inclusive one-based PDF page interval.
class TranslationRange {
  TranslationRange(this.from, this.to) {
    if (from < 1 || to < from) throw ArgumentError('Invalid translation range');
  }
  final int from, to;
  bool contains(int page) => page >= from && page <= to;
  Map<String, Object?> toJson() => {'from': from, 'to': to};
  factory TranslationRange.fromJson(Map j) => TranslationRange(j['from'] as int, j['to'] as int);
}

/// Current one-based batch number and inclusive interval.
class TranslationBatch {
  TranslationBatch({required this.index, required this.range}) {
    if (index < 1) throw ArgumentError('Invalid batch index');
  }
  final int index;
  final TranslationRange range;
  Map<String, Object?> toJson() => {'index': index, ...range.toJson()};
  factory TranslationBatch.fromJson(Map j) =>
      TranslationBatch(index: j['index'] as int, range: TranslationRange.fromJson(j));
}

/// Task-level token and request ledger, independent of cached text.
class TranslationUsage {
  TranslationUsage({this.inputTokens = 0, this.outputTokens = 0, this.requests = 0}) {
    if (inputTokens < 0 || outputTokens < 0 || requests < 0) throw ArgumentError('Invalid usage');
  }
  final int inputTokens, outputTokens, requests;
  int get totalTokens => inputTokens + outputTokens;
  Map<String, Object?> toJson() => {'inputTokens': inputTokens, 'outputTokens': outputTokens, 'requests': requests};
  factory TranslationUsage.fromJson(Map j) => TranslationUsage(
    inputTokens: j['inputTokens'] as int,
    outputTokens: j['outputTokens'] as int,
    requests: j['requests'] as int,
  );
}

/// Persisted failure keyed by the paragraph fingerprint, never by page number.
class TranslationFailure {
  TranslationFailure({required this.kind, required this.attempts, required this.at}) {
    if (kind.isEmpty || attempts < 0) throw ArgumentError('Invalid failure');
  }
  final String kind;
  final int attempts;
  final DateTime at;
  Map<String, Object?> toJson() => {'kind': kind, 'attempts': attempts, 'at': at.toUtc().toIso8601String()};
  factory TranslationFailure.fromJson(Map j) => TranslationFailure(
    kind: j['kind'] as String,
    attempts: j['attempts'] as int,
    at: DateTime.parse(j['at'] as String),
  );
}

/// Immutable v1 job record. Unknown JSON fields are tolerated; unsupported
/// versions and invalid settings fail decoding so storage can treat it stopped.
class TranslationJob {
  TranslationJob({
    required this.id,
    required this.documentId,
    this.sourceLang,
    required this.targetLang,
    required this.range,
    required this.mode,
    required this.batchSize,
    this.note = '',
    required this.model,
    this.promptVersion = 1,
    required this.state,
    this.pauseReason,
    required this.batch,
    TranslationUsage? usage,
    required this.estimateTokens,
    this.budgetAcknowledged = false,
    Map<String, TranslationFailure> failures = const {},
    required this.createdAt,
    required this.updatedAt,
  }) : usage = usage ?? TranslationUsage(),
       failures = Map.unmodifiable(failures) {
    if (id.isEmpty ||
        documentId.isEmpty ||
        targetLang.isEmpty ||
        model.isEmpty ||
        ![5, 10, 20, 50].contains(batchSize) ||
        note.runes.length > 1000 ||
        promptVersion < 1 ||
        estimateTokens < 0 ||
        !range.contains(batch.range.from) ||
        !range.contains(batch.range.to) ||
        (pauseReason != null && state != TranslationJobState.paused)) {
      throw ArgumentError('Invalid translation job');
    }
  }
  final String id, documentId, targetLang, note, model;
  final String? sourceLang;
  final TranslationRange range;
  final TranslationMode mode;
  final int batchSize, promptVersion, estimateTokens;
  final TranslationJobState state;
  final TranslationPauseReason? pauseReason;
  final TranslationBatch batch;
  final TranslationUsage usage;
  final bool budgetAcknowledged;
  final Map<String, TranslationFailure> failures;
  final DateTime createdAt, updatedAt;

  /// Active tasks suppress on-demand requests, including at checkpoints.
  bool get isActive => state != TranslationJobState.done && state != TranslationJobState.stopped;

  /// Settings and immutable children can be replaced as the scheduler advances.
  /// A state change clears the pause reason unless explicitly supplied.
  TranslationJob copyWith({
    TranslationMode? mode,
    int? batchSize,
    String? note,
    String? model,
    int? promptVersion,
    TranslationJobState? state,
    TranslationPauseReason? pauseReason,
    TranslationBatch? batch,
    TranslationUsage? usage,
    int? estimateTokens,
    bool? budgetAcknowledged,
    Map<String, TranslationFailure>? failures,
    DateTime? updatedAt,
  }) => TranslationJob(
    id: id,
    documentId: documentId,
    sourceLang: sourceLang,
    targetLang: targetLang,
    range: range,
    mode: mode ?? this.mode,
    batchSize: batchSize ?? this.batchSize,
    note: note ?? this.note,
    model: model ?? this.model,
    promptVersion: promptVersion ?? this.promptVersion,
    state: state ?? this.state,
    pauseReason: pauseReason ?? (state == null ? this.pauseReason : null),
    batch: batch ?? this.batch,
    usage: usage ?? this.usage,
    estimateTokens: estimateTokens ?? this.estimateTokens,
    budgetAcknowledged: budgetAcknowledged ?? this.budgetAcknowledged,
    failures: failures ?? this.failures,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// JSON representation matching docs/full-translation.md section 7.2.
  Map<String, Object?> toJson() => {
    'v': 1,
    'id': id,
    'documentId': documentId,
    'sourceLang': sourceLang,
    'targetLang': targetLang,
    'range': range.toJson(),
    'mode': mode.name,
    'batchSize': batchSize,
    'note': note,
    'model': model,
    'promptVersion': promptVersion,
    'state': state.name,
    'pauseReason': pauseReason?.name,
    'batch': batch.toJson(),
    'usage': usage.toJson(),
    'estimateTokens': estimateTokens,
    'budgetAcknowledged': budgetAcknowledged,
    'failures': failures.map((key, value) => MapEntry(key, value.toJson())),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  /// Decodes known fields without rejecting additions from future writers.
  factory TranslationJob.fromJson(Map<String, Object?> j) {
    if (j['v'] != 1) throw const FormatException('Unsupported translation job version');
    return TranslationJob(
      id: j['id'] as String,
      documentId: j['documentId'] as String,
      sourceLang: j['sourceLang'] as String?,
      targetLang: j['targetLang'] as String,
      range: TranslationRange.fromJson(j['range'] as Map),
      mode: TranslationMode.values.byName(j['mode'] as String),
      batchSize: j['batchSize'] as int,
      note: j['note'] as String,
      model: j['model'] as String,
      promptVersion: j['promptVersion'] as int,
      state: TranslationJobState.values.byName(j['state'] as String),
      pauseReason: j['pauseReason'] == null ? null : TranslationPauseReason.values.byName(j['pauseReason'] as String),
      batch: TranslationBatch.fromJson(j['batch'] as Map),
      usage: TranslationUsage.fromJson(j['usage'] as Map),
      estimateTokens: j['estimateTokens'] as int,
      budgetAcknowledged: j['budgetAcknowledged'] as bool,
      failures: (j['failures'] as Map).map((k, v) => MapEntry(k as String, TranslationFailure.fromJson(v as Map))),
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
    );
  }
}
