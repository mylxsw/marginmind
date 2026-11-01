import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/widgets/workspace_toolbar.dart';
import 'package:marginmind/features/workspace/widgets/reader_toolbar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';

import 'helpers.dart';

import 'package:marginmind/features/workspace/workspace_layout.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';

void main() {
  testWidgets('headers follow sidebar animation, split dragging and the assistant in the same frame', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final owner = container.read(workspaceProvider('demo-1').notifier);
    void aligned() {
      final scope = find.byType(WorkspaceLayoutGeometryScope);
      final geometry = tester.widget<WorkspaceLayoutGeometryScope>(scope).geometry;
      final origin = tester.getTopLeft(scope);
      expect(geometry.readerRect.shift(origin), tester.getRect(find.byType(ReaderPane)));
      expect(geometry.mapRect.shift(origin), tester.getRect(find.byType(MapPane)));
      final headers = find.byType(WorkspaceToolbar);
      expect(tester.getRect(headers.first).right, closeTo(tester.getRect(find.byType(ReaderPane)).right, .01));
      expect(tester.getRect(headers.last).left, closeTo(tester.getRect(find.byType(MapPane)).left, .01));
      expect(find.byKey(const ValueKey('map-locate-selected')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    owner.toggleSidebar();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    aligned();
    await tester.pumpAndSettle();
    aligned();
    owner.openPanel(RightPanel.assistant);
    await tester.pumpAndSettle();
    aligned();
    owner.setSplitFraction(.7);
    await tester.pump();
    aligned();
    owner.closePanel();
    owner.toggleSidebar();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    aligned();
    await tester.pumpAndSettle();
    owner.setLayout(MMSplitMode.split);
    await tester.pumpAndSettle();
    aligned();
  });

  for (final (size, touch) in [
    (const Size(1280, 820), false),
    (const Size(1194, 834), true),
    (const Size(834, 1194), true),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('one aligned toolbar per pane $size touch=$touch dark=$dark', (tester) async {
        final container = await pumpApp(
          tester,
          size: size,
          prefs: {'settings.appearance': dark ? 'dark' : 'light'},
          overrides: [touchPlatformProvider.overrideWithValue(touch)],
        );
        container.read(navigationProvider.notifier).openStudySet('demo-1');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final geometryScope = find.byType(WorkspaceLayoutGeometryScope);
        final geometry = tester.widget<WorkspaceLayoutGeometryScope>(geometryScope).geometry;
        final origin = tester.getTopLeft(geometryScope);
        expect(geometry.readerRect.shift(origin), tester.getRect(find.byType(ReaderPane)));
        expect(geometry.mapRect.shift(origin), tester.getRect(find.byType(MapPane)));
        final headers = find.byType(WorkspaceToolbar);
        expect(headers, findsNWidgets(2));
        final reader = tester.getRect(find.byType(ReaderToolbar));
        final map = tester.getRect(headers.last);
        expect(reader.height, touch ? 52 : 44);
        expect(map.height, touch ? 52 : 44);
        if (size.width > size.height) {
          expect(reader.top, map.top);
          expect(reader.right + 1, closeTo(map.left, .01));
        } else {
          expect(map.top, greaterThan(reader.bottom));
        }
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byKey(const ValueKey('map-style-button')), findsNothing);
        expect(find.byKey(const ValueKey('map-style-menu')), findsNothing);
        expect(find.byKey(const ValueKey('map-density')), findsNothing);
        final locate = find.byKey(const ValueKey('map-locate-selected'));
        final more = find.byKey(const ValueKey('map-more'));
        expect(locate.hitTestable(), findsOneWidget);
        final locateButton = tester.widget<MMToolbarButton>(locate);
        expect(locateButton.icon, MMIcons.locate);
        expect(locateButton.label, isNull);
        expect(tester.getRect(locate).right, lessThan(tester.getRect(more).left));
        expect(tester.getRect(more).left - tester.getRect(locate).right, lessThanOrEqualTo(16));
        expect(tester.getCenter(locate).dy, tester.getCenter(more).dy);
        await toggleMapStyle(tester);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('map-density')), findsOneWidget);
        await tester.tap(find.text('Full'));
        await tester.pumpAndSettle();
        expect(container.read(workspaceProvider('demo-1')).content?.map('main')?.density.name, 'full');
      });
    }
  }
}
