import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_layout.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'assistant_support.dart';

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
      expect(find.ancestor(of: progress, matching: find.byType(MMLiquidGlass)), findsOneWidget);
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
      if (width >= 834) {
        expect(area, findsOneWidget);
        await t.tap(area);
      } else {
        expect(area, findsNothing);
        await t.tap(find.byKey(const ValueKey('reader-more')));
        await t.pumpAndSettle();
        await t.tap(find.byWidgetPredicate((w) => w is MMDropdownItem && w.value == AnnotationTool.area));
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
