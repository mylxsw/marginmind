import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import 'reader_translation.dart';
import 'translation_schedulers.dart';
import 'workspace_controller.dart';

String formatTokens(int n) {
  if (n >= 10000) {
    final v = (n / 10000).toStringAsFixed(1);
    return '${v.endsWith('.0') ? v.substring(0, v.length - 2) : v} 万';
  }
  return NumberFormat('#,###', 'en-US').format(n);
}

class FullTranslationEstimation {
  const FullTranslationEstimation({
    required this.paras,
    required this.chars,
    required this.uniqueChars,
    required this.reused,
    required this.reusedPages,
    required this.skipped,
    required this.same,
    required this.dupe,
    required this.tokens,
    required this.minutes,
  });

  final int paras;
  final int chars;
  final int uniqueChars;
  final int reused;
  final int reusedPages;
  final int skipped;
  final int same;
  final int dupe;
  final int tokens;
  final int minutes;
}

FullTranslationEstimation estimateFullTranslation({
  required List<TranslationParagraph> paragraphs,
  required int from,
  required int to,
  required String targetLang,
  required Map<String, String> values,
  Set<String> marginFingerprints = const {},
}) {
  var paras = 0, chars = 0, reused = 0, reusedPages = 0, skipped = 0, same = 0, dupe = 0;
  for (var n = from; n <= to; n++) {
    final onPage = paragraphs.where((p) => p.page == n).toList();
    var pageAll = true, any = false;
    for (final p in onPage) {
      final skip = translationSkipReason(p, targetLang, marginFingerprints: marginFingerprints);
      if (skip != null) {
        if (skip == TranslationSkipReason.targetLanguage) {
          same++;
        } else {
          skipped++;
        }
        continue;
      }
      any = true;
      final key = textKey(p.text, targetLang);
      if (values.containsKey(p.fingerprint) || values.containsKey(key)) {
        reused++;
        continue;
      }
      pageAll = false;
      paras++;
      chars += p.text.length;
    }
    if (any && pageAll) reusedPages++;
  }

  final seen = <String>{};
  var dupChars = 0;
  for (var n = from; n <= to; n++) {
    final onPage = paragraphs.where((p) => p.page == n).toList();
    for (final p in onPage) {
      final skip = translationSkipReason(p, targetLang, marginFingerprints: marginFingerprints);
      if (skip != null) continue;
      final key = textKey(p.text, targetLang);
      if (values.containsKey(p.fingerprint) || values.containsKey(key)) continue;
      if (seen.contains(key)) {
        dupe++;
        dupChars += p.text.length;
      } else {
        seen.add(key);
      }
    }
  }

  final uniqueChars = chars - dupChars;
  final tokens = ((uniqueChars / 4 * 1) + (uniqueChars * 0.55) + (((paras - dupe) / 4).ceil() * 180)).round();
  final minutes = math.max(1, ((paras - dupe) * 2.4 / 2 / 60).round());
  return FullTranslationEstimation(
    paras: paras,
    chars: chars,
    uniqueChars: uniqueChars,
    reused: reused,
    reusedPages: reusedPages,
    skipped: skipped,
    same: same,
    dupe: dupe,
    tokens: tokens,
    minutes: minutes,
  );
}

class FullTranslationCounts {
  const FullTranslationCounts({
    required this.total,
    required this.done,
    required this.fail,
    required this.run,
    required this.reused,
    required this.pagesDone,
    required this.pagesTotal,
    required this.pct,
  });

  final int total;
  final int done;
  final int fail;
  final int run;
  final int reused;
  final int pagesDone;
  final int pagesTotal;
  final int pct;
}

class FullTranslationState {
  const FullTranslationState({
    required this.studySetId,
    required this.documentId,
    required this.targetLang,
    this.job,
    this.paragraphs = const [],
    this.values = const {},
    this.segmentStates = const {},
    this.runningKeys = const {},
    this.retries = const {},
    this.loading = true,
    this.loadError,
    this.recoveredQuit = false,
    this.currentReadingPage,
    this.checkpointCollapsed = false,
  });

