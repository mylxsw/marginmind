import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/map_generation/document_map_navigation.dart';
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/map_generation/widgets/generate_map_sheet.dart';
import 'package:marginmind/features/map_generation/widgets/document_map_banner.dart';
import 'package:marginmind/features/map_generation/widgets/map_generation_bar.dart';
import 'package:marginmind/features/workspace/widgets/map_source_chip.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_screen.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/expansion_controller.dart';
import 'package:marginmind/features/assistant/widgets/assistant_panel.dart' show ModelSetupCard;
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'map_generation_ui_test.dart' as harness;

MapGeneration generation(List<String> docs) => MapGeneration(
  sources: [for (final id in docs) MapSource(documentId: id, fingerprint: 'test', readThrough: 1)],
  organization: MapOrganization.topic,
  depth: 3,
  generatedAt: testNow,
);

StudySetContent multiDocumentContent() {
  final base = demoContent();
  return base.copyWith(
    maps: [
      base.maps.first.copyWith(generation: generation(['c1'])),
      MindMap(id: 'memory', title: '记忆与检索', generation: generation(['c2'])),
      MindMap(id: 'practice', title: '检索练习', generation: generation(['c2'])),
    ],
    documents: [
      ...base.documents,
      Document(id: 'new-doc', title: '第三份文档', fileName: 'new.pdf', pageCount: 3, importedAt: testNow),
    ],
    cards: [
      for (final card in base.cards)
        card.kind == CardKind.topic ? card.copyWith(source: CardSource(documentId: 'c2', page: 2)) : card,
    ],
  );
}

class RecordingGenerator extends FakeMapGenerator {
  RecordingGenerator()
    : super(
        chapters: {
          '*': ['{"k":"point","id":"p1","title":"Point","page":1,"marks":["A1"]}'],
        },
        generation: [
          '{"ref":"a","parent":"ROOT","title":"第一文档","doc":"D1","page":3}',
          '{"ref":"b","parent":"ROOT","title":"第二文档","doc":"D2","page":1}',
          '{"ref":"c","parent":"ROOT","title":"越界出处","doc":"D2","page":3}',
          '{"mark":"A1","parent":"a"}',
          '{"mark":"A2","parent":"b"}',
        ],
      );
  MapBuildInput? input;
  @override
  Stream<MapLine> generate(MapBuildInput input, CancellationToken cancel) {
    this.input = input;
    return super.generate(input, cancel);
  }
}

