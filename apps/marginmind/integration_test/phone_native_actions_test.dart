import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/main.dart' as app;
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_design/mm_design.dart';
import 'package:path_provider/path_provider.dart';

import 'mobile_redesign_acceptance_test.dart' show idle;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('reader actions share the native outline presentation', (tester) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await app.main();
    await idle(tester, 6);
    expect(MMNativePresentation.available, isTrue);
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final settings = container.read(settingsProvider.notifier);
    await settings.setLanguage(LanguagePreference.zh);
    container.read(navigationProvider.notifier).showLibrary();
    await idle(tester);
    final sample = find.text('打开示例学习集');
    if (sample.evaluate().isNotEmpty) {
      await tester.tap(sample);
    } else {
      await tester.tap(find.textContaining(RegExp(r'^(示例：|Sample:)')).first);
    }
    await idle(tester, 6);
    final route = container.read(navigationProvider) as WorkspaceRoute;
    final controller = container.read(workspaceProvider(route.studySetId).notifier);
    controller.openDocument(controller.content.documents.first.id);
    controller.setLayout(MMSplitMode.primary);
    final marker = File('${(await getTemporaryDirectory()).path}/mobile-redesign-shot');
    Future<void> native(String action) async {
      await tester.runAsync(() async {
        await marker.writeAsString('native:$action');
        // ignore: avoid_print
        print('PHONE_NATIVE:$action:${marker.path}');
      });
      final deadline = DateTime.now().add(const Duration(minutes: 4));
      while (await tester.runAsync(() => marker.readAsString()) != 'native-done:$action') {
        if (DateTime.now().isAfter(deadline)) throw TimeoutException(action);
        // Keep Flutter rebuilding while XCTest drives the native panel. The
        // outline is opened by a Flutter state change after menu dismissal.
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      }
      await idle(tester);
    }

    for (final appearance in [AppearancePreference.light, AppearancePreference.dark]) {
      await settings.setAppearance(appearance);
      await settings.setReaderStyle(MMReaderStyle.paper);
      await idle(tester);
      await tester.tap(find.byKey(const ValueKey('phone-workspace-more')));
      await idle(tester);
      await native(appearance == AppearancePreference.dark ? 'ReaderActionsDark' : 'ReaderActions');
      expect(container.read(settingsProvider).readerStyle, MMReaderStyle.dark);
      expect(container.read(workspaceProvider(route.studySetId)).readerPanelVisible, isFalse);
    }
    await tester.tap(find.byKey(const ValueKey('phone-workspace-more')));
    await idle(tester);
    await native('ReaderActionsClose');
    expect(tester.takeException(), isNull);
  });
}
