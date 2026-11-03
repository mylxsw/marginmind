import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/library/share_import_sheet.dart';
import 'package:marginmind/features/workspace/widgets/notices.dart';
import 'package:marginmind/main.dart' as app;
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:path_provider/path_provider.dart';

import 'mobile_redesign_acceptance_test.dart' show idle;

void main() => runModalMaterialAcceptance();

void runModalMaterialAcceptance({bool includeNative = true}) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('share import, settings and native forms share the modal material', (tester) async {
    await app.main();
    await idle(tester, 5);
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final settings = container.read(settingsProvider.notifier);
    await settings.setLanguage(LanguagePreference.zh);
    await idle(tester);
    // This suite runs only in a dedicated simulator. Keep the library behind
    // each panel realistic without fetching any shared page or invoking AI.
    if ((container.read(studySetsProvider).value ?? []).isEmpty) {
      await tester.tap(find.text('打开示例学习集'));
      await idle(tester, 5);
    }
    container.read(navigationProvider.notifier).showLibrary();
    await idle(tester);
    BuildContext context() => tester.element(find.byType(AppShell));
    final marker = File('${(await getTemporaryDirectory()).path}/mobile-redesign-shot');
    Future<void> host(String line, String expected) async {
      await tester.runAsync(() async {
        await marker.writeAsString(line);
        // ignore: avoid_print
        print('$line:${marker.path}');
      });
      final deadline = DateTime.now().add(const Duration(minutes: 4));
      while (await tester.runAsync(marker.readAsString) != expected) {
        if (DateTime.now().isAfter(deadline)) throw TimeoutException(line);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      }
      await idle(tester);
    }

    Future<void> shot(String name) async {
      await idle(tester);
      expect(tester.takeException(), isNull, reason: name);
      await host('PHONE_SHOT:$name', 'captured:$name');
    }

    for (final theme in [AppearancePreference.light, AppearancePreference.dark]) {
      await settings.setAppearance(theme);
      await idle(tester);
      final share = showMMBottomSheet<ShareImportTarget>(
        context: context(),
        expand: false,
        builder: (_) => ShareImportSheet(
          batch: MMIncomingShareBatch(id: 'material-review', url: Uri.parse('https://mp.weixin.qq.com/s/article')),
        ),
      );
      await shot('${theme.name}-share-import');
      expect(find.byType(MMModalSurface), findsOneWidget);
      expect(find.descendant(of: find.byType(ShareImportSheet), matching: find.byIcon(MMIcons.close)), findsNothing);
      final surface = find.byType(MMModalSurface);
      expect(find.descendant(of: surface, matching: find.byType(BackdropFilter)), findsNothing);
      expect(find.descendant(of: surface, matching: find.byType(UiKitView)), findsNothing);
      await tester.tap(find.widgetWithText(MMButton, '取消'));
      await idle(tester);
      expect(await share, isNull);

      final panel = showSettings(context());
      await shot('${theme.name}-settings');
      expect(find.byType(MMModalSurface), findsOneWidget);
      expect(find.descendant(of: find.byType(SettingsWindow), matching: find.byIcon(MMIcons.close)), findsNothing);
      final frame = tester.getRect(find.byKey(const ValueKey('mm-bottom-sheet')));
      expect(frame.height, greaterThan(tester.view.physicalSize.height / tester.view.devicePixelRatio * .8));
      expect(find.byKey(const ValueKey('settings-tab-webSearch')).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-tab-general')));
      await shot('${theme.name}-settings-general');
      await tester.binding.handlePopRoute();
      await idle(tester);
      expect(find.byKey(const ValueKey('phone-settings-sections')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await idle(tester);
      await panel;

      if (!includeNative) continue;

      final rename = showRenameSheet(context(), title: '重命名学习集', initial: '网页阅读');
      final action = theme == AppearancePreference.dark ? 'ModalRenameDark' : 'ModalRename';
      await host('PHONE_NATIVE:$action', 'native-done:$action');
      expect(await rename, isNull);
      final confirmation = showConfirmSheet(context(), title: '取消测试操作', message: '此验收不会删除任何文档。', confirmLabel: '确认');
      final confirmAction = theme == AppearancePreference.dark ? 'ModalConfirmDark' : 'ModalConfirm';
      await host('PHONE_NATIVE:$confirmAction', 'native-done:$confirmAction');
      expect(await confirmation, isFalse);
      if (theme == AppearancePreference.light) {
        final saved = showRenameSheet(context(), title: '保存验证', initial: '网页阅读');
        await host('PHONE_NATIVE:ModalRenameSave', 'native-done:ModalRenameSave');
        expect(await saved, '网页阅读 QA');
      }
      expect(tester.takeException(), isNull);
    }
  });
}
