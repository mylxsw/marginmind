import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

AssistantService service(String id) => AssistantService(
  id: id,
  protocol: ServiceProtocol.openai,
  name: 'Same',
  endpoint: 'https://example.test/v1',
  models: const [ServiceModel(id: 'same', name: 'Same')],
);
TaskRequest<String> request(
  TaskType type, {
  ModelReference? model,
  ReasoningPolicy? reasoning,
  Set<ModelCapability> required = const {},
}) => TaskRequest(
  spec: TaskSpec(
    type: type,
    inputSchema: 'input',
    resultSchema: 'output',
    promptVersion: '1',
    schemaVersion: '1',
    completionRule: 'complete',
    requiredCapabilities: required,
  ),
  input: {},
  inputFingerprint: 'fixture',
  modelOverride: model,
  reasoning: reasoning,
);
RoutingConfig routing({Map<String, dynamic> defaults = const {}, Map<String, dynamic> bindings = const {}}) =>
    RoutingConfig(document: {'version': 1, 'revision': 2, 'defaults': defaults, 'bindings': bindings});
ModelCapabilityProfile profile(
  AssistantService service, {
  ThinkingCapability thinking = ThinkingCapability.switchable,
  CapabilityEvidenceSource source = CapabilityEvidenceSource.maintainedProfile,
}) => ModelCapabilityProfile(
  identity: serviceCapabilityIdentity(service, service.models.first),
  thinking: thinking,
  tools: CapabilitySupport.supported,
  policies: {
    ReasoningPolicy.off: ReasoningRecipe.effortNone,
    ReasoningPolicy.standard: ReasoningRecipe.effortMedium,
    ReasoningPolicy.deep: ReasoningRecipe.effortHigh,
  },
  evidence: CapabilityEvidence(
    source: source,
    reference: 'fixture-only',
    semanticBasis: 'Synthetic protocol fixture, not real service verification',
    wireVerified: true,
    verifiedAt: DateTime.utc(2026),
  ),
);

class Index implements RoutingUsageIndex {
  @override
  Future<List<RoutingUse>> listModelUses() async => const [
    RoutingUse(RoutingUsageKind.conversationOverride, 'conversation', ModelReference('a', 'same')),
    RoutingUse(RoutingUsageKind.recoverableRun, 'run', ModelReference('a', 'same')),
  ];
}

