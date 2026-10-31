import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/widgets/reader_toolbar.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/map_selection_bar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_layout.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'assistant_support.dart';
import 'assistant_quick_actions_test.dart' show screenshot;
import 'vocabulary_screenshots.dart' show loadVocabularyScreenshotFonts;

Future<ProviderContainer> tablet(WidgetTester t, Size size) async {
  final container = await pumpApp(
    t,
    size: size,
    overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(false)],
  );
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await t.pumpAndSettle();
  container.read(workspaceProvider('demo-1').notifier).openDocument('c1');
  await t.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(loadVocabularyScreenshotFonts);

  for (final dark in [false, true]) {
    testWidgets('tablet split grip and compact tools ${dark ? 'dark' : 'light'}', (t) async {
      final container = await pumpApp(
        t,
        size: const Size(834, 1194),
        prefs: {'settings.appearance': dark ? 'dark' : 'light', 'settings.language': 'zh'},
        overrides: [
          touchPlatformProvider.overrideWithValue(true),
          phoneProvider.overrideWithValue(false),
          mapCommandBarVisibleProvider.overrideWithValue(true),
        ],
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await t.pumpAndSettle();
      final controller = container.read(workspaceProvider('demo-1').notifier);
      controller.openDocument('c1');
      controller.setLayout(MMSplitMode.split);
      await t.pumpAndSettle();
      final tools = t.widget<MMAdaptiveToolbar>(find.byType(MMAdaptiveToolbar).first).items;
      final toolIds = ['select', 'highlight', 'underline', 'ink', 'area', 'sync'];
      final cells = [for (final id in toolIds) find.byWidget(tools.firstWhere((item) => item.id == id).child)];
      for (var i = 0; i < cells.length; i++) {
        final cell = t.getRect(cells[i]);
        expect(cell.width, 44);
        expect(cell.height, 44);
        if (i > 0) expect(cell.left, t.getRect(cells[i - 1]).right, reason: 'no extra gap within the tool group');
      }
      final mapToolbar = t.widget<MMAdaptiveToolbar>(find.byType(MMAdaptiveToolbar).last);
      final view = find.byWidget(mapToolbar.items.firstWhere((item) => item.id == 'map-view').child);
      final style = find.byKey(const ValueKey('map-style-button'));
      expect(t.getRect(style).left, t.getRect(view).right, reason: 'map tools follow the same compact rhythm');
      final readerToolbar = t.widget<MMAdaptiveToolbar>(find.byType(MMAdaptiveToolbar).first);
      Rect readerAction(String id) =>
          t.getRect(find.byWidget(readerToolbar.items.firstWhere((item) => item.id == id).child));
      final layout = readerAction('layout-map');
      final compare = readerAction('compare');
      final documents = readerAction('documents');
      final assistant = readerAction('assistant');
      expect(compare.left - layout.right, 12);
      expect(documents.left, compare.right);
      expect(assistant.left, documents.right);
      expect(find.byKey(const ValueKey('toolbar-organize-note')), findsNothing);
      await t.tap(find.byKey(const ValueKey('reader-more')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('workspace-command-organize-note')).hitTestable(), findsOneWidget);
      await t.tapAt(const Offset(8, 300));
      await t.pumpAndSettle();
      final appearance = dark ? 'dark' : 'light';
      await screenshot(t, 'reader-toolbar-$appearance', target: find.byType(ReaderToolbar));
      controller.selectCards({'c3', 'c4'});
      await t.pumpAndSettle();
      expect(find.byType(MapSelectionBar), findsOneWidget);
      await screenshot(t, 'shared-tools-$appearance', target: find.byType(AppShell));
      controller.selectCards({});
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('map-more')));
      await t.pumpAndSettle();
      for (final label in ['添加子主题', '在后面添加同级节点', '添加关联线', '添加概要', '添加笔记', '插入图片…', '标签…', '显示详情', '定位选中节点', '多选']) {
        final row = find.ancestor(of: find.text(label), matching: find.byType(MMDropdownItem<VoidCallback>));
        expect(row, findsOneWidget);
        expect(
          find.descendant(
            of: row,
            matching: find.byWidgetPredicate((widget) => widget is Icon || widget is MMNodeActionIcon),
          ),
          findsOneWidget,
        );
      }
      await screenshot(t, 'map-menu-$appearance', target: find.byType(AppShell));
      await t.tapAt(const Offset(8, 300));
      await t.pumpAndSettle();

      final grip = find.byKey(const ValueKey('split-divider-grip'));
      expect(grip, findsOneWidget);
      expect(t.getSize(grip), const Size(32, 2));
      final restingGrip = t.widget<Container>(grip).decoration! as BoxDecoration;
      expect(restingGrip.border, isNull);
      final divider = find.byWidgetPredicate((w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeRow);
      expect(t.getSize(divider).height, 44);
      final readerBefore = t.getRect(find.byType(ReaderPane));
      expect(t.getCenter(grip).dy, closeTo(readerBefore.bottom + 6.5, .01));
      await screenshot(t, 'divider-$appearance', target: divider);
      await screenshot(t, 'split-$appearance', target: find.byType(AppShell));
      // Grab away from the tiny visual grip: the whole seam is a touch target.
      await t.dragFrom(t.getCenter(grip) + const Offset(100, 0), const Offset(0, 90));
      await t.pumpAndSettle();
      expect(t.getRect(find.byType(ReaderPane)).height, greaterThan(readerBefore.height + 60));
      final gesture = await t.startGesture(t.getCenter(grip));
      await t.pump();
      final box = t.widget<Container>(grip).decoration! as BoxDecoration;
      expect(box.color, isNot(restingGrip.color));
      expect(box.border, isNull);
      expect(t.getSize(grip), const Size(32, 2));
      await screenshot(t, 'split-grabbed-$appearance', target: find.byType(AppShell));
      await gesture.up();
      await t.pumpAndSettle();
      controller.setLayout(MMSplitMode.primary);
      await t.pumpAndSettle();
      expect(grip, findsNothing);
      expect(t.takeException(), isNull);
      await settleHud(t);
    });
  }

  for (final size in [const Size(834, 1194), const Size(1194, 834), const Size(500, 900)]) {
    testWidgets('tablet $size: configured composer sends above the software keyboard', (t) async {
      final app = await openAssistantApp(
        t,
        size: size,
        overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(false)],
      );
      app.workspace.openPanel(RightPanel.assistant);
      await t.pumpAndSettle();
      final input = find.byKey(const ValueKey('assistant-input'));
      expect(input, findsOneWidget);
      t.view.viewInsets = const FakeViewPadding(bottom: 340);
      await t.pumpAndSettle();
      final send = find.byKey(const ValueKey('assistant-send'));
      expect(t.getRect(send).bottom, lessThanOrEqualTo(size.height - 340));
      if (size.height > size.width) {
        expect(t.getRect(find.byKey(const ValueKey('tablet-workspace-panel'))).width, greaterThan(size.width * .8));
      }
      await t.enterText(input, '解释这一段');
      await t.pumpAndSettle();
      await t.tap(send);
      await pumpFor(t, 40);
      expect(conversationOf(t).messages.last.text, contains('好的'));
      expect(t.takeException(), isNull);
      await settleHud(t);
    });
  }
  for (final size in [
    const Size(834, 1194),
    const Size(1194, 834),
    const Size(1024, 768),
    const Size(600, 900),
    const Size(500, 900),
  ]) {
    testWidgets('tablet $size: companion does not cover or block the source', (t) async {
      final container = await tablet(t, size);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      controller.setLayout(MMSplitMode.primary);
      controller.openPanel(RightPanel.assistant);
      await t.pumpAndSettle();
      final panel = find.byKey(const ValueKey('tablet-workspace-panel'));
      expect(panel, findsOneWidget);
      final reader = t.getRect(find.byType(ReaderPane));
      expect(reader.overlaps(t.getRect(panel)), isFalse);
      await t.tapAt(t.getCenter(find.byKey(const ValueKey('pdf-placeholder-c1'))));
      await t.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).panel, RightPanel.assistant);
      if (size.height > size.width) {
        final grip = t.getRect(find.byKey(const ValueKey('tablet-panel-resize')));
        expect(grip.size, const Size.square(44));
        expect(t.getRect(panel).contains(grip.center), isTrue);
        expect(grip.overlaps(t.getRect(find.byKey(const ValueKey('tablet-reader-navigation')))), isFalse);
        final before = t.getSize(panel).height;
        await t.drag(find.byKey(const ValueKey('tablet-panel-resize')), const Offset(0, -70));
        await t.pumpAndSettle();
        expect(t.getSize(panel).height, greaterThan(before));
      }
      await t.tap(find.byKey(const ValueKey('assistant-close')));
      await t.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).panel, isNull);
      expect(container.read(workspaceProvider('demo-1')).layout, MMSplitMode.primary);
      final navigation = t.getRect(find.byKey(const ValueKey('tablet-reader-navigation')));
      final viewport = t.getRect(find.byKey(const ValueKey('pdf-placeholder-c1')));
      expect(viewport.bottom, t.getRect(find.byType(ReaderPane)).bottom, reason: 'no reserved footer');
      expect(navigation.overlaps(viewport), isTrue);
      expect(navigation.width, 300);
      expect(navigation.height, 44);
      expect(navigation.center.dx, closeTo(viewport.center.dx, .01));
      expect(viewport.bottom - navigation.bottom, 16);
      final progress = find.byKey(const ValueKey('reader-page-progress'));
      expect(t.getRect(progress).center.dy, closeTo(navigation.center.dy, .01));
      expect(progress.hitTestable(), findsOneWidget);
      final capsule = find.byKey(const ValueKey('tablet-reader-navigation'));
      expect(find.descendant(of: capsule, matching: find.byType(BackdropFilter)), findsNothing);
      expect(find.ancestor(of: progress, matching: find.byType(MMLiquidGlass)), findsNothing);
      expect(t.takeException(), isNull);
      await settleHud(t);
    });
  }

  testWidgets('tablet style menu preserves 53%, 100%, 200% camera on open and close', (t) async {
    final container = await tablet(t, const Size(834, 1194));
    container.read(workspaceProvider('demo-1').notifier).setLayout(MMSplitMode.secondary);
    await t.pumpAndSettle();
    for (final scale in [.53, 1.0, 2.0]) {
      final canvas = t.widget<MindMapCanvas>(find.byType(MindMapCanvas));
      final saved = Matrix4.identity()
        ..translateByDouble(20, 30, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
      canvas.transformation.value = saved.clone();
      await t.pumpAndSettle();
      final before = canvas.transformation.value.clone();
      await t.tap(find.byKey(const ValueKey('map-style-button')));
      await t.pumpAndSettle();
      expect(t.widget<MindMapCanvas>(find.byType(MindMapCanvas)).fitInsets, isNull);
      expect(canvas.transformation.value.storage, before.storage);
      await t.tap(find.byKey(const ValueKey('map-style-button')));
      await t.pumpAndSettle();
      expect(canvas.transformation.value.storage, before.storage);
    }
    await settleHud(t);
  });

  testWidgets('tablet settings controls remain reachable above landscape keyboard', (t) async {
    await tablet(t, const Size(1194, 834));
    showSettings(t.element(find.byType(AppShell)), showsGallery: false);
    await t.pumpAndSettle();
    final close = find.byKey(const ValueKey('settings-close'));
    expect(t.getSize(close).shortestSide, greaterThanOrEqualTo(44));
    t.view.viewInsets = const FakeViewPadding(bottom: 340);
    await t.pumpAndSettle();
    expect(t.getRect(find.byKey(const ValueKey('settings-window'))).bottom, lessThanOrEqualTo(834 - 340));
    await t.tap(close);
    await t.pumpAndSettle();
    expect(find.byType(SettingsWindow), findsNothing);
    await settleHud(t);
  });

  for (final size in [const Size(834, 1194), const Size(600, 900)]) {
    testWidgets('tablet $size: larger interface text fits reader, assistant and settings', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final container = await tablet(t, size);
      container.read(workspaceProvider('demo-1').notifier).openPanel(RightPanel.assistant);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      showSettings(t.element(find.byType(AppShell)), showsGallery: false);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey('settings-close')));
      await t.pumpAndSettle();
      await settleHud(t);
    });
  }

  for (final width in [500.0, 834.0]) {
    testWidgets('tablet $width: reader commands use available pane width', (t) async {
      final container = await tablet(t, Size(width, 1194));
      final controller = container.read(workspaceProvider('demo-1').notifier);
      controller.setLayout(MMSplitMode.primary);
      await t.pumpAndSettle();
      final area = find.byWidgetPredicate((w) => w is MMToolbarButton && w.icon == MMIcons.areaSelect);
      if (area.hitTestable().evaluate().isNotEmpty) {
        await t.tap(area.hitTestable());
      } else {
        await t.tap(find.byKey(const ValueKey('reader-more')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('tool-area')));
      }
      await t.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).tool, AnnotationTool.area);
      expect(t.takeException(), isNull);
      await settleHud(t);
    });
  }

  test('tablet pane layout is stable across the old 1180 threshold', () {
    for (final width in [1024.0, 1179.0, 1180.0, 1194.0]) {
      final layout = resolveTabletWorkspaceLayout(size: Size(width, 768), layout: MMSplitMode.split, panelOpen: false);
      expect(layout.splitAxis, Axis.horizontal);
      expect(layout.mode, MMSplitMode.split);
    }
  });
}
