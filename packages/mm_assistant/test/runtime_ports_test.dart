import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:dio/dio.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'model_policy_test.dart' as wire;
import 'task_runtime_test.dart' as fixture;
import 'support.dart';
import 'capability_probe_test.dart' show WaitingClient;

class MemoryRuns implements RunStore {
  final saved = <String, RunManifest>{};
  bool failComplete = false, failPending = false;
  @override
  Future<RunManifest?> load(String id) async => saved[id];
  @override
  Future<void> checkpoint(RunManifest snapshot, {required int? expectedRevision}) async {
    if (failPending && snapshot.status == RunStatus.validating && snapshot.checkpoint['pending'] != null) {
      throw StateError('disk pending');
    }
    if (saved[snapshot.context.runId]?.revision != expectedRevision) throw const RunStoreConflict();
    saved[snapshot.context.runId] = decodeRunManifest(jsonDecode(jsonEncode(encodeRunManifest(snapshot))));
  }

  @override
  Future<void> complete(RunManifest snapshot, Map<String, dynamic> result, {required int expectedRevision}) async {
    if (failComplete) throw StateError('disk terminal');
    await checkpoint(snapshot, expectedRevision: expectedRevision);
  }
}

RunContext context(
  ModelProtocol protocol, {
  String id = 'run',
  int ceiling = 77,
  bool multimodal = true,
  bool tools = true,
  TaskCategory category = TaskCategory.quick,
}) {
  final p = wire.profile(protocol);
  final caps = ModelCapabilityProfile(
    identity: p.identity,
    thinking: p.thinking,
    policies: p.policies,
    evidence: p.evidence,
    multimodal: multimodal ? CapabilitySupport.supported : CapabilitySupport.unknown,
    tools: tools ? CapabilitySupport.supported : CapabilitySupport.unknown,
  );
  return RunContext(
    runId: id,
    knowledgeVersions: const {'assistant.core': '1', 'explain': '1'},
    config: ResolvedTaskConfig(
      capabilities: caps,
      policy: const DefaultProviderPolicyCompiler().compile(
        category: category,
        requested: ReasoningPolicy.off,
        identity: caps.identity,
        capabilities: caps,
        maxOutputTokens: ceiling,
      ),
      routingRevision: 1,
      source: RoutingSource.explicitRequest,
    ),
  );
}

Future<RuntimeModelBinding> binding(RunContext c) async => RuntimeModelBinding(
  model: wire.model(c.config.capabilities.identity.protocol),
  key: 'fixture-key',
  serviceRevision: 1,
);

final image = TaskImage(base64Data: base64Encode([1, 2, 3, 4]), mimeType: 'image/png');
TaskRequest<String> request({bool images = true, bool stream = true}) => TaskRequest<String>(
  spec: fixture.spec,
  input: {'text': 'untrusted image question'},
  inputFingerprint: 'image-one',
  images: images ? [image] : [],
  streamDrafts: stream,
  maxOutputTokens: 33,
);

