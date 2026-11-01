import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/assistant/assistant_scope.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/widgets/assistant_panel.dart';
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/map_generation/widgets/generate_map_sheet.dart';
import 'package:marginmind/features/map_generation/widgets/map_empty_state.dart';
import 'package:marginmind/features/workspace/widgets/map_source_chip.dart';
import 'package:marginmind/features/workspace/widgets/map_selection_bar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart' hide Card;
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

Future<void> key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool primary = false,
  bool shift = false,
  bool alt = false,
}) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  if (primary) await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (primary) await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

Future<ProviderContainer> openWorkspace(
  WidgetTester tester, {
  List<Override> overrides = const [],
  InMemoryStudySetContentRepository? content,
  Map<String, Object> prefs = const {},
  AssistantCredentialState credentialState = AssistantCredentialState.ready,
  Future<String?> Function(String, int)? pageText,
}) async {
  final defaultContent = () {
    final base = demoContent();
    final d1 = base.documents.first;
    final newD1 = Document(id: d1.id, title: d1.title, fileName: d1.fileName, pageCount: 30, importedAt: d1.importedAt);
    final outline = DocumentOutline(
      documentId: d1.id,
      items: const [PdfOutlineEntry(id: 'c1', title: '学习的底层逻辑', page: 1)],
    );
    return base.copyWith(documents: [newD1, ...base.documents.skip(1)], documentOutlines: [outline]);
  }();

  final container = await pumpApp(
    tester,
    size: const Size(1280, 820),
    content: content ?? InMemoryStudySetContentRepository({'demo-1': defaultContent}),
    prefs: {'settings.language': 'zh', ...prefs},
    overrides: [
      assistantPageTextProvider.overrideWithValue(pageText ?? (path, page) async => '第 $page 页测试正文：关于记忆机制与认知负荷的内容。'),
      assistantCredentialStateProvider.overrideWith((ref) async => credentialState),
      ...overrides,
    ],
  );
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  return container;
}

