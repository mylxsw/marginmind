import 'translation_job.dart';

/// How a stored paragraph was produced.
enum TranslationOrigin { ai, edited, legacy }

/// One successful translation; repeated keys replace previous values in a log.
class TranslationSegment {
  /// Metadata describes the original occurrence; [key] alone controls reuse.
  TranslationSegment({
    required this.key,
    required this.fingerprint,
    required this.page,
    required this.index,
    required this.text,
    required this.model,
    required this.profile,
    required this.origin,
    required this.at,
  }) {
    if (key.isEmpty || fingerprint.isEmpty || page < 1 || index < 0 || text.trim().isEmpty) {
      throw ArgumentError('Invalid translation segment');
    }
  }
  final String key, fingerprint, text, model, profile;
  final int page, index;
  final TranslationOrigin origin;
  final DateTime at;

  /// Journal v1 representation. Unknown fields are ignored when decoding.
  Map<String, Object?> toJson() => {
    'v': 1,
    'key': key,
    'fp': fingerprint,
    'page': page,
    'index': index,
    'text': text,
    'model': model,
    'profile': profile,
    'origin': origin.name,
    'at': at.toUtc().toIso8601String(),
  };

  /// Rejects unsupported versions and malformed entries.
  factory TranslationSegment.fromJson(Map<String, Object?> j) {
    if (j['v'] != 1) throw const FormatException('Unsupported translation segment version');
    return TranslationSegment(
      key: j['key'] as String,
      fingerprint: j['fp'] as String,
      page: j['page'] as int,
      index: j['index'] as int,
      text: j['text'] as String,
      model: j['model'] as String,
      profile: j['profile'] as String,
      origin: TranslationOrigin.values.byName(j['origin'] as String),
      at: DateTime.parse(j['at'] as String),
    );
  }
}

/// Immutable journal snapshot and repair diagnostics (tail loss is separate).
class TranslationSnapshot {
  TranslationSnapshot({
    Map<String, TranslationSegment> segments = const {},
    this.lineCount = 0,
    this.corruptLines = 0,
    this.discardedTail = false,
    this.overwrittenLines = 0,
  }) : segments = Map.unmodifiable(segments);
  final Map<String, TranslationSegment> segments;
  final int lineCount, corruptLines, overwrittenLines;
  final bool discardedTail;

  /// Surface the documented corruption warning only above one percent.
  bool get needsCorruptionWarning => lineCount > 0 && corruptLines / lineCount > .01;

  /// Compact during idle time, after more than thirty percent was overwritten.
  bool get needsCompaction => lineCount > 0 && overwrittenLines / lineCount > .3;
}

/// Study-set-scoped translation persistence, outside content undo snapshots.
/// All methods for one document/language are serialized, including reads.
abstract interface class TranslationStore {
  /// Reads latest successful values and corruption counts.
  Future<TranslationSnapshot> load(String documentId, String targetLang);

  /// Durably appends one value before completing (native storage uses fsync).
  /// Explicit edits/retranslations may replace edited values; the scheduler
  /// must never send a cached key for a bulk operation.
  Future<void> append(String documentId, String targetLang, TranslationSegment segment);

  /// Atomically rewrites live values; callers schedule this when idle.
  Future<void> compact(String documentId, String targetLang);

  /// Missing/corrupt jobs return null (no active job, equivalent to stopped).
  /// Persisted running jobs are returned paused with pauseReason quit.
  Future<TranslationJob?> loadJob(String documentId, String targetLang);

  /// Atomically and durably replaces the small job record.
  Future<void> saveJob(TranslationJob job);

  /// Removes all state for the pair; does not modify legacy studyset.json.
  Future<void> remove(String documentId, String targetLang);
}
