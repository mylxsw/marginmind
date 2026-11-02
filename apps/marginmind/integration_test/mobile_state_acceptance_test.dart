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
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:marginmind/main.dart' as app;
import 'package:mm_design/mm_design.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';

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
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      // ignore: avoid_print
      print('LAYOUT_DIAGNOSTICS:$details');
      previousErrorHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousErrorHandler);
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

    BuildContext context() => tester.element(find.byType(AppShell, skipOffstage: false));
    if (MMInput.of(context()).phone) {
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
      expect(find.byKey(const ValueKey('ai-tasks-discard')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai-tasks-discard')));
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

    controller.toggleAssistantPanel();
    await idle(tester);
    final input = find.byKey(const ValueKey('assistant-input'));
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, false);
    await tester.enterText(input, '保留这段草稿');
    await shot('20-assistant-draft');
    await tester.tap(find.byKey(const ValueKey('assistant-close')));
    await idle(tester);
    controller.toggleAssistantPanel();
    await idle(tester);
    expect(find.text('保留这段草稿'), findsOneWidget);
    await shot('21-assistant-draft-restored');
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
    await idle(tester);
    final size = MediaQuery.sizeOf(context());
    final safe = MediaQuery.paddingOf(context());
    expect(
      tester.getSize(find.byKey(const ValueKey('mm-bottom-sheet'))).width,
      greaterThanOrEqualTo(size.width - safe.horizontal - 1),
    );
    await tester.tap(input);
    await tester.enterText(input, '横屏输入的草稿');
    await shot('22-assistant-landscape-keyboard');
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await shot('23-assistant-portrait-restored');
    expect(find.text('横屏输入的草稿'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assistant-close')));
    await idle(tester);
    await tester.tap(find.byWidgetPredicate((w) => w is MMIconButton && w.icon == MMIcons.sidebar).hitTestable().first);
    await shot('24-resources');
    await tester.binding.handlePopRoute();
    await idle(tester);
    expect(find.byKey(const ValueKey('phone-drawer-scrim')), findsNothing);
    final file = File('${(await getTemporaryDirectory()).path}/mobile-final-reading.md');
    await file.writeAsString(
      '# 手机阅读\n\n## 阅读与理解\n\n${List.generate(30, (i) => '第 ${i + 1} 段：阅读之后回忆重点，再回到原文核对。\n\n').join()}\n## 间隔复习\n\n检查遗漏。',
    );
    await controller.importDocuments([(path: file.path, name: 'mobile-final-reading.md')]);
    await idle(tester, 4);
    controller.showReaderPanel(ReaderPanelMode.outline);
    await shot('25-reflow-navigation');
    await tester.tap(find.text('间隔复习').hitTestable());
    await idle(tester);
    expect(container.read(workspaceProvider(route.studySetId)).readerPanelVisible, false);
    await shot('26-reflow-located');
    expect(errors, isEmpty);
  });
}
