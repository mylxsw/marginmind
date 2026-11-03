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
import 'package:path_provider/path_provider.dart';

import 'mobile_redesign_acceptance_test.dart' show idle;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Landscape keyboard leaves assistant input and send accessible', (tester) async {
    await app.main();
    await idle(tester, 6);
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    container.read(settingsProvider.notifier).setLanguage(LanguagePreference.zh);
    container.read(navigationProvider.notifier).showLibrary();
    await idle(tester);
    final sample = find.text('打开示例学习集');
    await tester.tap(sample.evaluate().isNotEmpty ? sample : find.textContaining(RegExp(r'^(示例：|Sample:)')).first);
    await idle(tester, 6);
    final route = container.read(navigationProvider) as WorkspaceRoute;
    final workspace = container.read(workspaceProvider(route.studySetId).notifier);
    workspace.toggleAssistantPanel();
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 700)));
    await idle(tester);
    await tester.tap(find.byKey(const ValueKey('assistant-input')));
    await tester.enterText(find.byKey(const ValueKey('assistant-input')), '横屏草稿');
    await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 900)));
    await idle(tester);
    final keyboard = tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final send = find.byKey(const ValueKey('assistant-send'));
    final rect = tester.getRect(send);
    // ignore: avoid_print
    print('ASSISTANT_KEYBOARD:screen=$screen,keyboard=$keyboard,send=$rect');
    if (const bool.fromEnvironment('CAPTURE_PHONE_UI')) {
      final marker = File('${(await getTemporaryDirectory()).path}/mobile-redesign-shot');
      await tester.runAsync(() async {
        await marker.writeAsString('01-landscape-keyboard');
        // ignore: avoid_print
        print('PHONE_SHOT:01-landscape-keyboard:${marker.path}');
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (await marker.readAsString() != 'captured:01-landscape-keyboard') {
          if (DateTime.now().isAfter(deadline)) throw TimeoutException('Host did not capture keyboard');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
    }
    expect(keyboard, greaterThan(0));
    expect(rect.height, greaterThanOrEqualTo(44));
    expect(rect.bottom, lessThanOrEqualTo(screen.height - keyboard + 1), reason: 'Send must stay above the keyboard');
    expect(send.hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-close')), findsNothing);
    expect(find.text('横屏草稿'), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await idle(tester);
    expect(find.text('横屏草稿'), findsOneWidget, reason: 'Changing the compact layout must retain the draft');
    expect(tester.takeException(), isNull);
  });
}
