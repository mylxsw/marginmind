import 'translation.dart';
import 'translation_content.dart';
import 'translation_job.dart';
import 'translation_store.dart';

/// Transient paragraph status, reconstructed rather than persisted.
enum TranslationSegmentState { none, queued, running, done, failed, reused, skipped }

/// Page status for the task grid, with skipped paragraphs ignored in mixtures.
enum TranslationPageState { none, queued, running, done, failed, partial, reused, skipped }

/// Reconstructs one paragraph: saved results win over stale failures/in-flight
/// flags. [completedKeys] distinguishes results produced in the current run.
/// Recovery defaults cached values to reused; stopped/done jobs never queue.
TranslationSegmentState deriveTranslationSegmentState(
  TranslationParagraph paragraph,
  String targetLang, {
  required Map<String, TranslationSegment> segments,
  TranslationJob? job,
  bool skipped = false,
  Set<String> completedKeys = const {},
  Set<String> runningKeys = const {},
}) {
  final key = textKey(paragraph.text, targetLang);
  if (segments.containsKey(key)) {
    return completedKeys.contains(key) ? TranslationSegmentState.done : TranslationSegmentState.reused;
  }
  if (skipped) return TranslationSegmentState.skipped;
  if (job == null ||
      job.documentId != paragraph.documentId ||
      job.targetLang != targetLang ||
      paragraph.textAnchor != null ||
      !job.range.contains(paragraph.page)) {
    return TranslationSegmentState.none;
  }
  if (job.failures.containsKey(paragraph.fingerprint)) return TranslationSegmentState.failed;
  // Explicit paragraph retries can run after the full task has completed.
  if (job.state == TranslationJobState.done && runningKeys.contains(key)) return TranslationSegmentState.running;
  if (!job.isActive) return TranslationSegmentState.none;
  if (runningKeys.contains(key)) return TranslationSegmentState.running;
  if (job.batch.range.contains(paragraph.page)) return TranslationSegmentState.queued;
  return TranslationSegmentState.none;
}

/// Priority: running, complete/reused, mixed failures, failed, queued, none.
/// Empty pages and pages made entirely of skipped text need no translation.
TranslationPageState deriveTranslationPageState(Iterable<TranslationSegmentState> segments) {
  final states = segments.where((s) => s != TranslationSegmentState.skipped).toList();
  if (states.isEmpty) return TranslationPageState.skipped;
  if (states.contains(TranslationSegmentState.running)) return TranslationPageState.running;
  bool success(TranslationSegmentState s) => s == TranslationSegmentState.done || s == TranslationSegmentState.reused;
  if (states.every(success)) {
    return states.every((s) => s == TranslationSegmentState.reused)
        ? TranslationPageState.reused
        : TranslationPageState.done;
  }
  if (states.contains(TranslationSegmentState.failed)) {
    if (states.any(success)) return TranslationPageState.partial;
    if (states.every((s) => s == TranslationSegmentState.failed)) return TranslationPageState.failed;
  }
  if (states.contains(TranslationSegmentState.queued)) return TranslationPageState.queued;
  return TranslationPageState.none;
}
