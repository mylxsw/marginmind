import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:mm_research/mm_research.dart';

import 'package:dart_agent_core/dart_agent_core.dart' hide MessageRole;
import 'package:dart_agent_core/eval.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  for (final skill in [null, ...skillPrompts.keys]) {
    for (final online in [false, true]) {
      for (final stream in [false, true]) {
        test('unique tools for skill=$skill online=$online stream=$stream', () async {
          final client = ScriptClient([answer('完成')]);
          final run = makeRun(client, skill: skill, online: online);
          await run.agent.runStream([UserMessage.text('解释')], useStream: stream).toList();
          final tools = client.toolRequests.single;
          final names = tools.map((t) => t.name).toList();
          expect(names, hasLength(names.toSet().length));
          expect(names, containsAll(AssistantTools.readNames));
          expect(names, containsAll(['activate_skills', 'deactivate_skills']));
          expect(names.contains('propose_map_edits'), skill == 'organize' || skill == 'quiz');
          expect(names.contains('web_search'), online && {'verify', 'papers', 'videos'}.contains(skill));
        });
      }
    }
  }
  test('overlapping active skills keep unique tools through reads and proposals', () async {
    final client = ScriptClient([
      call('activate_skills', '{"skill_names":["quiz","verify"]}', id: 'activate'),
      call('read_pages', '{"documentId":"doc","from":1,"to":1}', id: 'read'),
      call('propose_map_edits', '{"ops":[{"id":"one","kind":"addTopic","parentId":"root","title":"New"}]}'),
    ]);
    final run = makeRun(client, skill: 'organize');
    await run.run('整理').toList();
    expect(client.calls, 3);
    for (final tools in client.toolRequests) {
      final names = tools.map((t) => t.name).toList();
      expect(names, hasLength(names.toSet().length));
      expect(names, containsAll([...AssistantTools.readNames, 'propose_map_edits']));
    }
    expect(client.toolRequests.last.map((t) => t.name), contains('web_search'));
    expect(run.citations.items.single.page, 1);
    expect(run.proposals.proposals, hasLength(1));
  });
  test('page-only organize can read and propose without exposing unauthorized branches', () async {
    final client = ScriptClient([
      call('read_pages', '{"documentId":"doc","from":1,"to":1}', id: 'read'),
      call(
        'propose_map_edits',
        '{"ops":[{"id":"one","kind":"addTopic","parentId":"root","title":"New"},'
            '{"id":"two","kind":"addNote","parentId":"new:one","title":"Details","body":"Page content"}]}',
      ),
    ]);
    final run = createAssistantRun(
      client: client,
      model: 'fake',
      state: AgentState(sessionId: 'page-only'),
      requestId: 'request',
      reader: Reader(),
      scope: ReadScope(
        studySetId: 'set',
        pages: {
          'doc': {1},
        },
      ),
      mapId: 'map',
      baseRevision: 0,
      parents: {'root': null},
      primaryDocumentId: 'doc',
      skill: 'organize',
      online: false,
    );
    await run.run('把这部分整理进脑图').toList();
    for (final tools in client.toolRequests) {
      expect(tools.map((t) => t.name), isNot(contains('read_branch')));
      expect(tools.map((t) => t.name), containsAll(['read_pages', 'propose_map_edits']));
    }
    expect(run.citations.items.single.page, 1);
    expect(run.proposals.proposals, hasLength(1));
    expect(run.proposals.proposals.values.single.operations.last.parentId, 'new:one');
  });
  test('invalid proposal returns actionable field and reference guidance to the model', () async {
    final client = ScriptClient([
      call(
        'propose_map_edits',
        '{"ops":[{"id":"one","kind":"addTopic","parentId":"root","title":"New","body":"Invalid"}]}',
      ),
      call(
        'propose_map_edits',
        '{"ops":[{"id":"one","kind":"addTopic","parentId":"root","title":"New"}]}',
        id: 'fixed',
      ),
    ]);
    final run = makeRun(client, skill: 'organize');
    final events = await run.run('整理').toList();
    final firstResult =
        events.firstWhere((event) => event.eventType == StreamingEventType.functionCallResult).data
            as FunctionExecutionResultMessage;
    expect(firstResult.results.single.isError, true);
    final feedback = firstResult.results.single.content.whereType<TextPart>().map((part) => part.text).join();
    expect(feedback, contains('no body'));
    expect(feedback, contains('new:<opId>'));
    expect(client.requests.last.whereType<FunctionExecutionResultMessage>().single.results.single.isError, true);
    expect(run.proposals.proposals, hasLength(1));
  });
  test('focused selection can read surrounding pages in its study-set document', () async {
    final client = ScriptClient([
      call('read_pages', '{"documentId":"doc","from":193,"to":195}', id: 'surrounding'),
      answer('上下文解释 [page:193] [page:194] [page:195] [page:196]'),
    ]);
    final state = AgentState(sessionId: 'surrounding-pages');
    final run = createAssistantRun(
      client: client,
      model: 'fake',
      state: state,
      requestId: 'request',
      reader: Reader(),
      scope: scopeFromContexts(
        'set',
        const [ContextItem(id: 'sel', kind: ContextKind.selection, displayText: '术语', documentId: 'doc', page: 194)],
        documentIds: ['doc'],
      ),
      mapId: 'map',
      baseRevision: 0,
      parents: {'root': null},
      primaryDocumentId: 'doc',
      online: false,
    );
    final events = await run.run('解释一下这段话').toList();
    final result =
        events.firstWhere((e) => e.eventType == StreamingEventType.functionCallResult).data
            as FunctionExecutionResultMessage;
    expect(result.results.single.isError, false);
    expect(run.citations.items.map((c) => c.page), [193, 194, 195]);
    final last = events.lastWhere((e) => e.eventType == StreamingEventType.fullModelMessage).data as ModelMessage;
    expect(last.textOutput, '上下文解释 [page:193] [page:194] [page:195] ');
    expect(run.budget.pages, 3);
    expect((state.metadata['assistant.diagnostics'] as Map)['request']['tools'].single['result'], 'done');
  });
  test('four readers are scoped and register only actual page evidence', () async {
    final registry = CitationRegistry(primaryDocumentId: 'doc', online: false);
    final cancellation = CancellationToken();
    final tools = AssistantTools(
      reader: Reader(),
      scope: ReadScope(
        studySetId: 'set',
        pages: {
          'doc': {1, 2},
        },
        selections: {'sel'},
        branches: {
          'map': {'root'},
        },
      ),
      cancel: cancellation,
      citations: registry,
      budget: RunBudget(),
    );
    expect(await tools.execute('read_selection', {'selectionId': 'sel'}), isNotEmpty);
    final read = await tools.execute('read_pages', {'documentId': 'doc', 'from': 1, 'to': 2}) as Map;
    expect(read['pages'], hasLength(2));
    expect(read['complete'], true);
    expect(await tools.execute('search_study_set', {'query': 'term'}), hasLength(1));
    expect(await tools.execute('read_branch', {'mapId': 'map', 'nodeId': 'root'}), hasLength(1));
    for (final args in [
      {'documentId': 'other', 'from': 1, 'to': 1},
      {'documentId': 'doc', 'from': 0, 'to': 2},
      {'documentId': 'doc', 'from': 1, 'to': 6},
    ]) {
      await expectLater(tools.execute('read_pages', args), throwsFormatException);
    }
    await expectLater(tools.execute('read_selection', {'selectionId': 'other'}), throwsFormatException);
    await expectLater(tools.execute('read_branch', {'mapId': 'other', 'nodeId': 'root'}), throwsFormatException);
    await expectLater(tools.execute('search_study_set', {'query': '', 'limit': 0}), throwsFormatException);
    await expectLater(tools.execute('search_study_set', {'query': 'ok', 'limit': 30}), throwsFormatException);
    await expectLater(tools.execute('unknown', {}), throwsFormatException);
    await expectLater(tools.execute('web_search', {'query': 'ok'}), throwsA(isA<ResearchFailure>()));
    expect(registry.items, hasLength(2));
    cancellation.cancel();
    await expectLater(tools.execute('read_selection', {'selectionId': 'sel'}), throwsA(isA<ResearchFailure>()));
  });
  test('read -> split citations and final text; no unregistered source', () async {
    final client = ScriptClient([
      call('read_pages', '{"documentId":"doc","from":1,"to":1}'),
      answer('Answer [page:1] [page:9] [source:1]'),
    ]);
    final run = makeRun(client);
    final events = await run.run('explain').toList();
    final last = events.lastWhere((e) => e.eventType == StreamingEventType.fullModelMessage).data as ModelMessage;
    expect(last.textOutput, 'Answer [page:1]  ');
    expect(run.citations.items.single.page, 1);
    expect(client.calls, 2);
  });
  test('defer produces durable proposal and ends without executing or requesting again', () async {
    final client = ScriptClient([
      call('propose_map_edits', '{"ops":[{"id":"one","kind":"addTopic","parentId":"root","title":"New"}]}'),
    ]);
    final run = makeRun(client, skill: 'organize');
    final events = await run.run('organize').toList();
    expect(client.calls, 1);
    expect(run.proposals.proposals, hasLength(1));
    final result =
        (events.lastWhere((e) => e.eventType == StreamingEventType.functionCallResult).data
                as FunctionExecutionResultMessage)
            .results
            .single;
    expect(result.isError, false);
    expect(result.metadata!['proposalId'], 'request-call');
    expect(run.agent.state.metadata['assistant.proposals'], hasLength(1));
  });
  for (final name in ['delete_node', 'modify_original', 'fetch_source']) {
    test('policy rejects $name and never registers evidence', () async {
      final client = ScriptClient([call(name, '{"url":"http://127.0.0.1/secret"}'), answer('cannot do that')]);
      final run = makeRun(client, skill: 'verify', online: name != 'fetch_source');
      final events = await run.run('do it').toList();
      final result =
          (events.firstWhere((e) => e.eventType == StreamingEventType.functionCallResult).data
                  as FunctionExecutionResultMessage)
              .results
              .single;
      expect(result.isError, true);
      expect(run.citations.items, isEmpty);
    });
  }
  test('budget, empty stream and missing terminator never silently retry', () async {
    for (final client in [
      ScriptClient([answer('partial', stop: null)]),
      ScriptClient([answer('')]),
      ScriptClient([answer('too much')]),
    ]) {
      final run = makeRun(client, budget: RunBudget(limits: const ResearchBudget(responseBytes: 50)));
      await expectLater(run.run('x').toList(), throwsA(isA<ResearchFailure>()));
      expect(client.calls, 1);
    }
  });
  test('citation buffer spans chunks, strips forged and incomplete markers', () {
    final registry = CitationRegistry(primaryDocumentId: 'doc', online: true)..page(const ReadPage('doc', 2, 'text'));
    final buffer = CitationBuffer(registry);
    expect(buffer.add('a [pa'), 'a ');
    expect(buffer.add('ge:2] [source:8] '), '[page:2]  ');
    expect(buffer.add('[source:'), '');
    expect(buffer.finish(), '');
    expect(buffer.add('[ordinary'), '');
    expect(buffer.finish(), '[ordinary');
    expect(registry.page(const ReadPage('other', 2, 'other')), '[source:1]');
    expect(registry.used('[page:2][source:1]'), hasLength(2));
    expect(CitationRegistry(primaryDocumentId: 'doc', online: false).clean('[page:2]'), '');
    expect(
      () => CitationRegistry(online: false).source(
        AssistantSource(
          id: 's',
          version: 1,
          kind: 'snapshot',
          title: 't',
          url: Uri.parse('https://example.com'),
          paragraphs: {'p': 'text'},
        ),
      ),
      throwsA(isA<ResearchFailure>()),
    );
  });
  for (final skill in skillPrompts.keys) {
    for (var scenario = 0; scenario < 3; scenario++) {
      test('$skill case $scenario deterministic recording / strict replay', () async {
        final store = InMemoryRecordingStore();
        final fake = ScriptClient([answer('Case $scenario [page:99]')]);
        final recording = RecordingLLMClient(inner: fake, store: store);
        final run = makeRun(recording, skill: skill, online: scenario != 0);
        // Framework 2.1.8 only records generate(), never stream().
        await run.agent.runStream([UserMessage.text('case $scenario')], useStream: false).toList();
        final replay = makeRun(
          ReplayLLMClient(store: store),
          skill: skill,
          online: scenario != 0,
        );
        final events = await replay.agent.runStream([UserMessage.text('case $scenario')], useStream: false).toList();
        expect(
          (events.lastWhere((e) => e.eventType == StreamingEventType.fullModelMessage).data as ModelMessage).textOutput,
          'Case $scenario ',
        );
        expect(fake.calls, 1);
      });
    }
  }
  test('network separates discovery from persisted paragraphs', () async {
    final source = AssistantSource(
      id: 's',
      version: 1,
      kind: 'snapshot',
      title: 'Title',
      url: Uri.parse('https://example.com'),
      paragraphs: {'p1': 'actual text'},
    );
    final paper = AssistantSource(
      id: 'p',
      version: 1,
      kind: 'openAlex',
      title: 'Paper',
      url: Uri.parse('https://openalex.org/W1'),
      paragraphs: {'meta': 'metadata'},
    );
    final registry = CitationRegistry(online: true);
    final tools = AssistantTools(
      reader: Reader(),
      scope: ReadScope(studySetId: 's'),
      cancel: CancellationToken(),
      citations: registry,
      budget: RunBudget(),
      network: MemoryAssistantNetwork(
        results: [AssistantSearchResult('Title', source.url, 'snippet')],
        sources: [source, paper],
      ),
    );
    await tools.execute('web_search', {'query': 'term'});
    expect(registry.items, isEmpty);
    await tools.execute('fetch_source', {'url': source.url.toString()});
    expect(registry.items.single.quote, 'actual text');
    await tools.execute('search_papers', {'query': 'term'});
    expect(registry.items, hasLength(2));
    await expectLater(
      tools.execute('fetch_source', {'url': 'https://example.com/missing'}),
      throwsA(isA<ResearchFailure>()),
    );
    expect(jsonEncode(registry.items.map((c) => c.toJson()).toList()), contains('p1'));
  });
  test('only forged marker cannot trigger SDK hidden empty retry', () async {
    final client = ScriptClient([answer('[page:99]')]);
    await expectLater(makeRun(client).run('question').toList(), throwsA(isA<ResearchFailure>()));
    expect(client.calls, 1);
  });
  test('online policy rejects literal private addresses and mixed DNS results', () async {
    final run = makeRun(ScriptClient([]));
    final hook = PolicyHook(
      allowed: {'fetch_source'},
      budget: RunBudget(),
      online: true,
      urls: UrlPolicy(lookup: (_) async => [InternetAddress('8.8.8.8'), InternetAddress('10.0.0.1')]),
    );
    for (final url in ['http://127.0.0.1/', 'http://192.168.1.1/', 'https://rebound.example/']) {
      final m = call('fetch_source', jsonEncode({'url': url}));
      expect(
        (await hook.beforeToolCall(
          ToolCallHookContext(run.agent, call: m.functionCalls.single, modelMessage: m, availableTools: []),
        )).action,
        ToolCallHookAction.deny,
      );
    }
  });
  test('deadline cancels idle transport and classifies timeout', () async {
    final output = StreamController<StreamingMessage>();
    final client = StreamClient((token) {
      token!.whenCancel.then((_) => output.close());
      return output.stream;
    });
    final run = makeRun(
      client,
      budget: RunBudget(limits: const ResearchBudget(duration: Duration(milliseconds: 20))),
    );
    await expectLater(
      run.run('question').toList(),
      throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.timeout)),
    );
    expect(output.isClosed, true);
    expect(client.calls, 1);
  });
  test('record/replay includes actual read tools, citations and deferred proposal', () async {
    final store = InMemoryRecordingStore();
    final client = ScriptClient([
      call('read_pages', '{"documentId":"doc","from":1,"to":1}', id: 'read'),
      call(
        'propose_map_edits',
        '{"ops":[{"id":"one","kind":"addTopic","parentId":"root","title":"Topic"}]}',
        id: 'write',
      ),
    ]);
    final record = makeRun(
      RecordingLLMClient(inner: client, store: store),
      skill: 'organize',
    );
    await record.agent.runStream([UserMessage.text('read and organize')], useStream: false).toList();
    final replay = makeRun(ReplayLLMClient(store: store), skill: 'organize');
    await replay.agent.runStream([UserMessage.text('read and organize')], useStream: false).toList();
    expect(replay.citations.items.single.marker, '[page:1]');
    expect(replay.proposals.proposals.values.single.operations.single.title, 'Topic');
    expect(client.calls, 2);
  });
  test('chunk hook never emits incomplete or forged citation in stream', () async {
    late StreamClient client;
    client = StreamClient(
      (_) => client.calls == 1
          ? Stream.value(StreamingMessage(modelMessage: call('read_pages', '{"documentId":"doc","from":1,"to":1}')))
          : Stream.fromIterable([
              StreamingMessage(modelMessage: answer('A [pa', stop: null)),
              StreamingMessage(modelMessage: answer('ge:1] [page:999]')),
            ]),
    );
    final events = await makeRun(client).run('question').toList();
    final chunks = events
        .where((e) => e.eventType == StreamingEventType.modelChunkMessage)
        .map((e) => (e.data as ModelMessage).textOutput ?? '')
        .toList();
    expect(chunks, ['', 'A ', '[page:1] ']);
  });
}
