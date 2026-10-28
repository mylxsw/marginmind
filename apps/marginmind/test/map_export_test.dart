import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/map_export_scene.dart';
import 'package:marginmind/features/workspace/widgets/map_export_sheet.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:marginmind/l10n/generated/app_localizations_zh.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'workspace_test.dart' show openFirstSet;
import 'helpers.dart' show settleHud;

StudySetContent exportFixture([int count = 5]) => StudySetContent(
  cards: [
    for (var i = 0; i < count; i++)
      Card(
        id: 'c$i',
        kind: i == 1 ? CardKind.note : CardKind.topic,
        title: '节点 $i · Readable text',
        createdAt: DateTime.utc(2026),
      ),
  ],
  nodes: [
    for (var i = 0; i < count; i++)
      MapNode(cardId: 'c$i', order: i.toDouble(), parentId: i > 1 ? 'c0' : null, collapsed: i == 0),
  ],
  relations: const [MapRelation(id: 'r', fromId: 'c1', toId: 'c2', label: 'Related')],
  summaries: const [MapSummary(id: 's', parentId: 'c0', fromId: 'c2', toId: 'c3', label: 'Summary')],
);
MapExportScene scene(StudySetContent c, {bool transparent = false}) => MapExportScene.build(
  content: c,
  mapId: MindMap.defaultId,
  title: 'Root',
  colors: MMColors.light,
  researchLabel: '研究笔记',
  source: (d, p) => '${d.title} $p',
  transparent: transparent,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Chinese sheet title omits ellipsis while menu and save action retain it', () {
    final l = AppLocalizationsZh();
    expect(l.exportTitle, '导出脑图');
    expect(l.exportMap, '导出脑图…');
    expect(l.exportAction, '导出…');
  });
  testWidgets('File menu opens unified export; node menu preselects its branch', (tester) async {
    await openFirstSet(tester);
    Iterable<PlatformMenuItem> flatten(Iterable<PlatformMenuItem> items) sync* {
      for (final item in items) {
        yield item;
        if (item is PlatformMenu) yield* flatten(item.menus);
        if (item is PlatformMenuItemGroup) yield* flatten(item.members);
      }
    }

    final menus = flatten(tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus);
    expect(menus.where((i) => i.label == 'Export Map as Markdown…'), isEmpty);
    menus.singleWhere((i) => i.label == 'Export Map…').onSelected!();
    await tester.pumpAndSettle();
    expect(tester.widget<MapExportSheet>(find.byType(MapExportSheet)).initialBranch, isFalse);
    expect(tester.widget<MMSheet>(find.byType(MMSheet)).title, 'Export Map');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('遗忘的规律'), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export This Branch…'));
    await tester.pumpAndSettle();
    final sheet = tester.widget<MapExportSheet>(find.byType(MapExportSheet));
    expect(sheet.initialBranch, isTrue);
    expect(sheet.branchId, 'c3');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  test('500 nodes are present, text readable, bounds contain every drawing', () {
    final s = scene(exportFixture(500));
    expect(s.layout.rects, hasLength(501));
    expect(s.layout.summaries, hasLength(1));
    final texts = s.commands.where((c) => c['type'] == 'text').map((c) => c['text']).join('\n');
    expect(texts, contains('节点 499'));
    expect(texts, contains('Summary'));
    expect(texts, contains('Related'));
    for (final r in s.layout.rects.values) {
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(s.size.width));
      expect(r.bottom, lessThanOrEqualTo(s.size.height));
    }
    final plan = MapRasterPlan(s.size, 3);
    expect(plan.reduced, isTrue);
    expect(plan.width * plan.height, lessThanOrEqualTo(32000000));
    expect(plan.height, lessThanOrEqualTo(16384));
    expect(s.commands.where((c) => c['type'] == 'text').every((c) => (c['fontSize'] as double) >= 11), isTrue);
    expect(() => MapRasterPlan(Size.zero, 1), throwsArgumentError);
    expect(() => MapRasterPlan(const Size(1, 1), double.nan), throwsArgumentError);
    expect(MapRasterPlan(const Size(100, 100), 2).reduced, isFalse);
    expect(MapRasterPlan(const Size(9000, 100), 1).large, isTrue);
  });
  test('a formatted note is drawn without its markup; a plain one keeps its stars', () {
    final now = DateTime.utc(2026);
    final c = StudySetContent(
      cards: [
        Card(
          id: 'm',
          kind: CardKind.note,
          title: '**Key** idea\n- one',
          textFormat: TextFormat.markdown,
          createdAt: now,
        ),
        Card(id: 'p', kind: CardKind.note, title: '2 * 3 * 4', createdAt: now),
      ],
      nodes: const [
        MapNode(cardId: 'm', order: 0),
        MapNode(cardId: 'p', order: 1),
      ],
    );
    final texts = scene(c).commands.where((c) => c['type'] == 'text').map((c) => c['text']).toList();
    expect(texts, containsAll(['Key idea', '• one', '2 * 3 * 4']));
    expect(texts.any((t) => (t as String).contains('**')), isFalse);
  });

  test('full text and research bodies do not use ellipses', () {
    final now = DateTime.utc(2026);
    final note = ResearchNote(
      id: 'n',
      sessionId: 'session',
      title: 'Research',
      body: List.filled(30, '全文 full body').join('\n'),
      createdAt: now,
      updatedAt: now,
    );
    final c = StudySetContent(
      cards: [Card(id: 'a', kind: CardKind.research, title: 'Research', researchNoteId: 'n', createdAt: now)],
      nodes: const [MapNode(cardId: 'a', order: 0)],
      researchNotes: [note],
    );
    final s = scene(c);
    expect(s.commands.where((c) => c['type'] == 'text' && (c['text'] as String).contains('全文')), hasLength(30));
    expect(s.layout.rects['a']!.height, greaterThan(400));
  });
  test('offscreen tiles cover final image and preserve transparency', () async {
    const channel = MethodChannel('marginmind/map_export');
    Map<Object?, Object?>? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      arguments = call.arguments as Map<Object?, Object?>;
      return Uint8List.fromList([1]);
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );
    final s = scene(exportFixture(60), transparent: true);
    final plan = MapRasterPlan(s.size, 1);
    await s.png(plan);
    final tiles = arguments!['tiles'] as List;
    expect(tiles.length, greaterThan(1));
    var area = 0;
    for (final tile in tiles) {
      final codec = await ui.instantiateImageCodec(tile['bytes'] as Uint8List);
      final frame = await codec.getNextFrame();
      area += frame.image.width * frame.image.height;
      expect((tile['x'] as int) + frame.image.width, lessThanOrEqualTo(plan.width));
      expect((tile['y'] as int) + frame.image.height, lessThanOrEqualTo(plan.height));
      final data = await frame.image.toByteData();
      if (tile['x'] == 0 && tile['y'] == 0) expect(data!.getUint8(3), 0);
      frame.image.dispose();
      codec.dispose();
    }
    expect(area, plan.width * plan.height);
  });
  Future<void> pumpSheet(
    WidgetTester tester, {
    Future<bool> Function(String, Uint8List)? save,
    StudySetContent? content,
    String Function(String)? resolve,
  }) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: MMSizes.mapExportSheetWidth,
              child: MapExportSheet(
                content: content ?? exportFixture(),
                mapId: MindMap.defaultId,
                title: 'Root',
                branchId: 'c0',
                initialBranch: true,
                resolveImage: resolve ?? (n) => n,
                save: save,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('formats, scope, appearance and text exports; cancel keeps form', (tester) async {
    String? saved;
    await pumpSheet(
      tester,
      save: (name, bytes) async {
        saved = '$name\n${utf8.decode(bytes)}';
        return false;
      },
    );
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transparent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3×'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Transparent'), findsNothing);
    await tester.tap(find.text('Markdown'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();
    expect(saved, startsWith('节点 0'));
    expect(saved, contains('节点 4'));
    expect(saved, isNot(contains('节点 1')));
    await tester.tap(find.text('Entire map'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OPML'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();
    expect(saved, contains('<opml'));
    expect(saved, contains('节点 1'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('PNG and PDF encode snapshots; cancelling save keeps the sheet', (tester) async {
    const channel = MethodChannel('marginmind/map_export');
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return Uint8List.fromList([1, 2, 3]);
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );
    await pumpSheet(tester, save: (name, bytes) async => false);
    await tester.runAsync(() async {
      await tester.tap(find.text('Export…'));
      for (var i = 0; i < 10 && !methods.contains('png'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(methods, contains('png'));
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();
    expect(methods, contains('pdf'));
  });

  test('image loader decodes complete image and fails explicitly for missing files', () async {
    final dir = Directory.systemTemp.createTempSync('export-images-test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 30, 20), Paint()..color = MMColors.light.research);
    final picture = recorder.endRecording();
    final image = await picture.toImage(30, 20);
    picture.dispose();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    image.dispose();
    final file = File('${dir.path}/image.png');
    await file.writeAsBytes(bytes);
    final now = DateTime.utc(2026);
    final content = StudySetContent(
      cards: [Card(id: 'i', kind: CardKind.image, imageFileName: 'image.png', createdAt: now)],
      nodes: const [MapNode(cardId: 'i', order: 0)],
    );
    final (images, data) = await loadExportImages(content, (n) => '${dir.path}/$n');
    final s = MapExportScene.build(
      content: content,
      mapId: MindMap.defaultId,
      title: 'Image',
      colors: MMColors.dark,
      researchLabel: 'Research',
      source: (d, p) => '',
      images: images,
      imageBytes: data,
    );
    final r = ui.PictureRecorder();
    s.paint(Canvas(r), s.size);
    final result = r.endRecording();
    result.dispose();
    expect(s.commands.where((c) => c['type'] == 'image'), hasLength(1));
    expect(data['image.png'], bytes);
    expect(images['image.png']!.width, 30);
    expect(images['image.png']!.height, 20);
    for (final i in images.values) {
      i.dispose();
    }
    await expectLater(loadExportImages(content, (n) => '${dir.path}/missing'), throwsA(isA<FileSystemException>()));
  });

  testWidgets('missing image blocks visual export across format switches; another branch can export', (tester) async {
    final now = DateTime.utc(2026);
    final content = StudySetContent(
      cards: [
        Card(id: 'c0', kind: CardKind.topic, title: 'Branch', createdAt: now),
        Card(id: 'outside', kind: CardKind.image, imageFileName: 'missing.png', createdAt: now),
      ],
      nodes: const [
        MapNode(cardId: 'c0', order: 0),
        MapNode(cardId: 'outside', order: 1),
      ],
    );
    await pumpSheet(tester, content: content, resolve: (n) => throw const FileSystemException('Missing'));
    MMButton exportButton() => tester.widget<MMButton>(find.widgetWithText(MMButton, 'Export…'));
    expect(exportButton().onPressed, isNotNull);
    await tester.tap(find.text('Entire map'));
    await tester.pumpAndSettle();
    expect(exportButton().onPressed, isNull);
    await tester.tap(find.text('Markdown'));
    await tester.pumpAndSettle();
    expect(exportButton().onPressed, isNotNull);
    await tester.tap(find.text('PNG'));
    await tester.pumpAndSettle();
    expect(exportButton().onPressed, isNull);
    await tester.tap(find.text('Current branch'));
    await tester.pumpAndSettle();
    expect(exportButton().onPressed, isNotNull);
  });

  testWidgets('save failure is retryable', (tester) async {
    await pumpSheet(tester, save: (name, bytes) async => throw const FileSystemException('Denied'));
    await tester.tap(find.text('Markdown'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();
    expect(find.text('Export failed. Please try again.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Export failed. Please try again.'), findsNothing);
  });
}
