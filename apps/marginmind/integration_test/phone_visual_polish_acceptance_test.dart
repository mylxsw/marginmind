import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/workspace/reflow_document.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/widgets/outline_view.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_pane_chrome_controller.dart';
import 'package:marginmind/main.dart' as app;
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/shared/assistant_icon.dart';
import 'package:mm_core/mm_core.dart' hide Card;
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_design/mm_design.dart';
import 'package:path_provider/path_provider.dart';

import 'mobile_redesign_acceptance_test.dart' show idle;

// Local, screenshot-derived example text, not a fetched copy of the article.
// Run only on a dedicated simulator: this fixture creates two local study sets.
const _articleTitle = 'Super-agent 设计探索：迈向更自主的智能体';
const _passages = [
  ('Super-agent', -1),
  ('现有的主流 Agent 设计还需要用户不断发出指令，才能完成连续的任务。', 0),
  ('需要打破 Agent 与单次手动会话之间的边界。', 0),
  ('Super-agent 具备以下四个基本特征。', 0),
  ('连续：用户可以直接在 IM 聊天中发起任务，持续保留上下文。', 3),
  ('高效：交互响应迅速，同时能处理复杂的任务。', 3),
  ('主动：无需等待用户逐条下达指令，能够识别接下来的工作。', 3),
  ('持久：始终在线，直接接入日常使用的工具。', 3),
  ('五个模块构成了支撑上述四个特征的双层架构。', 0),
  ('图片摘录', 8),
  ('双层架构', 0),
  ('五个模块通过双层架构协作，以事件驱动的方式持续运行。', 10),
  ('要同时实现高效并发与连续性，需要在架构中明确不同模块的职责。', 10),
  ('由常驻的工作流负责持续交互与后台任务的协调。', 10),
  ('Router 层', 0),
  ('Router 层负责接收消息、识别意图，并将任务交给合适的工作流和记忆模块。', 14),
  ('记忆：保留用户偏好和任务进展，支持后续工作。', 14),
  ('工作流：将复杂任务分解为清晰、可以检查的步骤。', 14),
  ('事件驱动：用新的消息和任务状态推进后续执行。', 14),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().defaultTestTimeout = const Timeout(Duration(minutes: 8));
  testWidgets('seven phone reference surfaces have clean, consistent boundaries', (tester) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await app.main();
    await idle(tester, 5);
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final settings = container.read(settingsProvider.notifier);
    await settings.setLanguage(LanguagePreference.zh);
    await settings.setAppearance(AppearancePreference.dark);
    final library = container.read(studySetRepositoryProvider);
    final repository = container.read(contentRepositoryProvider);
    final directory = await getTemporaryDirectory();
    final marker = File('${directory.path}/phone-visual-polish-shot');
    final file = await File('${directory.path}/visual-polish-article.md')
        .writeAsString('# $_articleTitle\n\n${_passages.map((e) => e.$1).join('\n\n')}');
    final set = await library.create(const NewStudySet(title: '网页阅读', colorIndex: 1));
    final navigation = container.read(navigationProvider.notifier);
    navigation.openStudySet(set.id);
    await idle(tester);
    var owner = container.read(workspaceProvider(set.id).notifier);
    final imported = await tester.runAsync(() => owner.importDocuments([(path: file.path, name: 'article.md')]));
    expect(imported!.count, 1);
    await idle(tester, 4);
    final importedDocument = owner.content.documents.single;
    // Keep the real imported reflow content; represent a readable web capture
    // without any URL or network access, so the document icon matches the reference.
    final doc = Document.fromJson({...importedDocument.toJson(), 'format': 'web', 'title': _articleTitle});
    final book = await tester.runAsync(() => ReflowDocument.load(repository as DocumentRepository, set.id, doc));
    final chapter = book!.chapters.single;
    final editor = container.read(editorProvider);
    final ids = <String>[];
    await tester.runAsync(
      () => repository.update(set.id, (content) {
        var next = content.copyWith(documents: [doc]);
        for (final (text, parent) in _passages) {
          final start = chapter.canonicalText.indexOf(text);
          expect(start, greaterThanOrEqualTo(0));
          final result = editor.createExcerpt(
            next,
            documentId: doc.id,
            textAnchors: [chapter.anchor(start, start + text.length, revision: doc.revision!)],
            quote: text,
            colorIndex: 0,
            parentId: parent < 0 ? null : ids[parent],
          );
          next = result.$1;
          ids.add(result.$2.id);
        }
        return editor.setReadingPosition(next, doc.id, book.position(chapter.id, 0));
      }),
    );
    // A second real local document gives the library the same two-card structure.
    final sample = await library.create(const NewStudySet(title: 'Sample: Forgetting and Retrieval', colorIndex: 2));
    final pdf = await rootBundle.load('assets/sample/sample.pdf');
    final sampleFile = await File('${directory.path}/visual-polish-sample.pdf').writeAsBytes(pdf.buffer.asUint8List());
    final stored = await tester.runAsync(() => repository.importFile(sample.id, sampleFile.path));
    await tester.runAsync(
      () => repository.update(sample.id, (content) {
        final result = editor.addDocument(
          content,
          title: 'Sample chapter: The forgetting curve',
          fileName: stored!,
          pageCount: 2,
        );
        var next = editor.setLastPage(result.$1, result.$2.id, 1);
        for (var i = 0; i < 8; i++) {
          next = editor
              .createExcerpt(
                next,
                documentId: result.$2.id,
                page: 1,
                rects: const [PageRect(72, 100, 300, 120)],
                quote: 'Retrieval practice helps us remember what we learn.',
                colorIndex: 2,
              )
              .$1;
        }
        return next;
      }),
    );
    await library.markOpened(set.id);
    final services = container.read(assistantServicesProvider.notifier);
    await services.upsert(
      AssistantService(
        id: 'visual-polish-local',
        name: '视觉验收（本地）',
        protocol: ServiceProtocol.ollama,
        endpoint: 'http://localhost:11434/v1/chat/completions',
        localEnabled: true,
        models: const [ServiceModel(id: 'claude-opus-local-preview', name: 'Claude Opus · 本地预览')],
      ),
    );
    await services.setDefault(const ModelReference('visual-polish-local', 'claude-opus-local-preview'));
    await idle(tester);

    Future<void> shot(String name) async {
      await idle(tester);
      expect(tester.takeException(), isNull, reason: name);
      if (!const bool.fromEnvironment('CAPTURE_PHONE_UI')) return;
      await tester.runAsync(() async {
        // Let the simulator present the last Flutter frame before the host
        // takes a system screenshot; layout completion can precede presentation.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await marker.writeAsString(name);
        // ignore: avoid_print
        print('PHONE_SHOT:$name:${marker.path}');
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (await marker.readAsString() != 'captured:$name') {
          if (DateTime.now().isAfter(deadline)) throw TimeoutException(name);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
    }

    Future<void> sidebar() async {
      await tester.tap(
        find.byWidgetPredicate((w) => w is MMIconButton && w.icon == MMIcons.sidebar).hitTestable().first,
      );
      await idle(tester);
    }

    for (final theme in [AppearancePreference.dark, AppearancePreference.light]) {
      await settings.setAppearance(theme);
      navigation.showLibrary();
      await shot('${theme.name}-01-library');
      final searchBottom = tester.getBottomLeft(find.byType(PreferredSize).first).dy;
      final continueTop = tester.getTopLeft(find.text('继续学习')).dy;
      expect(continueTop - searchBottom, greaterThanOrEqualTo(MMSpacing.xl));
      navigation.openStudySet(set.id);
      await idle(tester, 3);
      owner = container.read(workspaceProvider(set.id).notifier);
      owner.openDocument(doc.id);
      owner.setLayout(MMSplitMode.secondary);
      owner.setMapView(MapViewMode.map);
      owner.selectCard(null);
      await idle(tester);
      await sidebar();
      expect(find.byIcon(MMIcons.close).hitTestable(), findsNothing);
      expect(find.text('返回脑图').hitTestable(), findsOneWidget);
      await shot('${theme.name}-02a-resources');
      await tester.tap(find.byTooltip('添加').hitTestable().first);
      await shot('${theme.name}-02-resources-add');
      expect(find.byType(MMPhoneSheetHeader), findsNothing);
      await tester.binding.handlePopRoute();
      await idle(tester);
      await tester.tap(find.byKey(const ValueKey('phone-resources-return')));
      await idle(tester);
      expect(find.byKey(const ValueKey('phone-drawer-scrim')), findsNothing);
      expect(container.read(workspaceProvider(set.id)).layout, MMSplitMode.secondary);
      owner.setLayout(MMSplitMode.primary);
      await idle(tester);
      await sidebar();
      expect(find.text('返回阅读').hitTestable(), findsOneWidget);
      await shot('${theme.name}-02b-resources-reading');
      await tester.fling(find.byKey(const ValueKey('phone-drawer-panel')), const Offset(-700, 0), 1400);
      await idle(tester);
      expect(find.byKey(const ValueKey('phone-drawer-scrim')), findsNothing);
      owner.setLayout(MMSplitMode.secondary);
      await idle(tester);

      owner.selectCard(ids[14]);
      await idle(tester);
      final paneContext = tester.element(find.byType(MapPane));
      final chrome = WorkspacePaneChromeScope.maybeOf(paneContext)!;
      chrome.map!.execute('center');
      await idle(tester);
      // Use the production locate action; the capture does not adjust zoom.
      final canvasRect = tester.getRect(find.byType(MindMapCanvas));
      for (final id in ids.sublist(14)) {
        final nodeRect = tester.getRect(find.byKey(ValueKey(id)).first);
        expect(nodeRect.left, greaterThanOrEqualTo(canvasRect.left));
        expect(nodeRect.right, lessThanOrEqualTo(canvasRect.right));
      }
      await idle(tester);
      await shot('${theme.name}-04-map-selection');
      expect(
        find.descendant(of: find.byKey(const ValueKey('node-bar-assistant')), matching: find.byType(AssistantIcon)),
        findsOneWidget,
      );

      owner.toggleAssistantPanel();
      await idle(tester);
      await shot('${theme.name}-03a-assistant-medium');
      await tester.drag(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, -600));
      await shot('${theme.name}-03-assistant');
      expect(find.byKey(const ValueKey('assistant-input')), findsOneWidget);
      expect(find.byKey(const ValueKey('assistant-model')), findsOneWidget);
      final frame = tester.getRect(find.byKey(const ValueKey('mm-bottom-sheet')));
      final inputFrame = tester.getRect(find.byKey(const ValueKey('assistant-input-container')));
      expect(inputFrame.left - frame.left, lessThanOrEqualTo(MMSpacing.s + 1));
      expect(frame.right - inputFrame.right, lessThanOrEqualTo(MMSpacing.s + 1));
      expect(find.byKey(const ValueKey('assistant-close')), findsNothing);
      expect(inputFrame.height, lessThanOrEqualTo(190));
      final modelRect = tester.getRect(find.byKey(const ValueKey('assistant-model')));
      final sendRect = tester.getRect(find.byKey(const ValueKey('assistant-send')));
      expect(modelRect.center.dy, closeTo(sendRect.center.dy, 1));
      await tester.tap(find.byKey(const ValueKey('assistant-input')));
      await tester.enterText(find.byKey(const ValueKey('assistant-input')), '请解释 Router 层的作用');
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 900)));
      await shot('${theme.name}-03b-assistant-keyboard');
      final keyboard = tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(keyboard, greaterThan(0));
      expect(
        tester.getRect(find.byKey(const ValueKey('assistant-send'))).bottom,
        lessThanOrEqualTo(screen.height - keyboard + 1),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await idle(tester);
      await tester.fling(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, 900), 1400);
      await idle(tester);
      owner.toggleAssistantPanel();
      await idle(tester);
      expect(find.text('请解释 Router 层的作用'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('assistant-input')), '');
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      owner.closePanel();
      await idle(tester);

      await tester.tap(find.byKey(const ValueKey('node-bar-assistant')));
      await idle(tester);
      await shot('${theme.name}-05-assistant-actions');
      expect(find.byKey(const ValueKey('quick-input')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-sidebar')), findsNothing);
      expect(find.byKey(const ValueKey('quick-close')), findsNothing);
      final quickFrame = tester.getRect(find.byKey(const ValueKey('mm-bottom-sheet')));
      final quickInput = tester.getRect(find.byKey(const ValueKey('quick-composer')));
      expect(quickInput.left - quickFrame.left, lessThanOrEqualTo(MMSpacing.s + 1));
      expect(quickFrame.right - quickInput.right, lessThanOrEqualTo(MMSpacing.s + 1));
      await tester.drag(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, -500));
      await shot('${theme.name}-05a-assistant-actions-expanded');
      final expandedFrame = tester.getRect(find.byKey(const ValueKey('mm-bottom-sheet')));
      final expandedInput = tester.getRect(find.byKey(const ValueKey('quick-composer')));
      expect(expandedFrame.bottom - expandedInput.bottom, lessThanOrEqualTo(MMSpacing.s + 1));
      expect(expandedFrame.bottom - expandedInput.bottom, greaterThanOrEqualTo(0));
      await tester.tap(find.byKey(const ValueKey('quick-input')));
      await tester.enterText(find.byKey(const ValueKey('quick-input')), '解释这个节点');
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 900)));
      await shot('${theme.name}-05b-assistant-actions-keyboard');
      final quickKeyboard = tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
      expect(quickKeyboard, greaterThan(0));
      expect(
        tester.getRect(find.byKey(const ValueKey('quick-composer'))).bottom,
        lessThanOrEqualTo(screen.height - quickKeyboard + 1),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await idle(tester);
      await tester.fling(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, 900), 1400);
      await idle(tester);
      expect(find.byKey(const ValueKey('quick-input')), findsNothing);

      owner.selectCard(null);
      owner.setMapView(MapViewMode.outline);
      await idle(tester);
      await tester.tap(find.byKey(const ValueKey('map-more')));
      await shot('${theme.name}-06-outline-more');
      expect(find.byType(MMPhoneSheetHeader), findsNothing);
      expect(find.text('切换脑图'), findsOneWidget);
      final activeMap = container.read(workspaceProvider(set.id)).activeMapId;
      await tester.tap(find.text('切换脑图'));
      await shot('${theme.name}-06a-map-submenu');
      expect(find.byType(MMPhoneSheetHeader), findsOneWidget);
      await tester.binding.handlePopRoute();
      await idle(tester);
      expect(find.byType(MMPhoneSheetHeader), findsNothing);
      expect(container.read(workspaceProvider(set.id)).activeMapId, activeMap);
      await tester.binding.handlePopRoute();
      await idle(tester);
      await shot('${theme.name}-07-outline');
      expect(find.byType(OutlineView), findsOneWidget);
      // The bottom rows can clear the floating toolbar when scrolled to the end.
      final list = find.descendant(of: find.byType(OutlineView), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.text(_passages.last.$1), 300, scrollable: list);
      await shot('${theme.name}-07a-outline-bottom');
      expect(tester.takeException(), isNull);
    }
  });
}
