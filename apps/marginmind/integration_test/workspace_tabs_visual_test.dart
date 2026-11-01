import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/widgets/assistant_panel.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../test/assistant_support.dart';

import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/workspace_pane_chrome_controller.dart';
import 'package:marginmind/features/map_generation/document_map_navigation.dart';

/// Real native Flutter rendering and the real reflow reader, with local-only
/// study data and a scripted assistant. Never reads or changes the user's library.
void main() {
  const server = String.fromEnvironment('WORKSPACE_TAB_SHOT_SERVER');
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  binding.defaultTestTimeout = const Timeout(Duration(minutes: 5));
  testWidgets('approved tab / content-sidebar design in a native window', (tester) async {
    final previousError = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrint('TAB_QA render error: ${details.exceptionAsString()}\n${details.stack}');
      previousError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousError);
    debugPrint('TAB_QA: initializing window');
    await DesktopWindow.initialize(title: 'Foliarc · 界面验证', minimumSize: MMSizes.windowMinSize);
    debugPrint('TAB_QA: preparing fixture');
    final temp = Directory.systemTemp.createTempSync('foliarc-tab-qa-');
    debugPrint('TAB_QA: fixture directory ready');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}/注意力研究.md');
    file.writeAsStringSync('''# 注意力与深度工作

## 02 减少任务切换

在信息过载的时代，注意力已经成为一种稀缺的认知资源。我们每天都会面对大量的干扰，来自外部的通知、消息和不断更新的内容，以及内部的想法与情绪。

减少任务切换，是保持专注的一种有效方式。

每一次任务切换，都会带来注意力残留。我们在心理上仍然停留在上一项任务中，难以全身心投入新的任务。这会降低工作效率，并增加认知负荷。

研究表明，即使是短暂的切换，也会让大脑重新建立工作上下文。频繁切换不仅影响当前任务的表现，还会增加压力感与疲劳感。

## 03 阅读中的实践

读完一节后，先合上书，用自己的话复述三个关键点，再回到原文核对。把临时想到的问题记下来，等当前主题结束后再处理。

为重要任务保留连续的专注时间，能让理解慢慢变得清晰。
''');
    debugPrint('TAB_QA: fixture file ready');
    final app = await openAssistantApp(
      tester,
      settle: false,
      size: const Size(1536, 1092),
      client: ScriptClient([
        answer(
          '可以从这三点开始：\n\n### 一次只读一个主题\n阅读时尽量专注于当前的问题，避免同时打开多个无关的资料。\n\n### 把临时想法记下来，稍后处理\n遇到无关的想法，先记录，再回到当前段落。\n\n### 每读完一节，停下来主动回忆\n合上文档，试着复述关键内容，再核对原文。',
        ),
      ]),
      prefs: {'settings.language': 'zh', 'settings.appearance': 'light'},
    );
    debugPrint('TAB_QA: app opened');
    await app.repository.update('demo-1', (_) => StudySetContent.empty);
    final owner = app.workspace;
    debugPrint('TAB_QA: importing document');
    await tester.runAsync(() => owner.importDocuments([(path: file.path, name: '注意力研究.md')]));
    debugPrint('TAB_QA: imported document');
    await pumpFor(tester, 8);
    final document = owner.content.documents.last;
    final source = app.container.read(reflowSessionProvider(('demo-1', document.id)));
    debugPrint('TAB_QA: initializing reader');
    await source.initialize();
    debugPrint('TAB_QA: reader ready');
    expect(source.book, isNotNull, reason: 'The real reflow book must load before capture');
    const passage = '减少任务切换，是保持专注的一种有效方式。';
    final chapter = source.book!.chapters.firstWhere((c) => c.canonicalText.contains(passage));
    final start = chapter.canonicalText.indexOf(passage);
    final anchor = chapter.anchor(start, start + passage.length, revision: document.revision!);
    await owner.excerptSource(document.id, SourceSelection.text([anchor]), MMAnnotationColor.yellow);
    debugPrint('TAB_QA: excerpt ready');
    await owner.renameMap(MindMap.defaultId, '注意力 · 概念整理');
    await owner.setMapStructure(MapStructure.logic);
    await owner.setMapDensity(MapDensity.titleOnly);
    final excerpt = owner.content.cards.firstWhere((c) => c.kind == CardKind.excerpt);
    await owner.setTitle(excerpt.id, '注意力残留');
    for (final entry in {
      '选择性注意': ['过滤无关信息', '聚焦重要目标', '抑制干扰刺激'],
      '减少任务切换': ['切换的认知成本', '建立连续的工作时间'],
      '阅读中的实践': ['主动阅读', '结构化笔记', '定期回顾'],
    }.entries) {
      owner.selectMapRoot();
      final topic = await owner.addTopic(entry.key);
      if (entry.key == '减少任务切换') await owner.moveCard(excerpt.id, topic.id);
      for (final title in entry.value) {
        owner.selectCard(topic.id);
        await owner.addTopic(title, asChild: true);
      }
    }
    for (final card in owner.content.cards.where((c) => c.kind == CardKind.topic).toList()) {
      await owner.setTags(card.id, ['专注']);
    }
    debugPrint('TAB_QA: topics ready');
    final first = await owner.organizeStudyNote(
      '关于专注的思考',
      const WholeSet(),
      NoteSettings(depth: NoteDepth.none),
      NoteTemplate.reading,
    );
    expect(first, isNotNull);
    await owner.changeStudyNote(
      first!.id,
      (note) => note.copyWith(
        sections: [
          NoteSection(
            id: 'thinking',
            title: '我的实践',
            blocks: const [
              TextBlock(
                id: 'thoughts',
                kind: TextKind.summary,
                text: '阅读这部分内容让我更加理解注意力残留的影响。即使我已经开始了新的任务，大脑仍会不自觉地回到上一个任务中。\n\n一次只处理一个问题，把临时想法记下来，等当前主题结束后再处理。',
              ),
            ],
          ),
        ],
      ),
    );
    debugPrint('TAB_QA: first note ready');
    final second = await owner.organizeStudyNote(
      '阅读方法摘记',
      const WholeSet(),
      NoteSettings(depth: NoteDepth.none),
      NoteTemplate.reading,
    );
    expect(second, isNotNull);
    debugPrint('TAB_QA: second note ready');
    owner.activateTab(WorkspaceTab.vocabulary);
    owner.activateTab(WorkspaceTab.review);
    owner.activateTab(WorkspaceTab.documents);
    owner.setLayout(MMSplitMode.split);
    owner.selectMapRoot();
    app.container.read(documentMapNavigationProvider('demo-1').notifier).dismiss();
    owner.openStudyNoteReference(first.id);
    await pumpFor(tester, 8);
    WorkspacePaneChromeScope.maybeOf(tester.element(find.byType(MapPane).first))?.map?.execute('fit');
    await pumpFor(tester, 8);
    Future<void> shot(String name) async {
      if (server.isEmpty) return;
      debugPrint('TAB_QA: capturing $name');
      await pumpFor(tester, 8);
      final view = tester.binding.renderViews.first;
      final image = (await tester.runAsync(
        () => (view.debugLayer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 2),
      ))!;
      final png = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
      image.dispose();
      final client = HttpClient();
      try {
        await tester.runAsync(() async {
          final request = await client.postUrl(Uri.parse('$server/capture/$name'));
          request.headers.contentType = ContentType('image', 'png');
          request.contentLength = png!.lengthInBytes;
          request.add(png.buffer.asUint8List());
          final response = await request.close();
          expect(response.statusCode, 200);
          debugPrint('TAB_QA: saved $name');
          await response.drain<void>();
        });
      } finally {
        client.close(force: true);
      }
    }

    await shot('document-reference-light');
    owner.showTags();
    owner.filterTag('专注');
    await pumpFor(tester, 8);
    await shot('document-tags-light');
    owner.closePanel();
    owner.openPanel(RightPanel.assistant);
    await pumpFor(tester, 8);
    final panel = ProviderScope.containerOf(tester.element(find.byType(AssistantPanel)));
    final asking = panel.read(assistantControllerProvider.notifier).send('如何减少阅读时的任务切换？');
    await pumpFor(tester, 30);
    await asking;
    await pumpFor(tester, 8);
    await shot('document-assistant-light');
    await app.container.read(settingsProvider.notifier).setAppearance(AppearancePreference.dark);
    await pumpFor(tester, 8);
    await shot('document-assistant-dark');
    owner.openStudyNote(first.id);
    owner.showNoteReference(NoteReference.document);
    await pumpFor(tester, 8);
    await shot('note-reference-dark');
    expect(tester.takeException(), isNull);
  });
}