  final String studySetId;
  final String documentId;
  final String targetLang;
  final TranslationJob? job;
  final List<TranslationParagraph> paragraphs;
  final Map<String, String> values;
  final Map<String, TranslationSegmentState> segmentStates;
  final Set<String> runningKeys;
  final Map<String, int> retries;
  final bool loading;
  final Object? loadError;
  final bool recoveredQuit;
  final int? currentReadingPage;
  final bool checkpointCollapsed;

  bool get hasJob => job != null;
  bool get isActive => job?.isActive == true;
  bool get isRunning => job?.state == TranslationJobState.running;
  bool get isReview => job?.state == TranslationJobState.review;
  bool get isPaused => job?.state == TranslationJobState.paused;
  bool get isOffline => job?.state == TranslationJobState.offline;
  bool get isBudget => job?.state == TranslationJobState.budget;
  bool get isError => job?.state == TranslationJobState.error;
  bool get isDone => job?.state == TranslationJobState.done;
  bool get isStopped => job?.state == TranslationJobState.stopped;

  int get pageCount => paragraphs.isEmpty ? 0 : paragraphs.map((p) => p.page).reduce(math.max);
  int get from => job?.range.from ?? 1;
  int get to => job?.range.to ?? pageCount;
  bool inRange(int page) => job != null && page >= from && page <= to;
  int batchOf(int page) => job == null || job!.mode == TranslationMode.all ? 1 : ((page - from) ~/ job!.batchSize) + 1;

  TranslationSegmentState segmentState(TranslationParagraph p) {
    if (segmentStates[p.fingerprint] case final status?) return status;
    final key = textKey(p.text, targetLang);
    if (values.containsKey(p.fingerprint) || values.containsKey(key)) {
      return TranslationSegmentState.done;
    }
    if (translationSkipReason(p, targetLang) != null) return TranslationSegmentState.skipped;
    final current = job;
    if (current == null || !current.range.contains(p.page)) return TranslationSegmentState.none;
    if (current.failures.containsKey(p.fingerprint)) return TranslationSegmentState.failed;
    if (!current.isActive) return TranslationSegmentState.none;
    if (runningKeys.contains(key)) return TranslationSegmentState.running;
    return current.batch.range.contains(p.page) ? TranslationSegmentState.queued : TranslationSegmentState.none;
  }

  Map<int, TranslationPageState> get pageStates {
    final grouped = <int, List<TranslationSegmentState>>{};
    for (final paragraph in paragraphs) {
      (grouped[paragraph.page] ??= []).add(segmentState(paragraph));
    }
    return {for (final entry in grouped.entries) entry.key: deriveTranslationPageState(entry.value)};
  }

  int get firstUnfinishedPage {
    final pages = pageStates;
    for (var page = from; page <= to; page++) {
      final status = pages[page] ?? TranslationPageState.skipped;
      if (status != TranslationPageState.done &&
          status != TranslationPageState.reused &&
          status != TranslationPageState.skipped) {
        return page;
      }
    }
    return to;
  }

  TranslationPageState pageState(int page) {
    final onPage = paragraphs.where((p) => p.page == page).toList();
    if (onPage.isEmpty) return TranslationPageState.skipped;
    return deriveTranslationPageState(onPage.map(segmentState));
  }

  FullTranslationCounts counts({int? fromPage, int? toPage}) {
    final f = fromPage ?? from;
    final t = toPage ?? to;
    var total = 0, done = 0, fail = 0, run = 0, reused = 0, pagesDone = 0, pagesTotal = 0;
    final byPage = <int, List<TranslationParagraph>>{};
    for (final p in paragraphs) {
      (byPage[p.page] ??= []).add(p);
    }
    for (var n = f; n <= t; n++) {
      final onPage = byPage[n] ?? const <TranslationParagraph>[];
      final sendable = onPage
          .where(
            (p) => translationSkipReason(p, targetLang) == null && segmentState(p) != TranslationSegmentState.skipped,
          )
          .toList();
      if (sendable.isNotEmpty) pagesTotal++;
      final ps = deriveTranslationPageState(onPage.map(segmentState));
      if (ps == TranslationPageState.done || ps == TranslationPageState.reused || ps == TranslationPageState.partial) {
        pagesDone++;
      }
      for (final p in sendable) {
        total++;
        final s = segmentState(p);
        if (s == TranslationSegmentState.done) done++;
        if (s == TranslationSegmentState.reused) {
          done++;
          reused++;
        }
        if (s == TranslationSegmentState.failed) fail++;
        if (s == TranslationSegmentState.running) run++;
      }
    }
    return FullTranslationCounts(
      total: total,
      done: done,
      fail: fail,
      run: run,
      reused: reused,
      pagesDone: pagesDone,
      pagesTotal: pagesTotal,
      pct: total > 0 ? (done * 100 / total).round() : 0,
    );
  }

