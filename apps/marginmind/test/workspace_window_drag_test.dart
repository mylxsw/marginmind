import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/reader_toolbar.dart';
import 'package:marginmind/features/workspace/widgets/workspace_toolbar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'workspace_tabs_test.dart' show openTabs;

void main() {
  const channel = MethodChannel('window_manager');
  const gestures = MethodChannel('marginmind/window_gestures');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'isMaximized' ? false : null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(gestures, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(gestures, null);
  });

  testWidgets('macOS sidebar controls keep the native window-button center when toggled and resized', (tester) async {
    await openTabs(tester);
    for (final size in [const Size(1536, 1092), const Size(1000, 800)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      final hide = find.byKey(const ValueKey('workspace-hide-sidebar'));
      final expandedCenter = tester.getCenter(hide).dy;
      expect(expandedCenter, 26);
      await tester.tap(hide);
      await tester.pumpAndSettle();
      final show = find.byKey(const ValueKey('workspace-show-sidebar'));
      expect(tester.getCenter(show).dy, expandedCenter);
      expect(tester.getRect(show).left, greaterThanOrEqualTo(MMSizes.windowButtonsWidth));
      await tester.tap(show);
      await tester.pumpAndSettle();
      expect(tester.getCenter(hide).dy, expandedCenter);
    }
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('tab-row empty space drags and zooms the window; content toolbars do neither', (tester) async {
    await openTabs(tester);
    final gap = find.byKey(const ValueKey('workspace-tab-drag-area'));
    expect(tester.getSize(gap).width, greaterThan(200));
    await tester.drag(gap, const Offset(80, 24), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'startDragging'), hasLength(1));
    await tester.tap(gap, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(gap, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'toggleZoom'), hasLength(1));

    calls.clear();
    final readerMore = tester.getRect(find.byKey(const ValueKey('reader-more')));
    final readerEmpty = Offset(readerMore.left - 40, readerMore.center.dy);
    expect(tester.getRect(find.byType(ReaderToolbar)).contains(readerEmpty), isTrue);
    await tester.dragFrom(readerEmpty, const Offset(60, 0), kind: PointerDeviceKind.mouse);
    await tester.tapAt(readerEmpty, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(readerEmpty, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'startDragging' || c.method == 'toggleZoom'), isEmpty);
    // The map/reader headers share the same content-only chrome scope.
    for (final element in find.byType(WorkspaceToolbar).evaluate()) {
      final chrome = MMWindowChrome.maybeOf(element);
      expect(chrome?.onDragStart, isNull);
      expect(chrome?.onTitleDoubleTap, isNull);
    }
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('tab selection and close remain immediate and never move the window', (tester) async {
    final c = await openTabs(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    owner.openStudyNote('written');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workspace-tab-documentMap')), kind: PointerDeviceKind.mouse);
    expect(owner.state.tabs.activeId, WorkspaceTab.documents.id);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('close-workspace-tab-documentMap')), kind: PointerDeviceKind.mouse);
    expect(owner.state.tabs.activeId, 'note:written');
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'startDragging' || c.method == 'toggleZoom'), isEmpty);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('overflowing tabs retain horizontal scrolling instead of window dragging', (tester) async {
    final c = await openTabs(tester, size: const Size(900, 820));
    final owner = c.read(workspaceProvider('demo-1').notifier);
    final original = owner.content.studyNotes.first;
    await c
        .read(contentRepositoryProvider)
        .update(
          'demo-1',
          (content) => content.copyWith(
            studyNotes: [
              ...content.studyNotes,
              for (var i = 0; i < 8; i++)
                StudyNote.fromJson({...original.toJson(), 'id': 'drag-$i', 'title': 'Reading note $i'}),
            ],
          ),
        );
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      owner.openStudyNote('drag-$i');
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-tab-drag-area')), findsNothing);
    final strip = find.byKey(const ValueKey('workspace-main-tabs'));
    final scroll = tester.state<ScrollableState>(find.descendant(of: strip, matching: find.byType(Scrollable)));
    final before = scroll.position.pixels;
    await tester.drag(strip, const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, lessThan(before));
    expect(calls.where((c) => c.method == 'startDragging'), isEmpty);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
