import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_tasks.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';

import 'assistant_settings_test.dart' show Secrets;
import '../../../packages/mm_assistant/test/support.dart' show Reader;

class SnapshotReader extends Reader {
  int reads = 0;
  String text = 'original text ' * 8000;
  @override
  Future<List<ReadPage>> readSelection(String id, ReadScope scope, CancellationToken cancel) async {
    reads++;
    return [ReadPage('doc', 1, text)];
  }
}

void main() {
  for (final switchLiveModel in [false, true]) {
    test('summary recovery: switch live model=$switchLiveModel, reuse verified stages', () async {
      final dir = await Directory.systemTemp.createTemp('assistant-recovery-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final calls = <String, int>{};
      final models = <String>[];
      var fail = true;
      final sub = server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        models.add(body['model']);
        final content = (body['messages'] as List).last['content'];
        final text = content is String ? content : (content as List).map((p) => p['text'] ?? '').join();
        final input = jsonDecode(text) as Map;
        final key = jsonEncode(input['units']);
        calls.update(key, (n) => n + 1, ifAbsent: () => 1);
        final bad = calls.length == 2 && fail;
        if (bad) fail = false;
        final answer = AssistantSummary(
          'Summary of original source',
          bad ? [] : [for (final u in input['units']) u['id'] as String],
          [],
          [],
          [],
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': 'fixture',
            'object': 'chat.completion',
            'model': body['model'],
            'choices': [
              {
                'index': 0,
                'message': {'role': 'assistant', 'content': jsonEncode(answer.toJson())},
                'finish_reason': 'stop',
              },
            ],
            'usage': {'prompt_tokens': 9, 'completion_tokens': 3, 'total_tokens': 12},
          }),
        );
        await request.response.close();
      });
      ProviderContainer? container;
      try {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final services = AssistantServicesStore(prefs, Secrets());
        final service = AssistantService(
          id: 'local',
          revision: 1,
          protocol: ServiceProtocol.ollama,
          name: 'Fixture',
          endpoint: 'http://127.0.0.1:${server.port}/v1',
          localEnabled: true,
          models: [
            const ServiceModel(id: 'chosen'),
            const ServiceModel(id: 'other'),
          ],
        );
        await services.save(
          AssistantServices(services: [service], defaultModel: const ModelReference('local', 'chosen')),
        );
        final routing = AssistantRoutingStore(prefs, services);
        await routing.load();
        Future<void> choose(String model) async {
          final current = await routing.load();
          await routing.save(
            RoutingConfig(
              document: {
                'version': 1,
                'revision': current.revision,
                'defaults': {
                  'heavy': {'serviceId': 'local', 'modelId': model},
                },
                'heavyReasoning': 'off',
                'bindings': <String, dynamic>{},
              },
            ),
            expectedRevision: current.revision,
          );
        }

        await choose('chosen');
        final profiles = CapabilityProfiles();
        for (final model in service.models) {
          profiles.put(
            ModelCapabilityProfile(
              identity: serviceCapabilityIdentity(service, model),
              thinking: ThinkingCapability.switchable,
              tools: CapabilitySupport.supported,
              historyReplay: CapabilitySupport.supported,
              policies: {ReasoningPolicy.off: ReasoningRecipe.effortNone},
              evidence: CapabilityEvidence(
                source: CapabilityEvidenceSource.maintainedProfile,
                reference: 'test-only',
                semanticBasis: 'Synthetic loopback',
                wireVerified: true,
                verifiedAt: DateTime.utc(2026),
              ),
            ),
          );
        }
        final reader = SnapshotReader();
        final storage = ConversationStorage(dir);
        ProviderContainer makeContainer() => ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            assistantServicesStoreProvider.overrideWithValue(services),
            assistantRoutingStoreProvider.overrideWithValue(routing),
            assistantCapabilityProfilesProvider.overrideWithValue(profiles),
            assistantDependenciesProvider.overrideWith(
              (ref) => AssistantDependencies(
                studySetId: 'study',
                model: service.configuration(service.models.first),
                storage: storage,
                executor: MemoryMapEditExecutor(studySetId: 'study', mapId: 'map', parents: {'root': null}),
                notes: MemoryNoteSaver(),
                runFactory: (state, conversation, question) async => createPersistentAssistantRun(
                  ref: ref,
                  directory: dir.path,
                  state: state,
                  conversation: conversation,
                  question: question,
                  reader: reader,
                  documents: [],
                  mapId: 'map',
                  revision: 0,
                  parents: {'root': null},
                ),
              ),
            ),
          ],
        );
        container = makeContainer();
        final view = container.listen(assistantControllerProvider, (_, _) {});
        final partial = Completer<void>();
        final activity = container.listen(assistantTaskActivityProvider('study'), (_, next) {
          if (next?.status == RunStatus.partial && !partial.isCompleted) partial.complete();
        });
        final controller = container.read(assistantControllerProvider.notifier);
        final pending = controller.send(
          'summarize',
          skill: 'summarize',
          contexts: [
            const ContextItem(
              id: 'selection',
              kind: ContextKind.selection,
              documentId: 'doc',
              displayText: 'selected source',
            ),
          ],
        );
        await partial.future.timeout(const Duration(seconds: 15));
        if (switchLiveModel) {
          final owner = container.read(assistantTaskActivityProvider('study'))!.owner!;
          await owner.controls!.useModel(const ModelReference('local', 'other'));
          expect(owner.controls!.context.phase, 1);
          await owner.controls!.resume();
          await pending.timeout(const Duration(seconds: 15));
          expect(container.read(assistantControllerProvider).messages.last.status, MessageStatus.done);
          expect(calls.values.first, 1);
          expect(models.take(2).toSet(), {'chosen'});
          expect(models.skip(2).toSet(), {'other'});
          activity.close();
          view.close();
          return;
        }
        final id = container.read(assistantControllerProvider).id;
        final first = calls.keys.first;
        expect(calls[first], 1);
        await controller.stop();
        await pending;
        final saved = await storage.loadOrCreate(id, null);
        final questionId = container.read(assistantControllerProvider).messages.first.requestId;
        final originalRecord = (saved.metadata['assistant.taskRecords.v1'] as Map)[questionId] as Map;
        final originalRun = decodeRunContext(Map<String, dynamic>.from(originalRecord['context']));
        expect((await FileRunStore(dir).load(originalRun.runId))!.status, RunStatus.partial);
        activity.close();
        view.close();
        container.dispose();
        reader.text = 'changed source must not be read';
        await choose('other');
        final before = calls.values.fold(0, (a, b) => a + b);
        container = makeContainer();
        final resumedView = container.listen(assistantControllerProvider, (_, _) {});
        final resumed = container.read(assistantControllerProvider.notifier);
        await resumed.openConversation(id);
        expect(calls.values.fold(0, (a, b) => a + b), before);
        expect(resumed.canResumeTask, true);
        await resumed.resumeTask().timeout(const Duration(seconds: 15));
        expect(container.read(assistantControllerProvider).messages.last.status, MessageStatus.done);
        expect(container.read(assistantControllerProvider).messages.length, 2);
        expect(calls[first], 1);
        expect(reader.reads, 1);
        expect(models.toSet(), {'chosen'});
        final archive = await storage.loadOrCreate(id, null);
        final record = (archive.metadata['assistant.taskRecords.v1'] as Map)[questionId] as Map;
        final current = decodeRunContext(Map<String, dynamic>.from(record['context']));
        expect(current.runId, isNot(originalRun.runId));
        final manifest = (await FileRunStore(dir).load(current.runId))!;
        expect(manifest.status, RunStatus.completed);
        expect(manifest.checkpoint['leafIds'], archive.metadata['assistant.summaryCoverage.v1']);
        expect((await FileRunStore(dir).loadResult(current.runId))!['summary']['text'], 'Summary of original source');
        resumedView.close();
      } finally {
        container?.dispose();
        await sub.cancel();
        await server.close(force: true);
        await dir.delete(recursive: true);
      }
    });
  }
}
