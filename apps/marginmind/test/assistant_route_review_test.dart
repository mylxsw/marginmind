import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:marginmind/features/assistant/settings/model_route_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/widgets/assistant_task_setup.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_support.dart';

import 'package:marginmind/features/assistant/assistant_scope.dart' show MemoryConversationArchive;

import 'package:marginmind/features/assistant/settings/ai_task_status.dart';

AssistantService service() => AssistantService(
  id: 'local',
  name: 'Local',
  protocol: ServiceProtocol.ollama,
  endpoint: 'http://localhost:11434/v1',
  localEnabled: true,
  models: [const ServiceModel(id: 'chat')],
);

CapabilityProfiles profiles(AssistantService s) => CapabilityProfiles()
  ..put(
    ModelCapabilityProfile(
      identity: serviceCapabilityIdentity(s, s.models.single),
      thinking: ThinkingCapability.switchable,
      tools: CapabilitySupport.supported,
      historyReplay: CapabilitySupport.supported,
      policies: {ReasoningPolicy.off: ReasoningRecipe.effortNone},
      evidence: CapabilityEvidence(
        source: CapabilityEvidenceSource.maintainedProfile,
        reference: 'test-only',
        semanticBasis: 'Synthetic routing UI test',
        wireVerified: true,
        verifiedAt: DateTime.utc(2026),
      ),
    ),
  );

Map<String, Object> preferences(AssistantService s) => {
  AssistantServicesStore.settingsKey: jsonEncode(AssistantServices(services: [s]).toJson()),
  AssistantRoutingStore.settingsKey: jsonEncode({
    'version': 1,
    'revision': 1,
    'defaults': {},
    'heavyReasoning': 'off',
    'bindings': {
      'assistant_chat': {
        'mode': 'explicit',
        'model': {'serviceId': 'local', 'modelId': 'chat'},
      },
    },
  }),
};

