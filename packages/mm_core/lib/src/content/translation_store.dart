import 'translation_job.dart';
import 'translation.dart';
import 'reading.dart';

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
    Map<String, String> tokens = const {},
    Map<String, List<TranslationChoice>> conflicts = const {},
    this.documentVersion,
    this.lineCount = 0,
    this.corruptLines = 0,
    this.discardedTail = false,
    this.overwrittenLines = 0,
  }) : segments = Map.unmodifiable(segments),
       tokens = Map.unmodifiable(tokens),
       conflicts = Map.unmodifiable({
         for (final e in conflicts.entries) e.key: List<TranslationChoice>.unmodifiable(e.value),
       });
  final Map<String, TranslationSegment> segments;
  final Map<String, String> tokens;
  final Map<String, List<TranslationChoice>> conflicts;
  final String? documentVersion;
  String? tokenFor(String key) => tokens[key] ?? (documentVersion == null ? null : 'absent:$documentVersion');
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

  /// Imports only exact legacy fingerprint matches; newer stored edits win.
  Future<TranslationSnapshot> importLegacy(
    String documentId,
    String targetLang, {
    required Iterable<TranslationParagraph> paragraphs,
    required Iterable<TranslationCache> caches,
  });

  /// Durably appends one value before completing (native storage uses fsync).
  /// Local journals replace the old value. Synced stores preserve unobserved
  /// human candidates; use GuardedTranslationStore for an observed replacement.
  Future<void> append(String documentId, String targetLang, TranslationSegment segment);

  /// Atomically rewrites live values; callers schedule this when idle.
  Future<void> compact(String documentId, String targetLang);

  /// Missing/corrupt jobs return null (no active job, equivalent to stopped).
  /// Persisted running/offline jobs are returned paused with pauseReason quit.
  Future<TranslationJob?> loadJob(String documentId, String targetLang);

  /// Atomically and durably replaces the small job record.
  Future<void> saveJob(TranslationJob job);

  /// Removes all state for the pair; does not modify legacy studyset.json.
  Future<void> remove(String documentId, String targetLang);
}

/// Repository-owned translation stores follow the lifetime of a study set.
abstract interface class TranslationStoreRepository {
  Future<TranslationStore> translationStore(String studySetId);
}

/// Optional durable observation and live publication capability.
class TranslationChoice {
  const TranslationChoice(this.id, this.segment);
  final String id;
  final TranslationSegment? segment;
}

abstract interface class GuardedTranslationStore {
  Stream<TranslationSnapshot> watchTranslations(String documentId, String language);
  Future<TranslationSnapshot> appendGuarded(
    String documentId,
    String language,
    TranslationSegment segment, {
    required String? expectedToken,
    bool replaceEdited = false,
  });
  Future<void> chooseTranslation(
    String documentId,
    String language,
    String key,
    String choice, {
    required String expectedToken,
  });
}
