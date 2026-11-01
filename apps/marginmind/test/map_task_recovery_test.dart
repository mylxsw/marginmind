import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/map_task_factory.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/assistant_reader.dart';
import 'package:marginmind/features/assistant/expansion_controller.dart';
import 'package:marginmind/features/assistant/map_generation_context.dart';
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';

import 'helpers.dart' show demoContent;

import 'package:marginmind/features/assistant/widgets/map_task_recovery.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:marginmind/features/assistant/assistant_scope.dart';
import 'package:mm_data/mm_data.dart';

import 'assistant_settings_test.dart' show Secrets;
import 'quick_task_assembly_test.dart' show DiskRepository;

class Fixture {
  late Directory directory;
  late HttpServer server;
  late StreamSubscription<HttpRequest> subscription;
  late ProviderContainer container;
  List<Override> overrides = [];
  int calls = 0;
  int statusCode = HttpStatus.ok;
  Future<void> Function()? beforeReply;
  String Function(Map<String, dynamic>) reply = (_) => 'saved result';

  Future<void> open({StudySetContent? content}) async {
    directory = await Directory.systemTemp.createTemp('map-domain-recovery-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    subscription = server.listen((request) async {
      final body = Map<String, dynamic>.from(jsonDecode(await utf8.decoder.bind(request).join()));
      calls++;
      await beforeReply?.call();
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': 'fixture',
          'object': 'chat.completion',
          'model': 'fixture',
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': reply(body)},
              'finish_reason': 'stop',
            },
          ],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 2, 'total_tokens': 12},
        }),
      );
      await request.response.close();
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final services = AssistantServicesStore(prefs, Secrets());
    final service = AssistantService(
      id: 'fixture',
      revision: 1,
      protocol: ServiceProtocol.ollama,
      name: 'Local fixture',
      endpoint: 'http://127.0.0.1:${server.port}/v1',
      localEnabled: true,
      models: [const ServiceModel(id: 'model')],
    );
    await services.save(AssistantServices(services: [service], defaultModel: const ModelReference('fixture', 'model')));
    final routing = AssistantRoutingStore(prefs, services);
    await routing.load();
    final profiles = CapabilityProfiles()
      ..put(
        ModelCapabilityProfile(
          identity: serviceCapabilityIdentity(service, service.models.single),
          thinking: ThinkingCapability.notApplicable,
          tools: CapabilitySupport.supported,
          historyReplay: CapabilitySupport.supported,
          contextTokens: 32000,
          outputTokens: 16000,
          evidence: CapabilityEvidence(
            source: CapabilityEvidenceSource.maintainedProfile,
            reference: 'fixture',
            semanticBasis: 'Loopback only',
            verifiedAt: DateTime.utc(2026),
            wireVerified: true,
          ),
        ),
      );
    overrides = [
      contentRepositoryProvider.overrideWithValue(
        content == null ? DiskRepository(directory.path) : DiskContent(directory.path, content),
      ),
      if (content != null) ...[
        workspaceProvider('study').overrideWith(() => TestWorkspace(content)),
        assistantControllerProvider.overrideWith(IdleAssistant.new),
        studySetProvider('study').overrideWith((ref) => null),
        assistantPageTextProvider.overrideWithValue((_, _) async => '${'x' * 9999}😀${'y' * 21000}'),
        documentDigestBuilderProvider('study').overrideWith(
          (ref) => DocumentDigestBuilder(
            WorkspaceReader(
              content: () => content,
              contexts: const [],
              filePath: (_) => 'fixture.pdf',
              pageText: (_, _) async => '${'x' * 9999}😀${'y' * 21000}',
            ),
          ),
        ),
      ],
      sharedPreferencesProvider.overrideWithValue(prefs),
      assistantServicesStoreProvider.overrideWithValue(services),
      assistantRoutingStoreProvider.overrideWithValue(routing),
      assistantCapabilityProfilesProvider.overrideWithValue(profiles),
    ];
    container = ProviderContainer(overrides: overrides);
  }

  void restart() {
    container.dispose();
    container = ProviderContainer(overrides: overrides);
  }

  MapTaskSession session(TaskSpec spec) => container.read(Provider((ref) => MapTaskSession(ref, 'study', spec)));
  Future<MapTaskSession> restore(TaskSpec spec, String id) =>
      container.read(Provider((ref) => MapTaskSession.restore(ref, 'study', spec, id)));

  Future<void> blockRunWrites() async {
    await Directory('${directory.path}/ai-runs').rename('${directory.path}/held-runs');
    await File('${directory.path}/ai-runs').writeAsString('blocked');
  }

  Future<void> restoreRunWrites() async {
    await File('${directory.path}/ai-runs').delete();
    await Directory('${directory.path}/held-runs').rename('${directory.path}/ai-runs');
  }

  Future<void> close() async {
    container.dispose();
    await subscription.cancel();
    await server.close(force: true);
    await directory.delete(recursive: true);
  }
}

