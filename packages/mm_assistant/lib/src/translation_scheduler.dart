import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:http_parser/http_parser.dart' show parseHttpDate;

import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:mm_core/mm_core.dart';

import 'runtime.dart';
import 'translation.dart';

/// Immutable observation, published only after successful translations are durable.
class TranslationSchedulerState {
  TranslationSchedulerState({
    required this.job,
    required Map<String, String> values,
    required Set<String> runningKeys,
    required Map<String, int> retries,
    this.failure,
  }) : values = Map.unmodifiable(values),
       runningKeys = Set.unmodifiable(runningKeys),
       retries = Map.unmodifiable(retries);
  final TranslationJob? job;
  final Map<String, String> values;
  final Set<String> runningKeys;
  final Map<String, int> retries;
  final Object? failure;
}

/// One owner per document/language. Bulk work has two slots; explicit paragraph
/// commands share the content-key registry but do not consume those slots.
class TranslationScheduler {
  TranslationScheduler({
    required this.documentId,
    required this.language,
    required List<TranslationParagraph> paragraphs,
    ParagraphTranslator? translator,
    this.createTranslator,
    required this.store,
    required this.model,
    this.budget = const ResearchBudget(),
    Map<int, double> pageHeights = const {},
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
    double Function()? random,
    Timer Function(Duration, void Function())? schedule,
    this.changed,
    bool online = true,
    // ignore: prefer_initializing_formals
  }) : _online = online,
       _translator = translator,
       paragraphs = List.unmodifiable(paragraphs),
       _pageHeights = Map.unmodifiable(pageHeights),
       _now = now ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed,
       _random = random ?? math.Random().nextDouble,
       _schedule = schedule ?? Timer.new {
    budget.validate();
    if (translator == null && createTranslator == null) throw ArgumentError('Missing translator');
    if (TranslationLanguage.fromCode(language) == null) throw ArgumentError('Invalid language');
    if (paragraphs.any((p) => p.documentId != documentId)) throw ArgumentError('Different document');
  }
  final String documentId, language, model;
  final List<TranslationParagraph> paragraphs;
  final Map<int, double> _pageHeights;
  final _keys = <String, String>{};
  ParagraphTranslator? _translator;
  final Future<ParagraphTranslator> Function()? createTranslator;
  Future<ParagraphTranslator>? _opening;
  bool _refreshTranslator = false;
  String? _boundJobId;
  bool _starting = false;
  Future<ParagraphTranslator> _getTranslator({bool prepareScope = true}) async {
    final t =
        _translator ??
        await (_opening ??= createTranslator!().then((t) => _translator = t).whenComplete(() => _opening = null));
    if (t is ScheduledParagraphTranslator && _job != null && _boundJobId != _job!.id) {
      final previous = _job!;
      final bound = await t.bindJob(previous);
      if (_job?.id == previous.id) {
        _job = _job!.copyWith(runContext: bound.runContext, model: bound.model);
        _boundJobId = previous.id;
      }
    }
    if (prepareScope && t is ScheduledParagraphTranslator && _job == null) await t.prepareScope();
    return t;
  }

  final TranslationStore store;
  final ResearchBudget budget;
  final void Function()? changed;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;
  final double Function() _random;
  final Timer Function(Duration, void Function()) _schedule;
  Timer? _ledgerTimer;
  Completer<void>? _progress;
  final _events = StreamController<TranslationSchedulerState>.broadcast(sync: true);
  final _segments = <String, TranslationSegment>{};
  final _skipped = <String>{}, _completed = <String>{}, _failed = <String>{};
  final _active = <String, Future<void>>{};
  final _retries = <String, int>{};
  Set<int> _visible = {}, _demand = {};
  int _focus = 0, _reserved = 0, _consecutive429 = 0, _commandVersion = 0;
  bool _online, _closed = false, _closingRequested = false, _batchRequested = false;
  Future<void>? _closing;
  DateTime? _last429, _lastSaved;
  Future<void>? _runFuture;
  Future<void> _writes = Future.value();
  Future<void> _segmentWrites = Future.value();
  final _editVersions = <String, int>{};
  TranslationJob? _job;
  Object? _failure;
  final _pendingSegments = <String, (TranslationSegment, int, bool)>{};
  final _requestCancels = <CancellationToken>{};
  TranslationUsage _usage = TranslationUsage();