class PortWire implements HttpClientAdapter {
  PortWire(this.protocol, {this.streaming = false, this.search = false});
  final ModelProtocol protocol;
  final bool streaming, search;
  final bodies = <Map<String, dynamic>>[];
  final responseStarted = Completer<void>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = <int>[];
    await for (final part in requestStream!) {
      bytes.addAll(part);
    }
    bodies.add(jsonDecode(utf8.decode(bytes)));
    if (!responseStarted.isCompleted) responseStarted.complete();
    if (streaming) {
      String chunk(Map<String, dynamic> c) => 'data: ${jsonEncode(c)}\n\n';
      return ResponseBody.fromString(
        [
          chunk({
            'choices': [
              {
                'index': 0,
                'delta': {'content': 'Draft '},
                'finish_reason': null,
              },
            ],
          }),
          chunk({
            'choices': [
              {
                'index': 0,
                'delta': {'content': 'title'},
                'finish_reason': null,
              },
            ],
          }),
          chunk({
            'choices': [
              {'index': 0, 'delta': {}, 'finish_reason': 'stop'},
            ],
            'usage': {'prompt_tokens': 9, 'completion_tokens': 2, 'total_tokens': 11},
          }),
          'data: [DONE]\n\n',
        ].join(),
        200,
        headers: {
          Headers.contentTypeHeader: ['text/event-stream'],
        },
      );
    }
    final data = switch (protocol) {
      ModelProtocol.anthropicMessages => {
        'id': 'message',
        'type': 'message',
        'role': 'assistant',
        'model': 'fixture-model',
        'stop_reason': 'end_turn',
        'usage': {'input_tokens': 9, 'output_tokens': 2},
        'content': [
          if (search)
            {
              'type': 'web_search_tool_result',
              'tool_use_id': 'server',
              'content': [
                {'type': 'web_search_result', 'url': 'https://evidence.example/page', 'title': 'Source'},
              ],
            },
          {'type': 'text', 'text': 'Title', 'citations': []},
        ],
      },
      ModelProtocol.responses => {
        'id': 'response',
        'status': 'completed',
        'model': 'fixture-model',
        'usage': {'input_tokens': 9, 'output_tokens': 2},
        'output': [
          {
            'type': 'message',
            'role': 'assistant',
            'content': [
              {
                'type': 'output_text',
                'text': 'Title',
                'annotations': [
                  if (search) {'type': 'url_citation', 'url': 'https://evidence.example/page', 'title': 'Source'},
                  if (search) {'type': 'url_citation', 'url': 'file:///private', 'title': 'Unsafe'},
                ],
              },
            ],
          },
        ],
      },
      ModelProtocol.gemini => {
        'candidates': [
          {
            'content': {
              'role': 'model',
              'parts': [
                {'text': 'Title'},
              ],
            },
            'finishReason': 'STOP',
            if (search)
              'groundingMetadata': {
                'groundingChunks': [
                  {
                    'web': {'uri': 'https://evidence.example/page', 'title': 'Source'},
                  },
                ],
              },
          },
        ],
        'usageMetadata': {'promptTokenCount': 9, 'candidatesTokenCount': 2, 'totalTokenCount': 11},
      },
      _ => {
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'Title'},
            'finish_reason': 'stop',
          },
        ],
        'usage': {'prompt_tokens': 9, 'completion_tokens': 2},
      },
    };
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

SdkAgentRuntime runtime(RunStore store, sdk.LLMClient client) => SdkAgentRuntime(
  store: store,
  tasks: fixture.registry(),
  knowledge: VersionedKnowledgeRegistry([]),
  loadModel: binding,
  testClient: client,
);

