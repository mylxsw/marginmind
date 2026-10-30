import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/workspace/word_lookup.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import 'assistant_support.dart' show FakeSecrets;

void main() {
  const remote = AssistantModel(
    provider: AssistantProvider.compatible,
    model: 'fixture',
    endpoint: 'https://example.org/v1',
    serviceId: 'lookup-service',
  );
  test('lookup factory resolves selected service credentials and maps missing keys', () async {
    final secrets = FakeSecrets();
    final container = ProviderContainer(
      overrides: [
        assistantSecretsProvider.overrideWithValue(secrets),
        assistantDefaultModelProvider.overrideWithValue(remote),
      ],
    );
    addTearDown(container.dispose);
    final service = container.read(wordLookupProvider);
    await expectLater(
      service.connect(remote),
      throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.authentication)),
    );
    secrets.values[AssistantServicesStore.account('lookup-service')] = 'fixture';
    final connection = await service.connect(remote);
    connection.close();
    expect(secrets.reads, everyElement(AssistantServicesStore.account('lookup-service')));
    container.read(assistantKeysProvider.notifier).changed();
    expect(container.read(wordLookupProvider), isNot(same(service)));
  });
  test('local Ollama factory needs no credential and uses translation connection policy', () async {
    const local = AssistantModel(
      provider: AssistantProvider.ollama,
      model: 'local',
      endpoint: 'http://localhost:11434',
      localEnabled: true,
    );
    final container = ProviderContainer(
      overrides: [
        assistantSecretsProvider.overrideWithValue(FakeSecrets()),
        assistantDefaultModelProvider.overrideWithValue(local),
      ],
    );
    addTearDown(container.dispose);
    final connection = await container.read(wordLookupProvider).connect(local);
    connection.close();
  });
}
