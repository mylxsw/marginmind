import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;

import '../../../packages/mm_assistant/test/support.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/assistant_reader.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import 'helpers.dart';

class Secrets implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String name) async => values[name];
  @override
  Future<void> write(String name, String value) async {
    values[name] = value;
  }

  @override
  Future<void> delete(String name) async {
    values.remove(name);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('production factory opens study-set documents independently of question focus', () async {
    final content = demoContent();
    final secrets = Secrets()..values['anthropic'] = 'key';
    final reads = <(String, int)>[];
    const contexts = [
      ContextItem(id: 'sel', kind: ContextKind.selection, displayText: '术语', documentId: 'c1', page: 24),
      ContextItem(id: 'page', kind: ContextKind.page, displayText: '书名', documentId: 'c1', page: 24, auto: true),
    ];
    final factory = assistantRunFactory(
      secrets: secrets,
      documents: content.documents,
      reader: WorkspaceReader(
        content: () => content,
        contexts: contexts,
        filePath: (document) => document.fileName,
        pageText: (path, page) async {
          reads.add((path, page));
          return '$path:$page';
        },
      ),
      mapId: 'map',
      revision: () => 0,
      parents: () => {'root': null},
    );
    final conversation = Conversation(
      id: 'c',
      studySetId: 'demo-1',
      model: const AssistantModel(
        provider: AssistantProvider.claude,
        model: 'm',
        endpoint: 'https://api.anthropic.com/v1/messages',
      ),
    );
    final run = await factory(
      sdk.AgentState(sessionId: 'c'),
      conversation,
      Message(id: 'q', requestId: 'r', role: MessageRole.user, text: '解释它', contexts: contexts),
    );
    addTearDown(run.stop);
    final tool = run.agent.tools!.singleWhere((tool) => tool.name == 'read_pages');
    Map<String, dynamic> readResult(Object? result) =>
        jsonDecode(((result as sdk.AgentToolResult).content as sdk.TextPart).text) as Map<String, dynamic>;
    final result = readResult(await tool.executable!({'documentId': 'c1', 'from': 23, 'to': 25}));
    final pages = result['pages'] as List;
    expect(result['complete'], true);
    expect(pages.map((page) => page['page']), [23, 24, 25]);
    expect(readResult(await tool.executable!({'documentId': 'c2', 'from': 1, 'to': 1}))['pages'], hasLength(1));
    final outside = await tool.executable!({'documentId': 'outside-study-set', 'from': 1, 'to': 1});
    expect(outside, isA<sdk.AgentToolResult>());
    expect((outside as sdk.AgentToolResult).metadata?['failure'], 'invalidRequest');
    expect(reads, [('a.pdf', 23), ('a.pdf', 24), ('a.pdf', 25), ('b.pdf', 1)]);
    expect(run.agent.systemPrompts.join('\n'), contains('学习的底层逻辑'));
    expect(run.agent.systemPrompts.join('\n'), contains('"pageCount":164'));

    final withoutFocus = await factory(
      sdk.AgentState(sessionId: 'no-focus'),
      conversation,
      Message(id: 'q2', requestId: 'r2', role: MessageRole.user, text: '读第二份文档'),
    );
    addTearDown(withoutFocus.stop);
    final unfocusedTool = withoutFocus.agent.tools!.singleWhere((tool) => tool.name == 'read_pages');
    expect(
      readResult(await unfocusedTool.executable!({'documentId': 'c2', 'from': 1, 'to': 1}))['pages'],
      hasLength(1),
    );
  });
  test('composition reads correct key, rejects missing credentials and closes invalid runs', () async {
    final secrets = Secrets();
    final factory = assistantRunFactory(
      secrets: secrets,
      reader: Reader(),
      documents: const [],
      mapId: 'map',
      revision: () => 0,
      parents: () => {'root': null},
    );
    final conversation = Conversation(
      id: 'c',
      studySetId: 'set',
      model: const AssistantModel(
        provider: AssistantProvider.claude,
        model: 'm',
        endpoint: 'https://api.anthropic.com/v1/messages',
      ),
    );
    final question = Message(id: 'q', requestId: 'r', role: MessageRole.user, text: 'question');
    await expectLater(factory(sdk.AgentState(sessionId: 'c'), conversation, question), throwsA(isA<ResearchFailure>()));
    secrets.values['anthropic'] = 'key';
    final run = await factory(sdk.AgentState(sessionId: 'c'), conversation, question);
    run.stop();
    expect(run.cancel.isCancelled, true);
    // A conversation asked to answer without tools gets a run without them.
    final plain = await factory(
      sdk.AgentState(sessionId: 'c'),
      conversation.copyWith(
        model: const AssistantModel(
          provider: AssistantProvider.claude,
          model: 'm',
          endpoint: 'https://api.anthropic.com/v1/messages',
          supportsTools: false,
        ),
      ),
      question,
    );
    plain.stop();
    await expectLater(
      factory(
        sdk.AgentState(sessionId: 'c'),
        conversation,
        Message(id: 'q', requestId: 'r', role: MessageRole.user, skill: 'unknown'),
      ),
      throwsFormatException,
    );
  });
}
