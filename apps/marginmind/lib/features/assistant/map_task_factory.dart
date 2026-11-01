import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import 'assistant_settings.dart';
import 'assistant_services.dart';
import 'assistant_routing.dart';
import 'task_run_store.dart';
import 'map_task_route.dart';
import 'map_task_journal.dart';

/// One feature invocation pins a route before reading its model-dependent cache.
class MapTaskSession {
  MapTaskSession(Ref ref, this.studySetId, this.spec, {this.workflow}) : ref = ref.read(mapTaskHostRefProvider);
  Map<String, dynamic>? workflow;
  bool explicitContinuation = false;
  int continuationRound = 0;
  final _stages = <String, Map<String, dynamic>>{};
  final _chapters = <String, Map<String, dynamic>>{};
  final _handles = <String, RuntimeRunHandle<String>>{};
  final _running = <String, Future<String>>{};
  final saveFailed = <String>{};
  bool retryingSave = false;
  String? id;
  String get directory => ref.read(contentRepositoryProvider).resolveFile(studySetId, '');
  MapTaskJournal get journal => MapTaskJournal(directory);

  static Future<MapTaskSession> restore(Ref ref, String studySetId, TaskSpec spec, String id) async {
    final retained = ref
        .read(mapSaveFailuresProvider)
        .where((s) => s.studySetId == studySetId && s.id == id)
        .firstOrNull;
    if (retained != null) {
      if (retained.spec.type != spec.type) throw const ConfigurationFailure('mapSessionMismatch');
      retained.explicitContinuation = true;
      retained.continuationRound++;
      return retained;
    }
    final session = MapTaskSession(ref, studySetId, spec);
    final data = await session.journal.load(id);
    if (data['type'] != spec.type.name ||
        data['promptVersion'] != spec.promptVersion ||
        data['schemaVersion'] != spec.schemaVersion ||
        data['dismissed'] == true) {
      throw const ConfigurationFailure('mapSessionMismatch');
    }
    session.id = id;
    session.continuationRound = (data['continuations'] as int? ?? 0) + 1;
    session.workflow = Map<String, dynamic>.from(data['workflow']);
    final context = decodeRunContext(Map<String, dynamic>.from(data['context']));
    if (context.runId != id || context.inputRange['studySetId'] != studySetId) {
      throw const ConfigurationFailure('mapSessionMismatch');
    }
    session._frozen = Future.value(context);
    session._stages.addAll({
      for (final e in (data['stages'] as Map).entries) e.key as String: Map<String, dynamic>.from(e.value),
    });
    session._chapters.addAll({
      for (final e in (data['chapters'] as Map? ?? {}).entries) e.key as String: Map<String, dynamic>.from(e.value),
    });
    session._rootStarted = session._stages.isNotEmpty;
    session.explicitContinuation = true;
    return session;
  }

  Future<void> saveWorkflow(Map<String, dynamic> value) async {
    workflow = value;
    await freeze();
    await journal.update(id!, (data) {
      data['workflow'] = value;
      data['continuations'] = continuationRound;
    });
    _changed();
  }

  List<MapLine>? chapterPoints(String key, String fingerprint) {
    final saved = _chapters[key];
    if (saved == null) return null;
    if (saved['fingerprint'] != fingerprint || saved['checksum'] != mapTaskFingerprint({'lines': saved['lines']})) {
      throw const ConfigurationFailure('mapChapterMismatch');
    }
    return [
      for (final p in saved['lines'])
        MapLine(
          id: p['id'],
          kind: MapLineKind.point,
          parentId: p['parentId'],
          title: p['title'],
          source: p['source'] == null ? null : CardSource.fromJson(Map<String, Object?>.from(p['source'])),
          quote: p['quote'],
          quoteSource: p['quoteSource'] == null
              ? null
              : CardSource.fromJson(Map<String, Object?>.from(p['quoteSource'])),
          marks: List<String>.from(p['marks']),
        ),
    ];
  }

