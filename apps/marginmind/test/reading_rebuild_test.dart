import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/widgets/workspace_sidebar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_screen.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  testWidgets('page changes and debounced saves do not rebuild workspace panes or menus', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final builds = <Type, int>{};
    const watched = {WorkspaceScreen, MapPane, ReaderPane, WorkspaceSidebar, AppMenus};
    final old = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, built) {
      old?.call(element, built);
      if (watched.contains(element.widget.runtimeType)) {
        builds.update(element.widget.runtimeType, (v) => v + 1, ifAbsent: () => 1);
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = old);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    for (var page = 2; page <= 20; page++) {
      controller.recordPage('c1', page);
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(builds, isEmpty, reason: 'live page updates must only rebuild page indicators');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(container.read(contentProvider('demo-1')).value!.document('c1')!.lastPage, 20);
    expect(builds, isEmpty, reason: 'persisting reading metadata must not rebuild presentation');

    // A real content edit must still reach subscribers.
    await controller.addTopicAndEdit('New topic');
    await tester.pumpAndSettle();
    expect(builds[MapPane], greaterThan(0));
    expect(builds[WorkspaceSidebar], greaterThan(0));
    expect(builds[AppMenus], greaterThan(0));
    await settleHud(tester);
  });
  testWidgets('disk-backed 300-node workspace ignores reading metadata and library summary emissions', (tester) async {
    late Directory dir;
    late FileLibraryStore store;
    late String id;
    late SharedPreferences prefs;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('marginmind-rebuild-');
      store = FileLibraryStore(dir, clock: () => testNow);
      id = (await store.create(const NewStudySet(title: 'Performance fixture', colorIndex: 0))).id;
      var content = demoContent();
      var n = 0;
      final editor = StudySetEditor(newId: () => 'perf-${++n}', now: () => testNow);
      for (var i = 0; i < 300; i++) {
        content = editor.addTopic(content, title: 'Node $i').$1;
      }
      await store.update(id, (_) => content);
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => testNow),
          studySetRepositoryProvider.overrideWithValue(store),
          contentRepositoryProvider.overrideWithValue(store),
          pdfRenderingEnabledProvider.overrideWithValue(false),
        ],
        child: const MarginMindApp(),
      ),
    );
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(MarginMindApp)));
    container.read(navigationProvider.notifier).openStudySet(id);
    await tester.pump();
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(container.read(contentProvider(id)).value!.nodes.length, greaterThan(300));
    final builds = <Type, int>{};
    const watched = {WorkspaceScreen, MapPane, ReaderPane, WorkspaceSidebar, AppMenus};
    final old = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, built) {
      old?.call(element, built);
      if (watched.contains(element.widget.runtimeType)) {
        builds.update(element.widget.runtimeType, (v) => v + 1, ifAbsent: () => 1);
      }
    };
    try {
      container.read(workspaceProvider(id).notifier).recordPage('c1', 42);
      await tester.pump(const Duration(seconds: 1));
      // File futures complete in real time; their continuations and Riverpod
      // notifications run in the test zone. Let both queues make progress.
      var waitingForWrite = false;
      var flushed = false;
      for (var i = 0; i < 500 && !flushed; i++) {
        await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
        if (!waitingForWrite && container.read(contentProvider(id)).value?.document('c1')?.lastPage == 42) {
          waitingForWrite = true;
          store.flush().then((_) => flushed = true);
        }
      }
      expect(flushed, isTrue);
      await tester.pumpAndSettle();
      expect(container.read(studySetProvider(id))!.lastPosition!.page, 42);
      expect(builds, isEmpty);
      final reloaded = FileLibraryStore(dir);
      final saved = await tester.runAsync(() => reloaded.load(id));
      expect(saved!.document('c1')!.lastPage, 42);
      await tester.runAsync(reloaded.dispose);
    } finally {
      debugOnRebuildDirtyWidget = old;
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(store.dispose);
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  });
}
