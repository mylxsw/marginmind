import 'package:dart_agent_core/dart_agent_core.dart' as sdk;

import '../../../packages/mm_assistant/test/support.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

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
  test('composition reads correct key, rejects missing credentials and closes invalid runs', () async {
    final secrets = Secrets();
    final factory = assistantRunFactory(
      secrets: secrets,
      reader: Reader(),
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