  Future<void> saveChapterPoints(String key, String fingerprint, List<MapLine> points) async {
    final lines = [
      for (final p in points)
        {
          'id': p.id,
          'parentId': p.parentId,
          'title': p.title,
          'source': p.source?.toJson(),
          'quote': p.quote,
          'quoteSource': p.quoteSource?.toJson(),
          'marks': p.marks,
        },
    ];
    final value = <String, dynamic>{
      'fingerprint': fingerprint,
      'lines': lines,
      'checksum': mapTaskFingerprint({'lines': lines}),
    };
    _chapters[key] = value;
    await journal.update(id!, (data) => (data['chapters'] ??= <String, dynamic>{})[key] = value);
  }

  Future<void> dismiss() async {
    if (id != null) await journal.update(id!, (data) => data['dismissed'] = true);
    _changed();
  }

  void _changed() {
    if (!ref.mounted) return;
    ref.read(mapSaveFailuresProvider.notifier).update(this);
    ref.invalidate(mapRecoverableTasksProvider(studySetId));
  }

  /// Only flush a retained pending result. Failure leaves the same button and
  /// handle available; it never starts a replacement paid request.
  Future<void> retrySave() async {
    if (retryingSave) return;
    retryingSave = true;
    _changed();
    try {
      for (final key in saveFailed.toList()) {
        final handle = _handles[key];
        if (handle == null) continue;
        try {
          await handle.resume();
          saveFailed.remove(key);
        } catch (_) {
          saveFailed.add(key);
        }
      }
    } finally {
      retryingSave = false;
      _changed();
    }
  }

  final Ref ref;
  final String studySetId;
  final TaskSpec spec;
  Future<RunContext>? _frozen;
  bool _rootStarted = false;
  Set<String> missingRangeIds = {};
  String _id() => List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  PersistentTaskAssembly _assembly(TaskRegistry tasks) {
    final directory = ref.read(contentRepositoryProvider).resolveFile(studySetId, '');
    if (studySetId.isEmpty || !p.isAbsolute(directory)) throw const ConfigurationFailure('persistentStudySetRequired');
    return PersistentTaskAssembly(
      studySetDirectory: directory,
      tasks: tasks,
      services: ref.read(assistantServicesStoreProvider),
      routing: ref.read(assistantRoutingStoreProvider),
      profiles: ref.read(assistantCapabilityProfilesProvider),
      knowledge: VersionedKnowledgeRegistry(mapTaskKnowledgeBundles),
    );
  }

