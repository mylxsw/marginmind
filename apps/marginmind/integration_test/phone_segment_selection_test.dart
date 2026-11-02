import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/library/library_screen.dart';
import 'package:marginmind/features/library/new_study_set.dart';
import 'package:marginmind/main.dart' as app;
import 'package:marginmind/settings/app_settings.dart';
import 'package:path_provider/path_provider.dart';

import 'mobile_redesign_acceptance_test.dart' show idle;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Phone creation source selection remains visible in both appearances', (tester) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await app.main();
    await idle(tester, 6);
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final settings = container.read(settingsProvider.notifier)..setLanguage(LanguagePreference.zh);
    container.read(navigationProvider.notifier).showLibrary();
    await idle(tester);
    final marker = File('${(await getTemporaryDirectory()).path}/mobile-redesign-shot');
    Future<void> shot(String name) async {
      await idle(tester);
      expect(tester.takeException(), isNull);
      if (!const bool.fromEnvironment('CAPTURE_PHONE_UI')) return;
      await tester.runAsync(() async {
        await marker.writeAsString(name);
        // ignore: avoid_print
        print('PHONE_SHOT:$name:${marker.path}');
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (await marker.readAsString() != 'captured:$name') {
          if (DateTime.now().isAfter(deadline)) throw TimeoutException('Host did not capture $name');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
    }

    for (final dark in [true, false]) {
      settings.setAppearance(dark ? AppearancePreference.dark : AppearancePreference.light);
      await idle(tester);
      final element = tester.element(find.byType(LibraryScreen));
      unawaited(showNewStudySet(element, element as WidgetRef));
      await idle(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 700)));
      if (dark) await shot('00-dark-blank-keyboard');
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      for (final entry in [('blank', '空白'), ('document', '文档'), ('web', '网页')]) {
        await tester.tap(find.text(entry.$2).hitTestable());
        await shot('${dark ? '01-dark' : '02-light'}-${entry.$1}');
      }
      await tester.tap(find.text('取消').hitTestable());
      await idle(tester);
    }
  }, skip: !Platform.isAndroid);
}
