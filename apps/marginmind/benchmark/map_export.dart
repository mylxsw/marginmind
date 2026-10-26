// Reproducible native export acceptance fixture (500 cards).
// flutter run -d macos -t benchmark/map_export.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Card;
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:marginmind/features/workspace/widgets/map_export_scene.dart';
import 'package:marginmind/features/workspace/widgets/map_export_sheet.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopWindow.initialize(
    title: 'GUL-523 Export acceptance',
    minimumSize: const Size(960, 700),
    initialSize: const Size(1100, 850),
  );
  final directory = await Directory.systemTemp.createTemp('gul523-export-');
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 200, 100), Paint()..color = MMColors.light.research);
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 100);
  picture.dispose();
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  await File('${directory.path}/chart.png').writeAsBytes(bytes);
  final now = DateTime.utc(2026, 10, 27);
  final content = StudySetContent(
    cards: [
      for (var i = 0; i < 500; i++)
        Card(
          id: 'c$i',
          kind: i == 25
              ? CardKind.image
              : i == 26
              ? CardKind.research
              : i == 27
              ? CardKind.excerpt
              : i < 20
              ? CardKind.topic
              : CardKind.note,
          title: i == 25
              ? '图片 · Figure'
              : i == 26
              ? '研究笔记'
              : i == 27
              ? '原文摘录'
              : i < 20
              ? '章节 $i · Chapter'
              : '知识点 $i · Evidence',
          imageFileName: i == 25 ? 'chart.png' : null,
          researchNoteId: i == 26 ? 'note' : null,
          annotationId: i == 27 ? 'a' : null,
          createdAt: now,
        ),
    ],
    nodes: [
      for (var i = 0; i < 500; i++)
        MapNode(cardId: 'c$i', order: i.toDouble(), parentId: i < 20 ? null : 'c${(i - 20) ~/ 24}', collapsed: i == 0),
    ],
    annotations: [
      Annotation(
        id: 'a',
        createdAt: now,
        documentId: 'doc',
        page: 1,
        quote: '完整原文使用宋体。Full excerpt remains readable and searchable.',
        rects: [],
        colorIndex: 0,
      ),
    ],
    documents: [Document(id: 'doc', title: '示例文献', fileName: 'source.pdf', pageCount: 1, importedAt: now)],
    researchNotes: [
      ResearchNote(
        id: 'note',
        sessionId: 's',
        title: '检索练习',
        body: '研究笔记正文：间隔检索促进长期记忆。\nResearch body exported in full.',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    relations: const [MapRelation(id: 'relation', fromId: 'c21', toId: 'c24', label: '相互关联')],
    summaries: const [MapSummary(id: 'summary', parentId: 'c0', fromId: 'c20', toId: 'c24', label: '学习策略')],
  );
  final scene = MapExportScene.build(
    content: content,
    mapId: MindMap.defaultId,
    title: '500 节点 · Export acceptance',
    colors: MMColors.light,
    researchLabel: '研究笔记',
    source: (d, p) => '${d.title} · $p',
    images: {'chart.png': image},
    imageBytes: {'chart.png': bytes},
  );
  final plan = MapRasterPlan(scene.size, 2);
  await File('${directory.path}/map-500.png').writeAsBytes(await scene.png(plan));
  await File('${directory.path}/map-500.pdf').writeAsBytes(await const NativeMapExport().pdf(scene.vector));
  image.dispose();
  stdout.writeln('EXPORT_ACCEPTANCE ${directory.path} ${plan.width}x${plan.height}');
  runApp(
    MaterialApp(
      theme: MMTheme.light(),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: MMSizes.mapExportSheetWidth,
            child: MapExportSheet(
              content: content,
              mapId: MindMap.defaultId,
              title: '500 节点 · Export acceptance',
              branchId: 'c0',
              resolveImage: (n) => '${directory.path}/$n',
            ),
          ),
        ),
      ),
    ),
  );
}
