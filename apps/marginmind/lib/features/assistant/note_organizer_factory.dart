import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import 'task_run_store.dart';

/// The domain contributes only its registry/knowledge. The common assembly's
/// default registry and settings aggregation remain owned by the integration.
TaskRegistry studyNotesTaskRegistry() {
  final registry = TaskRegistry();
  registerStudyNotesTask(registry);
  return registry;
}

Future<RuntimeNoteOrganizer> createModelNoteOrganizer({
  required PersistentTaskAssembly assembly,
  required String sessionId,
  ModelReference? modelOverride,
  bool online = true,
}) async => RuntimeNoteOrganizer(
  await PersistentNoteStages.open(assembly, sessionId, modelOverride: modelOverride, online: online),
);

class NoteStageFailure implements Exception {
  const NoteStageFailure(this.code);
  final String code;
  @override
  String toString() => 'NoteStageFailure($code)';
}

/// Holds only the current pending-save handle. Durable successful stages are
/// addressed by session + input fingerprint, so reopening never repurchases them.
class PersistentNoteStages implements NoteStageExecutor {
  PersistentNoteStages._(this.assembly, this.context, this.online);
  final PersistentTaskAssembly assembly;
  final RunContext context;
  final bool online;
  final _pending = <String, RuntimeRunHandle<Map<String, dynamic>>>{};

