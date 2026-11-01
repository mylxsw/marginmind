import 'dart:async';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:dio/dio.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:test/test.dart';

import 'support.dart';
import 'task_runtime_test.dart' as fixture;
import 'model_policy_test.dart' as policy;
import 'translation_scheduler_test.dart' as scheduler;

class Runs implements RunStore, RunReader {
  final manifests = <String, RunManifest>{};
  final results = <String, Map<String, dynamic>>{};
  bool failComplete = false;
  @override
  Future<RunManifest?> load(String id) async => manifests[id];
  @override
  Future<void> checkpoint(RunManifest snapshot, {required int? expectedRevision}) async {
    if (manifests[snapshot.context.runId]?.revision != expectedRevision) throw const RunStoreConflict();
    manifests[snapshot.context.runId] = decodeRunManifest(jsonDecode(jsonEncode(encodeRunManifest(snapshot))));
  }

  @override
  Future<void> complete(RunManifest snapshot, Map<String, dynamic> result, {required int expectedRevision}) async {
    if (failComplete) throw StateError('disk');
    await checkpoint(snapshot, expectedRevision: expectedRevision);
    results[snapshot.context.runId] = result;
  }

  @override
  Future<Map<String, dynamic>?> loadResult(String id) async => results[id];
  @override
  Future<List<RunManifest>> resumable() async => manifests.values.where(runMayResume).toList();
}

