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

/// One feature invocation pins a route before reading its model-dependent cache.
class MapTaskSession {
  MapTaskSession(this.ref, this.studySetId, this.spec);
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
    final work = _assembly(TaskRegistry()).freeze(
      request,
      runId: _id(),
      knowledgeVersions: {spec.knowledgePacks.single: '2'},
      inputRange: {'studySetId': studySetId},
    );
    _frozen = work;
    return work.catchError((Object error, StackTrace stack) {
      // Admission failure has no run to inherit. A later explicit attempt may
      // inspect corrected credentials/configuration; successful pins stay fixed.
      if (identical(_frozen, work)) _frozen = null;
      Error.throwWithStackTrace(error, stack);
    });
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
    if (!assistantOnlineDefault(ref, studySetId) &&
        root.config.capabilities.identity.protocol != ModelProtocol.ollamaChat) {
      throw const ResearchFailure(ResearchFailureKind.network);
    }
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
    final input = Map<String, dynamic>.from(payload);
    final request = TaskRequest<String>(
      spec: spec,
      input: input,
      inputFingerprint: mapTaskFingerprint(input),
      modelOverride: root.config.model,
      purpose: payload.containsKey('accepted') ? RunPurpose.schemaRepair : RunPurpose.task,
    );
    final context = _rootStarted ? root.child(_id()) : root;
    _rootStarted = true;
    final handle = assembly.runtime.start(request, context);
    RuntimeRunHandle<String>? active = handle;
    Future<void>? cancellation;
    unawaited(
      cancel.whenCancelled.then((_) {
        final current = active;
        if (current != null) {
          cancellation ??= current.cancel();
          cancellation!.ignore();
        }
      }),
    );
    try {
      final result = await cancel.bind(handle.result).timeout(mapGenerationRequestTimeout);
      cancel.check();
      // Partial output is released to the domain parser for preview and local
      // repair; it is durably marked partial, never upgraded here.
      if (result.value == null || !{RunStatus.completed, RunStatus.partial}.contains(result.status)) {
        throw const ResearchFailure(ResearchFailureKind.protocol, 'mapStageFailed');
      }
      return result.value!;
    } finally {
      active = null;
      if (!{RunStatus.completed, RunStatus.partial, RunStatus.failed, RunStatus.cancelled}.contains(handle.status) ||
          cancellation != null) {
        await (cancellation ??= handle.cancel());
      }
    }
  }
}

MapTaskExecutor createMapTaskExecutor(Ref ref, String studySetId, TaskSpec spec) =>
    MapTaskSession(ref, studySetId, spec).execute;