  TranslationJob? get job => _job;
  Map<String, TranslationSegment> get segments => Map.unmodifiable(_segments);
  Object? get failure => _failure;
  Stream<TranslationSchedulerState> get states => _events.stream;
  Map<String, String> get values => {
    for (final p in paragraphs)
      if (_segments.containsKey(keyOf(p)))
        p.fingerprint: _segments[keyOf(p)]!.text
      else if (_skipped.contains(p.fingerprint))
        p.fingerprint: p.text,
  };
  TranslationSchedulerState get state => TranslationSchedulerState(
    job: _job,
    values: values,
    runningKeys: _active.keys.toSet(),
    retries: _retries,
    failure: _failure,
  );
  String keyOf(TranslationParagraph p) => _keys[p.fingerprint] ?? textKey(p.text, language);
  int _page(TranslationParagraph p) => p.unit;
  bool get _available =>
      _online ||
      (_translator is ScheduledParagraphTranslator && (_translator as ScheduledParagraphTranslator).localOnly);
  bool get _gate =>
      !_closed &&
      !_closingRequested &&
      _available &&
      (_job == null || !_job!.isActive || _job!.state == TranslationJobState.running);
  int get concurrency => math.min(
    budget.outputTokens,
    _last429 != null && _now().difference(_last429!) < const Duration(minutes: 10) && _consecutive429 >= 2 ? 1 : 2,
  );

  TranslationSegmentState segmentState(TranslationParagraph p) => deriveTranslationSegmentState(
    p,
    language,
    segments: _segments,
    job: _job,
    skipped: _skipped.contains(p.fingerprint),
    completedKeys: _completed,
    runningKeys: _active.keys.toSet(),
  );

  Future<void> initialize({TranslationSnapshot? snapshot}) async {
    // Capture only immutable inputs, never the scheduler/transport or its Ref.
    final ps = paragraphs, lang = language, heights = _pageHeights;
    (Map<String, String>, Set<String>) prepared;
    try {
      prepared = await Isolate.run(() => _prepare(ps, lang, heights));
    } on UnsupportedError {
      prepared = _prepare(ps, lang, heights);
    }
    _keys.addAll(prepared.$1);
    _skipped.addAll(prepared.$2);
    _segments.addAll((snapshot ?? await store.load(documentId, language)).segments);
    _job = await store.loadJob(documentId, language);
    _usage = _job?.usage ?? TranslationUsage();
    _failed.addAll(_job?.failures.keys ?? []);
    if (_job?.runContext != null && _job!.isActive) {
      final t = await _getTranslator();
      if (t is ScheduledParagraphTranslator) await t.saveJob(_job!);
    }
    _emit();
  }

  void prioritize(Iterable<int> visible, {int? focus}) {
    _visible = visible.toSet();
    if (focus != null) _focus = focus;
  }

  Future<TranslationJob> prepareJob(TranslationJob job, {ModelReference? modelOverride}) async {
    if (_closed || _closingRequested || _job?.isActive == true) throw StateError('Scheduler is busy');
    _demand = {};
    if (_translator case final ScheduledParagraphTranslator current) current.pauseDispatch();
    await _runFuture;
    if (_active.isNotEmpty) await Future.wait(_active.values.toSet());
    final t = await _getTranslator(prepareScope: false);
    return t is ScheduledParagraphTranslator ? t.bindJob(job, modelOverride: modelOverride) : job;
  }

  Future<void> start(TranslationJob job) async {
    if (_closed || _closingRequested || _starting || _job?.isActive == true) throw StateError('Scheduler is busy');
    final command = ++_commandVersion;
    _starting = true;
    try {
      if (job.documentId != documentId || job.targetLang != language) throw ArgumentError('Different task scope');
      _demand = {};
      if (_translator case final ScheduledParagraphTranslator current) current.pauseDispatch();
      await _runFuture;
      if (_active.isNotEmpty) await Future.wait(_active.values.toSet());
      final translator = await _getTranslator(prepareScope: false);
      if (translator is ScheduledParagraphTranslator) {
        job = await translator.bindJob(job);
        _boundJobId = job.id;
        translator.authorizeRecovery();
      }
      if (_closed || _closingRequested || command != _commandVersion) throw StateError('Task start superseded');
      _job = job.copyWith(
        state: _available ? TranslationJobState.running : TranslationJobState.offline,
        updatedAt: _now(),
      );
      _usage = TranslationUsage(
        inputTokens: job.usage.inputTokens,
        outputTokens: job.usage.outputTokens,
        requests: job.usage.requests + _active.values.toSet().length,
      );
      _demand = {};
      _batchRequested = false;
      _failed
        ..clear()
        ..addAll(job.failures.keys);
      _failure = null;
      await _persist(force: true);
      _emit();
      await _run();
    } finally {
      _starting = false;
    }
  }

