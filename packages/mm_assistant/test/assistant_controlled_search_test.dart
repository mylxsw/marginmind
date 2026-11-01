import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'assistant_summary_run_test.dart' show root, SummaryStore;
import 'support.dart' show Reader;

class _Search implements SearchProvider {
  _Search(this.state);
  final sdk.AgentState state;
  int calls = 0;
  @override
  Future<List<SearchHit>> search(SearchRequest request, CancellationToken cancel) async {
    calls++;
    // The host has claimed this request before Runtime reserves/persists its ID.
    expect(state.metadata['assistant.nativeRequests.v1'], isNotEmpty);
    (state.metadata['runtime.providerChildren.v1'] as List).add('original-child');
    throw StateError('terminal disk write failed');
  }
}

void main() {
  test('restored proposals stay with their original request owner', () {
    final state = sdk.AgentState(sessionId: 'run');
    Map<String, dynamic> proposal(String id) => MapEditProposal(
      id: id,
      studySetId: 'study',
      mapId: 'map',
      baseRevision: 0,
      operations: [
        MapEditOperation.fromJson({
          'id': 'card',
          'kind': 'addReviewCard',
          'parentId': 'root',
          'question': 'Q [page:1]',
          'answer': 'A [page:1]',
        }),
      ],
    ).toJson();
    state.metadata['assistant.proposals'] = [proposal('previous-tool'), proposal('q-own')];
    final owner = AssistantTaskOwner(
      conversationState: sdk.AgentState(sessionId: 'conversation'),
      reader: Reader(),
      scope: ReadScope(studySetId: 'study'),
      requestId: 'q',
      mapId: 'map',
      baseRevision: 0,
      parents: {'root': null},
      online: false,
      execute: (_) async => throw StateError('not used'),
    );
    owner.restoreCheckpoint(
      RunManifest(
        context: root(),
        taskType: TaskType.reviewCards,
        inputFingerprint: 'f',
        promptVersion: '1',
        schemaVersion: '1',
        status: RunStatus.completed,
        revision: 0,
        checkpoint: {'state': state.toJson()},
      ),
    );
    expect(owner.proposals.proposals.keys, ['own']);
  });

  test('controlled search reconciles the original child after save failure and reuse', () async {
    final state = sdk.AgentState(sessionId: 'run');
    final conversation = sdk.AgentState(sessionId: 'conversation');
    final owner = AssistantTaskOwner(
      conversationState: conversation,
      reader: Reader(),
      scope: ReadScope(studySetId: 'study'),
      requestId: 'q',
      mapId: 'map',
      baseRevision: 0,
      parents: {'root': null},
      online: true,
      execute: (_) async => throw StateError('not used'),
    );
    final registry = TaskRegistry();
    registerAssistantTasks(registry, owner);
    final port = _Search(state);
    registry.resolve<String>(researchTaskSpec).createControlledBindings!(
      TaskExecutionScope(context: root(), state: state, input: {'question': 'research'}, nativeSearch: port),
    );
    final recovered = <String>[];
    owner.recoverProviderChild = (id) async {
      recovered.add(id);
      return {
        'hits': [
          {'url': 'https://example.com/article', 'title': 'Read me', 'snippet': ''},
        ],
      };
    };
    final first = await owner.nativeSearch.search(SearchRequest('short query'), owner.cancel);
    final second = await owner.nativeSearch.search(SearchRequest('short query'), owner.cancel);
    expect(first.single.url, second.single.url);
    expect(port.calls, 1);
    expect(recovered, ['original-child', 'original-child']);
    owner.synchronize();
    expect(conversation.metadata.containsKey('assistant.nativeRequests.v1'), false);
  });

  test('usage follows linked children once and retains unknown quality', () async {
    final store = SummaryStore();
    RunManifest manifest(String id, RunUsage usage, List<String> children) => RunManifest(
      context: decodeRunContext({...encodeRunContext(root()), 'runId': id}),
      taskType: TaskType.research,
      inputFingerprint: 'f',
      promptVersion: '1',
      schemaVersion: '1',
      revision: 0,
      status: RunStatus.running,
      usage: usage,
      checkpoint: {
        'state': {
          'metadata': {'runtime.providerChildren.v1': children},
        },
      },
    );
    await store.checkpoint(
      manifest(
        'parent',
        const RunUsage(
          quality: UsageQuality.reported,
          modelCalls: 2,
          inputTokens: 10,
          outputTokens: 4,
          reasoningTokens: 1,
        ),
        ['child', 'child'],
      ),
      expectedRevision: null,
    );
    await store.checkpoint(
      manifest(
        'child',
        const RunUsage(
          quality: UsageQuality.reported,
          modelCalls: 1,
          inputTokens: 3,
          outputTokens: 2,
          reasoningTokens: 2,
        ),
        [],
      ),
      expectedRevision: null,
    );
    final total = await loadAssistantTaskUsage(store, 'parent');
    expect(total.modelCalls, 3);
    expect(total.inputTokens, 13);
    expect(total.outputTokens, 6);
    expect(total.reasoningTokens, 3);
    expect(total.quality, UsageQuality.reported);
    store.manifests.remove('child');
    expect((await loadAssistantTaskUsage(store, 'parent')).quality, UsageQuality.unknown);
    expect(jsonEncode(encodeRunManifest(store.manifests['parent']!)), isNot(contains('secret')));
  });
}
