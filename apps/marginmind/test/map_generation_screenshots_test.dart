import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/assistant/assistant_scope.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart' hide Card;
import 'package:mm_core/testing.dart';

import 'helpers.dart';
import 'document_map_navigation_test.dart' show multiDocumentContent;
import 'map_generation_ui_test.dart' as harness;

// Opt-in like map_style_screenshots_test: MM_SCREENSHOTS=docs/evidence/gul-625
// MM_FONT=/Library/Fonts/Arial\ Unicode.ttf flutter test test/map_generation_screenshots_test.dart
final _out = Platform.environment['MM_SCREENSHOTS'];
final _font = Platform.environment['MM_FONT'];
final _skip = _out == null || _font == null;

Future<void> _loadFonts() async {
  final fontFile = File(_font!);
  if (fontFile.existsSync()) {
    final bytes = ByteData.sublistView(await fontFile.readAsBytes());
    for (final family in [
      '.AppleSystemUIFont',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'PingFang SC',
      'Songti SC',
      'SF Mono',
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  }
  final pub = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
  final iconsDir = Directory('$pub/hosted/pub.dev')
      .listSync()
      .whereType<Directory>()
      .lastWhere((d) => d.path.contains('cupertino_icons-'), orElse: () => Directory(''));
  if (iconsDir.path.isNotEmpty) {
    final iconFile = File('${iconsDir.path}/assets/CupertinoIcons.ttf');
    if (iconFile.existsSync()) {
      await (FontLoader(
        'packages/cupertino_icons/CupertinoIcons',
      )..addFont(Future.value(ByteData.sublistView(iconFile.readAsBytesSync())))).load();
    }
  }
  final lucideDir = Directory('$pub/hosted/pub.dev')
      .listSync()
      .whereType<Directory>()
      .lastWhere((d) => d.path.contains('lucide_icons_flutter-'), orElse: () => Directory(''));
  if (lucideDir.path.isNotEmpty) {
    final lucideFile = File('${lucideDir.path}/assets/lucide.ttf');
    if (lucideFile.existsSync()) {
      final lucideBytes = ByteData.sublistView(lucideFile.readAsBytesSync());
      await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(Future.value(lucideBytes))).load();
      await (FontLoader('Lucide')..addFont(Future.value(lucideBytes))).load();
    }
  }
}

Future<ProviderContainer> openWorkspace(
  WidgetTester tester, {
  InMemoryStudySetContentRepository? content,
  Map<String, Object> prefs = const {},
  List<Override> overrides = const [],
  AssistantCredentialState credentialState = AssistantCredentialState.ready,
}) async {
  final defaultContent = () {
    final base = demoContent();
    final d1 = base.documents.first;
    final newD1 = Document(id: d1.id, title: d1.title, fileName: d1.fileName, pageCount: 40, importedAt: d1.importedAt);
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
      assistantPageTextProvider.overrideWithValue((path, page) async => '第 $page 页测试正文：关于记忆机制与认知负荷的内容。'),
      assistantCredentialStateProvider.overrideWith((ref) async => credentialState),
      ...overrides,
    ],
  );
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  return container;
}

