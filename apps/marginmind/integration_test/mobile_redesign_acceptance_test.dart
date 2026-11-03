import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_pane_chrome_controller.dart';
import 'package:marginmind/features/workspace/phone_reader_controls_controller.dart';
import 'package:marginmind/features/study_notes/note_setup_sheet.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:marginmind/main.dart' as app;
import 'package:mm_design/mm_design.dart';
import 'package:mm_core/mm_core.dart' hide Card;
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:marginmind/features/workspace/workspace_browser.dart';
import 'package:marginmind/features/workspace/web_conversion.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/study_notes/note_export_sheet.dart';
import 'package:marginmind/features/vocabulary/vocabulary_controller.dart';
import 'package:marginmind/features/workspace/widgets/map_export_sheet.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/widgets/workspace_sidebar.dart';

Future<void> idle(WidgetTester tester, [int seconds = 2]) async {
  for (var i = 0; i < seconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('phone screens remain usable with the shared tablet design', (tester) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await app.main();
    await idle(tester, 6);
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final settings = container.read(settingsProvider.notifier);
    settings.setLanguage(LanguagePreference.zh);
    settings.setAppearance(AppearancePreference.light);
    final navigation = container.read(navigationProvider.notifier);
    navigation.showLibrary();
    await idle(tester);
    final errors = <Object>[];
    final marker = File('${(await getTemporaryDirectory()).path}/mobile-redesign-shot');
    Future<void> shot(String name) async {
      await idle(tester);
      Object? error;
      while ((error = tester.takeException()) != null) {
        errors.add(error!);
        // ignore: avoid_print
        print('SCREEN_ERROR:$name:$error');
      }
      if (!const bool.fromEnvironment('CAPTURE_PHONE_UI')) return;
      const captureFrom = String.fromEnvironment('MOBILE_UI_CAPTURE_FROM');
      if (captureFrom.isNotEmpty && name.compareTo(captureFrom) < 0) return;
      await tester.runAsync(() async {
        await marker.writeAsString(name);
        // The host acknowledges only after saving the actual simulator screen.
        // ignore: avoid_print
        print('PHONE_SHOT:$name:${marker.path}');
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (await marker.readAsString() != 'captured:$name') {
          if (DateTime.now().isAfter(deadline)) throw TimeoutException('Host did not capture $name');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
    }

    Future<void> nativeInteraction(String action) async {
      if (!const bool.fromEnvironment('CAPTURE_PHONE_UI')) {
        throw StateError('Run this native UI acceptance through tool/capture_mobile_redesign.py');
      }
      await tester.runAsync(() async {
        await marker.writeAsString('native:$action');
        // ignore: avoid_print
        print('PHONE_NATIVE:$action:${marker.path}');
        final deadline = DateTime.now().add(const Duration(minutes: 4));
        while (await marker.readAsString() != 'native-done:$action') {
          if (DateTime.now().isAfter(deadline)) throw TimeoutException('Native XCTest did not finish $action');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
      await idle(tester);
    }

    BuildContext context() => tester.element(find.byType(AppShell, skipOffstage: false));
    Future<void> dismiss() async {
      Navigator.of(context()).pop();
      await idle(tester);
    }

    const reference = bool.fromEnvironment('MOBILE_UI_REFERENCE');
    if (reference && Platform.isIOS) {
      await nativeInteraction('Portrait');
      expect(MediaQuery.sizeOf(context()).height, greaterThan(MediaQuery.sizeOf(context()).width));
    }
    await shot('01-library');
    expect(find.byKey(const ValueKey('phone-tabs')), findsNothing);
    await tester.tap(find.byWidgetPredicate((w) => w is MMIconButton && w.icon == MMIcons.sidebar).hitTestable().first);
    await shot('01a-library-sidebar');
    if (MMInput.of(context()).phone) {
      await tester.tap(find.byKey(const ValueKey('library-navigation-close')));
    } else {
      await tester.tapAt(const Offset(380, 400));
    }
    await idle(tester);

    for (final tab in SettingsTab.values.where(
      (tab) => !reference || tab == SettingsTab.general || tab == SettingsTab.reading,
    )) {
      unawaited(showSettings(context(), tab: tab));
      await idle(tester);
      if (tab == SettingsTab.general && MMInput.of(context()).phone) {
        await shot('02-settings-index');
        await tester.tap(find.byKey(const ValueKey('settings-tab-general')));
      }
      await shot('02-settings-${tab.name}');
      if (tab == SettingsTab.models) {
        final service = find.byKey(const ValueKey('service-header-legacy-claude'));
        if (service.evaluate().isNotEmpty) {
          await tester.tap(service);
          await shot('02a-model-service');
        }
      }
      await dismiss();
    }
    if (!reference && MMInput.of(context()).phone) {
      final services = container.read(assistantServicesProvider.notifier);
      await services.upsert(
        AssistantService(
          id: 'mobile-ui-forms',
          name: '本机测试服务',
          protocol: ServiceProtocol.ollama,
          endpoint: 'http://localhost:11434/v1/chat/completions',
          localEnabled: true,
          models: const [ServiceModel(id: 'local-model', name: '本机模型')],
        ),
      );
      unawaited(showSettings(context(), tab: SettingsTab.models));
      await idle(tester);
      await tester.tap(find.byKey(const ValueKey('service-header-mobile-ui-forms')));
      await idle(tester);
      final field = find.descendant(
        of: find.byKey(const ValueKey('service-name')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(field, '尚未保存的服务名称');
      await idle(tester);
      await tester.tap(find.byKey(const ValueKey('phone-settings-back')));
      await idle(tester);
      await tester.tap(find.byKey(const ValueKey('settings-tab-models')));
      await idle(tester);
      expect(find.text('尚未保存的服务名称'), findsOneWidget);
      await shot('02b-settings-draft-retained');
      await tester.tap(find.byKey(const ValueKey('phone-settings-back')));
      await idle(tester);
      await tester.tap(find.byKey(const ValueKey('settings-close')));
      await shot('02c-settings-unsaved-confirmation');
      if (MMNativePresentation.available) {
        await nativeInteraction('SettingsDiscard');
      } else {
        expect(find.byKey(const ValueKey('ai-tasks-discard')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('ai-tasks-discard')));
      }
      await idle(tester);
      expect(find.byType(SettingsWindow), findsNothing);
      expect(
        container.read(assistantServicesProvider).value!.services.firstWhere((s) => s.id == 'mobile-ui-forms').name,
        '本机测试服务',
      );
    }
    final sample = find.text('打开示例学习集');
    if (sample.evaluate().isNotEmpty) {
      await tester.tap(sample);
    } else {
      final sets = find.byType(MMInteractive); // Existing fixture from a prior run.
      // Open the first library card through its visible title.
      final existing = find.textContaining(RegExp(r'^(示例：|Sample:)'));
      expect(existing, findsWidgets, reason: 'The simulator must have a sample fixture');
      await tester.tap(existing.first);
      expect(sets, findsWidgets);
    }
    await idle(tester, 6);
    final route = container.read(navigationProvider) as WorkspaceRoute;
    var controller = container.read(workspaceProvider(route.studySetId).notifier);
    controller.openDocument(controller.content.documents.first.id);
    controller.setLayout(MMSplitMode.primary);
    expect(find.byType(ReaderPane), findsOneWidget);
    await shot('03-reader');
    if (!reference && MMInput.of(context()).phone) {
      final readerContext = tester.element(find.byType(ReaderPane));
      final controls = PhoneReaderControlsScope.maybeOf(readerContext)!;
      controls.openTools();
      await shot('03c-reader-tools');
      await tester.tap(find.byKey(const ValueKey('phone-reader-tool-highlight')));
      await shot('03d-reader-colors');
      await controller.setTool(AnnotationTool.select);
      controls.closeScrub();
      controls.collapseTools();
      await idle(tester);
    }
    if (reference) {
      controller.toggleAssistantPanel();
      await shot('05-assistant');
      controller.closePanel();
      controller.setLayout(MMSplitMode.secondary);
      await shot('06-map');
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
      if (Platform.isIOS) await nativeInteraction('Landscape');
      await idle(tester);
      expect(MediaQuery.sizeOf(context()).width, greaterThan(MediaQuery.sizeOf(context()).height));
      await shot('06a-ipad-map-landscape');
      controller.toggleAssistantPanel();
      await shot('06b-ipad-assistant-landscape');
      expect(errors, isEmpty);
      return;
    }
    await tester.tap(find.byKey(const ValueKey('phone-workspace-more')));
    await shot('03a-reader-menu');
    if (MMNativePresentation.available) {
      await nativeInteraction('ReaderActionsClose');
    } else {
      await dismiss();
    }
    final selection = MMPdfSelection(
      page: 1,
      rects: const [PageRect(72, 160, 340, 18)],
      text: '人在学习新知识之后，记忆并不是匀速流失的。',
      viewportRect: const Rect.fromLTWH(30, 230, 300, 24),
    );
    await controller.onSelectionCommitted(controller.content.documents.first.id, selection);
    await shot('03b-reader-selection');
    controller.dismissPending();
    final excerpt = await controller.excerpt(
      controller.content.documents.first.id,
      selection,
      MMAnnotationColor.yellow,
    );
    await controller.addBookmark(controller.content.documents.first.id, 1, '记忆与主动提取');
    controller.showReaderPanel(ReaderPanelMode.outline);
    await shot('04-reader-outline');
    if (MMNativePresentation.available) {
      await nativeInteraction('ReaderNavigation');
    } else {
      controller.setReaderPanelMode(ReaderPanelMode.bookmarks);
      await shot('04a-reader-bookmarks');
      await tester.tap(find.text('记忆与主动提取').hitTestable());
    }
    await idle(tester);
    expect(container.read(workspaceProvider(route.studySetId)).readerPanelVisible, isFalse);
    if (MMNativePresentation.available) {
      final doc = controller.content.documents.first;
      for (final bookmark
          in controller.content.bookmarksOn(doc.id).where((b) => b.title == 'Native Bookmark QA').toList()) {
        await controller.removeBookmark(bookmark.id);
      }
      controller.showReaderPanel(ReaderPanelMode.bookmarks);
      await idle(tester);
      await nativeInteraction('ReaderManage');
      await shot('04b-reader-management');
      await tester.tap(find.byIcon(MMIcons.add).hitTestable().last);
      await idle(tester);
      await nativeInteraction('BookmarkEditor');
      expect(controller.content.bookmarksOn(doc.id).any((b) => b.title == 'Native Bookmark QA' && b.page == 2), isTrue);
      await shot('04c-native-bookmark-saved');
      controller.closeReaderPanel();
      await idle(tester);
    }
    controller.toggleAssistantPanel();
    await shot('05-assistant');
    controller.closePanel();
    // Local model metadata enables the composer without saving keys or making requests.
    final services = container.read(assistantServicesProvider.notifier);
    await services.upsert(
      AssistantService(
        id: 'phone-ui-local',
        name: '本机模型',
        protocol: ServiceProtocol.ollama,
        endpoint: 'http://localhost:11434/v1/chat/completions',
        localEnabled: true,
        models: [ServiceModel(id: 'local-model', name: '本机模型')],
      ),
    );
    await services.setDefault(const ModelReference('phone-ui-local', 'local-model'));
    controller.toggleAssistantPanel();
    await shot('05a-assistant-composer');
    await tester.tap(find.byKey(const ValueKey('assistant-input')));
    await tester.enterText(find.byKey(const ValueKey('assistant-input')), '解释一下主动提取为什么有助于记忆');
    await shot('05b-assistant-draft');
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    controller.closePanel();
    controller.setLayout(MMSplitMode.secondary);
    await idle(tester);
    expect(find.byType(MapPane), findsOneWidget);
    await shot('06-map');
    controller.selectCard(excerpt.cardId);
    await shot('06a-map-selection');
    controller.showDetails(excerpt.cardId);
    await shot('06b-card-details');
    controller.closePanel();
    controller.selectCard(null);
    await idle(tester);
    controller.setMapView(MapViewMode.outline);
    await shot('06d-map-outline');
    controller.setMapView(MapViewMode.map);
    await idle(tester);
    final paneChrome = WorkspacePaneChromeScope.maybeOf(tester.element(find.byType(MapPane)))!;
    paneChrome.map!.execute('style');
    await shot('06da-map-style');
    if (MMNativePresentation.available) {
      final beforeColor = controller.content
          .map(container.read(workspaceProvider(route.studySetId)).activeMapId)
          ?.backgroundColor;
      await tester.ensureVisible(find.byKey(const ValueKey('map-background-custom')));
      await tester.tap(find.byKey(const ValueKey('map-background-custom')));
      await idle(tester);
      await nativeInteraction('ColorPicker');
      expect(
        controller.content.map(container.read(workspaceProvider(route.studySetId)).activeMapId)?.backgroundColor,
        isNot(beforeColor),
      );
      await controller.setMapBackgroundColor(beforeColor);
      await idle(tester);
    }
    await dismiss();
    unawaited(
      showMMSheet<void>(
        context: context(),
        builder: (_) => MapExportSheet(
          content: controller.content,
          mapId: container.read(workspaceProvider(route.studySetId)).activeMapId,
          title: '学习与记忆',
          resolveImage: controller.imagePath,
        ),
      ),
    );
    await shot('06e-map-export');
    await dismiss();
    await tester.tap(find.byWidgetPredicate((w) => w is MMIconButton && w.icon == MMIcons.sidebar).hitTestable().first);
    await idle(tester);
    expect(find.byType(WorkspaceSidebar).hitTestable(), findsOneWidget);
    await shot('07-workspace-sidebar');
    await tester.tap(find.byKey(const ValueKey('phone-resources-close')));
    await idle(tester);
    final widgetRef = tester.element(find.byType(MapPane)) as WidgetRef;
    unawaited(showAddWebPage(context(), widgetRef, route.studySetId));
    await shot('07a-add-web');
    if (MMNativePresentation.available) {
      await nativeInteraction('WebForm');
    } else {
      await dismiss();
    }
    navigation.showLibrary();
    await shot('07b-library-after-document');
    navigation.openStudySet(route.studySetId);
    await idle(tester);
    unawaited(
      showMMSheet<void>(
        context: context(),
        builder: (_) => NoteSetupSheet(studySetId: route.studySetId),
      ),
    );
    await shot('08-note-setup');
    await dismiss();
    final note = await controller.organizeStudyNote(
      '学习与记忆',
      const WholeSet(),
      NoteSettings(depth: NoteDepth.none),
      NoteTemplate.reading,
    );
    expect(note, isNotNull);
    await shot('08a-study-note');
    unawaited(
      showMMSheet<void>(
        context: context(),
        builder: (_) => NoteExportSheet(content: controller.content, note: note!),
      ),
    );
    await shot('08b-note-export');
    await dismiss();
    await controller.selectMap(container.read(workspaceProvider(route.studySetId)).activeMapId);
    final now = DateTime.now();
    await container
        .read(vocabularyProvider.notifier)
        .edit(
          (entries) => [
            ...entries,
            VocabularyEntry(
              id: 'phone-ui-curious',
              term: 'curious',
              language: 'en',
              kind: VocabularyKind.word,
              createdAt: now,
              updatedAt: now,
              gloss: '好奇的',
              forms: const ['curious'],
              senses: const [VocabularySense(partOfSpeech: 'adj.', meaning: '想了解、学习新事物的')],
              contexts: [
                VocabularyContext(
                  id: 'phone-ui-context',
                  studySetId: route.studySetId,
                  documentId: controller.content.documents.first.id,
                  studySetTitle: '学习与记忆',
                  documentTitle: '示例章节',
                  sentence: 'Stay curious, keep learning.',
                  hit: 'curious',
                  addedAt: now,
                  page: 1,
                  sentenceTranslation: '保持好奇，持续学习。',
                ),
              ],
            ),
          ],
        );
    navigation.showVocabulary(studySetId: route.studySetId);
    await shot('09-vocabulary');
    navigation.showVocabulary(studySetId: route.studySetId, entryId: 'phone-ui-curious');
    await shot('09a-vocabulary-detail');
    navigation.startReview(route.studySetId);
    await shot('10-review');
    expect(find.byKey(const ValueKey('phone-tabs')), findsNothing);
    final reveal = find.byKey(const ValueKey('review-card-tap'));
    if (reveal.evaluate().isNotEmpty) {
      await tester.tap(reveal);
      await shot('10a-review-answer');
    }
    navigation.showStats(route.studySetId);
    await shot('11-statistics');
    navigation.openStudySet(route.studySetId);
    await idle(tester);
    controller = container.read(workspaceProvider(route.studySetId).notifier);
    controller.setLayout(MMSplitMode.primary);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<!doctype html><html lang="zh"><meta name="viewport" content="width=device-width,initial-scale=1"><title>主动提取与记忆</title><body style="font:17px/1.8 -apple-system;padding:20px"><article><h1>主动提取与记忆</h1>'
        '${List.generate(8, (_) => '<p>学习之后，尝试合上书回忆重点。主动提取可以帮助我们发现遗漏，再回到原文核对。保持好奇，持续学习。</p>').join()}'
        '</article></body></html>',
      );
      await request.response.close();
    });
    final browser = container.read(workspaceBrowserProvider(route.studySetId).notifier);
    browser.open(Uri.parse('http://localhost:${server.port}/article'));
    await idle(tester);
    final session = container.read(workspaceBrowserProvider(route.studySetId)).session!;
    for (var attempt = 0; attempt < 20 && session.phase != BrowserPhase.ready; attempt++) {
      await idle(tester, 1);
    }
    expect(session.phase, BrowserPhase.ready);
    await shot('11a-web-browser');
    await tester.tap(find.byKey(const ValueKey('browser-convert')));
    for (var attempt = 0; attempt < 20 && find.byType(WebConversionSheet).evaluate().isEmpty; attempt++) {
      await idle(tester, 1);
    }
    expect(find.byType(WebConversionSheet), findsOneWidget);
    await shot('11b-web-conversion');
    await dismiss();
    browser.close();
    controller.activateTab(WorkspaceTab.documents);
    if (MMInput.of(context()).phone) {
      final file = File('${(await getTemporaryDirectory()).path}/mobile-redesign-reading.md');
      await file.writeAsString(
        '# 手机阅读\n\n## 阅读与理解\n\n${List.generate(40, (i) => '第 ${i + 1} 段：阅读之后，试着回忆重点，再回到原文核对。把摘录整理成脑图，可以建立知识之间的联系。\n\n').join()}\n## 间隔复习\n\n隔一段时间再回忆，检查记忆中的遗漏。',
      );
      await controller.importDocuments([(path: file.path, name: 'mobile-redesign-reading.md')]);
      await idle(tester, 4);
      await shot('12a-reflow-reader');
      controller.showReaderPanel(ReaderPanelMode.outline);
      await shot('12b-reflow-navigation');
      if (MMNativePresentation.available) {
        await nativeInteraction('ReflowNavigation');
      } else {
        await tester.tap(find.text('间隔复习').hitTestable());
      }
      await idle(tester);
      expect(container.read(workspaceProvider(route.studySetId)).readerPanelVisible, isFalse);
      await shot('12c-reflow-located');
    }
    controller.activateTab(WorkspaceTab.documents);
    settings.setAppearance(AppearancePreference.dark);
    await shot('12-reader-dark');
    controller.setLayout(MMSplitMode.secondary);
    await shot('13-map-dark');
    settings.setAppearance(AppearancePreference.light);
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
    controller.setLayout(MMSplitMode.primary);
    await idle(tester);
    final rotated = MediaQuery.sizeOf(context());
    if (rotated.width > rotated.height) await shot('14-reader-landscape');
    controller.toggleAssistantPanel();
    await shot('14a-assistant-landscape');
    await tester.tap(find.byKey(const ValueKey('assistant-input')));
    await tester.enterText(find.byKey(const ValueKey('assistant-input')), '横屏草稿');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 900)));
    await idle(tester);
    final keyboardTop =
        (tester.view.physicalSize.height - tester.view.viewInsets.bottom) / tester.view.devicePixelRatio;
    final send = find.byKey(const ValueKey('assistant-send'));
    expect(tester.view.viewInsets.bottom, greaterThan(0));
    expect(tester.getRect(send).bottom, lessThanOrEqualTo(keyboardTop + 1));
    expect(send.hitTestable(), findsOneWidget);
    final assistantClose = find.byKey(const ValueKey('assistant-close'));
    expect(tester.getRect(assistantClose).bottom, lessThanOrEqualTo(keyboardTop + 1));
    expect(assistantClose.hitTestable(), findsOneWidget);
    await shot('14aa-assistant-landscape-keyboard');
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await idle(tester);
    await tester.tap(find.byKey(const ValueKey('assistant-input')));
    await tester.enterText(find.byKey(const ValueKey('assistant-input')), '保留这段草稿');
    await shot('14b-assistant-keyboard');
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await shot('14c-assistant-keyboard-dismissed');
    await tester.tap(find.byKey(const ValueKey('assistant-close')));
    await idle(tester);
    controller.toggleAssistantPanel();
    await idle(tester);
    expect(find.text('保留这段草稿'), findsOneWidget);
    await shot('14d-assistant-draft-restored');
    expect(errors, isEmpty, reason: 'Every captured screen must lay out without Flutter errors');
  });
}
