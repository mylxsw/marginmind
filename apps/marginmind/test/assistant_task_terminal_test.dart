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
import 'assistant_route_review_test.dart' show profiles;
import '../../../packages/mm_assistant/test/support.dart' show Reader;

void main() {
  for (final scenario in ['failed', 'cancelled', 'researchPartial', 'reviewPartial']) {
    test('Runtime + Controller: $scenario offers branch retry, never invalid resume', () async {
      final dir = await Directory.systemTemp.createTemp('assistant-terminal-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final started = Completer<void>(), release = Completer<void>();
      final handlers = <Future<void>>[];
      var calls = 0;
      var retrying = false;
      Future<void> respond(HttpRequest request) async {
        calls++;
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        if (!started.isCompleted) started.complete();
        if (scenario == 'cancelled' && !retrying) await release.future;
        try {
          if (scenario == 'failed' && !retrying) {
            request.response.statusCode = 400;
            request.response.write('{"error":{"message":"synthetic failure"}}');
          } else {
            final text = scenario == 'researchPartial'
                ? '{"claims":[{"text":"Unverified","verified":false,"evidence":[]}],"conflicts":[],"unresolved":["No body"]}'
                : scenario == 'reviewPartial'
                ? 'No evidence-backed cards'
                : 'Answer';
            if (body['stream'] == true) {
              request.response.headers.contentType = ContentType('text', 'event-stream');
              request.response.write(
                'data: ${jsonEncode({
                  'choices': [
                    {
                      'index': 0,
                      'delta': {'content': text},
                      'finish_reason': null,
                    },
                  ],
                })}\n\n',
              );
              request.response.write(
                'data: ${jsonEncode({
                  'choices': [
                    {'index': 0, 'delta': <String, dynamic>{}, 'finish_reason': 'stop'},
                  ],
                })}\n\n',
              );
              request.response.write('data: [DONE]\n\n');
            } else {
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode({
                  'choices': [
                    {
                      'index': 0,
                      'message': {'role': 'assistant', 'content': text},
                      'finish_reason': 'stop',
                    },
                  ],
                }),
              );
            }
          }
          await request.response.close();
        } on HttpException {
          /* cancellation closes the original socket */
        }
      }

      final sub = server.listen((request) => handlers.add(respond(request)));
      ProviderContainer? container;
      try {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final services = AssistantServicesStore(prefs, Secrets());
        final service = AssistantService(
          id: 'local',
          name: 'Fixture',
          protocol: ServiceProtocol.ollama,
          endpoint: 'http://127.0.0.1:${server.port}/v1',
          localEnabled: true,
          models: [const ServiceModel(id: 'chat')],
        );
        await services.save(
          AssistantServices(services: [service], defaultModel: const ModelReference('local', 'chat')),
        );
        final routing = AssistantRoutingStore(prefs, services);
        await routing.load();
        await routing.save(
          RoutingConfig(
            document: {
              'version': 1,
              'revision': 0,
              'defaults': {
                'heavy': {'serviceId': 'local', 'modelId': 'chat'},
              },
              'bindings': <String, dynamic>{},
              'heavyReasoning': 'off',
            },
          ),
          expectedRevision: 0,
        );
        final storage = ConversationStorage(dir);
        ProviderContainer makeContainer() => ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            assistantServicesStoreProvider.overrideWithValue(services),
            assistantRoutingStoreProvider.overrideWithValue(routing),
            assistantCapabilityProfilesProvider.overrideWithValue(profiles(service)),
            assistantDependenciesProvider.overrideWith(
              (ref) => AssistantDependencies(
                studySetId: 'study',
                model: service.configuration(service.models.single),
                storage: storage,
                readTaskStatus: (id) async => (await FileRunStore(dir).load(id))?.status,
                executor: MemoryMapEditExecutor(studySetId: 'study', mapId: 'map', parents: {'root': null}),
                notes: MemoryNoteSaver(),
                runFactory: (state, conversation, question) async => createPersistentAssistantRun(
                  ref: ref,
                  directory: dir.path,
                  state: state,
                  conversation: conversation,
                  question: question,
                  reader: Reader(),
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
        var listener = container.listen(assistantControllerProvider, (_, _) {});
        final controller = container.read(assistantControllerProvider.notifier);
        final pending = controller.send(
          'question',
          skill: scenario == 'researchPartial'
              ? 'verify'
              : scenario == 'reviewPartial'
              ? 'quiz'
              : null,
        );
        await started.future.timeout(const Duration(seconds: 15));
        if (scenario == 'cancelled') {
          await controller.stop();
          release.complete();
        }
        await pending.timeout(const Duration(seconds: 15));
        expect(controller.canResumeTask, false);
        expect(controller.canRetryTask, true);
        expect(() => controller.resumeTask(), throwsStateError);
        final view = container.read(assistantControllerProvider);
        final saved = await storage.loadOrCreate(view.id, null);
        final record = (saved.metadata['assistant.taskRecords.v1'] as Map)[view.messages.last.requestId] as Map;
        final runId = (record['context'] as Map)['runId'] as String;
        final status = scenario == 'failed'
            ? RunStatus.failed
            : scenario == 'cancelled'
            ? RunStatus.cancelled
            : RunStatus.partial;
        expect((await FileRunStore(dir).load(runId))!.status, status);
        expect(record['status'], status.name);
        // Older archives lacked this field. Opening reconciles from the actual
        // durable manifest before rendering a recovery action.
        record.remove('status');
        await storage.save(saved);
        listener.close();
        container.dispose();
        container = makeContainer();
        listener = container.listen(assistantControllerProvider, (_, _) {});
        final reopened = container.read(assistantControllerProvider.notifier);
        await reopened.openConversation(view.id);
        expect(reopened.canResumeTask, false);
        expect(reopened.canRetryTask, true);
        expect(calls, 1);
        retrying = true;
        await reopened
            .retry(container.read(assistantControllerProvider).messages.last.id)
            .timeout(const Duration(seconds: 15));
        final archive = await storage.loadOrCreate(view.id, null);
        final next = (archive.metadata['assistant.taskRecords.v1'] as Map).values.last as Map;
        expect((next['context'] as Map)['runId'], isNot(runId));
        expect((await FileRunStore(dir).load(runId))!.status, status);
        expect(archive.metadata['assistant.viewBranches.v1'], isNotEmpty);
        expect(calls, 2);
        listener.close();
      } finally {
        if (!release.isCompleted) release.complete();
        container?.dispose();
        await sub.cancel();
        await server.close(force: true);
        await Future.wait(handlers);
        await dir.delete(recursive: true);
      }
    });
  }
}