Future<void> _save(WidgetTester tester, String name) async {
  Directory(_out!).createSync(recursive: true);
  final image = (await tester.runAsync(() {
    final view = tester.binding.renderViews.first;
    return (view.debugLayer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1);
  }))!;
  final png = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  await tester.runAsync(() => File('$_out/$name.png').writeAsBytes(png.buffer.asUint8List()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_skip) await _loadFonts();
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('Capture Scenes 1, 2, 3, 5, 7 ($mode mode)', skip: _skip, (tester) async {
      tester.view.physicalSize = const Size(1280, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final fake = FakeMapGenerator(
        chapters: {
          'c1-all': ['{"k":"point","id":"p1","title":"记忆的本质与遗忘机制"}', '{"k":"point","id":"p2","title":"间隔重复与提取效应"}'],
        },
        generation: [
          '{"ref":"t1","parent":"ROOT","title":"核心规律：间隔重复","page":24}',
          '{"ref":"t2","parent":"t1","title":"遗忘曲线的变化趋势","page":25}',
          '{"ref":"t3","parent":"ROOT","title":"主动提取策略","page":32}',
          '{"ref":"t4","parent":"t3","title":"自测与小测验应用","page":35}',
        ],
        delay: const Duration(milliseconds: 200),
      );

      final container = await openWorkspace(
        tester,
        prefs: {if (dark) 'settings.appearance': 'dark'},
        overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
      );

      final wsController = container.read(workspaceProvider('demo-1').notifier);
      final genController = container.read(mapGenerationControllerProvider('demo-1').notifier);

      // --- Scene 1: Empty state on mind map ---
      await wsController.addMap('学习的底层逻辑');
      await tester.pumpAndSettle();

      expect(find.text('从「学习的底层逻辑」生成脑图'), findsOneWidget);
      await _save(tester, 'scene_1_empty_$mode');

      // --- Scene 2: Settings sheet ---
      final headerButton = find.byKey(const ValueKey('map-generate-header-button'));
      expect(headerButton, findsOneWidget);
      await tester.tap(headerButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map-generate-sheet-start-button')), findsOneWidget);
      await _save(tester, 'scene_2_sheet_$mode');

      // Close the sheet
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // --- Scene 3: Reading phase with skeletons & bar ---
      final activeMapId = container.read(workspaceProvider('demo-1')).activeMapId;
      genController.start(
        MapGenerationRequest(
          studySetId: 'demo-1',
          mapId: activeMapId,
          title: '学习的底层逻辑',
          sources: const [MapDocumentSelection(documentId: 'c1')],
          destination: MapGenerationDestination.branch,
        ),
      );

      // Pump 50ms into reading phase
      await tester.pump(const Duration(milliseconds: 50));
      expect(genController.state?.phase, MapGenerationPhase.reading);
      await _save(tester, 'scene_3_reading_$mode');

      // --- Scene 5: Reviewing new map with ghost nodes & source chips ---
      // Pump until reading and streaming finish and review phase is reached
      var iterations = 0;
      while (genController.state?.phase != MapGenerationPhase.review && iterations < 50) {
        iterations++;
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      expect(genController.state?.phase, MapGenerationPhase.review);
      expect(find.byKey(const ValueKey('map-generation-keep-button')), findsOneWidget);
      await _save(tester, 'scene_5_review_$mode');

      // --- Scene 7: Keep completed with committed nodes & source chip on hover/selection ---
      final keepButton = find.byKey(const ValueKey('map-generation-keep-button'));
      await tester.tap(keepButton);
      await tester.pumpAndSettle();

      // Find the committed card and select it so MapSourceChip is shown
      final committedCard = container
          .read(workspaceProvider('demo-1').notifier)
          .content
          .cards
          .firstWhere((c) => c.title == '核心规律：间隔重复');
      wsController.selectCard(committedCard.id);
      await tester.pumpAndSettle();

      await _save(tester, 'scene_7_keep_$mode');
    });
  }
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('Capture Scenes 8, 9, 10 ($mode)', skip: _skip, (tester) async {
      final fake = FakeMapGenerator(
        chapters: {
          '*': ['{"k":"point","id":"p1","title":"检索与记忆","page":1}'],
        },
        generation: [
          '{"ref":"a","parent":"ROOT","title":"主动提取","doc":"D1","page":1}',
          '{"ref":"b","parent":"a","title":"间隔重复","doc":"D2","page":2}',
          '{"ref":"c","parent":"ROOT","title":"检索练习","doc":"D2","page":3}',
        ],
      );
      final sourceContent = multiDocumentContent();
      final content = sourceContent.copyWith(nodes: [
        ...sourceContent.nodes,
        for (final node in sourceContent.nodes)
          if (sourceContent.card(node.cardId)?.kind == CardKind.topic)
            MapNode(cardId: node.cardId, mapId: 'memory', parentId: node.parentId, order: node.order),
      ]);
      final c = await openWorkspace(
        tester,
        content: InMemoryStudySetContentRepository({'demo-1': content}),
        prefs: {if (dark) 'settings.appearance': 'dark'},
        overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
      );
      tester.view.physicalSize = const Size(1920, 1000);
      await tester.pumpAndSettle();
      final ws = c.read(workspaceProvider('demo-1').notifier);
      ws.openDocument('new-doc');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('document-map-banner')), findsOneWidget);
      await _save(tester, 'scene_8_banner_$mode');
      ws.openDocument('c2');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('map-follow-notice')), findsOneWidget);
      await _save(tester, 'scene_9_follow_$mode');
      await tester.pump(const Duration(seconds: 3));
      await ws.selectMap(MindMap.defaultId);
      final gen = c.read(mapGenerationControllerProvider('demo-1').notifier);
      await harness.runGeneration(
        tester,
        () => gen.start(
          const MapGenerationRequest(
            studySetId: 'demo-1',
            mapId: 'combined',
            title: '记忆与学习方法',
            sources: [
              MapDocumentSelection(documentId: 'c1'),
              MapDocumentSelection(documentId: 'c2'),
            ],
            organization: MapOrganization.topic,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _save(tester, 'scene_10_multi_$mode');
      gen.discard();
    });
  }
}
