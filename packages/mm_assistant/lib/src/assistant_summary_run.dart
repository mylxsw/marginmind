import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mm_core/mm_core.dart';

import 'assistant_summary.dart';
import 'assistant_tasks.dart';

/// Storage failures retain the planned operation/result. They are never a reason
/// to purchase another model response.
class SummaryPersistenceFailure implements Exception {}

class SummaryStageFailure implements Exception {
  const SummaryStageFailure(this.code);
  final String code;
}

typedef PersistentSummaryDispatch = Future<RunResult<String>> Function(TaskRequest<String> request, RunContext context);

/// Deterministic domain workflow; every inference is delegated to AgentRuntime.
/// The parent has its own CAS manifest and never doubles as a model-backed stage.
class PersistentAssistantSummary {
  PersistentAssistantSummary._(
    this.store,
    this.reader,
    this.spec,
    this.context,
    this.data,
    this._revision,
    this.status,
    this.phases,
  );
  final RunStore store;
  final RunReader reader;
  final TaskSpec spec;
  RunContext context;
  Map<String, dynamic> data;
  int _revision;
  RunStatus status;
  List<RunContext> phases;
  bool saveFailed = false;
  Future<void> _writes = Future.value();
  static const marker = 'assistantSummary';

  static Future<PersistentAssistantSummary> open({
    required RunStore store,
    required RunReader reader,
    required TaskSpec spec,
    required RunContext context,
    List<SummaryUnit>? units,
    String? question,
    int? requestCharacters,
    Map<String, dynamic>? evidence,
  }) async {
    final saved = await store.load(context.runId);
    if (saved != null) {
      if (saved.taskType != spec.type ||
          saved.promptVersion != spec.promptVersion ||
          saved.schemaVersion != spec.schemaVersion ||
          saved.checkpoint[marker] != 1 ||
          jsonEncode(saved.context.inputRange) != jsonEncode(context.inputRange)) {
        throw const ConfigurationFailure('summaryCheckpointMismatch');
      }
      return PersistentAssistantSummary._(
        store,
        reader,
        spec,
        saved.context,
        jsonDecode(jsonEncode(saved.checkpoint)),
        saved.revision,
        saved.status,
        saved.configurationPhases,
      );
    }
    if (units == null || units.isEmpty || question == null || requestCharacters == null) {
      throw const ConfigurationFailure('summaryInputRequired');
    }
    final run = PersistentAssistantSummary._(
      store,
      reader,
      spec,
      context,
      {
        marker: 1,
        'question': question,
        'capacity': requestCharacters,
        'units': [for (final u in units) u.toJson()],
        'evidence': evidence,
        'stages': <String, dynamic>{},
        'leafIds': <String>[],
        'coveredLeaves': <String>[],
      },
      -1,
      RunStatus.created,
      [context],
    );
    await run._save(RunStatus.created);
    return run;
  }

  List<SummaryUnit> get units => [for (final u in data['units'] as List) SummaryUnit(u['id'], u['text'])];
  Map<String, dynamic>? get evidence => data['evidence'] == null ? null : Map<String, dynamic>.from(data['evidence']);
  List<String> get leafIds => List<String>.from(data['leafIds']);
  List<String> get coveredLeaves => List<String>.from(data['coveredLeaves']);
  Map<String, dynamic> get stages => data['stages'] as Map<String, dynamic>;
  String get fingerprint => _hash({'question': data['question'], 'units': data['units'], 'capacity': data['capacity']});
  AssistantSummary? get pending => data['pending'] == null ? null : AssistantSummary.parse(jsonEncode(data['pending']));

  /// Terminal roots remain immutable. An explicit resume creates a deterministic
  /// successor, carrying the verified stage index rather than replaying success.
  Future<PersistentAssistantSummary> continuation() async {
    if (!{RunStatus.partial, RunStatus.failed, RunStatus.cancelled}.contains(status)) return this;
    final next = context.child('summary-${_hash({'previous': context.runId}).substring(0, 40)}');
    final existing = await store.load(next.runId);
    if (existing != null) return open(store: store, reader: reader, spec: spec, context: next);
    final copy = PersistentAssistantSummary._(
      store,
      reader,
      spec,
      next,
      jsonDecode(jsonEncode(data)),
      -1,
      RunStatus.created,
      [...phases, next],
    );
    copy.data.remove('failure');
    await copy._save(RunStatus.created);
    return copy;
  }