void main() {
  late AssistantServices catalog;
  late CapabilityProfiles profiles;
  late TaskModelResolver resolver;
  setUp(() {
    catalog = AssistantServices(services: [service('a'), service('b')]);
    profiles = CapabilityProfiles();
    for (final s in catalog.services) {
      profiles.put(profile(s));
    }
    resolver = TaskModelResolver(catalog: () async => catalog, profiles: profiles);
  });
  for (final type in TaskType.values) {
    test('${type.key} resolves class default, binding and explicit in order', () async {
      final config = routing(defaults: {type.category.name: const ModelReference('a', 'same').toJson()});
      final resolved = await resolver.resolve(request(type, reasoning: ReasoningPolicy.deep), config);
      expect(resolved.model, const ModelReference('a', 'same'));
      expect(resolved.source, RoutingSource.categoryDefault);
      expect(
        resolved.policy.effective,
        type.category == TaskCategory.quick ? ReasoningPolicy.off : ReasoningPolicy.deep,
      );
      final bound = routing(
        bindings: {type.key: const TaskModelBinding.explicit(ModelReference('b', 'same')).toJson()},
      );
      expect((await resolver.resolve(request(type), bound)).model, const ModelReference('b', 'same'));
      expect((await resolver.resolve(request(type), bound)).source, RoutingSource.functionBinding);
      expect(
        (await resolver.resolve(request(type, model: const ModelReference('a', 'same')), bound)).source,
        RoutingSource.explicitRequest,
      );
      expect((await resolver.inspect(request(type), routing())).issue, RoutingIssue.unset);
    });
  }
  test('invalid binding never inherits; deleted/disabled services and models are distinct', () async {
    final config = routing(
      defaults: {'heavy': const ModelReference('a', 'same').toJson()},
      bindings: {'assistant_chat': const TaskModelBinding.explicit(ModelReference('b', 'same')).toJson()},
    );
    catalog = catalog.upsert(service('b').copyWith(models: []));
    expect((await resolver.inspect(request(TaskType.assistantChat), config)).issue, RoutingIssue.deleted);
    catalog = catalog.upsert(service('b').copyWith(models: const [ServiceModel(id: 'same', enabled: false)]));
    expect((await resolver.inspect(request(TaskType.assistantChat), config)).issue, RoutingIssue.modelOff);
    catalog = catalog.upsert(service('b').copyWith(enabled: false));
    expect((await resolver.inspect(request(TaskType.assistantChat), config)).issue, RoutingIssue.serviceOff);
    catalog = catalog.remove('b');
    expect((await resolver.inspect(request(TaskType.assistantChat), config)).issue, RoutingIssue.serviceRemoved);
    final row = await resolver.inspect(
      request(TaskType.assistantChat),
      routing(
        bindings: {
          'assistant_chat': {'mode': 'future'},
        },
      ),
    );
    expect(row.issue, RoutingIssue.invalidConfiguration);
  });
  test('unknown, user declarations, always on and required capabilities fail closed', () async {
    final req = request(TaskType.wordLookup, model: const ModelReference('a', 'same'), reasoning: ReasoningPolicy.deep);
    for (final source in [CapabilityEvidenceSource.userDeclared, CapabilityEvidenceSource.wireProbe]) {
      profiles.put(profile(catalog.services.first, source: source));
      expect((await resolver.inspect(req, routing())).issue, RoutingIssue.unknown);
    }
    profiles.put(profile(catalog.services.first, thinking: ThinkingCapability.alwaysOn));
    expect((await resolver.inspect(req, routing())).issue, RoutingIssue.thinkingAlwaysOn);
    expect(
      (await resolver.resolve(request(TaskType.assistantChat, model: req.modelOverride), routing())).policy.effective,
      ReasoningPolicy.auto,
    );
    profiles.put(profile(catalog.services.first));
    expect(
      (await resolver.inspect(
        request(TaskType.assistantChat, model: req.modelOverride, required: {ModelCapability.multimodal}),
        routing(),
      )).issue,
      RoutingIssue.unknown,
    );
  });
  test('credentials are not capability failures', () async {
    resolver = TaskModelResolver(
      catalog: () async => catalog,
      profiles: profiles,
      credentialsAvailable: (_) async => throw StateError('locked'),
    );
    expect(
      (await resolver.inspect(
        request(TaskType.assistantChat, model: const ModelReference('a', 'same')),
        routing(),
      )).issue,
      RoutingIssue.secretUnavailable,
    );
  });
  test('catalog revisions invalidate profiles and immutable run snapshots', () async {
    final snapshot = await resolver.resolve(
      request(TaskType.assistantChat, model: const ModelReference('a', 'same')),
      routing(),
    );
    await resolver.validateCurrent(snapshot);
    final original = catalog.services.first;
    expect(catalog.upsert(original).services.first.revision, original.revision);
    catalog = catalog.upsert(original.copyWith(endpoint: 'https://other.test/v1'));
    expect(catalog.services.first.revision, original.revision + 1);
    expect(snapshot.serviceLabel, 'Same');
    await expectLater(resolver.validateCurrent(snapshot), throwsA(isA<ConfigurationFailure>()));
    expect(
      (await resolver.inspect(request(TaskType.assistantChat, model: snapshot.model), routing())).issue,
      RoutingIssue.unknown,
    );
    expect(() => snapshot.policy.parameters['bad'] = true, throwsUnsupportedError);
    profiles.put(profile(catalog.services.first));
    expect(
      (await resolver.resolve(request(TaskType.assistantChat, model: snapshot.model), routing())).capabilities.identity,
      isNot(snapshot.capabilities.identity),
    );
  });
  test('service ID reuse and adapter changes cannot resurrect verified profiles', () async {
    final snapshot = await resolver.resolve(
      request(TaskType.assistantChat, model: const ModelReference('a', 'same')),
      routing(),
    );
    catalog = catalog.remove('a').upsert(service('a'));
    expect(catalog.services.last.revision, greaterThan(snapshot.capabilities.identity.serviceRevision));
    expect(
      (await resolver.inspect(request(TaskType.assistantChat, model: snapshot.model), routing())).issue,
      RoutingIssue.unknown,
    );
    expect(
      profiles
          .lookup(serviceCapabilityIdentity(service('b'), service('b').models.first, adapterVersion: 'next'))
          .thinking,
      ThinkingCapability.unknown,
    );
  });
  test('binding reasoning overrides heavy default and request reasoning overrides both', () async {
    final config = RoutingConfig(
      document: {
        'version': 1,
        'revision': 0,
        'heavyReasoning': 'deep',
        'bindings': {
          'assistant_chat': const TaskModelBinding.explicit(
            ModelReference('a', 'same'),
            reasoning: ReasoningPolicy.standard,
          ).toJson(),
        },
      },
    );
    expect(
      (await resolver.resolve(request(TaskType.assistantChat), config)).policy.effective,
      ReasoningPolicy.standard,
    );
    expect(
      (await resolver.resolve(
        request(TaskType.assistantChat, reasoning: ReasoningPolicy.off),
        config,
      )).policy.effective,
      ReasoningPolicy.off,
    );
  });
  test('archive index reads legacy conversations and only recoverable run states', () async {
    final config = await resolver.resolve(
      request(TaskType.assistantChat, model: const ModelReference('a', 'same')),
      routing(),
    );
    final index = ArchiveRoutingUsageIndex(
      conversations: () async => {
        'old': {
          'model': {'provider': 'compatible', 'serviceId': 'b', 'model': 'same'},
        },
      },
      runs: () async => [
        for (final status in RunStatus.values)
          RunManifest(
            context: RunContext(runId: status.name, config: config, knowledgeVersions: {}),
            taskType: TaskType.assistantChat,
            inputFingerprint: 'fixture',
            promptVersion: '1',
            schemaVersion: '1',
            status: status,
            revision: 0,
          ),
      ],
    );
    final uses = await index.listModelUses();
    expect(uses.first.model, const ModelReference('b', 'same'));
    expect(uses.where((u) => u.kind == RoutingUsageKind.recoverableRun), hasLength(6));
    expect(uses.map((u) => u.id), isNot(contains('completed')));
  });
  test('only actually compilable heavy reasoning options are exposed', () {
    expect(resolver.reasoningOptions(profile(catalog.services.first)), ReasoningPolicy.values.toSet());
    expect(
      resolver.reasoningOptions(
        ModelCapabilityProfile(
          identity: serviceCapabilityIdentity(catalog.services.first, catalog.services.first.models.first),
        ),
      ),
      isEmpty,
    );
    expect(
      resolver.reasoningOptions(profile(catalog.services.first, thinking: ThinkingCapability.alwaysOn)),
      isNot(contains(ReasoningPolicy.off)),
    );
  });
  test('legacy conversation migration is idempotent, preserves data and only overrides chat', () {
    final old = {
      'model': {'provider': 'claude', 'model': 'same'},
      'messages': [1],
      'future': true,
    };
    final migrated = migrateConversationRouting(old);
    expect(migrateConversationRouting(migrated), migrated);
    expect(migrated['messages'], [1]);
    expect(conversationRoutingOverride(old, TaskType.assistantChat), const ModelReference('legacy-claude', 'same'));
    for (final type in TaskType.values.where((t) => t != TaskType.assistantChat)) {
      expect(conversationRoutingOverride(old, type), isNull);
    }
    final cleared = {
      ...migrated,
      'taskRouting': {'version': 1, 'assistantChat': null},
    };
    expect(conversationRoutingOverride(cleared, TaskType.assistantChat), isNull);
  });
  test('usage query includes defaults, unknown function bindings, legacy sessions and resumable runs', () async {
    final usage = RoutingUsage(
      routing: () async => routing(
        defaults: {'quick': const ModelReference('a', 'same').toJson()},
        bindings: {'future_task': const TaskModelBinding.explicit(ModelReference('a', 'same')).toJson()},
      ),
      index: Index(),
    );
    expect((await usage.of(serviceId: 'a')).map((u) => u.kind).toSet(), RoutingUsageKind.values.toSet());
    expect(await usage.of(model: const ModelReference('b', 'same')), isEmpty);
    expect(await usage.of(serviceId: 'a'), hasLength(4));
  });
}
