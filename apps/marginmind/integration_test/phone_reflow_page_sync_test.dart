import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/phone_reader_controls.dart';
import 'package:marginmind/features/workspace/widgets/reflow_scroll_reader.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/main.dart' as app;
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:path_provider/path_provider.dart';

import 'mobile_redesign_acceptance_test.dart' show idle;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().defaultTestTimeout = const Timeout(Duration(minutes: 3));
  testWidgets('phone reflow page capsule updates during touch scrolling and after slider navigation', (tester) async {
    await app.main();
    await idle(tester, 4);
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    container.read(settingsProvider.notifier)
      ..setLanguage(LanguagePreference.zh)
      ..setAppearance(AppearancePreference.dark)
      ..setReaderStyle(MMReaderStyle.dark);
    final library = container.read(studySetRepositoryProvider);
    final set = await tester.runAsync(() => library.create(const NewStudySet(title: '滚动页码验证', colorIndex: 1)));
    container.read(navigationProvider.notifier).openStudySet(set!.id);
    await idle(tester);
    final owner = container.read(workspaceProvider(set.id).notifier);
    final imported = await tester.runAsync(() async {
      final directory = await getTemporaryDirectory();
      final file = await File('${directory.path}/page-sync.md').writeAsString(
        '# 滚动页码验证\n\n${List.generate(70, (i) => '第 ${i + 1} 段：滚动阅读时，底部页码应该随当前内容更新。拖动进度条跳转后，继续滚动也要保持同步。').join('\n\n')}',
      );
      return owner.importDocuments([(path: file.path, name: 'page-sync.md')]);
    });
    expect(imported!.count, 1);
    owner.setLayout(MMSplitMode.primary);
    await idle(tester, 4);
    PhoneReaderControls controls() => tester.widget<PhoneReaderControls>(find.byType(PhoneReaderControls));
    Future<void> shot(String name) async {
      if (!const bool.fromEnvironment('CAPTURE_PHONE_UI')) return;
      await idle(tester);
      await tester.runAsync(() async {
        final marker = File('${(await getTemporaryDirectory()).path}/page-sync-shot');
        await marker.writeAsString(name);
        // ignore: avoid_print
        print('PHONE_SHOT:$name:${marker.path}');
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (await marker.readAsString() != 'captured:$name') {
          if (DateTime.now().isAfter(deadline)) throw TimeoutException('Screenshot was not captured');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
    }

    Future<void> pan(double dy) async {
      final finger = await tester.startGesture(tester.getCenter(find.byType(ReflowScrollReader)));
      for (var i = 0; i < 10; i++) {
        await finger.moveBy(Offset(0, dy / 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await finger.cancel();
      await idle(tester);
    }

    expect(controls().page, 1);
    await shot('01-before-scroll');
    await pan(-1200);
    expect(controls().page, greaterThan(1));
    await shot('02-after-scroll');
    await tester.tap(find.byKey(const ValueKey('phone-reader-page')));
    await idle(tester);
    tester.widget<Slider>(find.byKey(const ValueKey('phone-reader-slider'))).onChanged!(.5);
    await idle(tester, 3);
    final middle = controls().page;
    await pan(-1200);
    expect(controls().page, greaterThan(middle));
    await shot('03-scroll-after-slider');
    final scroll = tester.widget<ReflowScrollReader>(find.byType(ReflowScrollReader)).controller;
    for (var i = 0; i < 20 && scroll.offset < scroll.position.maxScrollExtent - 1; i++) {
      await pan(-1200);
    }
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
    expect(controls().page, controls().pageCount);
    await shot('04-document-bottom');
    expect(tester.takeException(), isNull);
  });
}