  Future<void> useConfiguration(RunContext next) async {
    if (next.runId != context.runId ||
        next.phase != context.phase + 1 ||
        !{RunStatus.paused, RunStatus.created, RunStatus.interrupted}.contains(status) ||
        pending != null ||
        jsonEncode(next.inputRange) != jsonEncode(context.inputRange)) {
      throw StateError('Summary configuration requires a paused workflow');
    }
    final old = context;
    final oldPhases = phases;
    context = next;
    phases = [...phases, next];
    try {
      await _save(RunStatus.paused);
    } catch (_) {
      context = old;
      phases = oldPhases;
      rethrow;
    }
  }

  Future<void> pause() => _save(RunStatus.paused);

  Future<AssistantSummary> run({
    required PersistentSummaryDispatch dispatch,
    required CancellationToken cancel,
    Future<void> Function()? beforeStage,
    void Function()? changed,
  }) async {
    if (status == RunStatus.completed) {
      final result = await reader.loadResult(context.runId);
      if (result?['summary'] == null) throw const ConfigurationFailure('summaryResultMissing');
      return AssistantSummary.parse(jsonEncode(result!['summary']));
    }
    if ({RunStatus.partial, RunStatus.failed, RunStatus.cancelled}.contains(status)) {
      throw StateError('Resume a terminal summary through continuation');
    }
    try {
      if (pending != null) return await _commit();
      final summary = await summarizeAssistantUnits(
        units: units,
        requestCharacters: data['capacity'],
        cancel: cancel,
        onCoverage: (ids) => data['leafIds'] = ids,
        execute: (group, stage) async {
          await beforeStage?.call();
          cancel.check();
          final input = <String, dynamic>{
            'question': data['question'],
            'units': [for (final u in group) u.toJson()],
          };
          final key = _hash(input);
          final entry = (stages[key] ??= <String, dynamic>{'attempts': <dynamic>[]}) as Map;
          final attempts = entry['attempts'] as List;
          RunManifest? previous;
          if (attempts.isNotEmpty) previous = await store.load(attempts.last['runId']);
          if (previous?.status == RunStatus.completed) {
            final value = await reader.loadResult(previous!.context.runId);
            final raw = value?['value']?['text'];
            if (previous.inputFingerprint != key ||
                previous.taskType != spec.type ||
                previous.promptVersion != spec.promptVersion ||
                previous.schemaVersion != spec.schemaVersion ||
                jsonEncode(previous.context.inputRange) != jsonEncode(context.inputRange) ||
                raw is! String) {
              throw const ConfigurationFailure('summaryStageResultMismatch');
            }
            _validate(raw, group);
            _recordCoverage(group);
            return RunResult<String>(
              runId: previous.context.runId,
              status: RunStatus.completed,
              value: raw,
              validation: ValidationReport(),
              usage: previous.usage,
            );
          }
          if (attempts.isEmpty ||
              previous != null &&
                  {RunStatus.failed, RunStatus.partial, RunStatus.cancelled}.contains(previous.status)) {
            final child = context.child(
              'stage-${_hash({'parent': context.runId, 'key': key, 'attempt': attempts.length}).substring(0, 48)}',
            );
            attempts.add({'runId': child.runId, 'context': encodeRunContext(child)});
          }
          final child = decodeRunContext(Map<String, dynamic>.from(attempts.last['context']));
          data['activeStage'] = key;
          await _save(RunStatus.running); // claim the stage before any dispatch
          changed?.call();
          final result = await dispatch(TaskRequest<String>(spec: spec, input: input, inputFingerprint: key), child);
          if (result.status != RunStatus.completed || result.value == null) {
            throw const SummaryStageFailure('partialSummaryStage');
          }
          _validate(result.value!, group);
          _recordCoverage(group);
          await _save(RunStatus.running); // an ACK failure is recovered from the child artifact
          changed?.call();
          return result;
        },
      );
      data['pending'] = summary.toJson();
      await _save(RunStatus.validating);
      changed?.call();
      final result = await _commit();
      changed?.call();
      return result;
    } on SummaryPersistenceFailure {
      rethrow;
    } on RunStoreConflict {
      rethrow;
    } catch (error) {
      data['failure'] = error is ConfigurationFailure
          ? error.code
          : error is SummaryStageFailure
          ? error.code
          : 'summaryStageFailed';
      await _save(cancel.isCancelled ? RunStatus.cancelled : RunStatus.partial, terminal: true);
      changed?.call();
      rethrow;
    }
  }

