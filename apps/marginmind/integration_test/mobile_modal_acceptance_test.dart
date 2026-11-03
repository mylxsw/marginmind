import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/map_generation/widgets/generate_map_sheet.dart';
import 'package:marginmind/features/map_generation/widgets/map_generation_bar.dart' show showMapAdjustSheet;
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/study_notes/note_setup_sheet.dart';
import 'package:marginmind/features/workspace/widgets/highlight_custom_color_picker.dart';
import 'package:marginmind/features/workspace/widgets/map_export_sheet.dart';
import 'package:marginmind/features/workspace/widgets/phone_map_selection.dart';
import 'package:marginmind/features/workspace/widgets/notices.dart';
import 'package:marginmind/features/workspace/widgets/phone_more_sheet.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/widgets/reading_settings.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/main.dart' as app;
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:path_provider/path_provider.dart';

import 'mobile_redesign_acceptance_test.dart' show idle;

void main() => runModalAcceptance();

void runModalAcceptance({
  bool navigationOnly = false,
  bool adjustmentOnly = false,
  bool nodeMenuOnly = false,
  bool gestureOnly = false,
  bool selectionOnly = false,
}) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('phone modal families share one frame and retain native platform behavior', (tester) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await app.main();
    await idle(tester, 6);
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final settings = container.read(settingsProvider.notifier);
    await settings.setLanguage(LanguagePreference.zh);
    container.read(navigationProvider.notifier).showLibrary();
    await idle(tester);
    final sample = find.text('打开示例学习集');
    await tester.tap(sample.evaluate().isNotEmpty ? sample : find.textContaining(RegExp(r'^(示例：|Sample:)')).first);
    await idle(tester, 6);
    final route = container.read(navigationProvider) as WorkspaceRoute;
    final owner = container.read(workspaceProvider(route.studySetId).notifier);
    owner.openDocument(owner.content.documents.first.id);
    owner.setLayout(MMSplitMode.primary);
    await idle(tester);
    BuildContext context() => tester.element(find.byType(AppShell));
    final marker = File('${(await getTemporaryDirectory()).path}/mobile-redesign-shot');
    Future<void> host(String kind, String action, String done) async {
      await tester.runAsync(() async {
        await marker.writeAsString('$kind:$action');
        // ignore: avoid_print
        print('PHONE_$kind:$action:${marker.path}');
      });
      final deadline = DateTime.now().add(const Duration(minutes: 4));
      while (await tester.runAsync(() => marker.readAsString()) != '$done:$action') {
        if (DateTime.now().isAfter(deadline)) throw TimeoutException('$kind:$action');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      }
      await idle(tester);
    }

    Future<void> back() async {
      if (Platform.isAndroid) {
        await host('ANDROID', 'Back', 'android-done');
      } else {
        await tester.binding.handlePopRoute();
        await idle(tester);
      }
    }

    Future<void> shot(String name) async {
      await idle(tester);
      expect(tester.takeException(), isNull, reason: name);
      await tester.runAsync(() async {
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

    void safeFrame() {
      final frame = tester.getRect(find.byKey(const ValueKey('mm-bottom-sheet')).last);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final keyboard = tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
      expect(frame.left, greaterThan(0));
      expect(frame.right, lessThan(screen.width));
      expect(frame.bottom, lessThanOrEqualTo(screen.height - keyboard));
    }

    if (selectionOnly) {
      owner.setLayout(MMSplitMode.secondary);
      await idle(tester);
      final mapId = container.read(workspaceProvider(route.studySetId)).activeMapId;
      final ids = owner.content.nodes.where((n) => n.mapId == mapId).take(2).map((n) => n.cardId).toList();
      final layer = find.byType(PhoneMapSelectionLayer);
      Future<PhoneMapSelectionController> enter() async {
        await tester.tap(find.byKey(const ValueKey('node-bar-more')));
        await idle(tester);
        await tester.tap(find.text('多选'));
        await idle(tester);
        expect(layer, findsOneWidget);
        return tester.widget<PhoneMapSelectionLayer>(layer).controller;
      }

      for (final theme in [AppearancePreference.light, AppearancePreference.dark]) {
        await settings.setAppearance(theme);
        owner.selectCard(ids[0]);
        await idle(tester);
        final selection = await enter();
        await shot('${theme.name}-01-selection-mode');
        await tester.tap(find.byKey(const ValueKey('phone-map-selection-clear')));
        await tester.tap(find.text('框选'));
        await idle(tester);
        final bounds = tester
            .getRect(find.byKey(ValueKey(ids[0])).first)
            .expandToInclude(tester.getRect(find.byKey(ValueKey(ids[1])).first))
            .inflate(10);
        final g = await tester.startGesture(tester.getCenter(find.byKey(ValueKey(ids[0])).first) - const Offset(4, 4));
        await g.moveTo(bounds.bottomRight);
        await tester.pump();
        await g.up();
        await idle(tester);
        expect(selection.selected, containsAll(ids));
        expect(container.read(workspaceProvider(route.studySetId)).selectedCardIds, {ids[0]});
        final frame = find.byKey(const ValueKey('phone-map-selection-frame'));
        expect(frame, findsOneWidget);
        await shot('${theme.name}-02-box-with-handles');
        final corner = find.byKey(const ValueKey('phone-map-selection-handle-bottomRight'));
        final beforeResize = selection.frame!;
        final resize = await tester.startGesture(tester.getCenter(corner));
        await resize.moveBy(const Offset(18, 20));
        await tester.pump();
        await resize.up();
        await idle(tester);
        expect(selection.selected, containsAll(ids));
        expect(selection.frame!.width, greaterThan(beforeResize.width));
        expect(selection.frame!.height, greaterThan(beforeResize.height));
        final storedFrame = selection.frame;
        final a = await tester.startGesture(const Offset(100, 330), pointer: 1);
        final b = await tester.startGesture(const Offset(270, 330), pointer: 2);
        for (var i = 0; i < 4; i++) {
          await a.moveBy(const Offset(-6, -5));
          await b.moveBy(const Offset(6, 5));
          await tester.pump();
        }
        await a.up();
        await b.up();
        await idle(tester);
        expect(selection.frame, storedFrame);
        expect(selection.selected, containsAll(ids));
        await shot('${theme.name}-03-zoom-preserves-frame');
        await tester.tap(find.text('点选'));
        await idle(tester);
        await tester.tapAt(tester.getCenter(find.byKey(ValueKey(ids[1])).first));
        await idle(tester);
        expect(selection.selected, {ids[0]});
        expect(frame, findsNothing);
        await shot('${theme.name}-04-refine-by-tapping');
        await back();
        expect(layer, findsNothing);
        expect(container.read(workspaceProvider(route.studySetId)).selectedCardIds, {ids[0]});
        final complete = await enter();
        await tester.tapAt(tester.getCenter(find.byKey(ValueKey(ids[1])).first));
        await idle(tester);
        expect(complete.selected, containsAll(ids));
        await tester.tap(find.byKey(const ValueKey('phone-map-selection-done')));
        await idle(tester);
        expect(layer, findsNothing);
        expect(container.read(workspaceProvider(route.studySetId)).selectedCardIds, containsAll(ids));
        await shot('${theme.name}-05-completed-selection');
        await tester.tap(find.byKey(const ValueKey('node-bar-select')));
        await idle(tester);
        expect(layer, findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('phone-map-selection-cancel')));
        await idle(tester);
        expect(container.read(workspaceProvider(route.studySetId)).selectedCardIds, containsAll(ids));
      }
      await tester.tap(find.byKey(const ValueKey('node-bar-select')));
      await idle(tester);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
      if (Platform.isIOS) await host('NATIVE', 'Landscape', 'native-done');
      await idle(tester);
      expect(MediaQuery.sizeOf(context()).width, greaterThan(MediaQuery.sizeOf(context()).height));
      for (final key in ['phone-map-selection-cancel', 'phone-map-selection-done', 'phone-map-selection-clear']) {
        expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
      }
      await shot('landscape-selection-controls');
      await tester.tap(find.byKey(const ValueKey('phone-map-selection-cancel')));
      await idle(tester);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      if (Platform.isIOS) await host('NATIVE', 'Portrait', 'native-done');
      return;
    }
    if (gestureOnly) {
      owner.setLayout(MMSplitMode.secondary);
      await idle(tester);
      final nodes = owner.content.nodes
          .where((n) => n.mapId == container.read(workspaceProvider(route.studySetId)).activeMapId)
          .toList();
      final source = nodes[0].cardId;
      final target = nodes[1].cardId;
      final toolbar = find.byKey(const ValueKey('phone-map-node-toolbar'));
      final hint = find.byKey(const ValueKey('phone-map-drag-hint'));
      final menu = find.byKey(const ValueKey('mm-action-sheet'));
      for (final theme in [AppearancePreference.light, AppearancePreference.dark]) {
        await settings.setAppearance(theme);
        await idle(tester);
        await tester.tap(find.byKey(ValueKey(source)).first);
        await idle(tester);
        expect(toolbar, findsOneWidget);
        final dock = tester.getRect(toolbar);
        expect(dock.bottom, greaterThan(MediaQuery.sizeOf(context()).height * .75));
        await shot('${theme.name}-selected-dock');
        final press = await tester.startGesture(tester.getCenter(find.byKey(ValueKey(source)).first));
        await tester.pump(const Duration(milliseconds: 650));
        expect(toolbar, findsNothing);
        expect(hint, findsOneWidget);
        expect(menu, findsNothing);
        await shot('${theme.name}-hold-to-move');
        await press.up();
        await idle(tester);
        expect(owner.content.node(source)!.parentId, isNull);
        expect(toolbar, findsOneWidget);
        final drag = await tester.startGesture(tester.getCenter(find.byKey(ValueKey(source)).first));
        await tester.pump(const Duration(milliseconds: 650));
        await drag.moveTo(tester.getCenter(find.byKey(ValueKey(target)).first));
        await idle(tester);
        expect(find.byKey(const ValueKey('map-drop-preview')), findsOneWidget);
        expect(toolbar, findsNothing);
        expect(menu, findsNothing);
        await shot('${theme.name}-child-drop-preview');
        await drag.up();
        await idle(tester);
        expect(owner.content.node(source)!.parentId, target);
        expect(toolbar, findsOneWidget);
        expect(hint, findsNothing);
        await shot('${theme.name}-after-drop');
        await owner.undo();
        await idle(tester);
        expect(owner.content.node(source)!.parentId, isNull);
        // The full menu is now an explicit action, independent of dragging.
        await tester.tap(find.byKey(const ValueKey('node-bar-more')));
        await idle(tester);
        expect(menu, findsOneWidget);
        await shot('${theme.name}-explicit-more');
        await back();
        expect(menu, findsNothing);
      }
      return;
    }
    if (nodeMenuOnly) {
      owner.setLayout(MMSplitMode.secondary);
      await idle(tester);
      final id = owner.content.nodes.first.cardId;
      for (final theme in [AppearancePreference.light, AppearancePreference.dark]) {
        await settings.setAppearance(theme);
        await idle(tester);
        await tester.tap(find.byKey(ValueKey(id)).first);
        await idle(tester);
        await tester.tap(find.byKey(const ValueKey('node-bar-more')));
        await idle(tester);
        final sheet = find.byKey(const ValueKey('mm-bottom-sheet'));
        expect(sheet, findsOneWidget);
        expect(find.text('F2'), findsNothing);
        expect(find.text('⌘L'), findsNothing);
        safeFrame();
        final medium = tester.getRect(sheet);
        expect(medium.height, lessThan(MediaQuery.sizeOf(context()).height * .6));
        await shot('${theme.name}-node-menu-medium');
        await tester.drag(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, -440));
        await idle(tester);
        expect(tester.getRect(sheet).height, greaterThan(medium.height));
        final scroll = find.descendant(
          of: find.byKey(const ValueKey('mm-action-sheet-scroll')),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(find.text('从脑图移除'), 240, scrollable: scroll);
        await shot('${theme.name}-node-menu-last-actions');
        await back();
        expect(sheet, findsNothing);
      }
      return;
    }
    if (adjustmentOnly) {
      for (final theme in [AppearancePreference.light, AppearancePreference.dark]) {
        await settings.setAppearance(theme);
        final state = container.read(workspaceProvider(route.studySetId));
        final adjusted = showMapAdjustSheet(
          context(),
          MapGenerationRequest(studySetId: route.studySetId, mapId: state.activeMapId, title: '示例', sources: const []),
        );
        await shot('${theme.name}-map-adjustment-sheet');
        safeFrame();
        await back();
        expect(await adjusted, isNull);
      }
      expect(tester.takeException(), isNull);
      return;
    }
    if (navigationOnly) {
      for (final theme in [AppearancePreference.light, AppearancePreference.dark]) {
        await settings.setAppearance(theme);
        owner.showReaderPanel(ReaderPanelMode.outline);
        await idle(tester);
        if (MMNativePresentation.available) {
          await host('NATIVE', theme == AppearancePreference.dark ? 'ReaderManageDark' : 'ReaderManage', 'native-done');
        }
        await shot('${theme.name}-navigation-sheet');
        expect(find.byKey(const ValueKey('phone-document-navigation')), findsOneWidget);
        safeFrame();
        await back();
        expect(container.read(workspaceProvider(route.studySetId)).readerPanelVisible, isFalse);
      }
      await owner.setTool(AnnotationTool.select);
      await owner.onSelectionCommitted(
        owner.content.documents.first.id,
        MMPdfSelection(
          page: 1,
          rects: const [PageRect(72, 160, 340, 18)],
          text: '人在学习新知识之后，记忆并不是匀速流失的。',
          viewportRect: const Rect.fromLTWH(30, 230, 300, 24),
        ),
      );
      await shot('selection-popover-before-back');
      expect(container.read(workspaceProvider(route.studySetId)).pending, isNotNull);
      await back();
      expect(container.read(workspaceProvider(route.studySetId)).pending, isNull);
      expect(container.read(navigationProvider), isA<WorkspaceRoute>());
      await shot('selection-popover-closed');
      expect(tester.takeException(), isNull);
      return;
    }
    for (final theme in [AppearancePreference.light, AppearancePreference.dark]) {
      final prefix = theme.name;
      await settings.setAppearance(theme);
      await idle(tester);
      unawaited(showSettings(context()));
      await shot('$prefix-01-settings-medium');
      safeFrame();
      final mediumTop = tester.getTopLeft(find.byKey(const ValueKey('mm-bottom-sheet'))).dy;
      await tester.fling(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, -300), 1200);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(const ValueKey('mm-bottom-sheet'))).dy, lessThan(mediumTop - 80));
      await tester.ensureVisible(find.byKey(const ValueKey('settings-tab-models')));
      await tester.tap(find.byKey(const ValueKey('settings-tab-models')));
      await shot('$prefix-02-settings-expanded-models');
      await back();
      expect(find.byKey(const ValueKey('phone-settings-sections')), findsOneWidget);
      await back();
      expect(find.byType(SettingsWindow), findsNothing);

      unawaited(
        showMMPhoneDropdown<int>(
          context(),
          title: '操作菜单',
          entries: const [
            MMDropdownItem(value: 1, enabled: false, child: Text('不可用操作')),
            MMDropdownSubmenu(label: '更多选项', entries: [(value: 2, label: '子选项', selected: true)]),
          ],
        ),
      );
      await shot('$prefix-03-menu');
      await tester.tap(find.text('更多选项'));
      await shot('$prefix-04-submenu');
      await back();
      expect(find.text('更多选项'), findsOneWidget);
      await back();
      expect(find.text('更多选项'), findsNothing);

      unawaited(
        showMMSheet<void>(
          context: context(),
          builder: (_) => GenerateMapSheet(studySetId: route.studySetId),
        ),
      );
      await shot('$prefix-05-map-generation');
      safeFrame();
      await back();
      unawaited(
        showMMSheet<void>(
          context: context(),
          builder: (_) => NoteSetupSheet(studySetId: route.studySetId),
        ),
      );
      await shot('$prefix-06-note-setup');
      safeFrame();
      await back();
      final state = container.read(workspaceProvider(route.studySetId));
      unawaited(
        showMMSheet<void>(
          context: context(),
          builder: (_) => MapExportSheet(
            content: owner.content,
            mapId: state.activeMapId,
            title: '示例脑图',
            resolveImage: owner.imagePath,
          ),
        ),
      );
      await shot('$prefix-07-map-export');
      safeFrame();
      await back();
      final reader = tester.element(find.byType(ReaderPane));
      showReadingSettings(reader, reader as WidgetRef, route.studySetId);
      await shot('$prefix-08-reading-settings');
      safeFrame();
      await back();
    }

    final renamed = showRenameSheet(context(), title: '重命名', initial: '示例');
    if (MMNativePresentation.available) {
      await host('NATIVE', 'ModalRename', 'native-done');
    } else {
      await idle(tester);
      await tester.enterText(find.byType(TextField).last, 'Retained modal draft');
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 900)));
      await shot('android-09-rename-keyboard');
      expect(tester.view.viewInsets.bottom, greaterThan(0));
      safeFrame();
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 900)));
      await shot('android-10-rename-landscape-keyboard');
      expect(tester.view.viewInsets.bottom, greaterThan(0));
      expect(find.text('Retained modal draft'), findsOneWidget);
      expect(find.byType(TextField).last.hitTestable(), findsOneWidget);
      safeFrame();
      final save = find.text('保存').last;
      await tester.ensureVisible(save);
      await shot('android-10a-landscape-save');
      expect(save.hitTestable(), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await idle(tester);
      await back();
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await idle(tester);
    }
    expect(await renamed, isNull);
    final confirm = showConfirmSheet(context(), title: '取消测试操作', message: '此验收不会删除任何文档。', confirmLabel: '确认');
    if (MMNativePresentation.available) {
      await host('NATIVE', 'ModalConfirm', 'native-done');
    } else {
      await shot('android-11-confirmation');
      await back();
    }
    expect(await confirm, isFalse);
    final color = showPhoneCustomColor(context(), MMAnnotationColor.yellow);
    if (MMNativePresentation.available) {
      await host('NATIVE', 'ColorPicker', 'native-done');
    } else {
      await shot('android-12-color-picker');
      await back();
    }
    await color;
    if (!MMNativePresentation.available) {
      await tester.tap(find.byKey(const ValueKey('phone-workspace-more')));
      await shot('android-13-reader-more');
      await tester.tap(find.byKey(const ValueKey('phone-tile-appearance')));
      await shot('android-14-reader-appearance');
      await back();
      expect(find.byKey(const ValueKey('phone-sheet-more')), findsOneWidget);
      await back();
      expect(find.byType(PhoneMoreSheet), findsNothing);
      owner.showReaderPanel(ReaderPanelMode.outline);
      await shot('android-15-reader-navigation');
      await back();
      expect(container.read(workspaceProvider(route.studySetId)).readerPanelVisible, isFalse);
    }
    expect(tester.takeException(), isNull);
  });
}