  /// Viewing a page never bypasses an unfinished full-document job.
  Future<void> demand(Iterable<int> pages) async {
    if (_job?.isActive == true || _closed || _closingRequested) return;
    _demand = pages.toSet();
    if (_translator case final ScheduledParagraphTranslator t) {
      t.pauseDispatch(paused: _demand.isEmpty);
    }
    _failure = null;
    await _run();
  }

  Future<void> pause({TranslationPauseReason reason = TranslationPauseReason.user}) async {
    _commandVersion++;
    if (_translator case final ScheduledParagraphTranslator t) t.pauseDispatch();
    if (_closed) return;
    if (_job?.isActive != true) {
      _demand = {};
      return;
    }
    _job = _job!.copyWith(state: TranslationJobState.paused, pauseReason: reason, updatedAt: _now());
    _emit();
    await _persist(force: true);
  }

  Future<void> resume() async {
    if (_closed || _closingRequested || _job?.isActive != true || _job!.state == TranslationJobState.review) return;
    final command = ++_commandVersion;
    await _refreshConnection();
    if (_closed || _closingRequested || command != _commandVersion) return;
    _failure = null;
    if (_translator case final ScheduledParagraphTranslator t) t.authorizeRecovery();
    _job = _job!.copyWith(
      state: _available ? TranslationJobState.running : TranslationJobState.offline,
      budgetAcknowledged: _job!.budgetAcknowledged || _job!.state == TranslationJobState.budget,
      updatedAt: _now(),
    );
    await _persist(force: true);
    _emit();
    await _run();
  }

  Future<void> continueBatch({int? batchSize, String? note, bool all = false}) async {
    if (_closed || _closingRequested || _job?.state != TranslationJobState.review) return;
    final j = _job!;
    if (_translator case final ScheduledParagraphTranslator t) t.authorizeRecovery();
    final from = j.batch.range.to + 1;
    if (from > j.range.to) return;
    final size = batchSize ?? j.batchSize;
    _job = j.copyWith(
      batchSize: size,
      note: note,
      mode: all ? TranslationMode.all : null,
      batch: TranslationBatch(
        index: j.batch.index + 1,
        range: TranslationRange(from, all ? j.range.to : math.min(j.range.to, from + size - 1)),
      ),
      state: _available ? TranslationJobState.running : TranslationJobState.offline,
      updatedAt: _now(),
    );
    _batchRequested = false;
    await _persist(force: true);
    _emit();
    await _run();
  }

  Future<void> stop() async {
    _commandVersion++;
    _demand = {};
    if (_closed || _job == null) return;
    _job = _job!.copyWith(state: TranslationJobState.stopped, updatedAt: _now());
    if (_translator case final ScheduledParagraphTranslator t) {
      for (final cancel in _requestCancels) {
        cancel.cancel();
      }
      await t.cancelPending();
    }
    _emit();
    await _persist(force: true);
  }

  Future<void> setOnline(bool online) async {
    if (_closed || _closingRequested) return;
    _online = online;
    if (!_available && _job?.state == TranslationJobState.running) {
      _job = _job!.copyWith(state: TranslationJobState.offline, updatedAt: _now());
      await _persist(force: true);
      _emit();
    } else if (_available && _job?.state == TranslationJobState.offline) {
      await resume();
    }
  }

  /// With no paragraph, retries only recorded failures, never successful keys.
  Future<void> retry([TranslationParagraph? paragraph]) async {
    _failure = null;
    if (paragraph != null) {
      await _explicit(paragraph, replace: false);
    } else {
      final failed = paragraphs.where((p) => _failed.contains(p.fingerprint)).toList();
      for (final p in failed) {
        await _explicit(p, replace: false);
      }
    }
    _emit();
  }

  /// User edits are journal entries, outside the content undo stack.
  Future<void> edit(TranslationParagraph p, String text) async {
    if (_closed || _closingRequested) throw StateError('Scheduler closed');
    final old = _segments[keyOf(p)];
    if (old == null ||
        text.trim().isEmpty ||
        p.documentId != documentId ||
        !paragraphs.any((q) => q.fingerprint == p.fingerprint && q.text == p.text)) {
      throw ArgumentError('Invalid paragraph edit');
    }
    final key = keyOf(p);
    await _append(
      TranslationSegment(
        key: key,
        fingerprint: p.fingerprint,
        page: _page(p),
        index: p.index,
        text: text.trim(),
        model: old.model,
        profile: old.profile,
        origin: TranslationOrigin.edited,
        at: _now(),
      ),
    );
  }