  void _recordCoverage(List<SummaryUnit> group) {
    final leaves = leafIds.toSet();
    data['coveredLeaves'] = ({...coveredLeaves, ...group.map((u) => u.id).where(leaves.contains)}.toList()..sort());
  }

  void _validate(String raw, List<SummaryUnit> group) {
    final value = AssistantSummary.parse(raw);
    final expected = group.map((u) => u.id).toSet();
    if (value.coveredIds.length != expected.length || !value.coveredIds.toSet().containsAll(expected)) {
      throw const ConfigurationFailure('summaryStageCoverageMismatch');
    }
  }

  Future<AssistantSummary> _commit() async {
    final summary = pending!;
    // A lost completion ACK is recognized before attempting any further write.
    final saved = await store.load(context.runId);
    if (saved?.status == RunStatus.completed) {
      final result = await reader.loadResult(context.runId);
      if (jsonEncode(result?['summary']) != jsonEncode(summary.toJson())) throw const RunStoreConflict();
      _revision = saved!.revision;
      status = RunStatus.completed;
      saveFailed = false;
      return summary;
    }
    await _save(RunStatus.completed, terminal: true);
    return summary;
  }

  Future<RunUsage> _usage() async {
    final manifests = <RunManifest>[];
    final seen = <String>{};
    for (final entry in stages.values) {
      for (final attempt in entry['attempts']) {
        if (seen.add(attempt['runId'])) {
          final saved = await store.load(attempt['runId']);
          if (saved != null) manifests.add(saved);
        }
      }
    }
    return sumAssistantUsage([
      for (final manifest in manifests) await loadAssistantTaskUsage(store, manifest.context.runId),
    ]);
  }

  Future<void> _save(RunStatus next, {bool terminal = false}) {
    final snapshot = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
    final snapshotContext = context;
    final snapshotPhases = List<RunContext>.of(phases);
    final work = _writes.then((_) async {
      final actual = !terminal && next == RunStatus.running && snapshot['paused'] == true ? RunStatus.paused : next;
      try {
        final manifest = RunManifest(
          context: snapshotContext,
          taskType: spec.type,
          inputFingerprint: fingerprint,
          promptVersion: spec.promptVersion,
          schemaVersion: spec.schemaVersion,
          status: actual,
          revision: _revision + 1,
          stage: 'summary_workflow',
          failureCode: snapshot['failure'],
          checkpoint: snapshot,
          configurationPhases: snapshotPhases,
          usage: await _usage(),
        );
        if (terminal) {
          await store.complete(manifest, {
            'summary': snapshot['pending'],
            'leafIds': snapshot['leafIds'],
            'coveredLeaves': snapshot['coveredLeaves'],
          }, expectedRevision: _revision);
        } else {
          await store.checkpoint(manifest, expectedRevision: _revision < 0 ? null : _revision);
        }
        _revision = manifest.revision;
        status = actual;
        saveFailed = false;
      } on RunStoreConflict {
        rethrow;
      } catch (_) {
        saveFailed = true;
        throw SummaryPersistenceFailure();
      }
    });
    _writes = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return work;
  }
}

String _hash(Object value) => sha256.convert(utf8.encode(jsonEncode(value))).toString();
