import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';

final _out = Platform.environment['MM_SCREENSHOTS'] ?? 'docs/evidence/gul-625';
final _font = Platform.environment['MM_FONT'] ?? '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';

Future<void> _loadFonts() async {
  final fontFile = File(_font);
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
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')
            ..addFont(Future.value(ByteData.sublistView(iconFile.readAsBytesSync()))))
          .load();
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
  final container = await pumpApp(
    tester,
    size: const Size(1280, 820),
    content: content,
    prefs: {
      'settings.language': 'zh',
      ...prefs,
    },
    overrides: [
      assistantCredentialStateProvider.overrideWith((ref) async => credentialState),
      ...overrides,
    ],
  );
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  return container;
}

Future<void> _save(WidgetTester tester, String name) async {
  Directory(_out).createSync(recursive: true);
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
    await _loadFonts();
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('Capture Scenes 1, 2, 3, 5, 7 ($mode mode)', (tester) async {
      tester.view.physicalSize = const Size(1280, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final fake = FakeMapGenerator(
        chapters: {
          'c1-all': [
            '{"k":"point","id":"p1","title":"记忆的本质与遗忘机制"}',
            '{"k":"point","id":"p2","title":"间隔重复与提取效应"}',
          ],
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
        prefs: {
          if (dark) 'settings.appearance': 'dark',
        },
        overrides: [
          mapGeneratorProvider.overrideWithValue(() async => fake),
        ],
      );

      final wsController = container.read(workspaceProvider('demo-1').notifier);
      final genController = container.read(mapGenerationControllerProvider('demo-1').notifier);

      // --- Scene 1: Empty state on mind map ---
      await wsController.addMap('从文档生成脑图');
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
          title: '从文档生成脑图',
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
      final committedCard = container.read(workspaceProvider('demo-1').notifier).content.cards.firstWhere(
        (c) => c.title == '核心规律：间隔重复',
      );
      wsController.selectCard(committedCard.id);
      await tester.pumpAndSettle();

      await _save(tester, 'scene_7_keep_$mode');
    });
  }
}