class Echo extends ScriptClient {
  Echo() : super([]);
  final received = StreamController<int>.broadcast(sync: true);
  Completer<void>? gate;
  bool invalid = false, fail = false;
  @override
  Future<sdk.ModelMessage> generate(
    List<sdk.LLMMessage> messages, {
    List<sdk.Tool>? tools,
    sdk.ToolChoice? toolChoice,
    required sdk.ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    calls++;
    requests.add(List.of(messages));
    modelConfigs.add(modelConfig);
    received.add(calls);
    await gate?.future;
    if (fail) throw StateError('connection dropped');
    final input = jsonDecode(
      (messages.whereType<sdk.UserMessage>().first.toJson()['contents'] as List).map((p) => p['text']).join(),
    ) as Map;
    return sdk.ModelMessage(
      model: 'fixture',
      textOutput: jsonEncode({'id': invalid ? 'wrong' : input['id'], 'text': input['text']}),
      stopReason: 'stop',
    );
  }
}

class Harness {
  Harness({Runs? store}) : runs = store ?? Runs() {
    final registry = TaskRegistry();
    registerDocumentTranslation(registry);
    runtime = SdkAgentRuntime(
      store: runs,
      tasks: registry,
      knowledge: VersionedKnowledgeRegistry([documentTranslationKnowledge]),
      testClient: client,
      loadModel: (context) async {
        contexts.add(context);
        if (revoked) throw const ConfigurationFailure('serviceConfigurationChanged');
        return RuntimeModelBinding(model: policy.model(ModelProtocol.chatCompletions), key: '', serviceRevision: 1);
      },
    );
  }
  final Runs runs;
  final client = Echo();
  late final SdkAgentRuntime runtime;
  final contexts = <RunContext>[];
  int freezes = 0, sequence = 0;
  bool revoked = false;
  RuntimeDocumentTranslator translator() => RuntimeDocumentTranslator(
    runtime: runtime,
    store: runs,
    reader: runs,
    freeze: (request, id, range) async {
      freezes++;
      final json = encodeRunContext(fixture.context(runId: id));
      (json['capabilities'] as Map).addAll(<String, dynamic>{'contextTokens': 64000, 'outputTokens': 8192});
      (json['policy'] as Map)['maxOutputTokens'] = 8192;
      (json['policy'] as Map)['requested'] = 'off';
      json['knowledgeVersions'] = {'translation.document': '1'};
      json['inputRange'] = range;
      return decodeRunContext(json);
    },
    scopeId: 'scope',
    documentId: 'doc',
    language: 'zh',
    inputIds: ['fp0', 'fp1'],
    nextId: () => 'child-${sequence++}',
  );
}

void main() {
  test('capacity splitting preserves Unicode and protected spans without truncation', () {
    final text = '${'abc 😀 ' * 100}{name} https://example.com/code ${'xyz ' * 100}';
    final parts = splitTranslationText(text, 150);
    expect(parts.join(), text);
    expect(parts.every((p) => p.length <= 150), isTrue);
    expect(() => splitTranslationText('`${'x' * 200}`', 128), throwsA(isA<ConfigurationFailure>()));
  });
  test('Heavy children retain frozen model, parent scope and knowledge across batches', () async {
    final h = Harness();
    final t = h.translator();
    final job = await t.bindJob(scheduler.job());
    await t.translatePack([scheduler.p(0)], 'zh', CancellationToken(), 64);
    await t.translatePack([scheduler.p(1)], 'zh', CancellationToken(), 64);
    expect(h.freezes, 1);
    expect(h.contexts.every((c) => c.parentRunId == job.id && c.config.source == RoutingSource.parentRun), isTrue);
    expect(h.contexts.map((c) => c.config.model).toSet(), {job.runContext!.config.model});
    expect(
      h.client.requests.every(
        (r) => r.whereType<sdk.SystemMessage>().any((m) => m.content.contains('Translate each assigned segment')),
      ),
      isTrue,
    );
    expect((await t.readUsage()).requests, 2);
  });
  test('long paragraph reuses validated children after restart and creates new retranslation', () async {
    final h = Harness();
    final t = h.translator();
    final job = await t.bindJob(scheduler.job());
    final p = scheduler.p(0, text: 'Source fragment. ' * 300);
    expect((await t.translatePack([p], 'zh', CancellationToken(), 64)).texts.single, p.text);
    final calls = h.client.calls;
    expect(calls, greaterThan(1));
    final reopened = h.translator();
    await reopened.bindJob(TranslationJob.fromJson(job.toJson()));
    expect(h.client.calls, calls);
    await reopened.translatePack([p], 'zh', CancellationToken(), 64);
    expect(h.client.calls, calls);
    expect((await reopened.readUsage()).requests, calls);
    reopened.newTranslation(p);
    await reopened.translatePack([p], 'zh', CancellationToken(), 64);
    expect(h.client.calls, calls * 2);
  });
  test('wrong IDs are partial after bounded repair; glossary omissions fail coverage', () async {
    final h = Harness();
    h.client.invalid = true;
    final t = h.translator();
    await t.bindJob(scheduler.job());
    await expectLater(
      t.translatePack([scheduler.p(0)], 'zh', CancellationToken(), 1024),
      throwsA(isA<ResearchFailure>()),
    );
    expect(h.client.calls, 2);
    expect(h.runs.manifests.values.any((m) => m.status == RunStatus.partial), isTrue);
    final registry = TaskRegistry();
    registerDocumentTranslation(registry);
    final report = registry
        .resolve<Map<String, dynamic>>(documentTranslationSpec)
        .validator
        .validate(
          {'id': 'x', 'text': 'attention'},
          {
            'id': 'x',
            'text': 'attention',
            'glossary': {'attention': '注意'},
          },
        );
    expect(report.missingInputIds, {'x'});
  });
  test('runtime save failure retries persistence without buying another response', () async {
    final h = Harness();
    h.runs.failComplete = true;
    final t = h.translator();
    await t.bindJob(scheduler.job());
    await expectLater(
      t.translatePack([scheduler.p(0)], 'zh', CancellationToken(), 1024),
      throwsA(isA<ResearchFailure>()),
    );
    expect(h.client.calls, 1);
    h.runs.failComplete = false;
    final reopened = h.translator();
    await reopened.bindJob(scheduler.job());
    await reopened.translatePack([scheduler.p(0)], 'zh', CancellationToken(), 1024);
    expect(h.client.calls, 1);
  });
  test('service change blocks next child without changing the snapshot', () async {
    final h = Harness();
    final t = h.translator();
    final job = await t.bindJob(scheduler.job());
    await t.translatePack([scheduler.p(0)], 'zh', CancellationToken(), 1024);
    h.revoked = true;
    await expectLater(
      t.translatePack([scheduler.p(1)], 'zh', CancellationToken(), 1024),
      throwsA(isA<ResearchFailure>()),
    );
    expect(h.client.calls, 1);
    expect(h.contexts.last.config.model, job.runContext!.config.model);
  });
  test('scheduler pause drains paid response; stop isolates late results', () async {
    final h = Harness();
    h.client.gate = Completer<void>();
    final s = await scheduler.scheduler([scheduler.p(0)], h.translator());
    final received = h.client.received.stream.first;
    final work = s.start(scheduler.job(pages: 1));
    await received;
    await s.pause();
    h.client.gate!.complete();
    await work;
    expect(s.values, isNotEmpty);
    expect(s.job!.state, TranslationJobState.paused);
    await s.close();
    final h2 = Harness();
    h2.client.gate = Completer<void>();
    final s2 = await scheduler.scheduler([scheduler.p(0)], h2.translator());
    final received2 = h2.client.received.stream.first;
    final work2 = s2.start(scheduler.job(pages: 1));
    await received2;
    await s2.stop();
    h2.client.gate!.complete();
    await work2;
    expect(s2.values, isEmpty);
    await s2.close();
  });
  test('automatic page recovery refuses an unknown paid request after restart', () async {
    final original = Harness();
    original.client.gate = Completer<void>();
    final received = original.client.received.stream.first;
    final work = original.translator().translatePack([scheduler.p(0)], 'zh', CancellationToken(), 1024);
    await received;
    final copied = Runs()
      ..manifests.addAll(original.runs.manifests)
      ..results.addAll(original.runs.results);
    final reopened = Harness(store: copied);
    await expectLater(
      reopened.translator().translatePack([scheduler.p(0)], 'zh', CancellationToken(), 1024),
      throwsA(isA<ResearchFailure>().having((e) => e.code, 'cause', 'interrupted')),
    );
    expect(reopened.client.calls, 0);
    original.client.gate!.complete();
    await work;
  });

  test('pause inside a long paragraph saves current child and stops further dispatch', () async {
    final h = Harness();
    h.client.gate = Completer<void>();
    final paragraph = scheduler.p(0, text: 'Source fragment. ' * 300);
    final session = await scheduler.scheduler([paragraph], h.translator());
    final received = h.client.received.stream.first;
    final work = session.start(scheduler.job(pages: 1));
    await received;
    await session.pause();
    h.client.gate!.complete();
    await work;
    expect(h.client.calls, 1);
    expect(session.values, isEmpty);
    expect(session.job!.state, TranslationJobState.paused);
    await session.resume();
    expect(h.client.calls, greaterThan(1));
    expect(session.values['fp0'], paragraph.text.trim());
    await session.close();
  });

  test('paragraph journal save failure resumes without buying or accounting twice', () async {
    final h = Harness();
    final store = FailingJournal();
    final session = await scheduler.scheduler([scheduler.p(0)], h.translator(), store: store);
    await expectLater(session.start(scheduler.job(pages: 1)), throwsStateError);
    expect(h.client.calls, 1);
    store.fail = false;
    await session.resume();
    expect(h.client.calls, 1);
    expect(session.values, hasLength(1));
    expect(session.job!.usage.requests, 1);
    await session.close();
  });

  test('a manual edit made during explicit retranslation wins over the paid result', () async {
    final h = Harness();
    final paragraph = scheduler.p(0);
    final session = await scheduler.scheduler([paragraph], h.translator());
    await session.start(scheduler.job(pages: 1));
    h.client.gate = Completer<void>();
    final received = h.client.received.stream.first;
    final work = session.retranslate(paragraph);
    await received;
    await session.edit(paragraph, 'Manual translation');
    h.client.gate!.complete();
    await work;
    expect(session.values['fp0'], 'Manual translation');
    expect(session.segments.values.single.origin, TranslationOrigin.edited);
    await session.close();
  });

  test('domain scheduler never multiplies runtime transport failure', () async {
    final h = Harness();
    h.client.fail = true;
    final s = await scheduler.scheduler([scheduler.p(0)], h.translator());
    await s.start(scheduler.job(pages: 1));
    expect(h.client.calls, 1);
    expect(s.job!.failures, isNotEmpty);
    await s.close();
  });
}

class FailingJournal extends InMemoryTranslationStore {
  bool fail = true;
  @override
  Future<void> append(String documentId, String targetLang, TranslationSegment segment) async {
    if (fail) throw StateError('disk');
    await super.append(documentId, targetLang, segment);
  }
}
