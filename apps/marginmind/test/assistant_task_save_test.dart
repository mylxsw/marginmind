import 'dart:async';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_task_session.dart';
import 'package:marginmind/features/assistant/task_run_store.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';

import 'assistant_settings_test.dart' show Secrets;
import '../../../packages/mm_assistant/test/support.dart' show Reader, ScriptClient, answer;
import '../../../packages/mm_assistant/test/assistant_summary_run_test.dart' show root;
import '../../../packages/mm_assistant/test/model_policy_test.dart' as wire;

class _Files extends FileRunStore {
  _Files(super.studySetDirectory);
  bool failComplete = true;
  @override
  Future<void> complete(RunManifest snapshot, Map<String, dynamic> result, {required int expectedRevision}) {
    if (failComplete) throw StateError('disk terminal');
    return super.complete(snapshot, result, expectedRevision: expectedRevision);
  }
}

class _Assembly extends PersistentTaskAssembly {
  _Assembly(this.files, this.engine, AssistantServicesStore services, AssistantRoutingStore routing)
    : super(
        studySetDirectory: files.studySetDirectory.path,
        tasks: TaskRegistry(),
        services: services,
        routing: routing,
        profiles: CapabilityProfiles(),
      );
  final _Files files;
  final SdkAgentRuntime engine;
  @override
  FileRunStore get runs => files;
  @override
  SdkAgentRuntime get runtime => engine;
}

void main() {
  test('same owner retries validated disk result and reopening buys no inference', () async {
    final directory = await Directory.systemTemp.createTemp('assistant-save-');
    try {
      SharedPreferences.setMockInitialValues({});
      final services = AssistantServicesStore(await SharedPreferences.getInstance(), Secrets());
      final routing = AssistantRoutingStore(await SharedPreferences.getInstance(), services);
      final files = _Files(directory);
      final client = ScriptClient([answer('Validated answer')]);
      final registry = TaskRegistry();
      final encoded = encodeRunContext(root());
      (encoded['capabilities'] as Map)['historyReplay'] = 'supported';
      final context = decodeRunContext({
        ...encoded,
        'knowledgeVersions': standardKnowledgeVersions(conversationSummarySpec),
      });
      // Summary stage has no tools; the same Session handles Runtime result saves
      // for every domain task. This exercises actual SDK + durable FileRunStore.
      final input = {
        'question': 'summarize',
        'units': [
          {'id': 'one', 'text': 'source'},
        ],
      };
      final request = TaskRequest<String>(spec: conversationSummarySpec, input: input, inputFingerprint: 'f');
      final text = '{"text":"Validated answer","coveredIds":["one"],"decisions":[],"suggestions":[],"unresolved":[]}';
      client.replies[0] = answer(text);
      late AssistantTaskSession session;
      final owner = AssistantTaskOwner(
        conversationState: sdk.AgentState(sessionId: 'conversation'),
        reader: Reader(),
        scope: ReadScope(studySetId: 'study'),
        requestId: 'question',
        mapId: 'map',
        baseRevision: 0,
        parents: {'root': null},
        online: false,
        execute: (_) => session.runTask(),
      );
      registerAssistantTasks(registry, owner);
      final runtime = SdkAgentRuntime(
        store: files,
        tasks: registry,
        knowledge: standardKnowledgeRegistry(),
        testClient: client,
        loadModel: (_) async =>
            RuntimeModelBinding(model: wire.model(ModelProtocol.chatCompletions), key: '', serviceRevision: 1),
      );
      final failed = Completer<void>();
      session = AssistantTaskSession(
        assembly: _Assembly(files, runtime, services, routing),
        owner: owner,
        request: request,
        initialContext: context,
        changed: (s) {
          if (s.saveFailed && !failed.isCompleted) failed.complete();
        },
      );
      owner.controls = session;
      final result = owner.run('summarize').toList();
      await failed.future.timeout(const Duration(seconds: 10));
      expect(session.status, RunStatus.paused);
      expect((await files.load(context.runId))!.status, RunStatus.validating);
      files.failComplete = false;
      await session.resume();
      await result;
      expect(client.calls, 1);
      expect((await files.load(context.runId))!.status, RunStatus.completed);
      final reopenedOwner = AssistantTaskOwner(
        conversationState: sdk.AgentState(sessionId: 'conversation'),
        reader: Reader(),
        scope: ReadScope(studySetId: 'study'),
        requestId: 'question',
        mapId: 'map',
        baseRevision: 0,
        parents: {'root': null},
        online: false,
        execute: (_) async => throw StateError('recovery uses session'),
      );
      final reopenedRegistry = TaskRegistry();
      registerAssistantTasks(reopenedRegistry, reopenedOwner);
      final freshClient = ScriptClient([]);
      final reopenedRuntime = SdkAgentRuntime(
        store: files,
        tasks: reopenedRegistry,
        knowledge: standardKnowledgeRegistry(),
        testClient: freshClient,
        loadModel: (_) async => throw StateError('completed recovery must not load credentials'),
      );
      final reopened = AssistantTaskSession(
        assembly: _Assembly(files, reopenedRuntime, services, routing),
        owner: reopenedOwner,
        request: request,
        initialContext: context,
        changed: (_) {},
      );
      final restored = await reopened.runTask();
      expect(freshClient.calls, 0);
      expect(restored.value, text);
      expect(client.calls, 1);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