class DiskContent extends InMemoryStudySetContentRepository {
  DiskContent(this.path, StudySetContent content) : super({'study': content});
  final String path;
  @override
  String resolveFile(String studySetId, String fileName) => '$path/$fileName';
}

class TestWorkspace extends WorkspaceController {
  TestWorkspace(this.snapshot) : super('study');
  final StudySetContent snapshot;
  @override
  WorkspaceState build() => WorkspaceState(content: snapshot);
  void changeSource() => state = const WorkspaceState(content: StudySetContent.empty);
}

class IdleAssistant extends AssistantController {
  @override
  Conversation build() => Conversation(id: 'idle', studySetId: 'study', model: unconfiguredAssistantModel);
}

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for fixture');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUp(() {
    HttpOverrides.global = null;
  });
  testWidgets('production RunStore save failure keeps the same handle and retry button through repeated failures', (
    tester,
  ) async {
    final fixture = Fixture();
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    late MapTaskSession session;
    late Future<String> result;
    try {
      await tester.runAsync(() async {
        await fixture.open();
        session = fixture.session(mapGenerateSpec);
        fixture.beforeReply = fixture.blockRunWrites;
        result = session.execute('fixed', {'part': 1}, CancellationToken(), (_) => ValidationReport());
        await until(() => session.saveFailed.isNotEmpty);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: MapTaskRecovery(studySetId: 'study', canContinue: false)),
          ),
        ),
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        expect(find.text('Retry saving'), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text('Retry saving'));
          await until(() => !session.retryingSave);
        });
        await tester.pump();
        expect(session.saveFailed, hasLength(1));
        expect(find.text('Retry saving'), findsOneWidget);
        expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Retry saving')).onPressed, isNotNull);
        expect(fixture.calls, 1);
      }
      await tester.runAsync(() async {
        await fixture.restoreRunWrites();
        await session.retrySave();
        expect(await result, 'saved result');
        final saved = (await FileRunStore(fixture.directory).load(session.id!))!;
        expect(saved.status, RunStatus.completed);
        expect(saved.usage.modelCalls, 1);
        expect(saved.usage.inputTokens, 10);
        expect(saved.usage.outputTokens, 2);
      });
      await tester.pump();
      expect(find.text('Retry saving'), findsNothing);
      expect(fixture.calls, 1);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(fixture.close);
      HttpOverrides.global = previous;
    }
  });

  testWidgets('saved task entry never dispatches on load and requires explicit confirmation', (tester) async {
    final fixture = Fixture();
    await tester.runAsync(() async {
      await fixture.open();
      final session = fixture.session(mapExpandSpec);
      await session.saveWorkflow({
        'request': {'mapId': 'map'},
        'sourceRevision': 'revision',
      });
      await fixture.container.read(mapRecoverableTasksProvider('study').future);
    });
    try {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: MapTaskRecovery(studySetId: 'study', canContinue: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fixture.calls, 0);
      await tester.tap(find.text('Continue saved map task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expand map · map'));
      await tester.pumpAndSettle();
      expect(find.textContaining('incur a charge'), findsOneWidget);
      expect(fixture.calls, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fixture.calls, 0);
      expect(find.byType(AlertDialog), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(fixture.close);
    }
  });

  for (final generate in [true, false]) {
    test(
      '${generate ? 'map_generate' : 'map_expand'} controller restores the original preview without buying complete stages',
      () async {
        final fixture = Fixture();
        final original = demoContent(), doc = demoContent().documents.first;
        final content = original.copyWith(
          documents: [
            Document(id: doc.id, title: doc.title, fileName: doc.fileName, pageCount: 1, importedAt: doc.importedAt),
          ],
        );
        await fixture.open(content: content);
        var container = fixture.container;
        var generationSub = container.listen(mapGenerationControllerProvider('study'), (_, _) {});
        var expansionSub = container.listen(expansionControllerProvider('study'), (_, _) {});
        try {
          fixture.reply = (body) {
            if (!generate) return '{"ref":"a","parent":"T1","title":"New idea"}';
            final input = jsonDecode((body['messages'] as List).last['content']) as Map;
            final line = input.containsKey('pages')
                ? {'k': 'point', 'id': 'p', 'title': 'Slice ${fixture.calls}', 'doc': 'D1', 'page': 1}
                : {'ref': 'a', 'parent': 'ROOT', 'title': 'Generated topic'};
            return '${jsonEncode(line)}\n${jsonEncode({'coverage': input['requiredCoverage']})}';
          };
          final mapId = content.maps.first.id;
          if (generate) {
            await container
                .read(mapGenerationControllerProvider('study').notifier)
                .start(
                  MapGenerationRequest(
                    studySetId: 'study',
                    mapId: mapId,
                    title: 'Map',
                    sources: [MapDocumentSelection(documentId: doc.id)],
                    includeAnnotations: false,
                  ),
                );
            final preview = container.read(mapGenerationControllerProvider('study'))!;
            expect(preview.phase, MapGenerationPhase.review);
            final calls = fixture.calls;
            final id = (await container.read(mapRecoverableTasksProvider('study').future)).single['id'] as String;
            final cache = Directory('${fixture.directory.path}/ai-cache');
            if (await cache.exists()) await cache.delete(recursive: true);
            generationSub.close();
            expansionSub.close();
            fixture.restart();
            container = fixture.container;
            generationSub = container.listen(mapGenerationControllerProvider('study'), (_, _) {});
            expansionSub = container.listen(expansionControllerProvider('study'), (_, _) {});
            await container.read(mapGenerationControllerProvider('study').notifier).continueTask(id);
            final restored = container.read(mapGenerationControllerProvider('study'))!;
            expect(restored.phase, MapGenerationPhase.review);
            expect(restored.proposalId, preview.proposalId);
            expect(restored.baseRevision, preview.baseRevision);
            expect(restored.lines.map((p) => p.id), preview.lines.map((p) => p.id));
            expect(fixture.calls, calls);
            generationSub.close();
            expansionSub.close();
            fixture.restart();
            container = fixture.container;
            generationSub = container.listen(mapGenerationControllerProvider('study'), (_, _) {});
            expansionSub = container.listen(expansionControllerProvider('study'), (_, _) {});
            (container.read(workspaceProvider('study').notifier) as TestWorkspace).changeSource();
            await expectLater(
              container.read(mapGenerationControllerProvider('study').notifier).continueTask(id),
              throwsA(isA<ConfigurationFailure>().having((e) => e.code, 'code', 'mapSourceRevisionChanged')),
            );
            expect(fixture.calls, calls);
          } else {
            await container
                .read(expansionControllerProvider('study').notifier)
                .start(
                  ExpansionRequest(
                    studySetId: 'study',
                    mapId: mapId,
                    targetIds: [content.nodes.first.cardId],
                    grounded: false,
                  ),
                );
            final preview = container.read(expansionControllerProvider('study'))!;
            expect(preview.phase, ExpansionPhase.review);
            final calls = fixture.calls;
            final id = (await container.read(mapRecoverableTasksProvider('study').future)).single['id'] as String;
            generationSub.close();
            expansionSub.close();
            fixture.restart();
            container = fixture.container;
            generationSub = container.listen(mapGenerationControllerProvider('study'), (_, _) {});
            expansionSub = container.listen(expansionControllerProvider('study'), (_, _) {});
            await container.read(expansionControllerProvider('study').notifier).continueTask(id);
            final restored = container.read(expansionControllerProvider('study'))!;
            expect(restored.phase, ExpansionPhase.review);
            expect(restored.proposalId, preview.proposalId);
            expect(restored.baseRevision, preview.baseRevision);
            expect(restored.drafts.map((p) => p.id), preview.drafts.map((p) => p.id));
            expect(fixture.calls, calls);
            generationSub.close();
            expansionSub.close();
            fixture.restart();
            container = fixture.container;
            generationSub = container.listen(mapGenerationControllerProvider('study'), (_, _) {});
            expansionSub = container.listen(expansionControllerProvider('study'), (_, _) {});
            (container.read(workspaceProvider('study').notifier) as TestWorkspace).changeSource();
            await expectLater(
              container.read(expansionControllerProvider('study').notifier).continueTask(id),
              throwsA(isA<ConfigurationFailure>().having((e) => e.code, 'code', 'mapSourceRevisionChanged')),
            );
            expect(fixture.calls, calls);
          }
        } finally {
          generationSub.close();
          expansionSub.close();
          await fixture.close();
        }
      },
    );
  }

  test('a continued partial map replays accepted refs and purchases only one missing repair stage', () async {
    final fixture = Fixture();
    await fixture.open();
    try {
      final session = fixture.session(mapGenerateSpec);
      await session.saveWorkflow({'request': {}, 'sourceRevision': 'revision'});
      const topic = '{"ref":"a","parent":"ROOT","title":"Topic"}';
      fixture.reply = (_) => fixture.calls == 1 ? '$topic\nbad' : 'bad';
      MapBuildInput input() => MapBuildInput(
        title: 'Map',
        points: [],
        generation: MapGeneration(
          sources: [MapSource(documentId: 'document', chapters: const [], fingerprint: 'fp', readThrough: 1)],
          organization: MapOrganization.chapter,
          depth: 3,
          generatedAt: DateTime.utc(2026),
        ),
        context: MapLineContext(
          phase: MapLinePhase.generation,
          mapId: 'map',
          draftPrefix: 'fixed-',
          documents: {},
          pages: {},
        ),
      );
      final model = ModelMapGenerator.runtime(session.execute);
      await expectLater(model.generate(input(), CancellationToken()).toList(), throwsA(isA<MapGenerationFailure>()));
      expect(fixture.calls, 3);
      await model.close();
      fixture.restart();
      final restored = await fixture.restore(mapGenerateSpec, session.id!);
      fixture.reply = (body) {
        final payload = jsonDecode((body['messages'] as List).last['content']);
        expect(payload['accepted'], [topic]);
        expect(payload['rejected'], ['bad']);
        return '{"ref":"b","parent":"a","title":"Child"}';
      };
      final continued = ModelMapGenerator.runtime(restored.execute, continuationRepairs: restored.continuationRound);
      final lines = await continued.generate(input(), CancellationToken()).toList();
      expect(lines.map((l) => l.title), ['Topic', 'Child']);
      expect(lines.last.parentId, 'new:${lines.first.id}');
      expect(fixture.calls, 4);
      await continued.close();
      fixture.restart();
      final again = await fixture.restore(mapGenerateSpec, session.id!);
      final complete = ModelMapGenerator.runtime(again.execute, continuationRepairs: again.continuationRound);
      expect((await complete.generate(input(), CancellationToken()).toList()).map((l) => l.title), ['Topic', 'Child']);
      expect(fixture.calls, 4);
      await complete.close();
    } finally {
      await fixture.close();
    }
  });

  test('continued expansion restores accepted parents and only buys the missing depth', () async {
    final fixture = Fixture();
    await fixture.open();
    try {
      final session = fixture.session(mapExpandSpec);
      await session.saveWorkflow({'request': {}, 'sourceRevision': 'revision'});
      final request = ExpansionRequest(
        studySetId: 'study',
        mapId: 'map',
        targetIds: ['target'],
        depth: 2,
        grounded: false,
      );
      ExpansionContext context() => ExpansionContext(
        targets: {'T1': 'target'},
        details: {'T1': ExpansionTargetContext(title: 'Root')},
        draftPrefix: 'stable-',
      );
      fixture.reply = (_) => fixture.calls == 1 ? '{"ref":"a","parent":"T1","title":"Accepted parent"}' : '';
      final model = ModelIdeaExpander.runtime(session.execute);
      await expectLater(
        model.expand(request, context(), CancellationToken()).toList(),
        throwsA(isA<ResearchFailure>()),
      );
      expect(fixture.calls, 2);
      model.close();
      fixture.restart();
      final restored = await fixture.restore(mapExpandSpec, session.id!);
      fixture.reply = (body) {
        final payload = jsonDecode((body['messages'] as List).last['content']);
        expect(payload['accepted'], hasLength(1));
        expect(payload['parentsNeedingChildren'], ['a']);
        return '{"ref":"b","parent":"a","title":"Missing child"}';
      };
      final continued = ModelIdeaExpander.runtime(restored.execute, continuationRepairs: restored.continuationRound);
      final drafts = await continued.expand(request, context(), CancellationToken()).toList();
      expect(drafts.map((d) => d.title), ['Accepted parent', 'Missing child']);
      expect(drafts.last.parentRef, 'new:${drafts.first.id}');
      expect(fixture.calls, 3);
      continued.close();
    } finally {
      await fixture.close();
    }
  });

  test('durable pending recovery only flushes, while unknown in-flight work needs explicit continuation', () async {
    final fixture = Fixture();
    await fixture.open();
    try {
      final session = fixture.session(mapGenerateSpec);
      await session.saveWorkflow({
        'request': {'mapId': 'map'},
        'sourceRevision': 'rev',
      });
      const input = {'part': 'pending'};
      await session.execute('fixed', input, CancellationToken(), (_) => ValidationReport());
      final file = File('${fixture.directory.path}/ai-runs/v1/${session.id}.json');
      final completed = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      // Simulate a process exit after Runtime's durable validating checkpoint,
      // before terminal completion. The SDK state and usage are genuine.
      final interrupted = jsonDecode(jsonEncode(completed)) as Map<String, dynamic>;
      interrupted['manifest']['status'] = 'interrupted';
      interrupted['manifest']['checkpoint']['pending'] = interrupted['result'];
      interrupted['result'] = null;
      await file.writeAsString(jsonEncode(interrupted));
      final restored = await fixture.restore(mapGenerateSpec, session.id!);
      expect(fixture.calls, 1); // Loading the workflow never dispatches.
      expect(await restored.execute('fixed', input, CancellationToken(), (_) => ValidationReport()), 'saved result');
      expect(fixture.calls, 1);
      expect((await FileRunStore(fixture.directory).load(session.id!))!.usage.modelCalls, 1);

      // A checkpoint without a verified pending result is deliberately not
      // replayed by load/recover. Only the explicit continue command permits it.
      final unknown = jsonDecode(jsonEncode(interrupted)) as Map<String, dynamic>;
      (unknown['manifest']['checkpoint'] as Map).remove('pending');
      await file.writeAsString(jsonEncode(unknown));
      final waiting = await fixture.restore(mapGenerateSpec, session.id!);
      waiting.explicitContinuation = false;
      await expectLater(
        waiting.execute('fixed', input, CancellationToken(), (_) => ValidationReport()),
        throwsA(isA<ConfigurationFailure>().having((e) => e.code, 'code', 'mapContinueRequired')),
      );
      expect(fixture.calls, 1);
      waiting.explicitContinuation = true;
      await waiting.execute('fixed', input, CancellationToken(), (_) => ValidationReport());
      expect(fixture.calls, 2);
      expect((await FileRunStore(fixture.directory).load(session.id!))!.usage.modelCalls, 2);
    } finally {
      await fixture.close();
    }
  });

  test('restored source payload and tampered request fingerprints fail before dispatch', () async {
    final fixture = Fixture();
    await fixture.open();
    try {
      final session = fixture.session(mapExpandSpec);
      await session.saveWorkflow({'request': {}, 'sourceRevision': 'rev'});
      const host = {
        'prefix': 'stable-',
        'targets': {'T1': 'private-target'},
        'repair': 0,
      };
      const input = {
        'targets': {'T1': 'original source'},
        '_mapHost': host,
      };
      await session.execute('fixed', input, CancellationToken(), (_) => ValidationReport());
      final restored = await fixture.restore(mapExpandSpec, session.id!);
      await expectLater(
        restored.execute(
          'fixed',
          {
            'targets': {'T1': 'changed source'},
            '_mapHost': host,
          },
          CancellationToken(),
          (_) => ValidationReport(),
        ),
        throwsA(isA<ConfigurationFailure>().having((e) => e.code, 'code', 'mapStageSourceChanged')),
      );
      await session.journal.update(
        session.id!,
        (data) => ((data['stages'] as Map).values.single as Map)['fingerprint'] = 'tampered',
      );
      final tampered = await fixture.restore(mapExpandSpec, session.id!);
      await expectLater(
        tampered.execute('fixed', input, CancellationToken(), (_) => ValidationReport()),
        throwsA(isA<ConfigurationFailure>().having((e) => e.code, 'code', 'mapStageMismatch')),
      );
      expect(fixture.calls, 1);
    } finally {
      await fixture.close();
    }
  });

  for (final spec in [mapGenerateSpec, mapExpandSpec]) {
    test(
      '${spec.type.name} journal restores frozen config, completed/partial stages and repair inputs without repurchase',
      () async {
        final fixture = Fixture();
        await fixture.open();
        try {
          final session = fixture.session(spec);
          await session.saveWorkflow({
            'request': {'mapId': 'map'},
            'sourceRevision': 'revision',
          });
          final root = await session.freeze();
          expect(
            await session.execute('fixed', {'part': 'complete'}, CancellationToken(), (_) => ValidationReport()),
            'saved result',
          );
          await session.execute(
            'fixed',
            {'part': 'partial'},
            CancellationToken(),
            (_) => ValidationReport(missingInputIds: {'range-2'}),
          );
          final restored = await fixture.restore(spec, session.id!);
          expect(encodeRunContext(await restored.freeze()), encodeRunContext(root));
          expect(restored.workflow!['sourceRevision'], 'revision');
          expect(
            await restored.execute('fixed', {'part': 'complete'}, CancellationToken(), (_) => ValidationReport()),
            'saved result',
          );
          await restored.execute(
            'fixed',
            {'part': 'partial'},
            CancellationToken(),
            (_) => ValidationReport(missingInputIds: {'range-2'}),
          );
          expect(fixture.calls, 2);
          final repair = {
            'part': 'repair',
            'accepted': ['good'],
            'rejected': ['bad'],
            'missing': ['range-2'],
          };
          await restored.execute('fixed', repair, CancellationToken(), (_) => ValidationReport());
          final again = await fixture.restore(spec, session.id!);
          await again.execute('fixed', repair, CancellationToken(), (_) => ValidationReport());
          expect(fixture.calls, 3);
          final journal = await again.journal.load(session.id!);
          final stages = (journal['stages'] as Map).values.cast<Map>();
          expect(stages.singleWhere((s) => s['payload']['part'] == 'repair')['payload']['accepted'], ['good']);
          await expectLater(
            fixture.restore(spec == mapGenerateSpec ? mapExpandSpec : mapGenerateSpec, session.id!),
            throwsA(isA<ConfigurationFailure>()),
          );
        } finally {
          await fixture.close();
        }
      },
    );
  }
}