  /// Appends the old value; a stale HUD cannot overwrite a later edit.
  Future<void> restore(TranslationSegment old, {required TranslationSegment replacing}) async {
    if (_closed || _closingRequested) return;
    final key = old.key;
    if (!identical(_segments[key], replacing)) return;
    await _append(old, replacing: replacing);
  }

  Future<void> _append(
    TranslationSegment segment, {
    int? editVersion,
    bool replaceEdited = true,
    TranslationSegment? replacing,
  }) async {
    final write = _segmentWrites.then((_) async {
      if (editVersion != null && (_editVersions[segment.key] ?? 0) != editVersion) return;
      if (!replaceEdited && _segments[segment.key]?.origin == TranslationOrigin.edited) return;
      if (replacing != null && !identical(_segments[segment.key], replacing)) return;
      await store.append(documentId, language, segment);
      if (editVersion == null) _editVersions[segment.key] = (_editVersions[segment.key] ?? 0) + 1;
      _segments[segment.key] = segment;
      _completed.add(segment.key);
      _clearFailures(paragraphs.firstWhere((p) => keyOf(p) == segment.key));
      _emit();
    });
    _segmentWrites = write.catchError((Object _) {});
    await write;
  }

  Future<void> retranslate(TranslationParagraph p) => _explicit(p, replace: true);

  Future<void> _explicit(TranslationParagraph p, {required bool replace}) async {
    if (_closed || _closingRequested) return;
    if (p.documentId != documentId || !paragraphs.any((q) => q.fingerprint == p.fingerprint && q.text == p.text)) {
      throw ArgumentError('Unknown paragraph');
    }
    final existing = _active[keyOf(p)];
    if (existing != null) {
      await existing;
      return;
    }
    if (!replace && _segments.containsKey(keyOf(p))) return;
    if (_refreshTranslator) {
      await _refreshConnection();
      if (_closed || _closingRequested || !_available) return;
      final racing = _active[keyOf(p)];
      if (racing != null) {
        await racing;
        return;
      }
      if (!replace && _segments.containsKey(keyOf(p))) return;
    }
    final currentTranslator = await _getTranslator();
    if (!_available || _closed || _closingRequested) return;
    if (_active[keyOf(p)] case final Future<void> racing) {
      await racing;
      return;
    }
    if (!replace && _segments.containsKey(keyOf(p))) return;
    if (currentTranslator is ScheduledParagraphTranslator) currentTranslator.authorizeRecovery();
    if (replace) {
      final t = currentTranslator;
      if (t is ScheduledParagraphTranslator) t.newTranslation(p);
    }
    _clearFailures(p);
    await _dispatch([p], explicit: true);
    await _persist(force: true);
  }

  List<TranslationParagraph> _candidates() {
    final j = _job;
    final seen = <String>{};
    final result = paragraphs
        .where(
          (p) =>
              !_segments.containsKey(keyOf(p)) &&
              !_skipped.contains(p.fingerprint) &&
              !_failed.contains(p.fingerprint) &&
              !_active.containsKey(keyOf(p)) &&
              (j?.isActive == true ? j!.batch.range.contains(_page(p)) : _demand.contains(_page(p))) &&
              seen.add(keyOf(p)),
        )
        .toList();
    final visiblePages = paragraphs.where((p) => _visible.contains(p.index)).map(_page).toSet();
    int priority(TranslationParagraph p) =>
        (visiblePages.contains(_page(p)) ? -1000000 : 0) +
        (_visible.contains(p.index) ? -10000 : 0) +
        (p.index - _focus).abs();
    result.sort((a, b) => priority(a).compareTo(priority(b)));
    return result;
  }

  List<TranslationParagraph> _pack(List<TranslationParagraph> candidates) {
    final first = candidates.first;
    if (_translator is! PackedParagraphTranslator) return [first];
    final available = {for (final p in candidates) p.fingerprint};
    final result = [first];
    var chars = first.text.length;
    var offset = paragraphs.indexOf(first) + 1;
    while (offset < paragraphs.length && result.length < 12) {
      final p = paragraphs[offset++];
      if (_page(p) != _page(first) || !available.contains(p.fingerprint) || chars + p.text.length > 2400) break;
      chars += p.text.length;
      result.add(p);
    }
    return result;
  }

  Future<void> _run() async {
    final previous = _runFuture;
    if (previous != null) {
      await previous;
      // A resume/page command can arrive while the old drain is flushing disk.
      if (_gate && (_candidates().isNotEmpty || _job?.state == TranslationJobState.running)) await _run();
      return;
    }
    final run = _drain();
    _runFuture = run;
    try {
      await run;
    } finally {
      if (identical(_runFuture, run)) _runFuture = null;
    }
  }