  Future<RunContext> freeze() {
    final current = _frozen;
    if (current != null) return current;
    final request = TaskRequest<String>(
      spec: spec,
      input: const {},
      inputFingerprint: 'map-session',
      modelOverride: ref.read(mapTaskChoicesProvider)[mapRouteKey(studySetId, spec.type)],
    );
    final work = _freeze(request);
    _frozen = work;
    return work.catchError((Object error, StackTrace stack) {
      if (identical(_frozen, work)) _frozen = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<RunContext> _freeze(TaskRequest<String> request) async {
    final context = await _assembly(TaskRegistry()).freeze(
      request,
      runId: _id(),
      knowledgeVersions: {spec.knowledgePacks.single: '2'},
      inputRange: {'studySetId': studySetId},
    );
    id = context.runId;
    await journal.update(id!, (data) {
      data['type'] = spec.type.name;
      data['promptVersion'] = spec.promptVersion;
      data['schemaVersion'] = spec.schemaVersion;
      data['context'] = encodeRunContext(context);
      data['workflow'] = workflow;
    });
    _changed();
    return context;
  }

  Future<String> cacheIdentity() async {
    final context = encodeRunContext(await freeze());
    return mapTaskFingerprint({
      'identity': context['identity'],
      'policy': context['policy'],
      'knowledge': context['knowledgeVersions'],
      'prompt': spec.promptVersion,
    });
  }

  Future<String> execute(
    String instructions,
    Map<String, Object?> payload,
    CancellationToken cancel,
    ValidationReport Function(String) validate,
  ) async {
    cancel.check();
    final root = await freeze();
    cancel.check();
    // Host aliases/prefixes disambiguate identical model inputs in distinct
    // targets without leaking private IDs into the model payload.
    final key = mapTaskFingerprint({
      'instructions': instructions,
      'payload': payload,
      'missing': missingRangeIds.toList()..sort(),
    });
    if (explicitContinuation && spec.type == TaskType.mapExpand && payload['_mapHost'] != null) {
      final host = mapTaskFingerprint({'instructions': instructions, 'host': payload['_mapHost']});
      for (final entry in _stages.entries) {
        final oldPayload = entry.value['payload'] as Map;
        if (entry.key != key &&
            mapTaskFingerprint({'instructions': entry.value['instructions'], 'host': oldPayload['_mapHost']}) == host) {
          throw const ConfigurationFailure('mapStageSourceChanged');
        }
      }
    }
    final running = _running[key];
    if (running != null) return cancel.bind(running);
    final work = _execute(key, root, instructions, payload, cancel, validate);
    _running[key] = work;
    try {
      return await work;
    } finally {
      if (identical(_running[key], work)) _running.remove(key);
    }
  }

  Future<String> _execute(
    String key,
    RunContext root,
    String instructions,
    Map<String, Object?> payload,
    CancellationToken cancel,
    ValidationReport Function(String) validate,
  ) async {
    final tasks = TaskRegistry();
    final missing = Set<String>.of(missingRangeIds);
    registerMapTaskDefinition(
      tasks,
      spec: spec,
      instructions: instructions,
      validate: (text) {
        final report = validate(text);
        return ValidationReport(issues: report.issues, missingInputIds: {...report.missingInputIds, ...missing});
      },
    );
    final assembly = _assembly(tasks);
    final input = Map<String, dynamic>.from(payload)..remove('_mapHost');
    final request = TaskRequest<String>(
      spec: spec,
      input: input,
      inputFingerprint: mapTaskFingerprint(input),
      modelOverride: root.config.model,
      purpose: payload.containsKey('accepted') ? RunPurpose.schemaRepair : RunPurpose.task,
    );
    var stage = _stages[key];
    final existed = stage != null;
    if (stage == null) {
      final context = _rootStarted ? root.child(_id()) : root;
      _rootStarted = true;
      stage = {
        'context': encodeRunContext(context),
        'fingerprint': request.inputFingerprint,
        'instructions': instructions,
        'payload': payload,
        'missing': missing.toList(),
      };
      _stages[key] = stage;
      await journal.update(id!, (data) {
        (data['stages'] as Map)[key] = stage;
        data['continuations'] = continuationRound;
      });
    }
    var context = decodeRunContext(Map<String, dynamic>.from(stage['context']));
    if (stage['fingerprint'] != request.inputFingerprint) throw const ConfigurationFailure('mapStageMismatch');
    // Runtime remains the authority for completion and usage, including a crash
    // after its commit but before a domain journal/UI update.
    var saved = await assembly.runs.load(context.runId);
    if (saved != null &&
        (saved.inputFingerprint != request.inputFingerprint ||
            saved.taskType != spec.type ||
            saved.promptVersion != spec.promptVersion ||
            saved.schemaVersion != spec.schemaVersion ||
            saved.context.config.capabilities.identity != context.config.capabilities.identity)) {
      throw const ConfigurationFailure('mapStageMismatch');
    }
    if (saved != null && {RunStatus.completed, RunStatus.partial}.contains(saved.status)) {
      final result = await assembly.runs.loadResult(context.runId);
      final text = (result?['value'] as Map?)?['text'];
      if (text is! String) throw const ConfigurationFailure('mapResultMissing');
      return text;
    }
    if (saved != null && {RunStatus.failed, RunStatus.cancelled}.contains(saved.status)) {
      if (!explicitContinuation) throw const ConfigurationFailure('mapContinueRequired');
      // A known terminal failure can be retried explicitly. Keep its identity
      // and usage in Runtime; the new attempt remains under the same root.
      context = root.child(_id());
      (stage['previousRuns'] ??= <String>[]).add(saved.context.runId);
      stage['context'] = encodeRunContext(context);
      await journal.update(id!, (data) {
        (data['stages'] as Map)[key] = stage;
        data['continuations'] = continuationRound;
      });
      _handles.remove(key);
      saved = null;
    }
    var handle = _handles[key];
    var recovered = false;
    if (handle == null) {
      if (saved != null) {
        if (!explicitContinuation) throw const ConfigurationFailure('mapContinueRequired');
        if (saved.checkpoint['pending'] == null &&
            !assistantOnlineDefault(ref, studySetId) &&
            root.config.capabilities.identity.protocol != ModelProtocol.ollamaChat) {
          throw const ResearchFailure(ResearchFailureKind.network);
        }
        handle = await assembly.runtime.recover(request, context);
        recovered = true;
      } else {
        // A journal entry without a Runtime checkpoint may be a paid request
        // whose first durable write failed. Only explicit continuation may retry.
        if (existed && !explicitContinuation) throw const ConfigurationFailure('mapContinueRequired');
        if (!assistantOnlineDefault(ref, studySetId) &&
            root.config.capabilities.identity.protocol != ModelProtocol.ollamaChat) {
          throw const ResearchFailure(ResearchFailureKind.network);
        }
        handle = assembly.runtime.start(request, context);
      }
      _handles[key] = handle;
    }
    final retained = handle;
    final paused = Completer<void>();
    void saveFailure() {
      saveFailed.add(key);
      if (!paused.isCompleted) paused.complete();
      _changed();
    }

    final subscription = retained.events.listen((event) {
      if (event.stage == 'save_failed') saveFailure();
    });
    if (retained.persistenceError != null) saveFailure();
    RuntimeRunHandle<String>? active = retained;
    Future<void>? cancellation;
    unawaited(
      cancel.whenCancelled.then((_) {
        final current = active;
        // cancel() flushes pending Runtime results too. Leave them owned by this
        // session instead, so stopping the preview cannot discard paid output.
        if (current != null && !saveFailed.contains(key) && current.persistenceError == null) {
          cancellation ??= current.cancel();
          cancellation!.ignore();
        }
      }),
    );
    try {
      if (recovered) {
        try {
          await retained.resume();
        } catch (_) {
          saveFailure();
        }
      }
      // The timeout bounds model work. A failed save waits for an explicit
      // retry/cancel, with a visible retry control, rather than timing out into
      // a new random child ID.
      await cancel.bind(
        Future.any<void>([retained.result.then((_) {}), paused.future]).timeout(mapGenerationRequestTimeout),
      );
      final result = await cancel.bind(retained.result);
      cancel.check();
      if (result.value == null || !{RunStatus.completed, RunStatus.partial}.contains(result.status)) {
        throw const ResearchFailure(ResearchFailureKind.protocol, 'mapStageFailed');
      }
      saveFailed.remove(key);
      _handles.remove(key);
      _changed();
      return result.value!;
    } finally {
      active = null;
      if (retained.persistenceError != null) saveFailure();
      await subscription.cancel();
      if (!saveFailed.contains(key) &&
          !{RunStatus.completed, RunStatus.partial, RunStatus.failed, RunStatus.cancelled}.contains(retained.status)) {
        await (cancellation ??= retained.cancel());
      }
    }
  }
}

MapTaskExecutor createMapTaskExecutor(Ref ref, String studySetId, TaskSpec spec) =>
    MapTaskSession(ref, studySetId, spec).execute;

// Sessions outlive auto-disposed preview controllers. Credentials and stores
// are still resolved in this study-set's application ProviderContainer.
final mapTaskHostRefProvider = Provider<Ref>((ref) => ref);

/// In-process pending handles remain owned here even when a preview is stopped.
final mapSaveFailuresProvider = NotifierProvider<MapSaveFailures, List<MapTaskSession>>(MapSaveFailures.new);

class MapSaveFailures extends Notifier<List<MapTaskSession>> {
  @override
  List<MapTaskSession> build() => [];
  void update(MapTaskSession session) {
    state = [
      for (final old in state)
        if (!identical(old, session)) old,
      if (session.saveFailed.isNotEmpty) session,
    ];
  }
}

final mapRecoverableTasksProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, studySetId) {
  final directory = ref.read(contentRepositoryProvider).resolveFile(studySetId, '');
  if (!p.isAbsolute(directory)) return Future.value([]);
  return MapTaskJournal(directory).list();
});
