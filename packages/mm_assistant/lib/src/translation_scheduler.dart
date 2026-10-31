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
  Future<ParagraphTranslator> _getTranslator() => _translator != null
      ? Future.value(_translator)
      : _opening ??= createTranslator!().then((t) => _translator = t).whenComplete(() => _opening = null);
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
  TranslationJob? _job;
  Object? _failure;
  TranslationUsage _usage = TranslationUsage();

  TranslationJob? get job => _job;
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
  int _page(TranslationParagraph p) => p.textAnchor == null ? p.page : p.index + 1;
  bool get _gate =>
      !_closed &&
      !_closingRequested &&
      _online &&
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
    _emit();
  }

  void prioritize(Iterable<int> visible, {int? focus}) {
    _visible = visible.toSet();
    if (focus != null) _focus = focus;
  }

  Future<void> start(TranslationJob job) async {
    _commandVersion++;
    if (_closed || _closingRequested || _job?.isActive == true) throw StateError('Scheduler is busy');
    if (job.documentId != documentId || job.targetLang != language) throw ArgumentError('Different task scope');
    _job = job.copyWith(state: _online ? TranslationJobState.running : TranslationJobState.offline, updatedAt: _now());
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
  }

  /// Viewing a page never bypasses an unfinished full-document job.
  Future<void> demand(Iterable<int> pages) async {
    if (_job?.isActive == true || _closed || _closingRequested) return;
    _demand = pages.toSet();
    _failure = null;
    await _run();
  }

  Future<void> pause({TranslationPauseReason reason = TranslationPauseReason.user}) async {
    _commandVersion++;
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
    _job = _job!.copyWith(
      state: _online ? TranslationJobState.running : TranslationJobState.offline,
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
      state: _online ? TranslationJobState.running : TranslationJobState.offline,
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
    _emit();
    await _persist(force: true);
  }

  Future<void> setOnline(bool online) async {
    if (_closed || _closingRequested) return;
    _online = online;
    if (!online && _job?.state == TranslationJobState.running) {
      _job = _job!.copyWith(state: TranslationJobState.offline, updatedAt: _now());
      await _persist(force: true);
      _emit();
    } else if (online && _job?.state == TranslationJobState.offline) {
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

  Future<void> retranslate(TranslationParagraph p) => _explicit(p, replace: true);

  Future<void> _explicit(TranslationParagraph p, {required bool replace}) async {
    if (_closed || _closingRequested || !_online) return;
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
      if (_closed || _closingRequested || !_online) return;
      final racing = _active[keyOf(p)];
      if (racing != null) {
        await racing;
        return;
      }
      if (!replace && _segments.containsKey(keyOf(p))) return;
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
    if (_candidates().isNotEmpty && _gate) {
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
    final done = Completer<void>();
    for (final p in pack) {
      _active[keyOf(p)] = done.future;
    }
    _emit();
    try {
      await _request(pack, explicit: explicit, slot: slot);
    } finally {
      for (final p in pack) {
        _active.remove(keyOf(p));
        _retries.remove(keyOf(p));
      }
      done.complete();
      _emit();
    }
  }

  Future<void> _request(List<TranslationParagraph> pack, {required bool explicit, int slot = 0}) async {
    // Capture provenance before awaiting: edits to requirements affect later requests.
    final note = _job?.note ?? '';
    final profile = translationProfile(note, promptVersion: _job?.promptVersion ?? 1);
    final inputEstimate = 512 + utf8.encode(note + pack.map((p) => p.text).join()).length;
    for (var attempt = 0; attempt <= 3; attempt++) {
      if (_closed || _closingRequested || !_online || (!explicit && (!_gate || slot >= concurrency))) return;
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
      try {
        await _persist();
        if (_closed || _closingRequested || !_online || (!explicit && (!_gate || slot >= concurrency))) return;
        final PackedParagraphTranslation response;
        saving = false;
        final t = await _getTranslator();
        if (_closed || _closingRequested || !_online || (!explicit && (!_gate || slot >= concurrency))) return;
        final requestModel = t is ModelParagraphTranslator ? t.model : model;
        if (pack.fold<int>(512 + note.length, (n, p) => n + p.text.length) > budget.inputCharacters) {
          await _recordFailure(pack, ResearchFailureKind.protocol, 0);
          return;
        }
        _usage = TranslationUsage(
          inputTokens: _usage.inputTokens,
          outputTokens: _usage.outputTokens,
          requests: _usage.requests + 1,
        );
        if (!explicit && _job?.isActive == true) _batchRequested = true;
        sent = true;
        if (t is PackedParagraphTranslator) {
          response = await t
              .translatePack(pack, language, requestCancel, allowance, sourceLanguage: _job?.sourceLang, note: note)
              .timeout(budget.duration);
        } else {
          final r = await t
              .translate(pack.single, language, requestCancel, allowance, sourceLanguage: _job?.sourceLang)
              .timeout(budget.duration);
          response = PackedParagraphTranslation([r.text], inputTokens: r.inputTokens, outputTokens: r.tokens);
        }
        _usage = TranslationUsage(
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
          await store.append(documentId, language, segment);
          _segments[segment.key] = segment;
          _completed.add(segment.key);
          _clearFailures(p);
          _emit();
        }
        await _persist();
        return;
      } catch (error) {
        if (_closed) return;
        if (saving) {
          _failure = const ResearchFailure(ResearchFailureKind.unavailable, 'storage');
          _demand = {};
          if (_job?.isActive == true) {
            _job = _job!.copyWith(state: TranslationJobState.error, errorKind: 'storage', updatedAt: _now());
          }
          _emit();
          // Never buy a translation again because its journal write failed.
          rethrow;
        }
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
        final reason = _taskError(error, kind);
        if (reason != null) {
          if (_job?.isActive == true) {
            _job = _job!.copyWith(state: TranslationJobState.error, errorKind: reason, updatedAt: _now());
          }
          _refreshTranslator = createTranslator != null;
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
        if ({ResearchFailureKind.protocol, ResearchFailureKind.refusal}.contains(kind) && pack.length > 1) {
          // Release the output reservation before the recursive single calls.
          _reserved -= reservation;
          try {
            for (final p in pack) {
              await _request([p], explicit: explicit, slot: slot);
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
        if (transient && attempt < 3) {
          for (final p in pack) {
            _retries[keyOf(p)] = attempt + 1;
          }
          _emit();
          final jitter = Duration(milliseconds: ([2000, 8000, 30000][attempt] * (.8 + _random() * .4)).round());
          final retryAfter = _retryAfter(error);
          await _sleep(retryAfter > jitter ? retryAfter : jitter);
          continue;
        }
        await _recordFailure(pack, kind, attempt + 1);
        return;
      } finally {
        requestCancel.cancel();
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
    _lastSaved = _now();
    final snapshot = _job!;
    final write = _writes.then((_) => store.saveJob(snapshot));
    _writes = write.catchError((Object _) {});
    await write;
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
      if (_job?.isActive == true) _job = _job!.copyWith(state: TranslationJobState.error, errorKind: 'storage');
      _demand = {};
      _failure = const ResearchFailure(ResearchFailureKind.unavailable, 'storage');
      _emit();
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
