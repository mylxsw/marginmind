import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'support.dart';

class HugeReader extends Reader {
  @override
  Future<List<BranchNode>> readBranch(String mapId, String nodeId, ReadScope scope, CancellationToken cancel) async => [
    BranchNode(id: 'root', title: 'Root', body: 'x' * 65000),
  ];
}

void main() {
  test('ordinary conversation history survives turns without source reads', () async {
    final state = sdk.AgentState(sessionId: 'conversation');
    final client = ScriptClient([answer('first-answer'), answer('second-answer')]);
    await makeRun(client, state: state).run('first-question').drain<void>();
    await makeRun(client, state: state).run('second-question').drain<void>();
    final sent = jsonEncode(client.requests.last.map((m) => m.toJson()).toList());
    expect(sent, contains('first-question'));
    expect(sent, contains('first-answer'));
    expect(sent, contains('second-question'));
  });
  test('all standard task knowledge versions resolve without cross-task translation style', () {
    final registry = standardKnowledgeRegistry();
    for (final type in TaskType.values) {
      final spec = TaskSpec(
        type: type,
        inputSchema: 'input',
        resultSchema: 'result',
        promptVersion: '1',
        schemaVersion: '1',
        completionRule: 'complete',
      );
      expect(registry.resolve(spec, standardKnowledgeVersions(spec)).map((b) => b.id), type.knowledgePacks);
    }
  });
  test('persistent source markers never bind another source and evidence IDs survive roundtrip', () {
    final metadata = <String, dynamic>{};
    final first = CitationRegistry(online: true, persistentState: metadata);
    final a = first.page(const ReadPage('A', 1, 'alpha'));
    final second = CitationRegistry(online: true, persistentState: jsonDecode(jsonEncode(metadata)));
    final b = second.page(const ReadPage('B', 1, 'beta'));
    expect(a, '[source:1]');
    expect(b, '[source:2]');
    expect(second.used(a).single.documentId, 'A');
    expect(second.used(a).single.evidenceId, first.items.single.evidenceId);
  });
  test('primary document changes do not reuse page markers', () {
    final metadata = <String, dynamic>{};
    final first = CitationRegistry(online: true, primaryDocumentId: 'A', persistentState: metadata);
    first.page(const ReadPage('A', 1, 'alpha'));
    final second = CitationRegistry(online: true, primaryDocumentId: 'B', persistentState: metadata);
    expect(second.page(const ReadPage('B', 1, 'beta')), '[source:1]');
    expect(second.used('[page:1]').single.documentId, 'A');
  });
  test('compaction archives complete tool rounds and preserves signed blocks verbatim', () async {
    final state = sdk.AgentState(sessionId: 'history');
    final signed = sdk.ModelMessage(
      model: 'fake',
      stopReason: 'tool_calls',
      contentBlocks: [
        {'type': 'thinking', 'thinking': 'private', 'signature': 'signed'},
      ],
      functionCalls: [sdk.FunctionCall(id: 'tool-1', name: 'read_pages', arguments: '{}')],
    );
    state.history.messages.addAll([
      sdk.UserMessage.text('x' * 65000),
      signed,
      sdk.FunctionExecutionResultMessage(
        results: [
          sdk.FunctionExecutionResult(
            id: 'tool-1',
            name: 'read_pages',
            isError: false,
            arguments: '{}',
            content: [sdk.TextPart('read content')],
          ),
        ],
      ),
      sdk.UserMessage.text('follow-up'),
      answer('previous'),
      sdk.UserMessage.text('latest'),
    ]);
    await TurnContextCompressor(maxCharacters: 2000).compress(state);
    expect(jsonEncode(state.history.messages.first.toJson()), contains('follow-up'));
    expect((state.metadata['runtime.history.v1'] as List).single[1], signed.toJson());
    expect(jsonEncode(state.history.toJson()).length, lessThan(2000));
  });
  test('oversized branch is bounded and paginated, subsequent model request succeeds', () async {
    final client = ScriptClient([call('read_branch', '{"mapId":"map","nodeId":"root"}'), answer('partial branch')]);
    final run = makeRun(client, reader: HugeReader());
    await run.run('Read branch').drain<void>();
    expect(client.calls, 2);
    final messages = jsonEncode(client.requests.last.map((m) => m.toJson()).toList());
    expect(messages.length, lessThan(60000));
    expect(messages, contains('nextCursor'));
    expect(messages, contains('dataFragment'));
  });
  test('translate prompt excludes summary style and attachments stay out of system', () async {
    final client = ScriptClient([answer('translation')]);
    final run = createAssistantRun(
      client: client,
      model: 'fake',
      state: sdk.AgentState(sessionId: 's'),
      requestId: 'r',
      reader: Reader(),
      scope: ReadScope(studySetId: 'set'),
      mapId: 'map',
      baseRevision: 0,
      parents: {},
      skill: 'translate',
      attachedContext: ['UNTRUSTED_SECRET_TEXT'],
    );
    await run.run('translate').drain<void>();
    final system = jsonEncode(client.requests.single.whereType<sdk.SystemMessage>().map((m) => m.toJson()).toList());
    expect(system, isNot(contains('加粗结论')));
    expect(system, isNot(contains('UNTRUSTED_SECRET_TEXT')));
    expect(jsonEncode(client.requests.single.map((m) => m.toJson()).toList()), contains('UNTRUSTED_SECRET_TEXT'));
  });
  test('65000-character archived history allows a short follow-up', () async {
    final state = sdk.AgentState(sessionId: 's');
    state.metadata['assistant.evidence.v1'] = {'next': 1, 'items': []};
    state.history.messages.addAll([sdk.UserMessage.text('x' * 65000), answer('old')]);
    final client = ScriptClient([answer('new')]);
    await makeRun(client, state: state).run('follow-up').drain<void>();
    expect(client.calls, 1);
    expect(state.metadata['runtime.history.v1'], isNotEmpty);
  });
}
