import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_network.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_support.dart' show FakeSecrets;

class NoSnapshots implements StudySetContentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'composition prefers the conversation native search, otherwise its configured fallback; offline has no backend',
    () async {
      SharedPreferences.setMockInitialValues({
        'assistant.searxng': 'https://search.example/search',
        'assistant.localEnabled': true,
        for (final p in AssistantProvider.values) 'assistant.model.${p.name}': 'm',
      });
      final prefs = await SharedPreferences.getInstance();
      final secrets = FakeSecrets();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          assistantSecretsProvider.overrideWithValue(secrets),
          contentRepositoryProvider.overrideWithValue(InMemoryStudySetContentRepository({})),
        ],
      );
      addTearDown(container.dispose);
      await container.read(assistantServicesProvider.future);
      for (final provider in AssistantProvider.values) {
        secrets.reads.clear();
        final conversation = Conversation(
          id: 'c',
          studySetId: 's',
          model: AssistantModel(provider: provider, model: 'm', endpoint: 'https://example.org/v1/responses'),
        );
        final p = Provider((ref) => assistantNetworkFor(ref, 's', conversation));
        final n = await container.read(p) as SnapshotAssistantNetwork;
        expect(n.discovery, switch (provider) {
          AssistantProvider.claude ||
          AssistantProvider.responses ||
          AssistantProvider.gemini => isA<UnavailableWebSearch>(),
          _ => isA<SearxngSearch>(),
        });
        expect(secrets.reads, [
          if (provider != AssistantProvider.ollama) ...[
            AssistantServicesStore.account('legacy-${provider.name}'),
            legacyAssistantAccount(provider),
          ],
        ]);
        if (n.discovery case final SearxngSearch s) expect(s.endpoint, 'https://search.example/search');
        final offline = Provider((ref) => assistantNetworkFor(ref, 's', conversation.copyWith(online: false)));
        expect(await container.read(offline), isNull);
      }
      final noFiles = ProviderContainer(overrides: [contentRepositoryProvider.overrideWithValue(NoSnapshots())]);
      addTearDown(noFiles.dispose);
      final p = Provider(
        (ref) => assistantNetworkFor(
          ref,
          's',
          Conversation(
            id: 'c',
            studySetId: 's',
            model: const AssistantModel(
              provider: AssistantProvider.claude,
              model: 'm',
              endpoint: 'https://x/v1/messages',
            ),
          ),
        ),
      );
      expect(await noFiles.read(p), isNull);
    },
  );
}
