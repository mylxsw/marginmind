import '../content/translation.dart';
import '../content/translation_content.dart';
import '../content/translation_job.dart';
import '../content/translation_store.dart';
import '../content/reading.dart';

/// Test implementation of the durable translation port, separate from content.
class InMemoryTranslationStore implements TranslationStore {
  final _segments = <(String, String), Map<String, TranslationSegment>>{};
  final _jobs = <(String, String), TranslationJob>{};
  final _removed = <(String, String)>{};
  @override
  Future<TranslationSnapshot> load(String documentId, String targetLang) async =>
      TranslationSnapshot(segments: _segments[(documentId, targetLang)] ?? {});
  @override
  Future<void> append(String documentId, String targetLang, TranslationSegment segment) async {
    _segments.putIfAbsent((documentId, targetLang), () => {})[segment.key] = segment;
  }

  @override
  Future<void> compact(String documentId, String targetLang) async {}
  @override
  Future<TranslationJob?> loadJob(String documentId, String targetLang) async {
    final job = _jobs[(documentId, targetLang)];
    return job?.state == TranslationJobState.running || job?.state == TranslationJobState.offline
        ? job!.copyWith(state: TranslationJobState.paused, pauseReason: TranslationPauseReason.quit)
        : job;
  }

  @override
  Future<void> saveJob(TranslationJob job) async {
    _jobs[(job.documentId, job.targetLang)] = job;
  }

  @override
  Future<void> remove(String documentId, String targetLang) async {
    _segments.remove((documentId, targetLang));
    _jobs.remove((documentId, targetLang));
    _removed.add((documentId, targetLang));
  }

  @override
  Future<TranslationSnapshot> importLegacy(
    String documentId,
    String targetLang, {
    required Iterable<TranslationParagraph> paragraphs,
    required Iterable<TranslationCache> caches,
  }) async {
    if (!_removed.contains((documentId, targetLang))) {
      for (final cache in caches.where((c) => c.documentId == documentId && c.targetLang == targetLang)) {
        for (final p in paragraphs.where((p) => p.documentId == documentId)) {
          final key = textKey(p.text, targetLang), text = cache.paragraphs[p.fingerprint];
          if (text == null || text.trim().isEmpty || _segments[(documentId, targetLang)]?.containsKey(key) == true) {
            continue;
          }
          await append(
            documentId,
            targetLang,
            TranslationSegment(
              key: key,
              fingerprint: p.fingerprint,
              page: p.textAnchor == null ? p.page : p.index + 1,
              index: p.index,
              text: text,
              model: cache.model,
              profile: '',
              origin: TranslationOrigin.legacy,
              at: cache.createdAt,
            ),
          );
        }
      }
    }
    return load(documentId, targetLang);
  }
}
