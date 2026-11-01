import 'dart:convert';

import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'model_policy_test.dart' as fixture;

class SummaryStore implements RunStore, RunReader {
  final manifests = <String, RunManifest>{};
  final results = <String, Map<String, dynamic>>{};
  String? failCheckpoint, failCompletion;
  @override
  Future<RunManifest?> load(String id) async => manifests[id];
  @override
  Future<Map<String, dynamic>?> loadResult(String id) async => results[id];
  @override
  Future<List<RunManifest>> resumable() async => manifests.values.where(runMayResume).toList();
  @override
  Future<void> checkpoint(RunManifest value, {required int? expectedRevision}) async {
    if (failCheckpoint == value.context.runId) {
      failCheckpoint = null;
      throw StateError('disk');
    }
    final old = manifests[value.context.runId];
    if (old?.revision != expectedRevision ||
        old != null &&
            {RunStatus.completed, RunStatus.partial, RunStatus.cancelled, RunStatus.failed}.contains(old.status)) {
      throw const RunStoreConflict();
    }
    manifests[value.context.runId] = decodeRunManifest(jsonDecode(jsonEncode(encodeRunManifest(value))));
  }

  @override
  Future<void> complete(RunManifest value, Map<String, dynamic> result, {required int expectedRevision}) async {
    if (failCompletion == value.context.runId) {
      failCompletion = null;
      throw StateError('disk');
    }
    await checkpoint(value, expectedRevision: expectedRevision);
    results[value.context.runId] = jsonDecode(jsonEncode(result));
  }
}

RunContext root() {
  final caps = fixture.profile(ModelProtocol.chatCompletions);
  return RunContext(
    runId: 'summary-root',
    config: ResolvedTaskConfig(
      capabilities: caps,
      policy: const DefaultProviderPolicyCompiler().compile(
        category: TaskCategory.heavy,
        requested: ReasoningPolicy.off,
        identity: caps.identity,
        capabilities: caps,
      ),
      routingRevision: 1,
      source: RoutingSource.functionBinding,
    ),
    knowledgeVersions: standardKnowledgeVersions(documentSummarySpec),
    inputRange: {'studySetId': 'study', 'conversationId': 'conversation', 'requestId': 'question'},
  );
}

Future<PersistentAssistantSummary> create(SummaryStore store) => PersistentAssistantSummary.open(
  store: store,
  reader: store,
  spec: documentSummarySpec,
  context: root(),
  units: [SummaryUnit('doc:1', 'a' * 24000)],
  question: 'summarize',
  requestCharacters: 4096,
);
Future<RunResult<String>> completeStage(SummaryStore store, TaskRequest<String> request, RunContext context) async {
  final text = jsonEncode(
    AssistantSummary('Summary', [for (final u in request.input['units']) u['id'] as String], [], [], []).toJson(),
  );
  await store.checkpoint(
    RunManifest(
      context: context,
      taskType: request.spec.type,
      inputFingerprint: request.inputFingerprint,
      promptVersion: request.spec.promptVersion,
      schemaVersion: request.spec.schemaVersion,
      status: RunStatus.running,
      revision: 0,
    ),
    expectedRevision: null,
  );
  await store.complete(
    RunManifest(
      context: context,
      taskType: request.spec.type,
      inputFingerprint: request.inputFingerprint,
      promptVersion: request.spec.promptVersion,
      schemaVersion: request.spec.schemaVersion,
      status: RunStatus.completed,
      revision: 1,
      usage: const RunUsage(quality: UsageQuality.reported, modelCalls: 1, inputTokens: 7, outputTokens: 3),
    ),
    {
      'status': 'completed',
      'value': {'text': text},
    },
    expectedRevision: 0,
  );
  return RunResult<String>(
    runId: context.runId,
    status: RunStatus.completed,
    validation: ValidationReport(),
    value: text,
  );
}

void main() {
  test('parent stays partial after a later stage fails; reopen reuses verified children', () async {
    final store = SummaryStore();
    final run = await create(store);
    final calls = <String, int>{};
    var fail = true;
    Future<RunResult<String>> dispatch(TaskRequest<String> request, RunContext context) async {
      calls.update(request.inputFingerprint, (v) => v + 1, ifAbsent: () => 1);
      if (calls.length == 2 && fail) {
        fail = false;
        throw StateError('provider');
      }
      expect(context.parentRunId, isNotNull);
      return completeStage(store, request, context);
    }

    await expectLater(run.run(dispatch: dispatch, cancel: CancellationToken()), throwsStateError);
    expect((await store.load(root().runId))!.status, RunStatus.partial);
    final first = calls.keys.first;
    final reopened = await PersistentAssistantSummary.open(
      store: store,
      reader: store,
      spec: documentSummarySpec,
      context: root(),
    );
    final continued = await reopened.continuation();
    final summary = await continued.run(dispatch: dispatch, cancel: CancellationToken());
    expect(calls[first], 1);
    expect(summary.coveredIds.length, greaterThan(3));
    expect((await store.load(continued.context.runId))!.status, RunStatus.completed);
    expect((await store.load(root().runId))!.status, RunStatus.partial);
    expect((await store.loadResult(continued.context.runId))!['leafIds'], summary.coveredIds);
    expect((await store.load(continued.context.runId))!.usage.modelCalls, calls.values.reduce((a, b) => a + b) - 1);
  });
  test('restart after child commit but before parent ACK never buys the child again', () async {
    final store = SummaryStore();
    final run = await create(store);
    var calls = 0;
    String? first;
    Future<RunResult<String>> dispatch(TaskRequest<String> request, RunContext context) async {
      calls++;
      first ??= request.inputFingerprint;
      final result = await completeStage(store, request, context);
      if (calls == 1) store.failCheckpoint = root().runId;
      return result;
    }

    await expectLater(
      run.run(dispatch: dispatch, cancel: CancellationToken()),
      throwsA(isA<SummaryPersistenceFailure>()),
    );
    final recovered = await PersistentAssistantSummary.open(
      store: store,
      reader: store,
      spec: documentSummarySpec,
      context: root(),
    );
    await recovered.run(
      dispatch: (request, context) {
        expect(request.inputFingerprint, isNot(first));
        return dispatch(request, context);
      },
      cancel: CancellationToken(),
    );
    expect(recovered.status, RunStatus.completed);
  });
  test('validated pending aggregate survives restart and save retry makes no model call', () async {
    final store = SummaryStore();
    final run = await create(store);
    store.failCompletion = root().runId;
    await expectLater(
      run.run(dispatch: (request, context) => completeStage(store, request, context), cancel: CancellationToken()),
      throwsA(isA<SummaryPersistenceFailure>()),
    );
    expect((await store.load(root().runId))!.status, RunStatus.validating);
    final reopened = await PersistentAssistantSummary.open(
      store: store,
      reader: store,
      spec: documentSummarySpec,
      context: root(),
    );
    await reopened.run(dispatch: (_, _) => throw StateError('must not infer'), cancel: CancellationToken());
    expect(reopened.status, RunStatus.completed);
  });
  test('independent owners CAS before inference; stale owner cannot dispatch', () async {
    final store = SummaryStore();
    final one = await create(store);
    final stale = await PersistentAssistantSummary.open(
      store: store,
      reader: store,
      spec: documentSummarySpec,
      context: root(),
    );
    await one.run(dispatch: (request, context) => completeStage(store, request, context), cancel: CancellationToken());
    await expectLater(
      stale.run(dispatch: (_, _) => throw StateError('must not infer'), cancel: CancellationToken()),
      throwsA(isA<RunStoreConflict>()),
    );
  });
}
