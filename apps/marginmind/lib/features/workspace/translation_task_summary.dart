import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';

import 'full_translation.dart';
import 'translation_schedulers.dart';

/// Menu/sidebar observation. Reading this never extracts document paragraphs or
/// creates a scheduler. Both languages are checked so a user-selected language
/// remains discoverable from every entry point.
class TranslationTaskSummary {
  const TranslationTaskSummary(this.job, this.percent);
  final TranslationJob job;
  final int percent;
  bool get isActive => job.isActive;
  String get targetLang => job.targetLang;
}

final translationTaskSummaryProvider = StreamProvider.autoDispose.family<TranslationTaskSummary?, (String, String)>((
  ref,
  key,
) {
  final registry = ref.watch(translationSchedulersProvider(key.$1));
  final events = StreamController<TranslationTaskSummary?>();
  final stored = <String, TranslationTaskSummary>{};
  var disposed = false;
  void emit() {
    if (disposed) return;
    final summaries = <TranslationTaskSummary>[];
    for (final lang in ['zh', 'en']) {
      final live = registry.peek(key.$2, lang);
      if (live != null) {
        final job = live.job;
        if (job != null) {
          final state = FullTranslationState(
            studySetId: key.$1,
            documentId: key.$2,
            targetLang: lang,
            job: job,
            paragraphs: live.paragraphs,
            values: live.values,
            segmentStates: {for (final p in live.paragraphs) p.fingerprint: live.segmentState(p)},
            runningKeys: live.state.runningKeys,
            loading: false,
          );
          summaries.add(TranslationTaskSummary(job, state.counts().pct));
        }
      } else if (stored[lang] case final summary?) {
        summaries.add(summary);
      }
    }
    summaries.sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return b.job.updatedAt.compareTo(a.job.updatedAt);
    });
    events.add(summaries.firstOrNull);
  }

  final sub = registry.changes.listen((changed) {
    if (changed.$1 != key.$2) return;
    stored.remove(changed.$2);
    emit();
  });
  unawaited(() async {
    try {
      final store = await ref.read(translationStoreProvider(key.$1).future);
      for (final lang in ['zh', 'en']) {
        final job = await store.loadJob(key.$2, lang);
        if (disposed) return;
        if (job == null) continue;
        // Before opening the reader, only completed batches are known.
        // The live scheduler supplies exact paragraph progress on opening.
        final percent = job.state == TranslationJobState.done
            ? 100
            : ((job.batch.range.from - job.range.from) * 100 / (job.range.to - job.range.from + 1)).round();
        stored[lang] = TranslationTaskSummary(job, percent);
      }
      emit();
    } catch (error, stack) {
      if (!disposed) events.addError(error, stack);
    }
  }());
  ref.onDispose(() {
    disposed = true;
    unawaited(sub.cancel());
    unawaited(events.close());
  });
  return events.stream;
});