void main() {
  test('typed image rejects URLs and unsupported MIME', () {
    expect(() => TaskImage(base64Data: 'https://example.com/a', mimeType: 'image/png'), throwsFormatException);
    expect(() => TaskImage(base64Data: 'YQ==', mimeType: 'text/html'), throwsFormatException);
  });
  for (final protocol in [
    ModelProtocol.chatCompletions,
    ModelProtocol.anthropicMessages,
    ModelProtocol.responses,
    ModelProtocol.gemini,
  ]) {
    test('SDK wire consumes typed image for $protocol', () async {
      final adapter = PortWire(protocol);
      final c = context(protocol);
      final connection = connectAssistant(wire.model(protocol), 'fixture-key', adapter: adapter);
      addTearDown(connection.close);
      final store = MemoryRuns();
      final handle = runtime(store, connection.client).start(request(stream: false), c);
      // Runtime narrows 77 to request 33; use no policy wire override in injected client.
      final result = await handle.result;
      expect(result.status, RunStatus.completed, reason: result.failureCode);
      final body = adapter.bodies.single;
      expect(jsonEncode(body), contains(image.base64Data));
      final system =
          body['system'] ??
          body['instructions'] ??
          body['systemInstruction'] ??
          (body['messages'] as List? ?? []).where((m) => m['role'] == 'system').toList();
      expect(jsonEncode(system), isNot(contains(image.base64Data)));
      expect(jsonEncode(system), isNot(contains('untrusted image question')));
      expect(store.saved['run']!.checkpoint['images'], [image.toJson()]);
      expect(jsonEncode(store.saved['run']!.checkpoint), isNot(contains('fixture-key')));
    });
  }
  test('SDK streaming drafts are deltas, usage reported, terminal waits for save retry', () async {
    final adapter = PortWire(ModelProtocol.chatCompletions, streaming: true);
    final connection = connectAssistant(wire.model(ModelProtocol.chatCompletions), '', adapter: adapter);
    addTearDown(connection.close);
    final store = MemoryRuns()..failComplete = true;
    final h = runtime(store, connection.client).start(request(), context(ModelProtocol.chatCompletions));
    final events = <RunEvent>[];
    final paused = Completer<void>();
    final sub = h.events.listen((e) {
      events.add(e);
      if (e.stage == 'save_failed') paused.complete();
    });
    await paused.future;
    expect(events.where((e) => e.draft != null).map((e) => e.draft).join(), 'Draft title');
    expect(events.any((e) => e.status == RunStatus.completed), false);
    expect(h.usage.inputTokens, 9);
    expect(h.usage.outputTokens, 2);
    store.failComplete = false;
    await h.resume();
    expect((await h.result).value, 'Draft title');
    await pumpEventQueue();
    expect(events.last.status, RunStatus.completed);
    expect(events.where((e) => e.kind == RunEventKind.modelStarted), hasLength(1));
    expect(events.where((e) => e.draft != null).every((e) => e.kind == RunEventKind.draftDelta), true);
    expect(events.map((e) => e.sequence).toSet().length, events.length);
    expect(adapter.bodies.single['max_completion_tokens'], 33);
    await sub.cancel();
  });
  test('SDK streamed signed and opaque history survives pending recovery unchanged', () async {
    final adapter = wire.WireAdapter(ModelProtocol.anthropicMessages);
    final connection = connectAssistant(wire.model(ModelProtocol.anthropicMessages), '', adapter: adapter);
    addTearDown(connection.close);
    final store = MemoryRuns()..failComplete = true;
    final c = context(ModelProtocol.anthropicMessages);
    final h = runtime(store, connection.client).start(request(), c);
    final drafts = <String>[];
    h.events.listen((e) {
      if (e.draft != null) drafts.add(e.draft!);
    });
    await h.events.firstWhere((e) => e.stage == 'save_failed');
    final checkpoint = jsonEncode((store.saved['run']!.checkpoint['state'] as Map)['history']);
    expect(checkpoint, contains('signed-stream'));
    expect(checkpoint, contains('opaque-stream'));
    expect(drafts.join(), 'done');
    expect(drafts.join(), isNot(contains('private')));
    final recovered = await runtime(store, ScriptClient([])).recover(request(), c);
    expect(jsonEncode((store.saved['run']!.checkpoint['state'] as Map)['history']), checkpoint);
    store.failComplete = false;
    await recovered.resume();
    expect((await recovered.result).value, 'done');
    expect(adapter.bodies.length, 1);
  });
  test('live controlled bindings inject parent-owned search and persist narrowed child', () async {
    final spec = TaskSpec(
      type: TaskType.assistantChat,
      inputSchema: 'text',
      resultSchema: 'text',
      promptVersion: '1',
      schemaVersion: '1',
      completionRule: 'valid',
      allowedTools: {'search'},
      maxOutputTokens: 41,
    );
    final store = MemoryRuns();
    final adapter = PortWire(ModelProtocol.responses, search: true);
    final steps = ProviderSteps(
      store: store,
      connection: (model, key, policy) =>
          connectAssistant(model, key, callPolicy: policy, adapter: adapter, retryRequests: false),
    );
    final registry = TaskRegistry()
      ..register<String>(
        TaskDefinition<String>(
          spec: spec,
          instructions: 'search',
          decode: (s) => s,
          encode: (s) => {'value': s},
          restore: (j) => j['value'] as String,
          validator: fixture.Validator(),
          validateInput: (_) => ValidationReport(),
          createControlledBindings: (scope) => TaskBindings(
            tools: [
              sdk.Tool(
                name: 'search',
                description: 'authorized search',
                parameters: const {},
                executable: () async {
                  final hits = await scope.nativeSearch.search(SearchRequest('keywords'), CancellationToken());
                  return hits.single.url.toString();
                },
              ),
            ],
          ),
        ),
      );
    final harness = SdkAgentRuntime(
      store: store,
      tasks: registry,
      providerSteps: steps,
      loadModel: binding,
      testClient: ScriptClient([call('search', '{}'), answer('Title')]),
      knowledge: VersionedKnowledgeRegistry([
        KnowledgeBundle(id: 'assistant.core', version: '1', instructions: 'search', tools: {'search'}),
        KnowledgeBundle(id: 'explain', version: '1', instructions: 'explain'),
      ]),
    );
    final handle = harness.start(
      TaskRequest<String>(spec: spec, input: {'text': 'question'}, inputFingerprint: 'q', maxOutputTokens: 29),
      context(ModelProtocol.responses, category: TaskCategory.heavy),
    );
    expect((await handle.result).status, RunStatus.completed);
    final child = store.saved.values.singleWhere((m) => m.context.parentRunId == 'run');
    expect(child.context.config.policy.maxOutputTokens, 29);
    expect(child.context.config.policy.effective, ReasoningPolicy.off);
    expect(child.usage.modelCalls, 1);
    expect(adapter.bodies.single['max_output_tokens'], 29);
    expect(store.saved['run']!.checkpoint.toString(), contains(child.context.runId));
    await expectLater(
      handle.nativeSearch.search(SearchRequest('late'), CancellationToken()),
      throwsA(isA<ResearchFailure>()),
    );
  });
  test('provider pending result commits after restart without another request', () async {
    final store = MemoryRuns()..failComplete = true;
    final client = ScriptClient([answer('OK')]);
    final steps = ProviderSteps(store: store, connection: (_, _, _) => AssistantConnection(client, Dio()));
    await expectLater(
      steps.run(
        context: context(ModelProtocol.chatCompletions, category: TaskCategory.heavy),
        category: TaskCategory.heavy,
        taskType: TaskType.assistantChat,
        purpose: RunPurpose.capabilityProbe,
        loadModel: binding,
        cancellation: CancellationToken(),
      ),
      throwsStateError,
    );
    store.failComplete = false;
    expect(await ProviderSteps(store: store).recoverSave('run'), {'accepted': true});
    expect(client.calls, 1);
    expect(store.saved['run']!.status, RunStatus.completed);
  });
  test('stream transport retry retains image, off policy and request ceiling', () async {
    final adapter = wire.WireAdapter(ModelProtocol.chatCompletions, failFirst: true);
    final connection = connectAssistant(
      wire.model(ModelProtocol.chatCompletions),
      '',
      adapter: adapter,
      retryRequests: false,
    );
    addTearDown(connection.close);
    final h = runtime(MemoryRuns(), connection.client).start(request(), context(ModelProtocol.chatCompletions));
    expect((await h.result).status, RunStatus.completed);
    expect(adapter.bodies, hasLength(2));
    for (final body in adapter.bodies) {
      expect(body['reasoning_effort'], 'none');
      expect(body['max_completion_tokens'], 33);
      expect(jsonEncode(body), contains(image.base64Data));
    }
  });
  test('partial stream failure records observed usage and never retries emitted text', () async {
    final client = StreamClient((_) async* {
      yield sdk.StreamingMessage(
        modelMessage: sdk.ModelMessage(
          model: 'fixture-model',
          textOutput: 'partial',
          usage: sdk.ModelUsage(promptTokens: 8, completionTokens: 1),
        ),
      );
      final options = RequestOptions(path: '/');
      throw DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 503),
      );
    });
    final h = runtime(MemoryRuns(), client).start(request(), context(ModelProtocol.chatCompletions));
    final result = await h.result;
    expect(result.status, RunStatus.failed);
    expect(result.usage.quality, UsageQuality.unknown);
    expect(result.usage.inputTokens, 8);
    expect(result.usage.outputTokens, 1);
    expect(client.calls, 1);
  });
  test('native substep cancels with parent and refuses stale service before transport', () async {
    final client = WaitingClient();
    final store = MemoryRuns();
    final steps = ProviderSteps(store: store, connection: (_, _, _) => AssistantConnection(client, Dio()));
    final cancellation = CancellationToken();
    final parent = context(ModelProtocol.responses, category: TaskCategory.heavy);
    final provider = RuntimeNativeSearch(
      steps: steps,
      parent: () => parent,
      taskType: TaskType.assistantChat,
      nextRunId: () async => 'cancelled-child',
      loadModel: binding,
      parentCancellation: cancellation,
    );
    final future = provider.search(SearchRequest('keywords'), CancellationToken());
    await client.started.future;
    cancellation.cancel();
    await expectLater(future, throwsA(isA<ResearchFailure>()));
    expect(store.saved['cancelled-child']!.status, RunStatus.cancelled);
    expect(store.saved['cancelled-child']!.usage.modelCalls, 1);
    expect(store.saved['cancelled-child']!.usage.quality, UsageQuality.unknown);
    await expectLater(
      steps.run(
        context: parent.child('changed-child'),
        category: TaskCategory.heavy,
        taskType: TaskType.assistantChat,
        purpose: RunPurpose.nativeSearch,
        cancellation: CancellationToken(),
        loadModel: (c) async =>
            RuntimeModelBinding(model: wire.model(ModelProtocol.responses), key: '', serviceRevision: 2),
      ),
      throwsA(isA<ConfigurationFailure>()),
    );
    expect(store.saved['changed-child']!.usage.modelCalls, 0);
  });
  test('unknown multimodal rejected even if spec omits capability', () async {
    final client = ScriptClient([answer('should not send')]);
    final h = runtime(MemoryRuns(), client).start(request(), context(ModelProtocol.chatCompletions, multimodal: false));
    expect((await h.result).status, RunStatus.failed);
    expect(client.calls, 0);
  });
  test('cancelled stream emits no late drafts and never validates incomplete output', () async {
    final source = StreamController<sdk.StreamingMessage>();
    final client = StreamClient((_) => source.stream);
    final h = runtime(MemoryRuns(), client).start(request(), context(ModelProtocol.chatCompletions));
    final draft = Completer<void>();
    final events = <RunEvent>[];
    final sub = h.events.listen((e) {
      events.add(e);
      if (e.draft != null) draft.complete();
    });
    source.add(
      sdk.StreamingMessage(
        modelMessage: sdk.ModelMessage(model: 'fixture-model', textOutput: 'unverified'),
      ),
    );
    await draft.future;
    await h.cancel();
    source.add(
      sdk.StreamingMessage(
        modelMessage: sdk.ModelMessage(model: 'fixture-model', textOutput: 'late', stopReason: 'stop'),
      ),
    );
    expect((await h.result).status, RunStatus.cancelled);
    expect(events.where((e) => e.draft != null).map((e) => e.draft).toList(), ['unverified']);
    await source.close();
    await sub.cancel();
  });
  test('restart restores pending image result, rejects changed image, sends no new request', () async {
    final store = MemoryRuns()..failComplete = true;
    final client = ScriptClient([answer('Title')]);
    final req = request(stream: false);
    final c = context(ModelProtocol.chatCompletions);
    final first = runtime(store, client).start(req, c);
    await first.events.firstWhere((e) => e.stage == 'save_failed');
    final recovered = runtime(store, ScriptClient([]));
    await expectLater(
      recovered.recover(request(images: false, stream: false), c),
      throwsA(isA<ConfigurationFailure>()),
    );
    final h = await recovered.recover(req, c);
    final events = <RunEvent>[];
    h.events.listen(events.add);
    store.failComplete = false;
    await h.resume();
    expect((await h.result).value, 'Title');
    expect(client.calls, 1);
    expect(events.every((e) => e.sequence > 1000000), true);
  });
  for (final protocol in [ModelProtocol.anthropicMessages, ModelProtocol.responses, ModelProtocol.gemini]) {
    test('native search SDK wire inherits identity policy ceiling usage for $protocol', () async {
      final adapter = PortWire(protocol, search: true);
      final store = MemoryRuns();
      final steps = ProviderSteps(
        store: store,
        connection: (model, key, policy) =>
            connectAssistant(model, key, callPolicy: policy, adapter: adapter, retryRequests: false),
      );
      final parent = context(protocol, category: TaskCategory.heavy);
      final provider = RuntimeNativeSearch(
        steps: steps,
        parent: () => parent,
        taskType: TaskType.assistantChat,
        nextRunId: () async => 'child',
        loadModel: binding,
        parentCancellation: CancellationToken(),
      );
      final hits = await provider.search(SearchRequest('short keywords'), CancellationToken());
      expect(hits.single.url.toString(), 'https://evidence.example/page');
      expect(hits.single.snippet, isEmpty);
      final saved = store.saved['child']!;
      expect(saved.context.parentRunId, 'run');
      expect(saved.context.config.capabilities.identity, parent.config.capabilities.identity);
      expect(saved.context.config.policy.maxOutputTokens, 77);
      expect(saved.stage, RunPurpose.nativeSearch.name);
      expect(saved.usage.quality, UsageQuality.reported);
      expect(saved.usage.inputTokens, 9);
      expect(saved.usage.outputTokens, 2);
      expect(adapter.bodies.single['tools'], isNotEmpty);
      expect(jsonEncode(saved.checkpoint), isNot(contains('short keywords')));
    });
  }
  test('native search rejects unknown tools and Quick without provider dispatch', () async {
    var calls = 0;
    final steps = ProviderSteps(
      connection: (_, _, _) {
        calls++;
        throw StateError('unexpected');
      },
    );
    for (final c in [
      context(ModelProtocol.responses, tools: false, category: TaskCategory.heavy),
      context(ModelProtocol.responses),
    ]) {
      await expectLater(
        steps.run(
          context: c,
          category:
              c.config.policy.effective == ReasoningPolicy.off &&
                  c.config.capabilities.tools == CapabilitySupport.supported
              ? TaskCategory.quick
              : TaskCategory.heavy,
          taskType: TaskType.assistantChat,
          purpose: RunPurpose.nativeSearch,
          loadModel: binding,
          cancellation: CancellationToken(),
        ),
        throwsA(isA<ConfigurationFailure>()),
      );
    }
    expect(calls, 0);
  });
  for (final failPending in [false, true]) {
    test('provider save failure retry does not repeat purchase (pending=$failPending)', () async {
      final store = MemoryRuns()
        ..failPending = failPending
        ..failComplete = !failPending;
      final client = ScriptClient([answer('OK')]);
      final steps = ProviderSteps(store: store, connection: (_, _, _) => AssistantConnection(client, Dio()));
      await expectLater(
        steps.run(
          context: context(ModelProtocol.chatCompletions, category: TaskCategory.heavy),
          category: TaskCategory.heavy,
          taskType: TaskType.assistantChat,
          purpose: RunPurpose.capabilityProbe,
          loadModel: binding,
          cancellation: CancellationToken(),
        ),
        throwsStateError,
      );
      store.failPending = store.failComplete = false;
      expect(await steps.retrySave('run'), {'accepted': true});
      expect(client.calls, 1);
      expect(store.saved['run']!.status, RunStatus.completed);
    });
  }
}