void main() {
  testWidgets('follows most recently used associated map and expires notice', (tester) async {
    final c = await harness.openWorkspace(
      tester,
      content: InMemoryStudySetContentRepository({'demo-1': multiDocumentContent()}),
    );
    final ws = c.read(workspaceProvider('demo-1').notifier);
    await ws.selectMap('practice');
    await ws.selectMap(MindMap.defaultId);
    ws.openDocument('c2');
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).activeMapId, 'practice');
    expect(find.byKey(const ValueKey('map-follow-notice')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('map-follow-notice')), findsNothing);
    ws.openDocument('c1');
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).activeMapId, MindMap.defaultId);
  });

  testWidgets('follow disabled persists; enabling follows again', (tester) async {
    final c = await harness.openWorkspace(
      tester,
      content: InMemoryStudySetContentRepository({'demo-1': multiDocumentContent()}),
    );
    await c.read(settingsProvider.notifier).setMapFollowDocument(false);
    final ws = c.read(workspaceProvider('demo-1').notifier);
    ws.openDocument('c2');
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).activeMapId, MindMap.defaultId);
    expect(find.byKey(const ValueKey('map-follow-notice')), findsNothing);
    expect(c.read(sharedPreferencesProvider).getBool('settings.mapFollowDocument'), false);
    await c.read(settingsProvider.notifier).setMapFollowDocument(true);
    ws.openDocument('c1');
    ws.openDocument('c2');
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).activeMapId, 'memory');
  });

  testWidgets('banner shown once when switching away and reopening', (tester) async {
    final c = await harness.openWorkspace(tester);
    final ws = c.read(workspaceProvider('demo-1').notifier);
    ws.openDocument('c2');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('document-map-banner')), findsOneWidget);
    ws.openDocument('c1');
    await tester.pumpAndSettle();
    ws.openDocument('c2');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('document-map-banner')), findsNothing);
    expect(c.read(sharedPreferencesProvider).getStringList('map_navigation.demo-1.seen'), contains('c2'));
    c.read(navigationProvider.notifier).showLibrary();
    await tester.pumpAndSettle();
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    c.read(workspaceProvider('demo-1').notifier).openDocument('c2');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('document-map-banner')), findsNothing);
  });

  testWidgets('dismissal and closing tabs do not repeat banner; empty maps hide merge', (tester) async {
    final c = await harness.openWorkspace(tester);
    final ws = c.read(workspaceProvider('demo-1').notifier);
    await ws.addMap('空图');
    ws.openDocument('c2');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('document-map-merge')), findsNothing);
    final banner = find.byKey(const ValueKey('document-map-banner'));
    await tester.tap(find.descendant(of: banner, matching: find.byIcon(MMIcons.close)));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
    ws.openDocument('c1');
    ws.closeDocument('c1');
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
    ws.openDocument('missing');
    expect(c.read(workspaceProvider('demo-1')).activeDocumentId, 'c2');
    await c.read(documentMapNavigationProvider('demo-1').notifier).documentChanged(null);
    await c.read(documentMapNavigationProvider('demo-1').notifier).documentChanged('missing');
  });

  testWidgets('merge selects current sources plus document, topic and reviews as a diff', (tester) async {
    final fake = FakeMapGenerator(
      chapters: {
        '*': ['{"k":"point","id":"p1","title":"Point","page":1}'],
      },
      diff: ['{"op":"add","ref":"a","parent":"ROOT","title":"合并主题","doc":"D1","page":1}'],
    );
    final c = await harness.openWorkspace(
      tester,
      content: InMemoryStudySetContentRepository({'demo-1': multiDocumentContent()}),
      overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
    );
    c.read(workspaceProvider('demo-1').notifier).openDocument('new-doc');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('document-map-merge')));
    await tester.pumpAndSettle();
    expect(find.byType(GenerateMapSheet), findsOneWidget);
    expect(find.text('按主题合并'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-generate-sheet-start-button')));
    await tester.pumpAndSettle();
    final r = c.read(mapGenerationControllerProvider('demo-1'))?.request;
    expect(r?.sources.map((s) => s.documentId).toSet(), {'c1', 'new-doc'});
    expect(r?.organization, MapOrganization.topic);
    expect(r?.destination, MapGenerationDestination.update);
    expect(r?.parentId, isNull);
    expect(find.byKey(const ValueKey('document-map-banner')), findsNothing);
    final preview = c.read(mapGenerationControllerProvider('demo-1'))!;
    expect(preview.phase, MapGenerationPhase.diff);
    expect(fake.calls, contains('update'));
    expect(preview.lines.single.title, '合并主题');
    c.read(mapGenerationControllerProvider('demo-1').notifier).discard();
  });

  testWidgets('source changes document then page and retains merged map', (tester) async {
    final base = multiDocumentContent();
    final merged = base.copyWith(
      maps: [
        base.maps.first.copyWith(generation: generation(['c1', 'c2'])),
        ...base.maps.skip(1),
      ],
    );
    final c = await harness.openWorkspace(tester, content: InMemoryStudySetContentRepository({'demo-1': merged}));
    final ws = c.read(workspaceProvider('demo-1').notifier);
    final chip = tester.widgetList<MapSourceChip>(find.byType(MapSourceChip)).firstWhere((c) => c.documentIndex == 1);
    expect(chip.documentTitle, '论文：检索练习效应');
    // Select to make the hover-only chip interactive.
    ws.selectCard(base.cards.firstWhere((c) => c.source != null).id);
    await tester.pumpAndSettle();
    tester.widgetList<MapSourceChip>(find.byType(MapSourceChip)).firstWhere((c) => c.onTap != null).onTap!();
    await tester.pumpAndSettle();
    final state = c.read(workspaceProvider('demo-1'));
    expect(referenceState(tester).activeDocumentId, 'c2');
    expect(state.activeMapId, MindMap.defaultId);
    expect(referenceState(tester).reveal?.page, 2);
    expect(find.byKey(const ValueKey('map-follow-notice')), findsNothing);
    ws.revealMapSource(CardSource(documentId: 'missing', page: 1));
    ws.revealMapSource(CardSource(documentId: 'c1', page: 9999));
    expect(c.read(workspaceProvider('demo-1')).tabs.current.reference?.id, 'c2');
    ws.revealMapSource(CardSource(documentId: 'c1', page: 3));
    await tester.pumpAndSettle();
    expect(referenceState(tester).reveal?.page, 3);
  });

  testWidgets('maps settings changes follow switch', (tester) async {
    final c = await harness.openWorkspace(tester);
    showSettings(tester.element(find.byType(WorkspaceScreen).first), tab: SettingsTab.maps);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).mapFollowDocument, true);
    await tester.tap(find.byKey(const ValueKey('settings-map-follow-document')));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).mapFollowDocument, false);
  });

  testWidgets('legend limits names to three and shows remaining count', (tester) async {
    await harness.openWorkspace(tester);
    showDialog<void>(
      context: tester.element(find.byType(WorkspaceScreen).first),
      builder: (_) => const Dialog(
        child: MapDocumentLegend(studySetId: 'demo-1', documentIds: ['c2', 'c1', 'missing', 'fourth']),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('+1'), findsOneWidget);
  });
  testWidgets('banner starts new map using remembered settings and only one prompt', (tester) async {
    final fake = FakeMapGenerator(
      chapters: {
        '*': ['{"k":"point","id":"p1","title":"Point","page":1}'],
      },
      generation: ['{"ref":"a","title":"New","page":1}'],
    );
    final c = await harness.openWorkspace(
      tester,
      prefs: {
        'map_gen.demo-1.organization': 'question',
        'map_gen.demo-1.depth': 4,
        'map_gen.demo-1.includeAnnotations': false,
      },
      overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
    );
    c.read(workspaceProvider('demo-1').notifier).openDocument('c2');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('document-map-generate')));
    await tester.pumpAndSettle();
    final preview = c.read(mapGenerationControllerProvider('demo-1'))!;
    expect(preview.request.organization, MapOrganization.question);
    expect(preview.request.depth, 4);
    expect(preview.request.includeAnnotations, false);
    expect(preview.request.destination, MapGenerationDestination.newMap);
    expect(find.byKey(const ValueKey('document-map-banner')), findsNothing);
    c.read(mapGenerationControllerProvider('demo-1').notifier).discard();
  });

  testWidgets('opening generation settings does not read credentials; starting displays setup', (tester) async {
    var reads = 0;
    final c = await pumpApp(
      tester,
      prefs: {'settings.language': 'zh'},
      overrides: [
        assistantCredentialStateProvider.overrideWith((ref) async {
          reads++;
          return AssistantCredentialState.missingKey;
        }),
      ],
    );
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    c.read(workspaceProvider('demo-1').notifier).openDocument('c2');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('document-map-merge')));
    await tester.pumpAndSettle();
    expect(reads, 0);
    await tester.tap(find.byKey(const ValueKey('map-generate-sheet-start-button')));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.byType(ModelSetupCard), findsOneWidget);
  });

  testWidgets('unconfigured banner new map opens settings instead of generating', (tester) async {
    await harness.openWorkspace(tester, credentialState: AssistantCredentialState.unconfigured);
    final c = tester.element(find.byType(WorkspaceScreen));
    // Resolve the container through the existing workspace harness.
    final container = ProviderScope.containerOf(c);
    container.read(workspaceProvider('demo-1').notifier).openDocument('c2');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('document-map-generate')));
    await tester.pumpAndSettle();
    expect(find.byType(GenerateMapSheet), findsOneWidget);
    expect(container.read(mapGenerationControllerProvider('demo-1')), isNull);
    expect(find.byType(ModelSetupCard), findsOneWidget);
  });

  testWidgets('rapid document changes never commit a stale map switch', (tester) async {
    final c = await harness.openWorkspace(
      tester,
      content: InMemoryStudySetContentRepository({'demo-1': multiDocumentContent()}),
    );
    final ws = c.read(workspaceProvider('demo-1').notifier);
    ws.openDocument('c2');
    ws.openDocument('c1');
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).activeMapId, MindMap.defaultId);
    ws.openDocument('c2');
    await tester.pumpAndSettle();
    ws.openDocument('c2');
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).activeMapId, 'memory');
  });

  testWidgets('multi-document generation separates page ranges, annotation aliases and navigable draft sources', (
    tester,
  ) async {
    final base = demoContent();
    final data = base.copyWith(
      documents: [
        for (final (i, doc) in base.documents.indexed)
          Document(
            id: doc.id,
            title: doc.title,
            fileName: doc.fileName,
            pageCount: i == 0 ? 3 : 1,
            importedAt: testNow,
          ),
      ],
      annotations: [
        for (final doc in base.documents)
          Annotation(
            id: 'mark-${doc.id}',
            documentId: doc.id,
            page: 1,
            rects: const [PageRect(1, 1, 10, 10)],
            quote: '测试正文',
            colorIndex: 0,
            createdAt: testNow,
          ),
      ],
    );
    final fake = RecordingGenerator();
    final c = await harness.openWorkspace(
      tester,
      content: InMemoryStudySetContentRepository({'demo-1': data}),
      overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
    );
    final gen = c.read(mapGenerationControllerProvider('demo-1').notifier);
    await harness.runGeneration(
      tester,
      () => gen.start(
        const MapGenerationRequest(
          studySetId: 'demo-1',
          mapId: 'combined',
          title: '多文档合成',
          sources: [
            MapDocumentSelection(documentId: 'c1'),
            MapDocumentSelection(documentId: 'c2'),
          ],
          organization: MapOrganization.topic,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fake.input!.context.pages, {
      'D1': {1, 2, 3},
      'D2': {1},
    });
    expect(fake.input!.context.annotations.values.toSet(), {'mark-c1', 'mark-c2'});
    final preview = c.read(mapGenerationControllerProvider('demo-1'))!;
    expect(preview.lines.firstWhere((l) => l.title == '越界出处').source, isNull);
    expect(preview.lines.where((l) => l.kind == MapLineKind.excerpt).length, 2);
    expect(find.byType(MapDocumentLegend), findsOneWidget);
    final chip = tester
        .widgetList<MapSourceChip>(find.byType(MapSourceChip))
        .firstWhere((c) => c.documentIndex == 1 && c.onTap != null);
    await tester.tap(find.byWidget(chip));
    await tester.pumpAndSettle();
    expect(referenceState(tester).activeDocumentId, 'c2');
    expect(referenceState(tester).reveal?.page, 1);
    expect(await gen.keep(), greaterThan(0));
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).activeMapId, 'combined');
    expect(c.read(workspaceProvider('demo-1').notifier).content.map('combined')!.generation!.sources.length, 2);
    await c.read(workspaceProvider('demo-1').notifier).undo();
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1').notifier).content.map('combined'), isNull);
  });
  testWidgets('banner actions fit a narrow map pane', (tester) async {
    final c = await harness.openWorkspace(tester);
    c.read(workspaceProvider('demo-1').notifier).openDocument('c2');
    await tester.pumpAndSettle();
    final scope = ProviderScope.containerOf(tester.element(find.byType(DocumentMapBanner)));
    showDialog<void>(
      context: tester.element(find.byType(WorkspaceScreen)),
      builder: (_) => UncontrolledProviderScope(
        container: scope,
        child: const Dialog(
          child: SizedBox(width: 320, child: DocumentMapBanner(studySetId: 'demo-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final banner = find.descendant(
      of: find.byType(Dialog),
      matching: find.byKey(const ValueKey('document-map-banner')),
    );
    expect(banner, findsOneWidget);
    expect(tester.getSize(banner).height, MMSizes.mapDocumentBanner * 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('banner disables AI actions while another operation owns the model', (tester) async {
    final c = await harness.openWorkspace(tester);
    c.read(workspaceProvider('demo-1').notifier).openDocument('c2');
    c.read(expansionBusyProvider.notifier).set(true);
    await tester.pumpAndSettle();
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('document-map-generate'))).onPressed, isNull);
    expect(
      tester.widget<MMButton>(find.byKey(const ValueKey('document-map-generate'))).variant,
      MMButtonVariant.primary,
    );
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('document-map-merge'))).onPressed, isNull);
    c.read(expansionBusyProvider.notifier).set(false);
    await tester.pumpAndSettle();
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('document-map-generate'))).onPressed, isNotNull);
  });
}