  Future<void> _drain() async {
    try {
      for (final entry in _pendingSegments.entries.toList()) {
        final (segment, version, replace) = entry.value;
        await _append(segment, editVersion: version, replaceEdited: replace);
        _pendingSegments.remove(entry.key);
      }
    } catch (_) {
      _storageFailed();
      rethrow;
    }
    if (_candidates().isNotEmpty &&
        !_closed &&
        !_closingRequested &&
        (_job == null || !_job!.isActive || _job!.state == TranslationJobState.running)) {
      try {
        await _getTranslator();
      } catch (error) {
        _failure = ResearchFailure(assistantFailureKind(error));
        if (_job?.isActive == true) {
          _job = _job!.copyWith(
            state: TranslationJobState.error,
            errorKind: assistantFailureKind(error) == ResearchFailureKind.authentication ? 'authentication' : 'model',
          );
          await _persist(force: true);
        }
        _emit();
        return;
      }
    }
    while (_gate) {
      await Future.wait([_worker(0), _worker(1)]);
      final inBatch = _active.entries
          .where((e) => paragraphs.any((p) => keyOf(p) == e.key && (_job?.batch.range.contains(_page(p)) ?? false)))
          .map((e) => e.value)
          .toSet();
      if (inBatch.isNotEmpty) await Future.wait(inBatch);
      if (!_gate || _candidates().isNotEmpty) {
        if (_gate) continue;
        break;
      }
      if (_job?.state != TranslationJobState.running) break;
      final j = _job!;
      if (j.batch.range.to >= j.range.to) {
        _job = j.copyWith(state: TranslationJobState.done, updatedAt: _now());
      } else if (j.mode == TranslationMode.batch &&
          (_batchRequested ||
              paragraphs.any((p) => j.batch.range.contains(_page(p)) && _failed.contains(p.fingerprint)))) {
        _job = j.copyWith(state: TranslationJobState.review, updatedAt: _now());
      } else {
        final from = j.batch.range.to + 1;
        _job = j.copyWith(
          batch: TranslationBatch(
            index: j.batch.index + 1,
            range: TranslationRange(
              from,
              j.mode == TranslationMode.all ? j.range.to : math.min(j.range.to, from + j.batchSize - 1),
            ),
          ),
          updatedAt: _now(),
        );
        _batchRequested = false;
        continue;
      }
      _emit();
      break;
    }
    await _persist(force: true);
    if (!_closed && _active.isEmpty) await store.compact(documentId, language);
  }

  Future<void> _worker(int slot) async {
    while (_gate) {
      if (slot >= concurrency) {
        if (_active.isEmpty && _candidates().isEmpty) return;
        await (_progress ??= Completer<void>()).future;
        continue;
      }
      final candidates = _candidates();
      if (candidates.isEmpty) return;
      await _dispatch(_pack(candidates), slot: slot);
    }
  }

  Future<void> _dispatch(List<TranslationParagraph> pack, {bool explicit = false, int slot = 0}) async {
    // Bind bulk attempts before observers can pause/stop the job in _emit.
    final bulkJobId = !explicit && _job?.isActive == true ? _job!.id : null;
    final done = Completer<void>();
    for (final p in pack) {
      _active[keyOf(p)] = done.future;
    }
    _emit();
    try {
      await _request(pack, explicit: explicit, slot: slot, bulkJobId: bulkJobId);
    } finally {
      for (final p in pack) {
        _active.remove(keyOf(p));
        _retries.remove(keyOf(p));
      }
      done.complete();
      _emit();
    }
  }

