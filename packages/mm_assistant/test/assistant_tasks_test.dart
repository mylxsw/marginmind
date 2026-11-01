import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'support.dart';
import 'task_runtime_test.dart' show Store;
import 'model_policy_test.dart' as fixture;

void main() {
  test('actions have independent routes and new conversations follow settings', () {
    expect(assistantSpecFor(null, []), same(assistantChatSpec));
    expect(assistantSpecFor('verify', []), same(researchTaskSpec));
    expect(assistantSpecFor('quiz', []), same(reviewCardsSpec));
    expect(assistantSpecFor('summarize', []), same(conversationSummarySpec));
    expect(
      assistantSpecFor('summarize', [const ContextItem(id: 'doc', kind: ContextKind.document, displayText: 'doc')]),
      same(documentSummarySpec),
    );
    final conversation = Conversation(id: 'c', studySetId: 's', model: fixture.model(ModelProtocol.chatCompletions));
    expect(conversationRoutingOverride(conversation.toJson(), TaskType.assistantChat), isNull);
    final old = conversation.toJson()..remove('taskRouting');
    old['future'] = {'keep': true};
    final restored = Conversation.fromJson(old);
    expect(conversationRoutingOverride(restored.toJson(), TaskType.assistantChat), isNotNull);
    expect(restored.copyWith(title: 'changed').toJson()['future'], {'keep': true});
  });
  test('task harness reads evidence and synchronizes the conversation owner', () async {
    final conversation = sdk.AgentState(sessionId: 'conversation');
    final client = ScriptClient([call('read_pages', '{"documentId":"doc","from":1,"to":1}'), answer('Read [page:1]')]);
    final store = Store();
    final registry = TaskRegistry();
    late AssistantTaskOwner owner;
    owner = AssistantTaskOwner(
      conversationState: conversation,
      reader: Reader(),
      scope: ReadScope(studySetId: 'set', documents: {'doc'}),
      requestId: 'request',
      mapId: 'map',
      baseRevision: 0,
      parents: {'root': null},
      online: false,
      primaryDocumentId: 'doc',
      execute: (_) async {
        final base = fixture.profile(ModelProtocol.chatCompletions);
        final caps = ModelCapabilityProfile(
          identity: base.identity,
          evidence: base.evidence,
          policies: base.policies,
          thinking: base.thinking,
          tools: CapabilitySupport.supported,
          historyReplay: CapabilitySupport.supported,
        );
        final runtime = SdkAgentRuntime(
          store: store,
          tasks: registry,
          knowledge: standardKnowledgeRegistry(),
          testClient: client,
          loadModel: (_) async =>
              RuntimeModelBinding(model: fixture.model(ModelProtocol.chatCompletions), key: '', serviceRevision: 1),
        );
        final context = RunContext(
          runId: 'run',
          config: ResolvedTaskConfig(
            capabilities: caps,
            policy: const DefaultProviderPolicyCompiler().compile(
              category: TaskCategory.heavy,
              requested: ReasoningPolicy.off,
              identity: caps.identity,
              capabilities: caps,
            ),
            routingRevision: 1,
            source: RoutingSource.functionBinding,
          ),
          knowledgeVersions: standardKnowledgeVersions(assistantChatSpec),
        );
        return runtime
            .start(
              TaskRequest<String>(spec: assistantChatSpec, input: {'question': 'read'}, inputFingerprint: 'read'),
              context,
            )
            .result;
      },
    );
    registerAssistantTasks(registry, owner);
    final events = await owner.run('read').toList().catchError((Object error) {
      fail('status=${store.saved?.status}, code=${store.saved?.failureCode}, calls=${client.calls}');
    });
    expect(store.saved!.status, RunStatus.completed);
    expect(events.last.data.textOutput, contains('[page:1]'));
    expect(owner.citations.used('Read [page:1]').single.documentId, 'doc');
    expect(conversation.history.messages, isNotEmpty);
    expect(conversation.metadata['assistant.evidence.v1'], isNotNull);
    expect(client.calls, 2);
  });
  test('review proposals require a real read and retain confirmation semantics', () async {
    final conversation = sdk.AgentState(sessionId: 'c');
    String ops(String marker) => jsonEncode({
      'ops': [
        {
          'id': 'card',
          'kind': 'addReviewCard',
          'parentId': 'root',
          'question': 'Question $marker',
          'answer': 'Answer $marker',
        },
      ],
    });
    final client = ScriptClient([
      call('propose_map_edits', ops('[page:1]'), id: 'forged'),
      call('read_pages', '{"documentId":"doc","from":1,"to":1}', id: 'read'),
      call('propose_map_edits', ops('[page:1]'), id: 'grounded'),
    ]);
    final store = Store();
    final registry = TaskRegistry();
    late AssistantTaskOwner owner;
    owner = AssistantTaskOwner(
      conversationState: conversation,
      reader: Reader(),
      scope: ReadScope(studySetId: 's', documents: {'doc'}),
      requestId: 'r',
      mapId: 'map',
      baseRevision: 7,
      parents: {'root': null},
      online: false,
      primaryDocumentId: 'doc',
      execute: (_) async {
        final base = fixture.profile(ModelProtocol.chatCompletions);
        final caps = ModelCapabilityProfile(
          identity: base.identity,
          evidence: base.evidence,
          policies: base.policies,
          thinking: base.thinking,
          tools: CapabilitySupport.supported,
          historyReplay: CapabilitySupport.supported,
        );
        final runtime = SdkAgentRuntime(
          store: store,
          tasks: registry,
          knowledge: assistantTaskKnowledgeRegistry(),
          testClient: client,
          loadModel: (_) async =>
              RuntimeModelBinding(model: fixture.model(ModelProtocol.chatCompletions), key: '', serviceRevision: 1),
        );
        final context = RunContext(
          runId: 'review',
          config: ResolvedTaskConfig(
            capabilities: caps,
            policy: const DefaultProviderPolicyCompiler().compile(
              category: TaskCategory.heavy,
              requested: ReasoningPolicy.off,
              identity: caps.identity,
              capabilities: caps,
            ),
            routingRevision: 1,
            source: RoutingSource.functionBinding,
          ),
          knowledgeVersions: standardKnowledgeVersions(reviewCardsSpec),
        );
        return runtime
            .start(
              TaskRequest<String>(
                spec: reviewCardsSpec,
                input: {'question': 'review', 'reviewOnly': true},
                inputFingerprint: 'review',
              ),
              context,
            )
            .result;
      },
    );
    registerAssistantTasks(registry, owner);
    await owner.run('review').toList();
    expect(store.saved!.status, RunStatus.completed);
    expect(owner.proposals.proposals.keys, ['grounded']);
    expect(owner.proposals.proposals.values.single.baseRevision, 7);
    expect(conversation.metadata['assistant.proposals'], hasLength(1));
  });
  test('research accepts body evidence, rejects metadata and preserves unverified output', () {
    final owner = AssistantTaskOwner(
      conversationState: sdk.AgentState(sessionId: 'c'),
      reader: Reader(),
      scope: ReadScope(studySetId: 's'),
      requestId: 'r',
      mapId: 'm',
      baseRevision: 0,
      parents: {},
      online: true,
      execute: (_) => throw UnimplementedError(),
    );
    final registry = TaskRegistry();
    registerAssistantTasks(registry, owner);
    final validator = registry.resolve<String>(researchTaskSpec).validator;
    final markers = owner.citations.source(
      AssistantSource(
        id: 'snapshot',
        version: 1,
        kind: 'snapshot',
        title: 'Body',
        url: Uri.parse('https://example.org'),
        paragraphs: {'p1': 'Real body'},
      ),
    );
    String result(String marker, bool verified) => jsonEncode({
      'claims': [
        {
          'text': 'Claim $marker',
          'verified': verified,
          'evidence': [marker],
        },
      ],
      'conflicts': ['disagreement'],
      'unresolved': ['missing'],
    });
    expect(validator.validate(result(markers.single, true), {}).complete, true);
    expect(validator.validate(result('[source:999]', true), {}).complete, false);
    final metadata = owner.citations.source(
      AssistantSource(
        id: 'paper',
        version: 1,
        kind: 'openAlex',
        title: 'Metadata',
        url: Uri.parse('https://example.org/paper'),
        paragraphs: {'meta': 'Abstract'},
      ),
    );
    expect(validator.validate(result(metadata.single, true), {}).complete, false);
    final unverified = result('', false);
    expect(validator.validate(unverified, {}).complete, false);
    expect(AssistantResearch.parse(unverified).render(chinese: false), contains('[Unverified]'));
  });
  test('long summary splits and hierarchically reduces bounded groups', () async {
    var calls = 0;
    final result = await summarizeAssistantUnits(
      units: [SummaryUnit('doc:1', 'a' * 24000), SummaryUnit('doc:2', 'b' * 24000)],
      requestCharacters: 4096,
      cancel: CancellationToken(),
      execute: (units, stage) async {
        calls++;
        expect(jsonEncode(units.map((u) => u.toJson()).toList()).length, lessThanOrEqualTo(4096));
        final value = AssistantSummary('summary [page:1]', units.map((u) => u.id).toList(), ['decision'], [], ['open']);
        return RunResult<String>(
          runId: '$stage',
          status: RunStatus.completed,
          validation: ValidationReport(),
          value: jsonEncode(value.toJson()),
        );
      },
    );
    expect(calls, greaterThan(3));
    expect(result.coveredIds, contains('doc:1/0'));
    expect(result.coveredIds, contains('doc:2/0'));
    expect(result.coveredIds.toSet().length, result.coveredIds.length);
    expect(result.unresolved, ['open']);
  });
  test('summary rejects missing coverage and empty sources', () async {
    Future<RunResult<String>> omit(List<SummaryUnit> units, int stage) async => RunResult<String>(
      runId: '$stage',
      status: RunStatus.completed,
      validation: ValidationReport(),
      value: jsonEncode(AssistantSummary('summary', [], [], [], []).toJson()),
    );
    await expectLater(
      summarizeAssistantUnits(
        units: [const SummaryUnit('one', 'text')],
        requestCharacters: 4096,
        execute: omit,
        cancel: CancellationToken(),
      ),
      throwsA(isA<ConfigurationFailure>()),
    );
    await expectLater(
      summarizeAssistantUnits(
        units: [const SummaryUnit('one', '')],
        requestCharacters: 4096,
        execute: omit,
        cancel: CancellationToken(),
      ),
      throwsA(isA<ConfigurationFailure>()),
    );
  });
}
