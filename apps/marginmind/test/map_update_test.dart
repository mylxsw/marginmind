import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/map_generation/map_updates.dart';
import 'package:marginmind/features/map_generation/widgets/map_diff_panel.dart';
import 'package:marginmind/features/map_generation/widgets/update_map_sheet.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/assistant/assistant_scope.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/widgets/assistant_panel.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';
import 'map_generation_ui_test.dart' show openWorkspace, runGeneration, key;

StudySetContent updateFixture() {
  final base = demoContent();
  final c = base.copyWith(
    documents: [
      for (final d in base.documents)
        Document(id: d.id, title: d.title, fileName: d.fileName, pageCount: 30, importedAt: d.importedAt),
    ],
  );
  final g = MapGeneration(
    sources: [MapSource(documentId: 'c1', fingerprint: 'old', readThrough: 1)],
    organization: MapOrganization.chapter,
    depth: 3,
    generatedAt: DateTime.utc(2026, 1),
    generated: {
      for (final n in c.nodes)
        if (c.card(n.cardId)!.kind == CardKind.topic) n.cardId: generatedNodeHash(c.card(n.cardId)!, n),
    },
  );
  return c.copyWith(maps: [for (final m in c.maps) m.copyWith(generation: g)]);
}

FakeMapGenerator updateEngine() => FakeMapGenerator(
  chapters: {
    '*': ['{"k":"point","id":"p","title":"材料","page":1}'],
  },
  diff: [
    '{"op":"add","ref":"a","parent":"ROOT","title":"新概念","page":1}',
    '{"op":"add","ref":"b","parent":"a","title":"子概念","page":1}',
    '{"op":"rename","node":"N1","title":"新名称"}',
    '{"op":"move","node":"N2","parent":"a"}',
    '{"op":"remove","node":"N2","why":"重复"}',
    '{"op":"rename","node":"N3","title":"禁止改写摘录"}',
  ],
);

