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
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_pane_chrome_controller.dart';
import 'package:marginmind/main.dart' as app;
import 'package:marginmind/settings/settings_window.dart';
import 'package:marginmind/features/workspace/widgets/reader_sidebar_tab_bar.dart';
import 'package:marginmind/features/assistant/widgets/assistant_quick_actions.dart';
import 'package:marginmind/settings/app_settings.dart';
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().defaultTestTimeout = const Timeout(Duration(minutes: 14));
  testWidgets('phone navigation, task heights and contextual panels keep a single clear hierarchy', (tester) async {
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
    final marker = File('${directory.path}/surface-hierarchy-shot');
    final file = await File('${directory.path}/visual-polish-article.md').writeAsString(
      '# $_articleTitle\n\n${_passages.indexed.map((e) => '${e.$1 == 14
          ? '### '
          : [0, 8, 10].contains(e.$1)
          ? '## '
          : ''}${e.$2.$1}').join('\n\n')}',
    );
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
        next = editor.toggleTextBookmark(next, doc.id, book.position(chapter.id, 0), title: 'Thread 与工作流的组织方式');
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

    Future<void> native(String action) async {
      await tester.runAsync(() async {
        await marker.writeAsString('native:$action');
        // ignore: avoid_print
        print('PHONE_NATIVE:$action:${marker.path}');
        final deadline = DateTime.now().add(const Duration(minutes: 5));
        while (await marker.readAsString() != 'native-done:$action') {
          if (DateTime.now().isAfter(deadline)) throw TimeoutException(action);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
      await idle(tester);
    }

    Size getScreen() => tester.view.physicalSize / tester.view.devicePixelRatio;
    Future<void> openDrawer() async {
      await tester.tap(
        find.byWidgetPredicate((w) => w is MMIconButton && w.icon == MMIcons.sidebar).hitTestable().first,
      );
      await idle(tester);
      final drawer = tester.getRect(find.byKey(const ValueKey('phone-drawer-panel')));
      expect(drawer.width, lessThanOrEqualTo(getScreen().width * MMPhoneNavigation.drawerWidthFraction));
      expect(getScreen().width - drawer.right, greaterThanOrEqualTo(MMSizes.touchTarget));
      expect(find.byIcon(MMIcons.close).hitTestable(), findsNothing);
    }

    Future<void> closeDrawer() async {
      await tester.tapAt(Offset(getScreen().width - MMSpacing.s, 300));
      await idle(tester);
      expect(find.byKey(const ValueKey('phone-drawer-scrim')), findsNothing);
    }

    void expectExpanded() {
      final frame = tester.getRect(find.byKey(const ValueKey('mm-bottom-sheet')));
      expect(
        frame.top,
        // The reader's SafeArea has already consumed the inherited top padding.
        // Compare global geometry against the actual window's safe area.
        lessThanOrEqualTo(tester.view.padding.top / tester.view.devicePixelRatio + MMSpacing.s + 1),
      );
      expect(frame.height, greaterThan(getScreen().height * .8));
    }

    for (final theme in [AppearancePreference.dark, AppearancePreference.light]) {
      final name = theme.name;
      await settings.setAppearance(theme);
      await settings.setReaderStyle(theme == AppearancePreference.dark ? MMReaderStyle.dark : MMReaderStyle.white);
      navigation.showLibrary();
      await idle(tester);
      await shot('$name-00-library');
      await openDrawer();
      await shot('$name-01-library-drawer');
      await closeDrawer();
      navigation.openStudySet(set.id);
      await idle(tester, 3);
      owner = container.read(workspaceProvider(set.id).notifier);
      owner.openDocument(doc.id);
      owner.setLayout(MMSplitMode.primary);
      await idle(tester, 3);
      await openDrawer();
      final documentTitle = find.text(_articleTitle).hitTestable();
      expect(tester.widget<Text>(documentTitle).maxLines, 1);
      expect(find.text('返回阅读'), findsNothing);
      await shot('$name-02-study-drawer');
      await tester.tap(find.byTooltip('添加').hitTestable().first);
      await shot('$name-03-add-menu');
      expect(find.byType(MMPhoneSheetHeader), findsNothing);
      final short = tester.getRect(find.byKey(const ValueKey('mm-bottom-sheet')));
      expect(short.height, lessThan(getScreen().height * .3));
      await tester.binding.handlePopRoute();
      await idle(tester);
      await closeDrawer();
      final readerChrome = WorkspacePaneChromeScope.maybeOf(tester.element(find.byType(ReaderPane)))!;
      expect(readerChrome.reader?.commands['reader-settings']?.enabled, true);
      readerChrome.reader!.execute('reader-settings');
      await shot('$name-10-reading-settings');
      expect(find.byType(MMModalContent), findsOneWidget);
      expect(find.descendant(of: find.byType(MMModalContent), matching: find.byType(MMGlass)), findsNothing);
      await tester.binding.handlePopRoute();
      await idle(tester);
      owner.showReaderPanel(ReaderPanelMode.outline);
      await idle(tester, 3);
      await native(theme == AppearancePreference.dark ? 'ReaderHierarchyDark' : 'ReaderHierarchyLight');
      expect(find.byKey(const ValueKey('phone-document-navigation')), findsOneWidget);
      expectExpanded();
      expect(find.byType(ReaderSidebarTab), findsNWidgets(3));
      expect(find.byKey(const ValueKey('phone-document-navigation-close')), findsNothing);
      final navigationFrame = find.byKey(const ValueKey('phone-document-navigation'));
      expect(find.descendant(of: navigationFrame, matching: find.text(_articleTitle)), findsNothing);
      expect(tester.getTopLeft(find.byType(ReaderSidebarTabBar)).dy, tester.getTopLeft(navigationFrame).dy);
      final outlineRows = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> && (widget.key! as ValueKey<String>).value.startsWith('reader-outline-'),
      );
      for (final row in outlineRows.evaluate()) {
        expect(
          tester.getSize(find.byWidget(row.widget)).height,
          greaterThanOrEqualTo(MMReaderNavigationLayout.rowHeight),
        );
        for (final title in tester.widgetList<Text>(
          find.descendant(of: find.byWidget(row.widget), matching: find.byType(Text)),
        )) {
          expect(title.maxLines, 1);
          expect(title.style!.fontWeight, anyOf(isNull, FontWeight.w400));
        }
      }
      expect(find.text('文档开头').hitTestable(), findsNothing);
      expect(find.descendant(of: navigationFrame, matching: find.byIcon(MMIcons.check)), findsNothing);
      final root = tester.getTopLeft(find.text('Super-agent').hitTestable());
      final child = tester.getTopLeft(find.text('Router 层').hitTestable());
      expect(child.dx - root.dx, MMReaderNavigationLayout.indent);
      await shot('$name-04-reader-management-outline');
      await tester.tap(find.descendant(of: find.byType(ReaderSidebarTab), matching: find.text('书签')));
      expect(find.descendant(of: navigationFrame, matching: find.text('书签')), findsOneWidget);
      await shot('$name-04b-reader-management-bookmarks');
      await tester.tap(find.descendant(of: find.byType(ReaderSidebarTab), matching: find.text('标注')));
      expect(find.descendant(of: navigationFrame, matching: find.text('标注')), findsOneWidget);
      await shot('$name-04c-reader-management-annotations');
      await tester.fling(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, 950), 1600);
      await idle(tester);
      expect(container.read(workspaceProvider(set.id)).readerPanelVisible, false);
      owner.setLayout(MMSplitMode.secondary);
      owner.selectCard(ids[15]);
      await idle(tester);
      final chrome = WorkspacePaneChromeScope.maybeOf(tester.element(find.byType(MapPane)))!;
      chrome.map!.execute('center');
      await idle(tester);
      owner.openPanel(RightPanel.assistant);
      await shot('$name-05-assistant-expanded');
      expectExpanded();
      for (final action in ['解释', '出复习题']) {
        expect(
          find.descendant(of: find.byKey(const ValueKey('assistant-suggestions')), matching: find.text(action)),
          findsOneWidget,
        );
      }
      final input = find.byKey(const ValueKey('assistant-input'));
      await tester.tap(input);
      await tester.enterText(input, '请解释这段 Router 工作流的含义');
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 900)));
      await shot('$name-05b-assistant-keyboard');
      final keyboard = tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
      expect(keyboard, greaterThan(0));
      expect(
        tester.getRect(find.byKey(const ValueKey('assistant-send'))).bottom,
        lessThanOrEqualTo(getScreen().height - keyboard + 1),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await idle(tester);
      await tester.fling(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, 950), 1600);
      await idle(tester);
      owner.openPanel(RightPanel.assistant);
      await idle(tester);
      expect(find.text('请解释这段 Router 工作流的含义'), findsOneWidget);
      owner.closePanel();
      await idle(tester);
      await tester.tap(find.byKey(const ValueKey('node-bar-assistant')));
      await shot('$name-06-quick-actions');
      expect(find.byType(AssistantQuickActions), findsOneWidget);
      final quick = tester.getRect(find.byKey(const ValueKey('mm-bottom-sheet')));
      expect(quick.height, greaterThan(getScreen().height * .55));
      expect(quick.height, lessThan(getScreen().height * .85));
      await tester.fling(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, 950), 1600);
      await idle(tester);
      chrome.map!.execute('style');
      await shot('$name-09-map-style');
      expect(find.byKey(const ValueKey('map-style-popover')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('map-style-popover')), matching: find.byType(MMGlass)),
        findsNothing,
      );
      await tester.binding.handlePopRoute();
      await idle(tester);
      showSettings(tester.element(find.byType(AppShell)));
      await shot('$name-07-settings');
      expectExpanded();
      await tester.binding.handlePopRoute();
      await idle(tester);
    }
  });
}