void main() {
  for (final width in [1000.0, 1400.0]) {
    for (final issue in [
      RoutingIssue.none,
      RoutingIssue.unknown,
      RoutingIssue.invalidConfiguration,
      RoutingIssue.serviceOff,
      RoutingIssue.secretUnavailable,
    ]) {
      testWidgets('real composer bounds $issue warning and keeps repair controls at $width', (tester) async {
        await openAssistantApp(
          tester,
          size: Size(width, 800),
          overrides: [
            assistantTaskRouteProvider((TaskType.assistantChat, null)).overrideWith(
              (ref) async => RoutingRowState(
                effective: const ModelReference('local', 'chat'),
                source: RoutingSource.functionBinding,
                issue: issue,
              ),
            ),
          ],
        );
        await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('assistant-model')), findsOneWidget);
        expect(find.byKey(const ValueKey('assistant-input')), findsOneWidget);
        final model = find.byKey(const ValueKey('assistant-model'));
        expect(
          find.descendant(of: model, matching: find.byType(RoutingIssueLine)),
          issue == RoutingIssue.none ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('malformed conversation routing leaves its picker reachable and can follow settings', (tester) async {
    final s = service();
    final archive = MemoryConversationArchive();
    final saved = sdk.AgentState(sessionId: 'broken');
    saved.metadata['assistant.view'] = Conversation(
      id: 'broken',
      title: 'Broken routing',
      messages: [
        Message(id: 'q', requestId: 'r', role: MessageRole.user, text: 'Question'),
        Message(id: 'a', requestId: 'r', role: MessageRole.agent, text: 'Answer'),
      ],
      studySetId: 'demo-1',
      model: s.configuration(s.models.single),
      archiveFields: {
        'taskRouting': {'version': 1, 'assistantChat': 42},
      },
    ).toJson();
    await archive.save(saved);
    await openAssistantApp(
      tester,
      archive: archive,
      prefs: preferences(s),
      overrides: [assistantCapabilityProfilesProvider.overrideWithValue(profiles(s))],
    );
    await openAssistantConversation(tester, 'broken');
    expect(find.text('设置无法读取'), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-model')), findsOneWidget);
    await tester.tap(find.byType(ModelRoutePicker));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跟随设置'));
    await tester.pumpAndSettle();
    expect(conversationRoutingOverride(conversationOf(tester).toJson(), TaskType.assistantChat), isNull);
    expect(find.text('设置无法读取'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('preview refreshes on service identity, keys and capability-provider refresh', () async {
    final s = service();
    final cloud = AssistantService(
      id: 'local',
      name: 'Cloud',
      protocol: ServiceProtocol.openai,
      endpoint: 'https://fixture.example/v1',
      models: [const ServiceModel(id: 'chat')],
    );
    SharedPreferences.setMockInitialValues(preferences(s));
    final prefs = await SharedPreferences.getInstance();
    final secrets = FakeSecrets();
    var evidence = profiles(s);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantSecretsProvider.overrideWithValue(secrets),
        assistantCapabilityProfilesProvider.overrideWith((ref) => evidence),
      ],
    );
    addTearDown(container.dispose);
    final provider = assistantTaskRouteProvider((TaskType.assistantChat, null));
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    Future<RoutingRowState> row() async {
      await container.pump();
      return container.read(provider.future);
    }

    expect((await row()).issue, RoutingIssue.none);
    final revision = (await container.read(assistantRoutingProvider.future)).revision;
    final services = container.read(assistantServicesProvider.notifier);
    await services.setEnabled('local', false);
    expect((await row()).issue, RoutingIssue.serviceOff);
    await services.setEnabled('local', true);
    // Re-enabling advances identity. Old evidence must not grant the new revision.
    expect((await row()).issue, RoutingIssue.unknown);
    await services.updateDetails('local', endpoint: 'http://localhost:11435/v1');
    expect((await row()).issue, RoutingIssue.unknown);
    var current = (await container.read(assistantServicesProvider.future)).services.single;
    evidence = profiles(current);
    container.invalidate(assistantCapabilityProfilesProvider);
    expect((await row()).issue, RoutingIssue.none);
    await services.upsert(cloud);
    expect((await row()).issue, RoutingIssue.secretUnavailable);
    current = (await container.read(assistantServicesProvider.future)).services.single;
    evidence = profiles(current);
    container.invalidate(assistantCapabilityProfilesProvider);
    secrets.values[AssistantServicesStore.account('local')] = 'synthetic-fixture';
    container.read(assistantKeysProvider.notifier).changed();
    expect((await row()).issue, RoutingIssue.none);
    secrets.values.clear();
    container.read(assistantKeysProvider.notifier).changed();
    expect((await row()).issue, RoutingIssue.secretUnavailable);
    expect((await container.read(assistantRoutingProvider.future)).revision, revision);
  });

  testWidgets('a ready function binding remains usable when the unrelated legacy default lacks credentials', (
    tester,
  ) async {
    final s = service();
    final cloud = AssistantService(
      id: 'cloud',
      name: 'Unconfigured cloud',
      protocol: ServiceProtocol.openai,
      endpoint: 'https://api.openai.com/v1',
      models: [const ServiceModel(id: 'cloud-model')],
    );
    final app = await openAssistantApp(
      tester,
      key: false,
      prefs: {
        ...preferences(s),
        AssistantServicesStore.settingsKey: jsonEncode(
          AssistantServices(services: [cloud, s], defaultModel: const ModelReference('cloud', 'cloud-model')).toJson(),
        ),
      },
      overrides: [assistantCapabilityProfilesProvider.overrideWithValue(profiles(s))],
    );
    final route = await app.container.read(assistantTaskRouteProvider((TaskType.assistantChat, null)).future);
    expect(route.issue, RoutingIssue.none, reason: 'actual resolver accepts the function-specific route');
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-model')), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-input')), findsOneWidget);
    final services = app.container.read(assistantServicesProvider.notifier);
    await services.setDefault(const ModelReference('local', 'chat'));
    await tester.pumpAndSettle();
    await services.setDefault(const ModelReference('cloud', 'cloud-model'));
    await tester.pumpAndSettle();
    expect(conversationRoutingOverride(conversationOf(tester).toJson(), TaskType.assistantChat), isNull);
    expect(
      (await app.container.read(assistantTaskRouteProvider((TaskType.assistantChat, null)).future)).issue,
      RoutingIssue.none,
    );
    expect(tester.takeException(), isNull);
  });

  test('the visible route rechecks when a service is disabled without changing routing settings', () async {
    final s = service();
    SharedPreferences.setMockInitialValues(preferences(s));
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantSecretsProvider.overrideWithValue(FakeSecrets()),
        assistantCapabilityProfilesProvider.overrideWithValue(profiles(s)),
      ],
    );
    addTearDown(container.dispose);
    final provider = assistantTaskRouteProvider((TaskType.assistantChat, null));
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    expect((await container.read(provider.future)).issue, RoutingIssue.none);
    await container.read(assistantServicesProvider.future);
    await container.read(assistantServicesProvider.notifier).setEnabled('local', false);
    await container.pump();
    expect((await container.read(provider.future)).issue, RoutingIssue.serviceOff);
    await container.read(assistantServicesProvider.notifier).setEnabled('local', true);
    await container.pump();
    expect((await container.read(provider.future)).issue, RoutingIssue.unknown);
  });
}