void main() {
  testWidgets('update uses diff, protects excerpt, cascades selection, applies and undoes generation atomically', (
    tester,
  ) async {
    final before = updateFixture();
    final fake = updateEngine();
    final container = await openWorkspace(
      tester,
      content: InMemoryStudySetContentRepository({'demo-1': before}),
      overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
    );
    final ctl = container.read(mapGenerationControllerProvider('demo-1').notifier);
    final ws = container.read(workspaceProvider('demo-1').notifier);
    await runGeneration(
      tester,
      () => ctl.start(
        MapGenerationRequest(
          studySetId: 'demo-1',
          mapId: before.maps.first.id,
          title: '更新测试',
          sources: const [MapDocumentSelection(documentId: 'c1')],
          destination: MapGenerationDestination.update,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final p = container.read(mapGenerationControllerProvider('demo-1'))!;
    expect(p.phase, MapGenerationPhase.diff);
    expect(fake.calls, contains('update'));
    expect(p.lines, hasLength(5));
    expect(p.lines.last.kept, isFalse);
    expect(find.byType(MapDiffPanel), findsOneWidget);
    expect(ws.expansionPreviewActive, isTrue);
    expect(ws.content.map(before.maps.first.id)!.generation!.sources.first.fingerprint, 'old');
    ctl.toggle(p.lines.first.id, false);
    expect(container.read(mapGenerationControllerProvider('demo-1'))!.lines[1].kept, isFalse);
    ctl.toggle(p.lines[1].id, true);
    expect(container.read(mapGenerationControllerProvider('demo-1'))!.lines.first.kept, isTrue);
    ctl.edit(p.lines[3].id, 'cannot edit a move');
    expect(container.read(mapGenerationControllerProvider('demo-1'))!.lines[3].title, isNull);
    final canvas = find.byType(MindMapCanvas);
    final zoom = mapScale(tester.widget<MindMapCanvas>(canvas).transformation.value);
    await tester.tapAt(tester.getCenter(find.descendant(of: canvas, matching: find.text('遗忘的规律'))));
    await tester.pumpAndSettle();
    expect(container.read(mapDiffFocusProvider('demo-1')), p.lines[2].id);
    expect(mapScale(tester.widget<MindMapCanvas>(canvas).transformation.value), zoom);
    await ws.rename(before.nodes.first.cardId, 'blocked edit');
    expect(ws.content.card(before.nodes.first.cardId)!.title, before.card(before.nodes.first.cardId)!.title);
    await tester.tap(find.byKey(const ValueKey('map-update-apply')));
    await tester.pumpAndSettle();
    expect(container.read(mapGenerationControllerProvider('demo-1')), isNull);
    expect(ws.content.cards.any((c) => c.title == '新名称'), isTrue);
    expect(ws.content.cards.any((c) => c.title == '禁止改写摘录'), isFalse);
    expect(ws.content.map(before.maps.first.id)!.generation!.sources.first.fingerprint, isNot('old'));
    await key(tester, LogicalKeyboardKey.keyZ, primary: true);
    await tester.pumpAndSettle();
    expect(ws.content.map(before.maps.first.id)!.generation!.toJson(), before.maps.first.generation!.toJson());
    expect(ws.content.nodes.map((n) => n.toJson()).toList(), before.nodes.map((n) => n.toJson()).toList());
    await settleHud(tester);
  });

  testWidgets('discard leaves map unchanged and update form has sources, scope and protection count', (tester) async {
    final before = updateFixture();
    final container = await openWorkspace(
      tester,
      content: InMemoryStudySetContentRepository({'demo-1': before}),
      overrides: [mapGeneratorProvider.overrideWithValue(() async => updateEngine())],
    );
    await tester.tap(find.byKey(const ValueKey('map-generate-header-button')));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateMapSheet), findsOneWidget);
    expect(find.text('只处理新内容'), findsOneWidget);
    expect(find.text('你改过、添加的 1 个节点保持不变'), findsOneWidget);
    Navigator.of(tester.element(find.byType(UpdateMapSheet))).pop();
    await tester.pumpAndSettle();
    final ctl = container.read(mapGenerationControllerProvider('demo-1').notifier);
    await runGeneration(
      tester,
      () => ctl.start(
        MapGenerationRequest(
          studySetId: 'demo-1',
          mapId: before.maps.first.id,
          title: '更新测试',
          sources: const [MapDocumentSelection(documentId: 'c1')],
          destination: MapGenerationDestination.update,
        ),
      ),
    );
    ctl.discard();
    await tester.pumpAndSettle();
    expect(
      container.read(workspaceProvider('demo-1').notifier).content.map(before.maps.first.id)!.generation!.toJson(),
      before.maps.first.generation!.toJson(),
    );
  });

  testWidgets('current source fingerprint is shared and detects text and reading changes', (tester) async {
    final before = updateFixture();
    final repo = InMemoryStudySetContentRepository({'demo-1': before});
    var body = 'original';
    var reads = 0;
    final container = await pumpApp(
      tester,
      content: repo,
      prefs: {'settings.language': 'zh'},
      overrides: [
        assistantPageTextProvider.overrideWithValue((path, page) async {
          reads++;
          return body;
        }),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final source = container.read(currentMapSourceProvider(('demo-1', 'c1'))).value!;
    expect(container.read(mapHasUpdatesProvider(('demo-1', before.maps.first.id))), isTrue);
    await repo.update(
      'demo-1',
      (c) => c.copyWith(
        maps: [
          for (final m in c.maps)
            m.copyWith(
              generation: MapGeneration(
                sources: [source],
                organization: MapOrganization.chapter,
                depth: 3,
                generatedAt: DateTime.utc(2026),
              ),
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(mapHasUpdatesProvider(('demo-1', before.maps.first.id))), isFalse);
    final cachedReads = reads;
    await repo.update('demo-1', (c) => c.copyWith(maps: [for (final m in c.maps) m.copyWith(title: 'Another title')]));
    await tester.pumpAndSettle();
    expect(reads, cachedReads);
    body = 'changed text layer';
    await repo.update(
      'demo-1',
      (c) => c.copyWith(documents: [for (final d in c.documents) d.id == 'c1' ? d.copyWith(revision: 'text-v2') : d]),
    );
    await tester.pumpAndSettle();
    final changedText = container.read(currentMapSourceProvider(('demo-1', 'c1'))).value!;
    expect(changedText.fingerprint, isNot(source.fingerprint));
    await repo.update('demo-1', (c) => c.copyWith(annotations: const []));
    await tester.pumpAndSettle();
    expect(
      container.read(currentMapSourceProvider(('demo-1', 'c1'))).value!.fingerprint,
      isNot(changedText.fingerprint),
    );

    await repo.update(
      'demo-1',
      (c) => c.copyWith(documents: [for (final d in c.documents) d.id == 'c1' ? d.copyWith(lastPage: 2) : d]),
    );
    await tester.pumpAndSettle();
    expect(container.read(mapHasUpdatesProvider(('demo-1', before.maps.first.id))), isTrue);
  });
  testWidgets('form adds a document, switches scope and starts a preview with instructions', (tester) async {
    final before = updateFixture();
    final container = await openWorkspace(
      tester,
      content: InMemoryStudySetContentRepository({'demo-1': before}),
      overrides: [mapGeneratorProvider.overrideWithValue(() async => updateEngine())],
    );
    await tester.tap(find.byKey(const ValueKey('map-generate-header-button')));
    await tester.pumpAndSettle();
    final sheet = find.byType(UpdateMapSheet);
    await tester.tap(find.descendant(of: sheet, matching: find.byType(MMCheckbox)).last);
    await tester.tap(find.text('只处理新内容'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全文重新梳理').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: sheet, matching: find.byType(TextField)), '按概念合并');
    await tester.tap(find.text('预览更改'));
    await tester.pumpAndSettle();
    final preview = container.read(mapGenerationControllerProvider('demo-1'))!;
    expect(preview.request.sources, hasLength(2));
    expect(preview.request.onlyNewContent, isFalse);
    expect(preview.request.instructions, '按概念合并');
    expect(preview.phase, MapGenerationPhase.diff);
    final panel = find.byType(MapDiffPanel);
    await tester.tap(find.descendant(of: panel, matching: find.text('新名称')));
    await tester.pumpAndSettle();
    expect(container.read(mapDiffFocusProvider('demo-1')), preview.lines[2].id);
    await key(tester, LogicalKeyboardKey.f2);
    await tester.enterText(find.byType(TextField).last, '自定义名称');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(container.read(mapGenerationControllerProvider('demo-1'))!.lines[2].title, '自定义名称');
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.space);
    await key(tester, LogicalKeyboardKey.arrowUp);

    await tester.ensureVisible(find.descendant(of: panel, matching: find.byType(MMCheckbox)).last);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: panel, matching: find.byType(MMCheckbox)).last);
    await tester.pumpAndSettle();
    expect(container.read(mapGenerationControllerProvider('demo-1'))!.lines.last.kept, isTrue);
    await tester.tap(find.text('放弃').last);
    await tester.pumpAndSettle();
    expect(container.read(mapGenerationControllerProvider('demo-1')), isNull);
  });

  testWidgets('credentials are requested only on preview, missing model stays in form', (tester) async {
    await openWorkspace(
      tester,
      content: InMemoryStudySetContentRepository({'demo-1': updateFixture()}),
      credentialState: AssistantCredentialState.missingKey,
    );
    await tester.tap(find.byKey(const ValueKey('map-generate-header-button')));
    await tester.pumpAndSettle();
    expect(find.byType(ModelSetupCard), findsNothing);
    await tester.tap(find.text('预览更改'));
    await tester.pumpAndSettle();
    expect(find.byType(ModelSetupCard), findsOneWidget);
  });
  testWidgets('phone review leaves canvas visible above a bottom panel', (tester) async {
    final before = updateFixture();
    final container = await openWorkspace(
      tester,
      content: InMemoryStudySetContentRepository({'demo-1': before}),
      overrides: [mapGeneratorProvider.overrideWithValue(() async => updateEngine())],
    );
    tester.view.physicalSize = const Size(402, 874);
    await tester.pumpAndSettle();
    final ctl = container.read(mapGenerationControllerProvider('demo-1').notifier);
    await runGeneration(
      tester,
      () => ctl.start(
        MapGenerationRequest(
          studySetId: 'demo-1',
          mapId: before.maps.first.id,
          title: '更新',
          sources: const [MapDocumentSelection(documentId: 'c1')],
          destination: MapGenerationDestination.update,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(MapDiffPanel));
    expect(rect.top, greaterThan(300));
    expect(rect.width, lessThanOrEqualTo(402));
    expect(tester.takeException(), isNull);
    ctl.discard();
    await tester.pumpAndSettle();
  });
}