  static Future<PersistentNoteStages> open(
    PersistentTaskAssembly assembly,
    String id, {
    ModelReference? modelOverride,
    bool online = true,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,47}$').hasMatch(id)) {
      throw const ConfigurationFailure('noteSessionId');
    }
    final saved = await assembly.runs.load(id);
    final context =
        saved?.context ??
        await assembly.freeze(
          TaskRequest<Map<String, dynamic>>(
            spec: studyNotesSpec,
            input: const {'operation': 'text', 'data': <String, dynamic>{}},
            inputFingerprint: id,
            modelOverride: modelOverride,
          ),
          runId: id,
          knowledgeVersions: {'notes.organize': '2'},
        );
    if (saved == null) {
      await assembly.runs.checkpoint(
        RunManifest(
          context: context,
          taskType: TaskType.studyNotes,
          inputFingerprint: id,
          promptVersion: studyNotesSpec.promptVersion,
          schemaVersion: studyNotesSpec.schemaVersion,
          status: RunStatus.awaitingUser,
          revision: 0,
          stage: 'notes_session',
        ),
        expectedRevision: null,
      );
    } else if (saved.taskType != TaskType.studyNotes ||
        saved.promptVersion != studyNotesSpec.promptVersion ||
        saved.schemaVersion != studyNotesSpec.schemaVersion ||
        saved.stage != 'notes_session' ||
        saved.context.knowledgeVersions['notes.organize'] != '2') {
      throw const ConfigurationFailure('noteSessionVersion');
    }
    return PersistentNoteStages._(assembly, context, online);
  }

  Future<void> _record(RunManifest stage) async {
    final root = await assembly.runs.load(context.runId);
    if (root == null || {RunStatus.completed, RunStatus.partial}.contains(root.status)) return;
    final stages = Map<String, dynamic>.from(root.checkpoint['stages'] as Map? ?? {});
    stages[stage.context.runId] = {'usage': encodeRunUsage(stage.usage), 'status': stage.status.name};
    final values = stages.values.map((v) => decodeRunUsage(v['usage'] as Map)).toList();
    final usage = RunUsage(
      quality: values.every((u) => u.quality == UsageQuality.reported) ? UsageQuality.reported : UsageQuality.unknown,
      modelCalls: values.fold(0, (n, u) => n + u.modelCalls),
      repairs: values.fold(0, (n, u) => n + u.repairs),
      inputTokens: values.fold(0, (n, u) => n + u.inputTokens),
      outputTokens: values.fold(0, (n, u) => n + u.outputTokens),
      elapsed: values.fold(Duration.zero, (n, u) => n + u.elapsed),
    );
    await assembly.runs.checkpoint(
      RunManifest(
        context: context,
        taskType: TaskType.studyNotes,
        inputFingerprint: root.inputFingerprint,
        promptVersion: root.promptVersion,
        schemaVersion: root.schemaVersion,
        revision: root.revision + 1,
        status: RunStatus.awaitingUser,
        stage: 'notes_session',
        usage: usage,
        checkpoint: {...root.checkpoint, 'stages': stages},
      ),
      expectedRevision: root.revision,
    );
  }

  @override
  Future<void> finish(Set<String> covered, Set<String> missing) async {
    final root = await assembly.runs.load(context.runId);
    if (root == null || {RunStatus.completed, RunStatus.partial}.contains(root.status)) return;
    await assembly.runs.complete(
      RunManifest(
        context: context,
        taskType: TaskType.studyNotes,
        inputFingerprint: root.inputFingerprint,
        promptVersion: root.promptVersion,
        schemaVersion: root.schemaVersion,
        revision: root.revision + 1,
        status: missing.isEmpty ? RunStatus.completed : RunStatus.partial,
        stage: 'notes_session',
        usage: root.usage,
        checkpoint: {...root.checkpoint, 'covered': covered.toList(), 'missing': missing.toList()},
      ),
      {'covered': covered.toList(), 'missing': missing.toList()},
      expectedRevision: root.revision,
    );
  }

  @override
  String get model => context.modelDisplayName;
  @override
  int get requestCharacters {
    final caps = context.config.capabilities;
    // Match Runtime's conservative UTF-16 budget; reserve space for schemas,
    // knowledge, tool output, protocol wrapping and one validation repair turn.
    final capacity = caps.contextTokens == null ? 60000 : caps.contextTokens! - (caps.outputTokens ?? 0);
    return ((capacity - 16000) ~/ 4).clamp(0, 120000);
  }

  @override
  Future<Map<String, dynamic>> execute(String operation, Map<String, dynamic> data, CancellationToken cancel) async {
    cancel.check();
    final input = <String, dynamic>{'operation': operation, 'data': data};
    final fingerprint = sha256.convert(utf8.encode(jsonEncode(input))).toString();
    final baseId = '${context.runId}-$fingerprint';
    var id = baseId;
    final request = TaskRequest<Map<String, dynamic>>(
      spec: studyNotesSpec,
      input: input,
      inputFingerprint: fingerprint,
    );
    var saved = await assembly.runs.load(id);
    var retry = 0;
    while (saved != null && {RunStatus.failed, RunStatus.cancelled}.contains(saved.status)) {
      id = '$baseId-r${++retry}';
      saved = await assembly.runs.load(id);
    }
    Map<String, dynamic>? encoded;
    if (saved != null && {RunStatus.completed, RunStatus.partial}.contains(saved.status)) {
      encoded = await assembly.runs.loadResult(id);
    }
    RunResult<Map<String, dynamic>>? result;
    if (encoded == null) {
      if (!online &&
          context.config.capabilities.identity.protocol != ModelProtocol.ollamaChat &&
          saved?.checkpoint['pending'] == null &&
          _pending[id]?.persistenceError == null) {
        throw const ResearchFailure(ResearchFailureKind.network);
      }
      RuntimeRunHandle<Map<String, dynamic>> handle;
      var shouldResume = false;
      if (_pending[id] case final pending?) {
        handle = pending;
        shouldResume = true; // pending result: save only, never generate
      } else if (saved != null && !{RunStatus.failed, RunStatus.cancelled}.contains(saved.status)) {
        handle = await assembly.runtime.recover(request, saved.context);
        shouldResume = true; // this method is reached only by explicit UI retry
      } else {
        // Failed/cancelled unknown outcomes are never automatically replayed.
        // A user retry gets a new attempt identity, retaining the original.
        final attempt = id;
        final child = decodeRunContext({
          ...encodeRunContext(context.child(attempt)),
          'inputRange': {
            'ids': [for (final m in data['materials'] as List? ?? []) m['id']],
          },
        });
        handle = assembly.runtime.start(request, child);
      }
      _pending[id] = handle;
      final saveFailed = Completer<RunResult<Map<String, dynamic>>>();
      final subscription = handle.events.listen((event) {
        if (event.stage == 'save_failed' && !saveFailed.isCompleted) {
          saveFailed.completeError(const NoteStageFailure('save_failed'));
        }
      });
      var finished = false;
      Future<void>? cancelling;
      unawaited(
        cancel.whenCancelled.then((_) {
          if (!finished) {
            cancelling = handle.cancel();
            cancelling!.ignore();
          }
        }),
      );
      try {
        if (shouldResume) await handle.resume();
        result = await cancel.bind(Future.any([handle.result, saveFailed.future]));
        cancel.check();
        _pending.remove(id);
        encoded = await assembly.runs.loadResult(result!.runId);
      } finally {
        finished = true;
        try {
          if (cancelling != null) {
            await cancelling;
            await Future.any([handle.result, saveFailed.future]);
            _pending.remove(id);
            final cancelled = await assembly.runs.load(id);
            if (cancelled != null) await _record(cancelled);
          }
        } finally {
          await subscription.cancel();
        }
      }
    }
    if (encoded == null) throw const NoteStageFailure('missingResult');
    final stage = await assembly.runs.load(result?.runId ?? id);
    if (stage != null) await _record(stage);
    final status = result?.status ?? RunStatus.values.byName(encoded['status'] as String);
    final value = encoded['value'];
    if (value is! Map || !{RunStatus.completed, RunStatus.partial}.contains(status)) {
      throw NoteStageFailure(result?.failureCode ?? 'validation');
    }
    final output = Map<String, dynamic>.from(value);
    final validation = const StudyNotesValidator().validate(output, input);
    if (validation.issues.isNotEmpty) throw const NoteStageFailure('validation');
    if (validation.missingInputIds.isEmpty) return output;
    // Repair only the missing range. Validated sections/materials are immutable.
    final missing = validation.missingInputIds;
    final narrowed = {
      ...data,
      'materials': [
        for (final m in data['materials'] as List)
          if (missing.contains(m['id'])) m,
      ],
    };
    if (data['repairOf'] != null) {
      throw const NoteStageFailure('noProgress');
    }
    final repair = await execute(operation, {...narrowed, 'repairOf': id}, cancel);
    if (operation == 'place') {
      return {
        'placements': [...output['placements'], ...repair['placements']],
      };
    }
    if (operation == 'outline') {
      return {
        'sections': [...output['sections'], ...repair['sections']],
      };
    }
    final section = Map<String, dynamic>.from((output['sections'] as List).single as Map);
    final next = (repair['sections'] as List).single as Map;
    return {
      'sections': [
        {
          ...section,
          'blocks': [...section['blocks'], ...next['blocks']],
        },
      ],
    };
  }
}
