import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dart_agent_core/dart_agent_core.dart' as sdk;

import '../../../packages/mm_assistant/test/support.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  test('settings default online; keys only in service-specific secret store', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secrets = Secrets();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantSecretsProvider.overrideWithValue(secrets),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(assistantSettingsProvider).online, true);
    expect(container.read(assistantSettingsProvider).localEnabled, false);
    final controller = container.read(assistantSettingsProvider.notifier);
    await controller.saveKey('claude-key');
    expect(secrets.values['anthropic'], 'claude-key');
    for (final provider in AssistantProvider.values) {
      await controller.configure(
        AssistantSettings(
          provider: provider,
          model: 'model',
          endpoint: 'https://example.com',
          online: false,
          localEnabled: true,
          searxngEndpoint: 'https://search.example.com',
        ),
      );
      await controller.saveKey('key-${provider.name}');
      expect(container.read(assistantSettingsProvider).configuration.provider, provider);
      container.invalidate(assistantSettingsProvider);
      expect(container.read(assistantSettingsProvider).online, false);
    }
    expect(prefs.getKeys().any((k) => k.contains('key')), false);
    await container.read(assistantSettingsProvider.notifier).saveKey('');
    expect(secrets.values.containsKey('assistant.ollama'), false);
    expect(AssistantSettingsController.account(AssistantProvider.responses), 'openai');
  });
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
