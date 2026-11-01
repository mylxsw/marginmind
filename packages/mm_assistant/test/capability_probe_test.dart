import 'dart:async';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:dio/dio.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'support.dart';
import 'task_routing_test.dart' as fixtures;

class WaitingClient extends ScriptClient {
  WaitingClient() : super([]);
  final started = Completer<void>();
  @override
  Future<sdk.ModelMessage> generate(
    List<sdk.LLMMessage> messages, {
    List<sdk.Tool>? tools,
    sdk.ToolChoice? toolChoice,
    required sdk.ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    started.complete();
    await cancelToken!.whenCancel;
    throw const ResearchFailure(ResearchFailureKind.cancelled);
  }
}

void main() {
  test('HTTP acceptance stays unknown; untrusted evidence is never promoted', () async {
    final service = fixtures.service('a');
    final profiles = CapabilityProfiles();
    final resolver = TaskModelResolver(
      catalog: () async => AssistantServices(services: [service]),
      profiles: profiles,
    );
    final client = ScriptClient([answer('OK')]);
    final probe = RoutingCapabilityProbe(
      resolver: resolver,
      key: (_) async => 'fixture-key',
      connection: (model, key, policy) {
        expect(policy, isNull);
        return AssistantConnection(client, Dio());
      },
    );
    final result = await probe.probe(const ModelReference('a', 'same'), cancellation: CancellationToken());
    expect(result.accepted, true);
    expect(result.purpose, RunPurpose.capabilityProbe);
    expect(result.profile.thinking, ThinkingCapability.unknown);
    expect(resolver.reasoningOptions(result.profile), isEmpty);
    expect(client.toolRequests.single, isEmpty);
    expect(client.modelConfigs.single.extra, isNull);
    expect(profiles.lookup(result.identity).thinking, ThinkingCapability.unknown);
    await expectLater(
      probe.probe(const ModelReference('a', 'same'), cancellation: CancellationToken(), reasoning: ReasoningPolicy.off),
      throwsA(isA<ConfigurationFailure>()),
    );
  });
  test('probe uses verified policy and never executes returned tools', () async {
    final service = fixtures.service('a');
    final profiles = CapabilityProfiles()..put(fixtures.profile(service));
    final resolver = TaskModelResolver(
      catalog: () async => AssistantServices(services: [service]),
      profiles: profiles,
    );
    final client = ScriptClient([call('probe_tool', '{}')]);
    final probe = RoutingCapabilityProbe(
      resolver: resolver,
      key: (_) async => 'fixture-key',
      connection: (model, key, policy) {
        expect(policy!.effective, ReasoningPolicy.off);
        return AssistantConnection(client, Dio());
      },
    );
    await probe.probe(
      const ModelReference('a', 'same'),
      cancellation: CancellationToken(),
      reasoning: ReasoningPolicy.off,
    );
    expect(client.modelConfigs.single.extra, {'reasoning_effort': 'none'});
    expect(client.toolRequests.single, isEmpty);
  });
  test('cancelling an in-flight probe cancels its SDK request', () async {
    final resolver = TaskModelResolver(
      catalog: () async => AssistantServices(services: [fixtures.service('a')]),
      profiles: CapabilityProfiles(),
    );
    final client = WaitingClient();
    final probe = RoutingCapabilityProbe(
      resolver: resolver,
      key: (_) async => 'fixture-key',
      connection: (model, key, policy) => AssistantConnection(client, Dio()),
    );
    final cancellation = CancellationToken();
    final future = probe.probe(const ModelReference('a', 'same'), cancellation: cancellation);
    await client.started.future;
    cancellation.cancel();
    await expectLater(
      future,
      throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.cancelled)),
    );
  });
  test('late result after service edit is discarded', () async {
    var catalog = AssistantServices(services: [fixtures.service('a')]);
    final resolver = TaskModelResolver(catalog: () async => catalog, profiles: CapabilityProfiles());
    final client = ScriptClient([answer('OK')]);
    final probe = RoutingCapabilityProbe(
      resolver: resolver,
      key: (_) async => 'fixture-key',
      connection: (model, key, policy) {
        catalog = catalog.upsert(catalog.services.single.copyWith(endpoint: 'https://changed.test/v1'));
        return AssistantConnection(client, Dio());
      },
    );
    await expectLater(
      probe.probe(const ModelReference('a', 'same'), cancellation: CancellationToken()),
      throwsA(isA<ConfigurationFailure>().having((e) => e.code, 'code', 'serviceConfigurationChanged')),
    );
  });
}
