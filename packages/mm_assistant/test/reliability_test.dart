import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' hide MessageRole;
import 'package:dart_agent_core/eval.dart';
import 'package:dio/dio.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('coding/auto compatible-shaped recording replays three denials then fallback', () async {
    final store = InMemoryRecordingStore();
    final fake = ScriptClient([
      for (var n = 0; n < 3; n++) call('functions.read_selction', '{}', id: 'bad$n'),
      answer('**结论：依据选区回答。**\n- 只解释已有内容。'),
    ]);
    for (final client in [RecordingLLMClient(inner: fake, store: store), ReplayLLMClient(store: store)]) {
      final state = AgentState(sessionId: 'reliability');
      final run = createAssistantRun(
        client: client,
        model: 'coding/auto',
        state: state,
        requestId: 'r',
        reader: Reader(),
        scope: ReadScope(studySetId: 's'),
        mapId: 'm',
        baseRevision: 0,
        parents: {},
        serviceHost: 'compatible.example',
        attachedContext: ['选区内容'],
      );
      final events = await run.agent.runStream([UserMessage.text('解释选区')], useStream: false).toList();
      final diagnostic = (state.metadata['assistant.diagnostics'] as Map)['r'] as Map;
      expect(diagnostic['fallback'], true);
      expect(diagnostic['model'], 'coding/auto');
      expect(diagnostic['host'], 'compatible.example');
      expect((diagnostic['tools'] as List).map((t) => t['reason']), everyElement('不存在的工具 functions.read_selction'));
      final output = (events.lastWhere((e) => e.eventType == StreamingEventType.fullModelMessage).data as ModelMessage)
          .textOutput!;
      expect(output, startsWith('**结论：'));
      expect(output, contains('\n- '));
      expect(output, isNot(contains('需要我')));
      expect(jsonEncode(diagnostic), isNot(contains('选区内容')));
    }
    expect(fake.calls, 4);
    expect(fake.toolRequests.last, isEmpty);
    expect(fake.requests.last.first.toJson().toString(), contains('工具已关闭'));
  });

  test('consecutive failure fallback resets across conversation turns', () async {
    final state = AgentState(sessionId: 'same');
    for (var round = 0; round < 2; round++) {
      final client = ScriptClient([for (var n = 0; n < 3; n++) call('unknown', '{}', id: '$round-$n'), answer('done')]);
      await makeRun(client, state: state).run('question').toList();
      expect(client.calls, 4);
    }
  });
  test('different consecutive tool failures also switch to a direct answer', () async {
    final client = ScriptClient([
      for (var n = 1; n <= 3; n++) call('read_selection' * (n + 1), '{}', id: 'bad$n'),
      answer('依据上下文直接解释。'),
    ]);
    final state = AgentState(sessionId: 'varied-failures');
    await makeRun(client, state: state).run('解释').toList();
    expect(client.calls, 4);
    expect(client.toolRequests.last, isEmpty);
    expect(client.requests.last.first.toJson().toString(), contains('工具已关闭'));
  });
  test('normalizes function prefix, case, hyphens and integer strings before execution', () async {
    final fake = ScriptClient([
      call('functions.READ-PAGES', '{"documentId":"doc","from":"1","to":"2"}'),
      answer('**已读取。**'),
    ]);
    final run = makeRun(fake);
    final events = await run.run('question').toList();
    expect(run.citations.items, hasLength(2));
    final result =
        (events.firstWhere((e) => e.eventType == StreamingEventType.functionCallResult).data
                as FunctionExecutionResultMessage)
            .results
            .single;
    expect(result.isError, false);
    expect(jsonDecode(result.arguments)['to'], 2);
  });

  test('bad types return specific reason to model, successes reset consecutive failures', () async {
    final fake = ScriptClient([
      call('read_pages', '{"documentId":"doc","from":1,"to":"oops"}', id: '1'),
      call('read_selection', '{"selectionId":"sel"}', id: '2'),
      call('read_pages', '{"documentId":"doc","from":1,"to":"oops"}', id: '3'),
      answer('done'),
    ]);
    final run = makeRun(fake);
    final events = await run.run('question').toList();
    final results = events
        .where((e) => e.eventType == StreamingEventType.functionCallResult)
        .map((e) => (e.data as FunctionExecutionResultMessage).results.single)
        .toList();
    expect(results.first.metadata?['reason'], '参数 to 应为整数');
    expect(fake.requests[1].map((m) => m.toJson()).toString(), contains('参数 to 应为整数'));
    expect(fake.calls, 4);
  });

  test('selection and more than five document pages do not consume the research page quota', () async {
    final client = ScriptClient([
      call('read_selection', '{"selectionId":"sel"}', id: 'selection'),
      call('read_pages', '{"documentId":"doc","from":195,"to":205}', id: 'context'),
      answer('根据上下文解释心声社区。[page:197]'),
    ]);
    final run = makeRun(
      client,
      skill: 'explain',
      online: false,
      budget: RunBudget(limits: const ResearchBudget(pages: 0)),
    );
    final events = await run.run('解释心声社区').toList();
    final results = events
        .where((event) => event.eventType == StreamingEventType.functionCallResult)
        .expand((event) => (event.data as FunctionExecutionResultMessage).results)
        .toList();
    expect(results.map((result) => result.isError), [false, false]);
    expect(run.budget.pages, 11);
    expect(run.citations.items.map((citation) => citation.page), [1, for (var p = 195; p <= 205; p++) p]);
    expect(client.requests.last.first.toJson().toString(), contains('没有每轮总页数上限'));
    expect(client.calls, 3);
  });

  test('large ranges paginate and continue without a total page cap', () async {
    final client = ScriptClient([
      call('read_pages', '{"documentId":"doc","from":1,"to":25}', id: 'first'),
      call('read_pages', '{"documentId":"doc","from":21,"to":25}', id: 'next'),
      answer('已读完相关页面。[page:25]'),
    ]);
    final run = makeRun(client);
    final events = await run.run('解释').toList();
    final results = events
        .where((event) => event.eventType == StreamingEventType.functionCallResult)
        .expand((event) => (event.data as FunctionExecutionResultMessage).results)
        .map((result) => jsonDecode(result.content.whereType<TextPart>().single.text) as Map)
        .toList();
    expect(results.first['complete'], false);
    expect(results.first['pages'], hasLength(20));
    expect(results.first['nextPage'], 21);
    expect(results.last['complete'], true);
    expect(results.last['pages'], hasLength(5));
    expect(run.budget.pages, 25);
    expect(run.citations.items, hasLength(25));
    expect(run.budget.contextFull, false);
  });

  test('dense pages fit actual context space, preserve partial evidence and finish directly', () async {
    final reader = DenseReader();
    final client = ScriptClient([
      call('read_pages', '{"documentId":"doc","from":1,"to":10}', id: 'dense'),
      answer('依据已读片段回答，资料不完整。[page:1] [page:2]'),
    ]);
    final run = makeRun(
      client,
      reader: reader,
      budget: RunBudget(limits: const ResearchBudget(inputCharacters: 18000)),
    );
    final events = await run.run('解释').toList();
    final toolResult =
        (events.firstWhere((event) => event.eventType == StreamingEventType.functionCallResult).data
                as FunctionExecutionResultMessage)
            .results
            .single;
    expect(toolResult.isError, false);
    final result = jsonDecode(toolResult.content.whereType<TextPart>().single.text) as Map;
    expect(result['complete'], false);
    expect(result['notice'], contains('资料不完整'));
    final row = (result['pages'] as List).single as Map;
    final text = row['text'] as String;
    expect(row['textComplete'], false);
    expect(text, isNotEmpty);
    expect(reader.text, startsWith(text));
    expect(text.length, lessThan(reader.text.length));
    expect(utf8.decode(utf8.encode(text)), text);
    expect(reader.reads, [1]);
    expect(run.citations.items.single.quote, text);
    expect(run.citations.items.single.page, 1);
    expect(client.toolRequests.last, isEmpty);
    expect(jsonEncode(client.requests.last.map((message) => message.toJson()).toList()).length, lessThan(18000));
    final last =
        events.lastWhere((event) => event.eventType == StreamingEventType.fullModelMessage).data as ModelMessage;
    expect(last.textOutput, '依据已读片段回答，资料不完整。[page:1] ');
    expect(client.calls, 2);
  });

  test('no context space returns an explicit incomplete result without reading or registering evidence', () async {
    final reader = DenseReader();
    final registry = CitationRegistry(primaryDocumentId: 'doc', online: false);
    final budget = RunBudget(limits: const ResearchBudget(inputCharacters: 2300));
    final tools = AssistantTools(
      reader: reader,
      scope: ReadScope(studySetId: 'set', documents: {'doc'}),
      cancel: CancellationToken(),
      citations: registry,
      budget: budget,
    );
    final result = await tools.execute('read_pages', {'documentId': 'doc', 'from': 1, 'to': 1}) as Map;
    expect(result['complete'], false);
    expect(result['pages'], isEmpty);
    expect(reader.reads, isEmpty);
    expect(registry.items, isEmpty);
    expect(budget.contextFull, true);
  });

  test('concurrent page tools share context space and leave room for a final answer', () async {
    final client = ScriptClient([
      ModelMessage(
        model: 'fake',
        stopReason: 'tool_calls',
        functionCalls: [
          FunctionCall(id: 'one', name: 'read_pages', arguments: '{"documentId":"doc","from":1,"to":1}'),
          FunctionCall(id: 'two', name: 'read_pages', arguments: '{"documentId":"doc","from":2,"to":2}'),
        ],
      ),
      answer('仅依据已返回的片段回答。'),
    ]);
    final run = makeRun(
      client,
      reader: DenseReader(),
      budget: RunBudget(limits: const ResearchBudget(inputCharacters: 18000)),
    );
    final events = await run.run('解释').toList();
    final results =
        (events.firstWhere((event) => event.eventType == StreamingEventType.functionCallResult).data
                as FunctionExecutionResultMessage)
            .results;
    expect(results, hasLength(2));
    expect(results.map((result) => result.isError), everyElement(false));
    expect(run.citations.items, hasLength(1));
    expect(client.toolRequests.last, isEmpty);
    expect(jsonEncode(client.requests.last.map((message) => message.toJson()).toList()).length, lessThan(18000));
    expect(client.calls, 2);
  });

  test('study-set searches are independent of online search quota', () async {
    final client = ScriptClient([
      for (var i = 0; i < 4; i++) call('search_study_set', '{"query":"term"}', id: 'search-$i'),
      answer('根据本地检索结果回答。'),
    ]);
    final run = makeRun(client, online: false, budget: RunBudget(limits: const ResearchBudget(searches: 0)));
    await run.run('查找').toList();
    expect(run.budget.searches, 0);
    expect(client.calls, 5);
  });

  test('a rejected online search reservation preserves the search allowance', () {
    final budget = RunBudget(limits: const ResearchBudget(searches: 1));
    budget.reserve(search: true);
    expect(
      () => budget.reserve(search: true),
      throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.budget)),
    );
    expect(budget.searches, 1);
    expect(budget.remainingSearches, 0);
  });

  test('capability false sends no tools and rejects unsolicited tool calls', () async {
    final client = ScriptClient([answer('direct')]);
    final run = createAssistantRun(
      client: client,
      model: 'fake',
      state: AgentState(sessionId: 's'),
      requestId: 'r',
      reader: Reader(),
      scope: ReadScope(studySetId: 's'),
      mapId: 'm',
      baseRevision: 0,
      parents: {},
      supportsTools: false,
    );
    await run.run('question').toList();
    expect(client.toolRequests.single, isEmpty);
    final hook = PolicyHook(allowed: {'read_selection'}, budget: RunBudget(), online: true, toolsEnabled: false);
    final m = call('read_selection', '{}');
    final result = await hook.beforeToolCall(
      ToolCallHookContext(run.agent, call: m.functionCalls.single, modelMessage: m, availableTools: []),
    );
    expect(result.error, isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.toolProtocol));
    expect(
      AssistantModel.fromJson({
        'provider': 'compatible',
        'model': 'm',
        'endpoint': 'https://example.com',
        'supportsTools': false,
      }).supportsTools,
      false,
    );
  });

  test('connection errors differ from service errors and loops', () {
    expect(
      assistantFailureKind(DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError)),
      ResearchFailureKind.network,
    );
    expect(
      assistantFailureKind(const ResearchFailure(ResearchFailureKind.unavailable, 'connection')),
      ResearchFailureKind.network,
    );
    expect(assistantFailureKind(AgentException(AgentExceptionCode.loopDetection, 'private')), ResearchFailureKind.loop);
    expect(assistantFailureKind(StateError('private')), ResearchFailureKind.unavailable);
    final dio = DioException(
      requestOptions: RequestOptions(),
      response: Response(requestOptions: RequestOptions(), statusCode: 503),
    );
    expect(assistantFailureStatus(AgentException(AgentExceptionCode.unknown, 'private', error: dio)), 503);
    expect(assistantFailureStatus(StateError('private')), null);
    expect(assistantFailureStatus(const ResearchFailure(ResearchFailureKind.unavailable, null, null, 500)), 500);

    expect(
      () => RunBudget(maxCalls: 0).reserve(),
      throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.loop)),
    );
  });

  test('every skill carries the style contract', () {
    for (final skill in assistantSkills([])) {
      expect(skill.systemPrompt, contains(assistantAnswerStyle));
    }
    for (final token in ['150', '表格', '句末', 'web_search', 'fetch_source', '用户提问的语言', '不反问']) {
      expect(assistantSystemPrompt, contains(token));
    }
  });

  test('timeline keeps narration order, merges adjacent actions and roundtrips time', () {
    final start = DateTime.utc(2026);
    final message = Message(
      id: 'a',
      requestId: 'r',
      role: MessageRole.agent,
      startedAt: start,
      traces: [
        const TraceStep('n', '', TraceStatus.done, narration: '读取内容'),
        for (var i = 0; i < 3; i++) TraceStep('$i', 'unknown', TraceStatus.error, reason: '不存在的工具 unknown'),
      ],
    ).copyWith(endedAt: start.add(const Duration(milliseconds: 2300)));
    final copy = Message.fromJson(message.toJson());
    expect(copy.elapsedSeconds, 3);
    expect(copy.activity.first.narration, '读取内容');
    expect(copy.activity.last.count, 3);
    expect(() => copy.activity.add(copy.activity.first), throwsUnsupportedError);
  });
}

class DenseReader extends Reader {
  final text = List.filled(10000, '原文😀"\\\n').join();
  final reads = <int>[];
  @override
  Future<List<ReadPage>> readPages(
    String documentId,
    int from,
    int to,
    ReadScope scope,
    CancellationToken cancel,
  ) async {
    reads.add(from);
    return [ReadPage(documentId, from, text)];
  }
}
