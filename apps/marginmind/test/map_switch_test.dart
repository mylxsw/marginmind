import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
  for (final size in [const Size(1280, 820), const Size(402, 874)]) {
    testWidgets('map submenu switches directly and marks the active map at $size', (tester) async {
      final container = await pumpApp(
        tester,
        size: size,
        overrides: [touchPlatformProvider.overrideWithValue(size.width < 600)],
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final owner = container.read(workspaceProvider('demo-1').notifier);
      final original = container.read(workspaceProvider('demo-1')).activeMapId;
      await owner.addMap('Other map');
      final other = container.read(workspaceProvider('demo-1')).activeMapId;
      await owner.selectMap(original);
      if (size.width < 600) owner.setLayout(MMSplitMode.secondary);
      await tester.pumpAndSettle();

      Future<void> openPicker() async {
        await tester.tap(find.byKey(const ValueKey('map-more')));
        await tester.pumpAndSettle();
        final styleItem = find.byKey(const ValueKey('map-style-menu'));
        final styleIcon = find.descendant(of: styleItem, matching: find.byIcon(MMIcons.mapStyle));
        final glyph = tester.widget<RichText>(find.descendant(of: styleIcon, matching: find.byType(RichText)));
        expect(glyph.text.style?.fontSize, MMSizes.dropdownIcon);
        expect(
          tester.getRect(styleIcon).right,
          lessThan(tester.getRect(find.descendant(of: styleItem, matching: find.text('Style'))).left),
        );
        await tester.tap(find.byKey(const ValueKey('map-switch-menu')));
        await tester.pumpAndSettle();
      }

      await openPicker();
      expect(
        find.descendant(of: find.byKey(ValueKey('map-switch-$original')), matching: find.byIcon(MMIcons.check)),
        findsOneWidget,
      );
      final target = find.byKey(ValueKey('map-switch-$other'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).activeMapId, other);
      expect(find.byKey(ValueKey('map-switch-$other')), findsNothing);
      await openPicker();
      expect(
        find.descendant(of: find.byKey(ValueKey('map-switch-$other')), matching: find.byIcon(MMIcons.check)),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).activeMapId, other);
      expect(tester.takeException(), isNull);
    });
  }
}
