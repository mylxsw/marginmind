import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/map_style_popover.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

import 'phone_layout_test.dart' show Phone, openStudySet;

void main() {
  for (final Phone phone in [
    (
      name: '320pt',
      size: const Size(320, 700),
      safe: const EdgeInsets.only(top: 20, bottom: 20),
      platform: TargetPlatform.iOS,
    ),
    (
      name: '390pt',
      size: const Size(390, 844),
      safe: const EdgeInsets.only(top: 44, bottom: 34),
      platform: TargetPlatform.iOS,
    ),
    (
      name: 'landscape',
      size: const Size(844, 390),
      safe: const EdgeInsets.fromLTRB(44, 0, 44, 21),
      platform: TargetPlatform.iOS,
    ),
  ]) {
    testWidgets('phone map style stays on screen at ${phone.name}', (tester) async {
      final container = await openStudySet(tester, phone);
      container.read(workspaceProvider('demo-1').notifier).setLayout(MMSplitMode.secondary);
      await tester.pumpAndSettle();
      await toggleMapStyle(tester);
      await tester.pumpAndSettle();
      final popup = find.byType(MapStylePopover);
      expect(popup, findsOneWidget);
      final viewport = tester.getRect(find.ancestor(of: popup, matching: find.byType(SingleChildScrollView)).first);
      expect(viewport.left, greaterThanOrEqualTo(phone.safe.left));
      expect(viewport.right, lessThanOrEqualTo(phone.size.width - phone.safe.right));
      expect(viewport.top, greaterThanOrEqualTo(phone.safe.top));
      expect(viewport.bottom, lessThanOrEqualTo(phone.size.height - phone.safe.bottom));
      expect(tester.takeException(), isNull);
      // Keep the same popup open while rotating; the anchor also moves.
      final rotated = Size(phone.size.height, phone.size.width);
      tester.view.physicalSize = rotated;
      tester.view.padding = rotated.width > rotated.height
          ? const FakeViewPadding(left: 44, right: 44, bottom: 21)
          : const FakeViewPadding(top: 44, bottom: 34);
      await tester.pumpAndSettle();
      if (popup.evaluate().isEmpty) {
        await toggleMapStyle(tester);
        await tester.pumpAndSettle();
      }
      final moved = tester.getRect(find.ancestor(of: popup, matching: find.byType(SingleChildScrollView)).first);
      expect(moved.left, greaterThanOrEqualTo(rotated.width > rotated.height ? 44 : 0));
      expect(moved.right, lessThanOrEqualTo(rotated.width - (rotated.width > rotated.height ? 44 : 0)));
      expect(moved.top, greaterThanOrEqualTo(0));
      expect(moved.bottom, lessThanOrEqualTo(rotated.height));
      expect(tester.takeException(), isNull);
    });
  }
}