Future<void> runGeneration(WidgetTester tester, Future<void> Function() action) async {
  Object? error;
  StackTrace? stack;
  var done = false;
  action().then(
    (_) => done = true,
    onError: (e, st) {
      error = e;
      stack = st;
      done = true;
    },
  );
  var iterations = 0;
  while (!done && iterations < 100) {
    iterations++;
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (error != null) {
    Error.throwWithStackTrace(error!, stack!);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MapEmptyState', () {
    testWidgets('renders all elements on empty map and suggestions toggle instruction text', (tester) async {
      final container = await openWorkspace(tester);
      final wsController = container.read(workspaceProvider('demo-1').notifier);

      // Create an empty map so MapEmptyState appears in MapPane
      await wsController.addMap('空脑图');
      await tester.pumpAndSettle();

      // Empty state glyph and title
      expect(find.byKey(const ValueKey('map-empty-state-source')), findsOneWidget);
      expect(find.text('从资料生成脑图'), findsOneWidget);

      // Suggestions
      final examChip = find.text('保留原文关键句');
      expect(examChip, findsOneWidget);
      final explainChip = find.text('每个主题附一句解释');
      expect(explainChip, findsOneWidget);

      final instructionsField = find.byKey(const ValueKey('map-empty-state-instructions'));

      // Toggle suggestion 1
      await tester.tap(examChip);
      await tester.pumpAndSettle();
      expect(find.descendant(of: instructionsField, matching: find.textContaining('保留原文关键句')), findsOneWidget);

      // Toggle suggestion 2
      await tester.tap(explainChip);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: instructionsField, matching: find.textContaining('保留原文关键句；每个主题附一句解释')),
        findsOneWidget,
      );

      // Untoggle suggestion 1
      await tester.tap(examChip);
      await tester.pumpAndSettle();
      expect(find.descendant(of: instructionsField, matching: find.textContaining('每个主题附一句解释')), findsOneWidget);

      // Blank topic button creates a topic, replacing empty state
      final blankButton = find.byKey(const ValueKey('map-empty-state-blank-button'));
      expect(blankButton, findsOneWidget);
      await tester.tap(blankButton);
      await tester.pumpAndSettle();

      // Now map has a topic, so MapEmptyState is dismissed
      expect(find.byType(MapEmptyState), findsNothing);
    });

    testWidgets('renders ModelSetupCard once a start finds AI not configured', (tester) async {
      final container = await openWorkspace(tester, credentialState: AssistantCredentialState.missingKey);
      final wsController = container.read(workspaceProvider('demo-1').notifier);
      await wsController.addMap('空脑图');
      await tester.pumpAndSettle();

      // Showing the empty map never reads credentials; starting does.
      expect(find.byType(ModelSetupCard), findsNothing);
      await tester.tap(find.byKey(const ValueKey('map-empty-state-start-button')));
      await tester.pumpAndSettle();

      expect(find.byType(ModelSetupCard), findsOneWidget);
      expect(find.byKey(const ValueKey('map-empty-state-start-button')), findsNothing);
    });

    testWidgets('Cmd+Enter in MapEmptyState triggers generation', (tester) async {
      FakeMapGenerator? fakeGen;
      final container = await openWorkspace(
        tester,
        overrides: [
          mapGeneratorProvider.overrideWithValue(() async {
            fakeGen = FakeMapGenerator(
              chapters: {
                'c1-all': ['{"k":"point","id":"p1","title":"Point 1"}'],
              },
              generation: ['{"ref":"t1","parent":"ROOT","title":"Chapter 1","page":1}'],
            );
            return fakeGen!;
          }),
        ],
      );
      final wsController = container.read(workspaceProvider('demo-1').notifier);
      await wsController.addMap('空脑图');
      await tester.pumpAndSettle();

      // Focus instructions text field specifically
      await tester.tap(find.byKey(const ValueKey('map-empty-state-instructions')));
      await tester.pump();

      // Press primary shortcut (Ctrl/Cmd + Enter)
      await key(tester, LogicalKeyboardKey.enter, primary: true);

      final preview = container.read(mapGenerationControllerProvider('demo-1'));
      expect(preview, isNotNull);
      expect(preview!.request.studySetId, 'demo-1');
    });
  });

  group('GenerateMapSheet', () {
    testWidgets('form controls, checklist and persistence', (tester) async {
      final container = await openWorkspace(
        tester,
        prefs: {
          'map_gen.demo-1.organization': 'topic',
          'map_gen.demo-1.depth': 4,
          'map_gen.demo-1.includeAnnotations': false,
        },
      );

      // Open sheet from the map menu
      await tester.tap(find.byKey(const ValueKey('map-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map-generate-menu-item')));
      await tester.pumpAndSettle();

      final sheet = find.byType(GenerateMapSheet);
      expect(sheet, findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('论文：检索练习效应')), findsNothing);
      expect(find.descendant(of: sheet, matching: find.byType(MMCheckbox)), findsNothing);
      expect(find.descendant(of: sheet, matching: find.byType(MMSwitch)), findsNothing);
      expect(find.text('按主题重组'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('map-generate-change-sources')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: sheet, matching: find.byType(MMCheckbox)), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('map-document-check-c1')));
      await tester.pumpAndSettle();
      expect(tester.widget<MMButton>(find.byKey(const ValueKey('map-generate-apply-sources'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('map-document-check-c2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map-generate-apply-sources')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: sheet, matching: find.text('论文：检索练习效应')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('map-generate-organization-question')));
      await tester.tap(find.byKey(const ValueKey('map-generate-more-settings')));
      await tester.pumpAndSettle();
      expect(tester.widget<MMSegmentedControl<int>>(find.byKey(const ValueKey('map-generate-detail'))).value, 4);
      final switches = tester
          .widgetList<MMSwitch>(find.descendant(of: sheet, matching: find.byType(MMSwitch)))
          .toList();
      expect(switches.first.value, isFalse);
      expect(switches.last.onChanged, isNotNull);
      expect(
        tester.widget<MMTextField>(find.byKey(const ValueKey('map-generate-target-title'))).controller!.text,
        '论文：检索练习效应',
      );
      await tester.tap(find.byKey(const ValueKey('map-generate-target-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('当前脑图的新分支').last);
      await tester.pumpAndSettle();

      // Start generation
      await tester.tap(find.byKey(const ValueKey('map-generate-sheet-start-button')));
      await tester.pump();

      final preview = container.read(mapGenerationControllerProvider('demo-1'));
      expect(preview, isNotNull);
      expect(preview!.request.organization, MapOrganization.question);
      expect(preview.request.destination, MapGenerationDestination.branch);
    });
  });

  group('Generation & Review Flow', () {
    testWidgets('Reading skeletons -> Streaming ghost nodes -> Review -> Keep creates map with source chip', (
      tester,
    ) async {
      final fake = FakeMapGenerator(
        chapters: {
          'c1-all': ['{"k":"point","id":"p1","title":"遗忘曲线与间隔重复"}', '{"k":"point","id":"p2","title":"提取练习效应"}'],
        },
        generation: [
          '{"ref":"t1","parent":"ROOT","title":"核心概念：间隔重复","page":24}',
          '{"ref":"t2","parent":"t1","title":"最佳复习间隔","page":25}',
        ],
      );

      final container = await openWorkspace(
        tester,
        overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
      );

      final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);

      // Start generation for new map
      await runGeneration(
        tester,
        () => controller.start(
          const MapGenerationRequest(
            studySetId: 'demo-1',
            mapId: 'new-map-1',
            title: '记忆机制',
            sources: [MapDocumentSelection(documentId: 'c1')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final preview = container.read(mapGenerationControllerProvider('demo-1'));
      expect(preview, isNotNull);
      expect(preview!.phase, MapGenerationPhase.review);
      expect(preview.lines.length, 2);

      // Review UI: MapSourceChip renders with page 24 & 25
      expect(find.byType(MapSourceChip), findsWidgets);
      expect(find.text('p.24'), findsOneWidget);
      expect(find.text('p.25'), findsOneWidget);

      // Test draft toggle cascade:
      // Deselect parent (t1) -> should deselect child (t2)
      controller.toggle(preview.lines[0].id, false);
      expect(container.read(mapGenerationControllerProvider('demo-1'))!.selectedCount, 0);

      // Select child (t2) -> should re-select parent (t1)
      controller.toggle(preview.lines[1].id, true);
      expect(container.read(mapGenerationControllerProvider('demo-1'))!.selectedCount, 2);

      // Inline edit: update t1's title
      controller.edit(preview.lines[0].id, '核心规律：间隔重复');
      expect(container.read(mapGenerationControllerProvider('demo-1'))!.lines[0].title, '核心规律：间隔重复');

      // Keep generation
      final keepButton = find.byKey(const ValueKey('map-generation-keep-button'));
      expect(keepButton, findsOneWidget);
      await tester.tap(keepButton);
      await tester.pumpAndSettle();

      // Generation should be committed into workspace
      final wsContent = container.read(workspaceProvider('demo-1').notifier).content;
      final newMap = wsContent.map('new-map-1');
      expect(newMap, isNotNull);
      expect(newMap!.generation, isNotNull);
      expect(newMap.generation!.sources.length, 1);
      expect(newMap.generation!.sources[0].documentId, 'c1');

      // Topics created with CardSource
      final createdCard = wsContent.cards.where((c) => c.title == '核心规律：间隔重复').firstOrNull;
      expect(createdCard, isNotNull);
      expect(createdCard!.source, isNotNull);
      expect(createdCard.source!.documentId, 'c1');
      expect(createdCard.source!.page, 24);

      // Test single-step undo (Cmd+Z)
      final wsController = container.read(workspaceProvider('demo-1').notifier);
      await wsController.undo();
      await tester.pumpAndSettle();

      // The new map should be undone in one step
      expect(wsController.content.map('new-map-1'), isNull);
    });

    testWidgets('Stop generation during reading phase discards, or stops during streaming', (tester) async {
      final fake = FakeMapGenerator(
        chapters: {
          'c1-all': ['{"k":"point","id":"p1","title":"Point"}'],
        },
        generation: ['{"ref":"t1","parent":"ROOT","title":"Topic 1"}'],
        delay: const Duration(seconds: 5),
      );

      final container = await openWorkspace(
        tester,
        overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
      );

      final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);
      unawaited(
        controller.start(
          const MapGenerationRequest(
            studySetId: 'demo-1',
            mapId: 'map-stop',
            title: '测试停止',
            sources: [MapDocumentSelection(documentId: 'c1')],
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('map-generation-stop-button')), findsOneWidget);

      // Press stop
      await tester.tap(find.byKey(const ValueKey('map-generation-stop-button')));
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      final preview = container.read(mapGenerationControllerProvider('demo-1'));
      expect(preview, isNull);
    });

    testWidgets('Discard during review resets generation state', (tester) async {
      final fake = FakeMapGenerator(
        chapters: {
          'c1-all': ['{"k":"point","id":"p1","title":"Point"}'],
        },
        generation: ['{"ref":"t1","parent":"ROOT","title":"Topic 1"}'],
      );

      final container = await openWorkspace(
        tester,
        overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
      );

      final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);
      await runGeneration(
        tester,
        () => controller.start(
          const MapGenerationRequest(
            studySetId: 'demo-1',
            mapId: 'map-discard',
            title: '测试放弃',
            sources: [MapDocumentSelection(documentId: 'c1')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map-generation-discard-button')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('map-generation-discard-button')));
      await tester.pumpAndSettle();

      expect(container.read(mapGenerationControllerProvider('demo-1')), isNull);
    });

    testWidgets('Adjust popover opens, updates settings, and triggers regeneration', (tester) async {
      final fake = FakeMapGenerator(
        chapters: {
          'c1-all': ['{"k":"point","id":"p1","title":"Point"}'],
        },
        generation: ['{"ref":"t1","parent":"ROOT","title":"Topic 1"}', '{"ref":"t2","parent":"t1","title":"Topic 2"}'],
      );

      final container = await openWorkspace(
        tester,
        overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
      );

      final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);
      await runGeneration(
        tester,
        () => controller.start(
          const MapGenerationRequest(
            studySetId: 'demo-1',
            mapId: 'map-adjust-test',
            title: '微调测试',
            sources: [MapDocumentSelection(documentId: 'c1')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(mapGenerationControllerProvider('demo-1'))?.phase, MapGenerationPhase.review);

      // Open Adjust popover
      final adjustButton = find.byKey(const ValueKey('map-generation-adjust-button'));
      expect(adjustButton, findsOneWidget);
      await tester.tap(adjustButton);
      await tester.pumpAndSettle();

      // Check adjust controls visible
      expect(find.byKey(const ValueKey('map-adjust-regenerate-button')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('map-adjust-instructions')), '更多细节');

      // Tap regenerate in adjust popover
      fake.generation.clear();
      fake.generation.add('{"ref":"t3","parent":"ROOT","title":"Regenerated Topic"}');

      await tester.tap(find.byKey(const ValueKey('map-adjust-regenerate-button')));
      while (container.read(mapGenerationControllerProvider('demo-1'))?.phase != MapGenerationPhase.review) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      expect(container.read(mapGenerationControllerProvider('demo-1'))?.round, 1);
      expect(find.text('Regenerated Topic'), findsOneWidget);
    });

    testWidgets('Review editing and toggle update selection and titles', (tester) async {
      final fake = FakeMapGenerator(
        chapters: {
          'c1-all': ['{"k":"point","id":"p1","title":"Point"}'],
        },
        generation: ['{"ref":"t1","parent":"ROOT","title":"Topic 1"}', '{"ref":"t2","parent":"t1","title":"Topic 2"}'],
      );

      final container = await openWorkspace(
        tester,
        overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
      );

      final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);
      await runGeneration(
        tester,
        () => controller.start(
          const MapGenerationRequest(
            studySetId: 'demo-1',
            mapId: 'map-edit-test',
            title: '编辑测试',
            sources: [MapDocumentSelection(documentId: 'c1')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final preview = container.read(mapGenerationControllerProvider('demo-1'))!;
      expect(preview.selectedCount, 2);
      final line1 = preview.lines.first;

      // Edit topic
      controller.edit(line1.id, 'Edited Title');
      expect(container.read(mapGenerationControllerProvider('demo-1'))?.editedTitles[line1.id], 'Edited Title');

      // Toggle topic
      controller.toggle(line1.id, false);
      expect(container.read(mapGenerationControllerProvider('demo-1'))?.selectedCount, 0);

      controller.toggle(line1.id, true);
      expect(container.read(mapGenerationControllerProvider('demo-1'))?.selectedCount, 1);
    });

    testWidgets('Multi-chapter document with outline generates with skeletons', (tester) async {
      final content = demoContent();
      final oldDoc = content.documents.first;
      final docWithOutline = Document(
        id: oldDoc.id,
        title: oldDoc.title,
        fileName: oldDoc.fileName,
        pageCount: 20,
        importedAt: oldDoc.importedAt,
      );
      final outline = DocumentOutline(
        documentId: docWithOutline.id,
        items: const [
          PdfOutlineEntry(id: 'ch1', title: 'Chapter 1', page: 1),
          PdfOutlineEntry(id: 'ch2', title: 'Chapter 2', page: 10),
        ],
      );
      final repo = InMemoryStudySetContentRepository({
        'demo-1': content.copyWith(documents: [docWithOutline], documentOutlines: [outline]),
      });

      final fake = FakeMapGenerator(
        chapters: {
          '${docWithOutline.id}-ch1': ['{"k":"point","id":"p1","title":"P1"}'],
          '${docWithOutline.id}-ch2': ['{"k":"point","id":"p2","title":"P2"}'],
        },
        generation: ['{"ref":"t1","parent":"ROOT","title":"Outline Topic"}'],
      );

      final container = await openWorkspace(
        tester,
        content: repo,
        overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
      );

      final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);
      await runGeneration(
        tester,
        () => controller.start(
          MapGenerationRequest(
            studySetId: 'demo-1',
            mapId: 'map-outline-test',
            title: '多章大纲测试',
            sources: [MapDocumentSelection(documentId: docWithOutline.id)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(mapGenerationControllerProvider('demo-1'))?.phase, MapGenerationPhase.review);
      expect(find.text('Outline Topic'), findsOneWidget);
    });

    testWidgets('Integration with DocumentDigestBuilder, cache hit, and fingerprint matching', (tester) async {
      final fake = FakeMapGenerator(
        chapters: {
          '*': ['{"k":"point","id":"p1","title":"核心要点：遗忘曲线","page":24,"marks":["A1"]}'],
        },
        generation: ['{"ref":"t1","parent":"ROOT","title":"遗忘曲线","page":24}', '{"mark":"A1","parent":"t1"}'],
      );

      final container = await openWorkspace(
        tester,
        overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
      );

      final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);
      final digestBuilder = container.read(documentDigestBuilderProvider('demo-1'));
      final wsController = container.read(workspaceProvider('demo-1').notifier);

      // 1. Run generation for new map with annotations enabled
      await runGeneration(
        tester,
        () => controller.start(
          const MapGenerationRequest(
            studySetId: 'demo-1',
            mapId: 'digest-map-1',
            title: '学习的底层逻辑',
            sources: [MapDocumentSelection(documentId: 'c1')],
            includeAnnotations: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final preview = container.read(mapGenerationControllerProvider('demo-1'));
      expect(preview, isNotNull);
      expect(preview!.phase, MapGenerationPhase.review);

      // Assert 1: chapter input text is non-empty and contains annotation alias
      final input = controller.chapterInputs.values.first;
      expect(input.textByPage.values.every((t) => t.isNotEmpty), isTrue);
      expect(input.context.annotations, isNotEmpty);
      expect(input.context.annotations.containsKey('A1'), isTrue);

      // Assert 2: after keep(), MindMap.generation fingerprint equals digest fingerprint
      final expectedDigest = await digestBuilder.build(
        wsController.content,
        studySetId: 'demo-1',
        documentId: 'c1',
        mapId: 'digest-map-1',
        draftPrefix: 'test-prefix-',
        documentAlias: 'D1',
        includeAnnotations: true,
      );

      final keepCount = await controller.keep();
      await tester.pumpAndSettle();
      expect(keepCount, greaterThan(0));

      final createdMap = wsController.content.map('digest-map-1');
      expect(createdMap, isNotNull);
      expect(createdMap!.generation, isNotNull);
      expect(createdMap.generation!.sources.first.fingerprint, expectedDigest.source.fingerprint);

      // Assert 3: second generation hits cache, readChapter is not called again
      final initialReadCalls = fake.calls.where((c) => c.startsWith('chapter:')).length;
      expect(initialReadCalls, greaterThan(0));

      await runGeneration(
        tester,
        () => controller.start(
          const MapGenerationRequest(
            studySetId: 'demo-1',
            mapId: 'digest-map-2',
            title: '学习的底层逻辑 2',
            sources: [MapDocumentSelection(documentId: 'c1')],
            includeAnnotations: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final secondReadCalls = fake.calls.where((c) => c.startsWith('chapter:')).length;
      expect(secondReadCalls, initialReadCalls);
    });
  });

  group('Error Handling', () {
    testWidgets('Network failure shows error banner and retry recovers', (tester) async {
      final fake = FakeMapGenerator(
        chapters: {
          'c1-all': ['{"k":"point","id":"p1","title":"Point"}'],
        },
        generationFailure: const ResearchFailure(ResearchFailureKind.network),
      );

      final container = await openWorkspace(
        tester,
        overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
      );

      final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);
      await runGeneration(
        tester,
        () => controller.start(
          const MapGenerationRequest(
            studySetId: 'demo-1',
            mapId: 'map-net-err',
            title: '网络错误测试',
            sources: [MapDocumentSelection(documentId: 'c1')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify network error state
      expect(find.text('网络不可用'), findsOneWidget);
      final retryButton = find.byKey(const ValueKey('map-generation-failed-retry-button'));
      expect(retryButton, findsOneWidget);

      // Fix failure and retry
      fake.generationFailure = null;
      fake.generation.add('{"ref":"t1","parent":"ROOT","title":"Recovered Topic"}');

      await tester.tap(retryButton);
      while (container.read(mapGenerationControllerProvider('demo-1'))?.phase != MapGenerationPhase.review) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      expect(container.read(mapGenerationControllerProvider('demo-1'))?.phase, MapGenerationPhase.review);
      expect(find.text('Recovered Topic'), findsOneWidget);
    });

    testWidgets('Single chapter failure shows warning banner and retry chapter recovers', (tester) async {
      final fake = FakeMapGenerator(
        chapterFailures: {'c1-all': const ResearchFailure(ResearchFailureKind.timeout)},
        chapters: {
          'c1-all': ['{"k":"point","id":"p1","title":"Point"}'],
        },
        generation: ['{"ref":"t1","parent":"ROOT","title":"Topic 1"}'],
      );

      final container = await openWorkspace(
        tester,
        overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
      );

      final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);
      await runGeneration(
        tester,
        () => controller.start(
          const MapGenerationRequest(
            studySetId: 'demo-1',
            mapId: 'map-ch-err',
            title: '单章重试测试',
            sources: [MapDocumentSelection(documentId: 'c1')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check chapter retry button
      final retryChapterButton = find.byKey(const ValueKey('map-generation-retry-chapter-button'));
      expect(retryChapterButton, findsOneWidget);
      fake.chapterFailures.clear();
      await tester.tap(retryChapterButton);
      while (container.read(mapGenerationControllerProvider('demo-1'))?.phase != MapGenerationPhase.review) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(container.read(mapGenerationControllerProvider('demo-1'))?.phase, MapGenerationPhase.review);
    });
  });

  group('Sidebar and Header Controls', () {
    testWidgets('generation lives in the neutral more menu and follows preview state', (tester) async {
      final container = await openWorkspace(tester);

      expect(find.text('生成脑图'), findsNothing);
      expect(find.byKey(const ValueKey('map-generate-header-button')), findsNothing);
      final workspace = container.read(workspaceProvider('demo-1').notifier);
      workspace.selectCard('c3');
      await tester.pumpAndSettle();
      expect(find.byType(MapNodeBar), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('map-more')));
      await tester.pumpAndSettle();
      final item = find.byKey(const ValueKey('map-generate-menu-item'));
      expect(find.descendant(of: item, matching: find.text('生成脑图')), findsOneWidget);
      expect(tester.widget<MMDropdownItem<VoidCallback>>(item).enabled, isTrue);
      final icon = find.descendant(of: item, matching: find.byIcon(MMIcons.generateMap));
      expect(IconTheme.of(tester.element(icon)).color, tester.element(icon).mmColors.label);
      final menu = find.byWidgetPredicate((w) => w is MMAdaptiveToolbar && w.menuKey == const ValueKey('map-more'));
      final entries = tester.widget<MMAdaptiveToolbar>(menu).menuEntries;
      for (final label in ['添加子主题', '在后面添加同级节点', '添加关联线', '添加概要', '添加笔记', '插入图片…', '标签…', '显示详情']) {
        for (final entry in entries) {
          expect(find.descendant(of: find.byWidget(entry), matching: find.text(label)), findsNothing);
        }
      }
      expect(find.text('定位选中节点'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);

      // Simulate generating state
      controller.state = MapGenerationPreview(
        request: const MapGenerationRequest(studySetId: 'demo-1', mapId: 'demo-1', title: 'T', sources: []),
        baseRevision: 0,
        proposalId: 'p1',
        generation: MapGeneration(
          sources: [MapSource(documentId: 'c1', chapters: const [], fingerprint: 'fp', readThrough: 1)],
          organization: MapOrganization.chapter,
          depth: 3,
          generatedAt: DateTime.now(),
        ),
        phase: MapGenerationPhase.streaming,
        lines: [MapLine(id: 'draft-1', kind: MapLineKind.add, parentId: 'ROOT', title: '待审阅主题')],
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('map-more')));
      await tester.pump();
      expect(find.descendant(of: item, matching: find.text('生成中')), findsOneWidget);
      expect(tester.widget<MMDropdownItem<VoidCallback>>(item).enabled, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      // Simulate review state
      controller.state = controller.state!.copyWith(phase: MapGenerationPhase.review);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map-more')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: item, matching: find.text('审阅中')), findsOneWidget);
      expect(tester.widget<MMDropdownItem<VoidCallback>>(item).enabled, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });

    testWidgets('WorkspaceSidebar shows mind map icon for associated document and updates dot', (tester) async {
      // Create study set where demo-1 map has generation referencing c1
      final content = demoContent();
      final mapWithGen = content.maps.first.copyWith(
        generation: MapGeneration(
          sources: [MapSource(documentId: 'c1', chapters: const [], fingerprint: 'fp1', readThrough: 10)],
          organization: MapOrganization.chapter,
          depth: 3,
          generatedAt: DateTime.now(),
        ),
      );
      final repo = InMemoryStudySetContentRepository({
        'demo-1': content.copyWith(maps: [mapWithGen]),
      });

      await openWorkspace(tester, content: repo);

      // Check document row has mind map icon
      final docRow = find.byKey(const ValueKey('document-row-c1'));
      expect(docRow, findsOneWidget);
      expect(find.descendant(of: docRow, matching: find.byIcon(MMIcons.mindMap)), findsOneWidget);

      // Check Maps section '+' dropdown button exists
      expect(find.byKey(const ValueKey('add-map-menu')), findsOneWidget);
    });
  });
}
