import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/note_organizer_factory.dart';
import 'package:marginmind/features/assistant/task_run_store.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';

import 'assistant_settings_test.dart' show Secrets;

class FailingStore extends FileRunStore {
  FailingStore(super.directory);
  bool fail = false;
  @override
  Future<void> complete(RunManifest snapshot, Map<String, dynamic> result, {required int expectedRevision}) async {
    if (fail && snapshot.stage != 'notes_session') throw const FileSystemException('fixture disk failure');
    await super.complete(snapshot, result, expectedRevision: expectedRevision);
  }
}

class Assembly extends PersistentTaskAssembly {
  Assembly({
    required super.studySetDirectory,
    required super.tasks,
    required super.services,
    required super.routing,
    required super.profiles,
    required this.disk,
  }) : super(knowledge: VersionedKnowledgeRegistry([studyNotesKnowledge]));
  final FailingStore disk;
  @override
  FileRunStore get runs => disk;
}

class NotesFixture {
  late Directory dir;
  late HttpServer server;
  late StreamSubscription<HttpRequest> listener;
  late Assembly assembly;
  late CapabilityProfiles profiles;
  late FailingStore disk;
  final bodies = <Map<String, dynamic>>[];
  Map<String, dynamic> Function(Map<String, dynamic>) output = (_) => {'text': 'validated'};
  Future<void> open({bool admit = true}) async {
    dir = await Directory.systemTemp.createTemp('notes-stage-');
    disk = FailingStore(dir);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    listener = server.listen((request) async {
      final body = Map<String, dynamic>.from(jsonDecode(await utf8.decoder.bind(request).join()));
      bodies.add(body);
      final messages = body['messages'] as List;
      final input = Map<String, dynamic>.from(jsonDecode(messages.last['content'] as String));
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': 'fixture',
          'object': 'chat.completion',
          'model': 'task-model',
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': jsonEncode(output(input))},
              'finish_reason': 'stop',
            },
          ],
          'usage': {'prompt_tokens': 9, 'completion_tokens': 2, 'total_tokens': 11},
        }),
      );
      await request.response.close();
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final services = AssistantServicesStore(prefs, Secrets());
    final service = AssistantService(
      id: 'notes',
      revision: 1,
      protocol: ServiceProtocol.ollama,
      name: 'Fixture',
      endpoint: 'http://127.0.0.1:${server.port}/v1',
      localEnabled: true,
      models: const [
        ServiceModel(id: 'legacy-model'),
        ServiceModel(id: 'task-model'),
      ],
    );
    await services.save(
      AssistantServices(services: [service], defaultModel: const ModelReference('notes', 'legacy-model')),
    );
    final routing = AssistantRoutingStore(prefs, services);
    final original = await routing.load();
    await routing.save(
      RoutingConfig(
        document: {
          ...original.document,
          'bindings': {
            'study_notes': const TaskModelBinding.explicit(
              ModelReference('notes', 'task-model'),
              reasoning: ReasoningPolicy.off,
            ).toJson(),
          },
        },
      ),
      expectedRevision: original.revision,
    );
    profiles = CapabilityProfiles();
    if (admit) {
      profiles.put(
        ModelCapabilityProfile(
          identity: serviceCapabilityIdentity(service, service.models.last),
          thinking: ThinkingCapability.switchable,
          tools: CapabilitySupport.supported,
          historyReplay: CapabilitySupport.supported,
          contextTokens: 60000,
          outputTokens: 8192,
          policies: {ReasoningPolicy.off: ReasoningRecipe.effortNone},
          evidence: CapabilityEvidence(
            source: CapabilityEvidenceSource.maintainedProfile,
            reference: 'fixture-only',
            semanticBasis: 'Offline fixture, not live admission',
            verifiedAt: DateTime.utc(2026),
            wireVerified: true,
          ),
        ),
      );
    }
    assembly = Assembly(
      studySetDirectory: dir.path,
      tasks: studyNotesTaskRegistry(),
      services: services,
      routing: routing,
      profiles: profiles,
      disk: disk,
    );
  }

  Future<void> close() async {
    await listener.cancel();
    await server.close(force: true);
    await dir.delete(recursive: true);
  }
}