  Future<void> _request(
    List<TranslationParagraph> pack, {
    required bool explicit,
    int slot = 0,
    String? bulkJobId,
  }) async {
    // A stopped job permits new on-demand work, but never revives its old bulk attempts.
    bool bulkJobRunning() => bulkJobId == null || (_job?.id == bulkJobId && _job?.state == TranslationJobState.running);
    bool canAttempt() =>
        !_closed && !_closingRequested && _available && (explicit || (bulkJobRunning() && _gate && slot < concurrency));
    final editVersions = {for (final p in pack) keyOf(p): _editVersions[keyOf(p)] ?? 0};
    // Capture provenance before awaiting: edits to requirements affect later requests.
    final note = _job?.note ?? '';
    final profile = translationProfile(note, promptVersion: _job?.promptVersion ?? 1);
    final inputEstimate = 512 + utf8.encode(note + pack.map((p) => p.text).join()).length;
    for (var attempt = 0; attempt <= 3; attempt++) {
      if (!canAttempt()) return;
      final remaining = explicit ? budget.outputTokens : budget.outputTokens - _reserved;
      if (remaining <= 0) {
        await _sleep(const Duration(milliseconds: 1));
        continue;
      }
      final allowance = math.min(4096, math.min(remaining, math.max(1, budget.outputTokens ~/ 2)));
      final reservation = explicit ? 0 : allowance;
      _reserved += reservation;
      var saving = true, accounted = false, sent = false;
      final requestCancel = CancellationToken();
      _requestCancels.add(requestCancel);
      try {
        await _persist();
        if (!canAttempt()) return;
        final PackedParagraphTranslation response;
        saving = false;
        final t = await _getTranslator();
        if (!canAttempt()) return;
        final managed = t is ScheduledParagraphTranslator;
        final requestModel = t is ScheduledParagraphTranslator
            ? t.modelIdentity
            : t is ModelParagraphTranslator
            ? t.model
            : model;
        if (!managed && pack.fold<int>(512 + note.length, (n, p) => n + p.text.length) > budget.inputCharacters) {
          if (!bulkJobRunning()) return;
          await _recordFailure(pack, ResearchFailureKind.protocol, 0);
          return;
        }
        if (!managed) {
          _usage = TranslationUsage(
            inputTokens: _usage.inputTokens,
            outputTokens: _usage.outputTokens,
            requests: _usage.requests + 1,
          );
        }
        if (!explicit && _job?.isActive == true) _batchRequested = true;
        sent = true;
        if (t is PackedParagraphTranslator) {
          final pending = t.translatePack(
            pack,
            language,
            requestCancel,
            allowance,
            sourceLanguage: _job?.sourceLang,
            note: note,
          );
          // A long source paragraph may require many bounded SDK children;
          // Runtime-backed calls enforce timeout per child, not per paragraph.
          response = managed ? await pending : await pending.timeout(budget.duration);
        } else {
          final r = await t
              .translate(pack.single, language, requestCancel, allowance, sourceLanguage: _job?.sourceLang)
              .timeout(budget.duration);
          response = PackedParagraphTranslation([r.text], inputTokens: r.inputTokens, outputTokens: r.tokens);
        }
        _usage = t is ScheduledParagraphTranslator
            ? await t.readUsage()
            : TranslationUsage(
                inputTokens: _usage.inputTokens + _positiveUsage(response.inputTokens, inputEstimate),
                outputTokens:
                    _usage.outputTokens +
                    _positiveUsage(response.outputTokens, utf8.encode(response.texts.join()).length + pack.length * 8),
                requests: _usage.requests,
              );
        accounted = true;
        if (_consecutive429 < 2) _consecutive429 = 0;
        _checkBudget();
        if (response.texts.length != pack.length || response.texts.any((s) => s.trim().isEmpty)) {
          throw const ResearchFailure(ResearchFailureKind.protocol);
        }
        saving = true;
        if (managed) await _persist(force: true);
        if (managed && bulkJobId != null && (_job?.id != bulkJobId || _job?.state == TranslationJobState.stopped)) {
          return;
        }
        if (managed) requestCancel.check();
        for (var i = 0; i < pack.length; i++) {
          final p = pack[i];
          final segment = TranslationSegment(
            key: keyOf(p),
            fingerprint: p.fingerprint,
            page: _page(p),
            index: p.index,
            text: response.texts[i].trim(),
            model: requestModel,
            profile: profile,
            origin: TranslationOrigin.ai,
            at: _now(),
          );
          _pendingSegments[segment.key] = (segment, editVersions[segment.key]!, explicit);
        }
        for (final key in pack.map(keyOf)) {
          final pending = _pendingSegments[key];
          if (pending == null) continue;
          final (segment, version, replace) = pending;
          await _append(segment, editVersion: version, replaceEdited: replace);
          _pendingSegments.remove(key);
        }
        await _persist();
        return;
      } catch (error) {
        if (_closed) return;
        if (saving) {
          _storageFailed();
          // Never buy a translation again because its journal write failed.
          rethrow;
        }
        if (_translator case final ScheduledParagraphTranslator t) {
          _usage = await t.readUsage();
          accounted = true;
        }
        if (error is ResearchFailure && error.code == 'translationPaused') return;
        if (!accounted && sent) {
          _usage = TranslationUsage(
            inputTokens:
                _usage.inputTokens +
                (error is TranslationResponseFailure
                    ? _positiveUsage(error.inputTokens, inputEstimate)
                    : inputEstimate),
            outputTokens:
                _usage.outputTokens +
                (error is TranslationResponseFailure ? _positiveUsage(error.outputTokens, allowance) : allowance),
            requests: _usage.requests,
          );
          _checkBudget();
        }
        requestCancel.cancel();
        final kind = error is TimeoutException ? ResearchFailureKind.timeout : assistantFailureKind(error);
        if (kind == ResearchFailureKind.network && !_online) return;
        if (bulkJobId != null && (_job?.id != bulkJobId || _job?.state == TranslationJobState.stopped)) return;
        final reason = error is ConfigurationFailure ? 'model' : _taskError(error, kind);
        if (reason != null) {
          if (_job?.isActive == true) {
            _job = _job!.copyWith(state: TranslationJobState.error, errorKind: reason, updatedAt: _now());
          }
          _refreshTranslator = _translator is! ScheduledParagraphTranslator && createTranslator != null;
          _failure = ResearchFailure(kind);
          _demand = {};
          await _persist(force: true);
          _emit();
          return;
        }
        if (kind == ResearchFailureKind.cancelled) {
          _demand = {};
          await pause(reason: TranslationPauseReason.quit);
          return;
        }
        if (_translator is! ScheduledParagraphTranslator &&
            {ResearchFailureKind.protocol, ResearchFailureKind.refusal}.contains(kind) &&
            pack.length > 1) {
          // Release the output reservation before the recursive single calls.
          _reserved -= reservation;
          try {
            for (final p in pack) {
              await _request([p], explicit: explicit, slot: slot, bulkJobId: bulkJobId);
            }
          } finally {
            _reserved += reservation;
          }
          return;
        }
        if (kind == ResearchFailureKind.rateLimited) {
          _consecutive429 = _last429 != null && _now().difference(_last429!) < const Duration(minutes: 10)
              ? _consecutive429 + 1
              : 1;
          _last429 = _now();
        }
        if (kind != ResearchFailureKind.rateLimited && _consecutive429 < 2) _consecutive429 = 0;
        final transient = {
          ResearchFailureKind.timeout,
          ResearchFailureKind.rateLimited,
          ResearchFailureKind.unavailable,
          ResearchFailureKind.network,
        }.contains(kind);
        if (_translator is! ScheduledParagraphTranslator && transient && attempt < 3) {
          for (final p in pack) {
            _retries[keyOf(p)] = attempt + 1;
          }
          _emit();
          final jitter = Duration(milliseconds: ([2000, 8000, 30000][attempt] * (.8 + _random() * .4)).round());
          final retryAfter = _retryAfter(error);
          await _sleep(retryAfter > jitter ? retryAfter : jitter);
          continue;
        }
        if (!bulkJobRunning()) return;
        await _recordFailure(pack, kind, attempt + 1);
        return;
      } finally {
        requestCancel.cancel();
        _requestCancels.remove(requestCancel);
        _reserved -= reservation;
      }
    }
  }

