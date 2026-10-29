import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

import 'harness.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('inline count follows foreground and grows in ${brightness.name}', (tester) async {
      final colors = brightness == Brightness.light ? MMColors.light : MMColors.dark;
      Future<void> mount({int count = 12, bool selected = false, bool enabled = true}) async {
        await tester.pumpWidget(
          harness(
            MMToolbarButton(
              icon: MMIcons.marginNote,
              tooltip: 'Notes',
              count: count,
              compact: true,
              selected: selected,
              onPressed: enabled ? () {} : null,
            ),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();
      }

      void check(int count, Color foreground) {
        final text = tester.widget<Text>(find.text('$count'));
        expect(text.style!.fontSize, 10);
        expect(text.style!.fontWeight, FontWeight.w600);
        expect(text.style!.fontFeatures, const [FontFeature.tabularFigures()]);
        expect(text.style!.color, foreground);
        expect(tester.widget<Icon>(find.byIcon(MMIcons.marginNote)).color, foreground);
        expect(
          tester.getTopLeft(find.text('$count')).dx - tester.getTopRight(find.byIcon(MMIcons.marginNote)).dx,
          closeTo(2, .01),
        );
      }

      await mount();
      check(12, colors.label);
      final width = tester.getSize(find.byType(MMToolbarButton)).width;
      await mount(count: 123456, selected: true);
      check(123456, colors.accent);
      expect(tester.getSize(find.byType(MMToolbarButton)).width, greaterThan(width));
      final buttonRect = tester.getRect(find.byType(MMToolbarButton));
      expect(tester.getRect(find.text('123456')).right, lessThanOrEqualTo(buttonRect.right));
      await mount(enabled: false);
      check(12, colors.label.withValues(alpha: .3));
      await mount(count: 0);
      expect(find.byType(Text), findsNothing);
      expect(tester.getSize(find.byType(MMToolbarButton)), const Size(30, 26));
      expect(tester.takeException(), isNull);
    });
  }
}