void main() {
  late NotesFixture fixture;
  setUp(() async {
    fixture = NotesFixture();
    await fixture.open();
  });
  tearDown(() => fixture.close());
  test('production factory resolves study_notes binding, uses SDK wire and durable cache across reopen', () async {
    final organizer = await createModelNoteOrganizer(assembly: fixture.assembly, sessionId: 'session');
    expect(await organizer.rewrite('generated prose', NoteRewrite.concise), 'validated');
    expect(fixture.bodies.single['model'], 'task-model');
    expect(fixture.bodies.single['reasoning_effort'], 'none');
    expect(fixture.bodies.single['max_completion_tokens'], 8192);
    expect(fixture.bodies.single['tools'], isNotEmpty);
    organizer.close();
    final reopened = await createModelNoteOrganizer(assembly: fixture.assembly, sessionId: 'session');
    expect(await reopened.rewrite('generated prose', NoteRewrite.concise), 'validated');
    expect(fixture.bodies, hasLength(1));
    final root = (await fixture.disk.load('session'))!;
    expect(root.status, RunStatus.completed);
    expect(root.usage.modelCalls, 1);
    expect(root.usage.quality, UsageQuality.reported);
    reopened.close();
  });
  test('unknown profile blocks production before dispatch', () async {
    fixture.profiles.clear();
    await expectLater(
      createModelNoteOrganizer(assembly: fixture.assembly, sessionId: 'unknown'),
      throwsA(isA<ConfigurationFailure>()),
    );
    expect(fixture.bodies, isEmpty);
  });
  test('save failure resumes validated output without another model call', () async {
    final stages = await PersistentNoteStages.open(fixture.assembly, 'save');
    fixture.disk.fail = true;
    await expectLater(
      stages.execute('text', {'text': 'generated'}, CancellationToken()),
      throwsA(isA<NoteStageFailure>()),
    );
    fixture.disk.fail = false;
    expect(await stages.execute('text', {'text': 'generated'}, CancellationToken()), {'text': 'validated'});
    expect(fixture.bodies, hasLength(1));
  });
  test('partial stage retries only missing materials and retains original partial record', () async {
    fixture.output = (input) {
      final data = input['data'] as Map;
      final assigned = data['materials'] as List;
      return {
        'sections': [
          {
            'title': 'Theme',
            'refs': [assigned.first['id']],
          },
        ],
      };
    };
    final stages = await PersistentNoteStages.open(fixture.assembly, 'partial');
    final output = await stages.execute('outline', {
      'materials': [
        {'id': 'h1', 'source': 'highlight'},
        {'id': 'h2', 'source': 'highlight'},
      ],
    }, CancellationToken());
    expect((output['sections'] as List).expand((s) => s['refs']), ['h1', 'h2']);
    final input = jsonDecode((fixture.bodies.last['messages'] as List).last['content'] as String);
    expect(input['data']['materials'], [
      {'id': 'h2', 'source': 'highlight'},
    ]);
    expect((await fixture.disk.resumable()).any((r) => r.status == RunStatus.partial), isTrue);
    expect(fixture.bodies, hasLength(2));
  });
  test('cancel awaits the durable outcome; explicit retry uses a child then reuses its result', () async {
    final stages = await PersistentNoteStages.open(fixture.assembly, 'cancel');
    final token = CancellationToken();
    fixture.output = (_) {
      token.cancel();
      return {'text': 'late'};
    };
    await expectLater(stages.execute('text', {'text': 'generated'}, token), throwsA(isA<ResearchFailure>()));
    fixture.output = (_) => {'text': 'retried'};
    expect(await stages.execute('text', {'text': 'generated'}, CancellationToken()), {'text': 'retried'});
    expect(await stages.execute('text', {'text': 'generated'}, CancellationToken()), {'text': 'retried'});
    expect(fixture.bodies, hasLength(2));
  });
}
