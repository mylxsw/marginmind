import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';

import 'helpers.dart';
import 'workspace_test.dart' show openFirstSet;

void main() {
  testWidgets('held node shows its menu before release, continuing the same touch dismisses it and moves the node', (
    tester,
  ) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final target = tester.getCenter(find.byKey(const ValueKey('c4')));
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('c3'))),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Add Relationship'), findsOneWidget);
    await g.moveTo(target);
    await tester.pumpAndSettle();
    expect(find.text('Add Relationship'), findsNothing);
    await g.up();
    await tester.pumpAndSettle();
    expect(controller.content.node('c3')!.parentId, 'c4');
    await settleHud(tester);
  });

  testWidgets('cancelling a held touch dismisses its menu and leaves the map unchanged', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('c3'))),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Add Relationship'), findsOneWidget);
    await g.cancel();
    await tester.pumpAndSettle();
    expect(find.text('Add Relationship'), findsNothing);
    expect(controller.content.node('c3')!.parentId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch selection mode remains below the map toolbar', (tester) async {
    await openFirstSet(tester);
    final selection = tester.getRect(find.byKey(const ValueKey('map-multi-select')));
    final style = tester.getRect(find.byKey(const ValueKey('map-style-button')));
    expect(selection.top, greaterThan(style.bottom));
  });

  testWidgets('map sidebar has the same menu under touch long press', (tester) async {
    await openFirstSet(tester);
    await tester.longPress(find.byKey(const ValueKey('sidebar-map-main')));
    await tester.pumpAndSettle();
    expect(find.text('Rename Mind Map…'), findsOneWidget);
  });
}
