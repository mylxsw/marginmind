import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/widgets/phone_map_selection.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';

import 'phone_layout_test.dart' show phones, openStudySet;

void main() {
  for (final phone in phones) {
    testWidgets('${phone.name}: selection drafts cancel, complete, and restore node dragging', (tester) async {
      final container = await openStudySet(tester, phone);
      final owner = container.read(workspaceProvider('demo-1').notifier);
      owner.setLayout(MMSplitMode.secondary);
      owner.selectCard('c3');
      await tester.pumpAndSettle();
      Future<PhoneMapSelectionController> open() async {
        await tester.tap(find.byKey(const ValueKey('node-bar-more')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Multiple Selection'));
        await tester.pumpAndSettle();
        return tester.widget<PhoneMapSelectionLayer>(find.byType(PhoneMapSelectionLayer)).controller;
      }

      final selection = await open();
      expect(selection.selected, {'c3'});
      expect(find.byKey(const ValueKey('phone-map-node-toolbar')), findsNothing);
      selection.clear();
      selection.toggle('c4');
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).selectedCardIds, {'c3'});
      expect(find.byKey(const ValueKey('phone-map-selected-c4')), findsOneWidget);
      tester.view.physicalSize = Size(phone.size.height, phone.size.width);
      tester.view.padding = const FakeViewPadding(left: 44, right: 44, bottom: 21);
      await tester.pumpAndSettle();
      expect(tester.widget<PhoneMapSelectionLayer>(find.byType(PhoneMapSelectionLayer)).controller, same(selection));
      expect(selection.selected, {'c4'});
      tester.view.physicalSize = phone.size;
      tester.view.padding = FakeViewPadding(top: phone.safe.top, bottom: phone.safe.bottom);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PhoneMapSelectionLayer), findsNothing);
      expect(container.read(workspaceProvider('demo-1')).selectedCardIds, {'c3'});
      final committed = await open();
      committed.clear();
      committed.toggle('c4');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('phone-map-selection-done')));
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).selectedCardIds, {'c4'});
      expect(find.byType(PhoneMapSelectionLayer), findsNothing);
      expect(find.byKey(const ValueKey('phone-map-node-toolbar')), findsOneWidget);
      // A cached selected node must regain its drag recognizer after selection ends.
      final canvas = find.byType(MindMapCanvas);
      final node = find.descendant(of: canvas, matching: find.byKey(const ValueKey('c4'))).first;
      final g = await tester.startGesture(tester.getCenter(node));
      await tester.pump(const Duration(milliseconds: 650));
      expect(find.byKey(const ValueKey('phone-map-drag-hint')), findsOneWidget);
      expect(find.byKey(const ValueKey('mm-action-sheet')), findsNothing);
      await g.up();
      await tester.pumpAndSettle();
      final multiple = await open();
      multiple.toggle('c3');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('phone-map-selection-done')));
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).selectedCardIds, {'c3', 'c4'});
      await tester.tap(find.byKey(const ValueKey('node-bar-select')));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneMapSelectionLayer), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('phone-map-selection-cancel')));
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).selectedCardIds, {'c3', 'c4'});
      owner.selectCards(['c3', 'c6']);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('node-bar-select')));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneMapSelectionLayer), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('phone-map-selection-cancel')));
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).selectedCardIds, {'c3', 'c6'});
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(phone.platform));
  }
}