  Future<void> _recordFailure(List<TranslationParagraph> pack, ResearchFailureKind kind, int attempts) async {
    final keys = pack.map(keyOf).toSet();
    for (final p in paragraphs.where((p) => keys.contains(keyOf(p)))) {
      _failed.add(p.fingerprint);
      _job = _job?.copyWith(
        failures: {
          ..._job!.failures,
          p.fingerprint: TranslationFailure(kind: kind.name, attempts: attempts, at: _now()),
        },
      );
    }
    _failure = ResearchFailure(kind);
    await _persist();
    _emit();
  }

  void _checkBudget() {
    final j = _job;
    if (j?.state == TranslationJobState.running &&
        !j!.budgetAcknowledged &&
        _usage.totalTokens > j.estimateTokens * 1.5) {
      _job = j.copyWith(state: TranslationJobState.budget, updatedAt: _now());
      _emit();
    }
  }

  String? _taskError(Object error, ResearchFailureKind kind) {
    Object? code = error is ResearchFailure ? error.code : null;
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['error'] is Map) {
        final fields = data['error'] as Map;
        code = fields['code'] ?? fields['type'];
      }
      if (error.response?.statusCode == 402) return 'quota';
      if (error.response?.statusCode == 404) return 'model';
    }
    if (code == 'storage') return 'storage';
    if (kind == ResearchFailureKind.authentication) return 'authentication';
    if ({'quota', 'insufficient_quota', 'quota_exceeded', 'billing_hard_limit_reached'}.contains(code)) return 'quota';
    if ({'model', 'model_not_found'}.contains(code)) return 'model';
    return kind == ResearchFailureKind.invalidRequest ? 'invalidRequest' : null;
  }

  Duration _retryAfter(Object error) {
    if (error is! DioException) return Duration.zero;
    final value = error.response?.headers.value('retry-after');
    if (value == null) return Duration.zero;
    final seconds = int.tryParse(value);
    if (seconds != null) return Duration(seconds: math.max(0, seconds));
    try {
      final duration = parseHttpDate(value).difference(_now());
      return duration.isNegative ? Duration.zero : duration;
    } on FormatException {
      return Duration.zero;
    }
  }

  void _clearFailures(TranslationParagraph p) {
    final fingerprints = paragraphs.where((q) => keyOf(q) == keyOf(p)).map((q) => q.fingerprint).toSet();
    _failed.removeAll(fingerprints);
    if (_job != null) {
      _job = _job!.copyWith(failures: {..._job!.failures}..removeWhere((fp, _) => fingerprints.contains(fp)));
    }
  }

  Future<void> _persist({bool force = false}) async {
    if (_job == null) return;
    _job = _job!.copyWith(usage: _usage, updatedAt: _now());
    if (!force && _lastSaved != null && _now().difference(_lastSaved!) < const Duration(seconds: 2)) {
      _ledgerTimer ??= _schedule(const Duration(seconds: 2) - _now().difference(_lastSaved!), () {
        _ledgerTimer = null;
        unawaited(_flushLedger());
      });
      return;
    }
    _ledgerTimer?.cancel();
    _ledgerTimer = null;
    final savedAt = _now();
    final snapshot = _job!;
    final write = _writes.then((_) async {
      await store.saveJob(snapshot);
      if (_translator case final ScheduledParagraphTranslator t) await t.saveJob(snapshot);
    });
    _writes = write.catchError((Object _) {});
    try {
      await write;
      _lastSaved = savedAt;
    } catch (_) {
      _storageFailed();
      rethrow;
    }
  }

  // Saving is part of the task lifecycle, including before dispatch and when
  // retrying a validated result. Publish even if disk cannot persist the error.
  void _storageFailed() {
    if (_job != null && _job!.state != TranslationJobState.stopped) {
      _job = _job!.copyWith(state: TranslationJobState.error, errorKind: 'storage', usage: _usage, updatedAt: _now());
    }
    _demand = {};
    _failure = const ResearchFailure(ResearchFailureKind.unavailable, 'storage');
    _emit();
  }

  Future<void> _refreshConnection() async {
    if (!_refreshTranslator) return;
    while (_active.isNotEmpty) {
      await Future.wait(_active.values.toSet());
    }
    if (!_refreshTranslator) return;
    _translator?.close();
    _translator = null;
    _refreshTranslator = false;
  }

  Future<void> _flushLedger() async {
    try {
      await _persist(force: true);
    } catch (_) {
      // _persist has already published the storage failure.
    }
  }

  void _emit() {
    _progress?.complete();
    _progress = null;
    if (_closed) return;
    _events.add(state);
    changed?.call();
  }

  /// Shutdown drains paid calls before closing the transport and state stream.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _ledgerTimer?.cancel();
    _ledgerTimer = null;
    _closingRequested = true;
    if (_translator case final ScheduledParagraphTranslator t) t.pauseDispatch();
    _emit();
    try {
      if (_job?.state == TranslationJobState.running || _job?.state == TranslationJobState.offline) {
        await pause(reason: TranslationPauseReason.quit);
      } else {
        // Review and other already-closed gates survive a window/process exit.
        _demand = {};
        await _persist(force: true);
      }
      await _runFuture;
    } finally {
      await Future.wait(_active.values.toSet());
      await _segmentWrites;
      try {
        await _persist(force: true);
      } finally {
        _closed = true;
        _translator?.close();
        await _events.close();
      }
    }
  }
}

(Map<String, String>, Set<String>) _prepare(
  List<TranslationParagraph> paragraphs,
  String language,
  Map<int, double> pageHeights,
) {
  final margins = translationMarginFingerprints(paragraphs, pageHeights: pageHeights);
  return (
    {for (final p in paragraphs) p.fingerprint: textKey(p.text, language)},
    {
      for (final p in paragraphs)
        if (translationSkipReason(p, language, marginFingerprints: margins) != null) p.fingerprint,
    },
  );
}

int _positiveUsage(int? reported, int estimate) => reported != null && reported > 0 ? reported : estimate;