  FullTranslationState copyWith({
    TranslationJob? job,
    bool clearJob = false,
    List<TranslationParagraph>? paragraphs,
    Map<String, String>? values,
    Map<String, TranslationSegmentState>? segmentStates,
    Set<String>? runningKeys,
    Map<String, int>? retries,
    bool? loading,
    Object? loadError,
    bool clearLoadError = false,
    bool? recoveredQuit,
    int? currentReadingPage,
    bool? checkpointCollapsed,
  }) => FullTranslationState(
    studySetId: studySetId,
    documentId: documentId,
    targetLang: targetLang,
    job: clearJob ? null : job ?? this.job,
    paragraphs: paragraphs ?? this.paragraphs,
    values: values ?? this.values,
    segmentStates: segmentStates ?? this.segmentStates,
    runningKeys: runningKeys ?? this.runningKeys,
    retries: retries ?? this.retries,
    loading: loading ?? this.loading,
    loadError: clearLoadError ? null : loadError ?? this.loadError,
    recoveredQuit: recoveredQuit ?? this.recoveredQuit,
    currentReadingPage: currentReadingPage ?? this.currentReadingPage,
    checkpointCollapsed: checkpointCollapsed ?? this.checkpointCollapsed,
  );
}

final fullTranslationProvider = NotifierProvider.autoDispose
    .family<FullTranslationController, FullTranslationState, (String, String, String)>(
      (key) => FullTranslationController(key.$1, key.$2, key.$3),
    );

class FullTranslationController extends Notifier<FullTranslationState> {
  FullTranslationController(this.studySetId, this.documentId, this.targetLang);

  final String studySetId;
  final String documentId;
  final String targetLang;

  TranslationScheduler? _scheduler;
  StreamSubscription<TranslationSchedulerState>? _subscription;
  int _loadGeneration = 0;
  Future<void>? _loading;

  @override
  FullTranslationState build() {
    ref.watch(translationSchedulersProvider(studySetId));
    ref.onDispose(() {
      _loadGeneration++;
      unawaited(_subscription?.cancel());
    });
    ref.listen(workspaceProvider(studySetId).select((s) => s.content?.document(documentId)?.revision), (before, next) {
      if (before != next) _loading = _reload();
    });
    _loading = Future.microtask(_reload);
    return FullTranslationState(studySetId: studySetId, documentId: documentId, targetLang: targetLang, loading: true);
  }

  Future<void> _reload() async {
    final gen = ++_loadGeneration;
    try {
      final paragraphs = await ref.read(translationParagraphsProvider((studySetId, documentId)).future);
      if (!ref.mounted || gen != _loadGeneration) return;
      final workspace = ref.read(workspaceProvider(studySetId).notifier);
      final schedulers = ref.read(translationSchedulersProvider(studySetId));
      final scheduler = await schedulers.get(documentId, targetLang, paragraphs, content: workspace.content);
      if (!ref.mounted || gen != _loadGeneration) return;
      _scheduler = scheduler;
      await _subscription?.cancel();
      if (!ref.mounted || gen != _loadGeneration) return;
      _subscription = scheduler.states.listen(_onSchedulerState);
      final initialJob = scheduler.job;
      final isRecoveredQuit =
          initialJob?.state == TranslationJobState.paused && initialJob?.pauseReason == TranslationPauseReason.quit;
      state = state.copyWith(
        job: initialJob,
        clearJob: initialJob == null,
        paragraphs: paragraphs,
        values: scheduler.values,
        segmentStates: {for (final p in paragraphs) p.fingerprint: scheduler.segmentState(p)},
        runningKeys: scheduler.state.runningKeys,
        retries: scheduler.state.retries,
        loading: false,
        clearLoadError: true,
        recoveredQuit: isRecoveredQuit,
      );
    } catch (error) {
      if (ref.mounted && gen == _loadGeneration) {
        state = state.copyWith(loading: false, loadError: error);
      }
    }
  }

  void _onSchedulerState(TranslationSchedulerState s) {
    if (!ref.mounted) return;
    state = state.copyWith(
      job: s.job,
      clearJob: s.job == null,
      values: s.values,
      segmentStates: {for (final p in state.paragraphs) p.fingerprint: _scheduler!.segmentState(p)},
      runningKeys: s.runningKeys,
      retries: s.retries,
    );
  }

  void setCurrentReadingPage(int page) {
    state = state.copyWith(currentReadingPage: page);
  }

  void toggleCheckpointCollapsed() {
    state = state.copyWith(checkpointCollapsed: !state.checkpointCollapsed);
  }

  void setCheckpointCollapsed(bool collapsed) {
    state = state.copyWith(checkpointCollapsed: collapsed);
  }

  Future<void> startJob({
    required int from,
    required int to,
    required TranslationMode mode,
    required int batchSize,
    String? note,
    String? sourceLang,
    required String modelName,
    required int estimatedTokens,
  }) async {
    await _loading;
    if (!ref.mounted) throw StateError('Workspace closed');
    final scheduler = _scheduler;
    if (scheduler == null || state.loadError != null) throw StateError('Translation unavailable: ${state.loadError}');
    final isOnline = ref.read(translationOnlineProvider(studySetId));
    final job = TranslationJob(
      id: newId(),
      documentId: documentId,
      sourceLang: sourceLang,
      targetLang: targetLang,
      range: TranslationRange(from, to),
      mode: mode,
      batchSize: batchSize,
      note: note?.trim() ?? '',
      model: modelName,
      state: isOnline ? TranslationJobState.running : TranslationJobState.offline,
      batch: TranslationBatch(
        index: 1,
        range: TranslationRange(from, mode == TranslationMode.all ? to : math.min(to, from + batchSize - 1)),
      ),
      estimateTokens: estimatedTokens,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    state = state.copyWith(job: job, recoveredQuit: false, checkpointCollapsed: false);
    unawaited(scheduler.start(job));
  }

  Future<void> pause() async {
    await _scheduler?.pause();
  }

  Future<void> resume() async {
    state = state.copyWith(recoveredQuit: false);
    unawaited(_scheduler?.resume());
  }

  Future<void> continueBatch({int? batchSize, String? note, bool all = false}) async {
    state = state.copyWith(checkpointCollapsed: false);
    unawaited(_scheduler?.continueBatch(batchSize: batchSize, note: note, all: all));
  }

  Future<void> stop() async {
    await _scheduler?.stop();
  }

  Future<void> retry([TranslationParagraph? paragraph]) async {
    unawaited(_scheduler?.retry(paragraph));
  }

  Future<void> translatePage(int page) async {
    final scheduler = _scheduler;
    if (scheduler == null) return;
    final onPage = state.paragraphs.where((p) => p.page == page).toList();
    for (final p in onPage) {
      if (!state.values.containsKey(p.fingerprint) && !state.values.containsKey(textKey(p.text, targetLang))) {
        unawaited(scheduler.retry(p));
      }
    }
  }

  Future<void> removeTranslations() async {
    final schedulers = ref.read(translationSchedulersProvider(studySetId));
    await schedulers.removeTranslations(documentId, targetLang);
    if (!ref.mounted) return;
    state = state.copyWith(
      clearJob: true,
      values: const {},
      segmentStates: const {},
      runningKeys: const {},
      retries: const {},
      checkpointCollapsed: false,
    );
    await _reload();
    if (ref.mounted) {
      await ref.read(readerTranslationProvider(studySetId).notifier).reloadAfterRemoval(documentId, targetLang);
    }
  }
}
