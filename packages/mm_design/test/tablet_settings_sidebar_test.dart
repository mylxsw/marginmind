import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final tablet in [false, true]) {
    testWidgets('${tablet ? 'tablet' : 'Mac'} settings pop-up separates paint from its hit target', (t) async {
      String selected = 'Light';
      await t.pumpWidget(
        MaterialApp(
          theme: MMTheme.light(),
          home: MMInput(
            touchPlatform: tablet,
            child: Scaffold(
              body: Center(
                child: MMPopUpButton<String>(
                  value: selected,
                  semanticLabel: 'Appearance',
                  items: const [('Light', 'Light'), ('Dark', 'Dark')],
                  onChanged: (value) => selected = value,
                ),
              ),
            ),
          ),
        ),
      );
      final popup = find.byType(MMPopUpButton<String>);
      expect(t.getSize(popup).height, tablet ? 44 : 22);
      expect(t.getSize(find.descendant(of: popup, matching: find.byType(AnimatedContainer))).height, tablet ? 32 : 22);
      await t.tapAt(t.getBottomLeft(popup) + const Offset(4, -2));
      await t.pumpAndSettle();
      await t.tap(find.text('Dark'));
      await t.pumpAndSettle();
      expect(selected, 'Dark');
    });
  }
  testWidgets('marker selection retains its semantics and touch target without a button fill', (t) async {
    final semantics = t.ensureSemantics();
    try {
      await t.pumpWidget(
        MaterialApp(
          theme: MMTheme.light(),
          home: MMInput(
            touchPlatform: true,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 260,
                  child: MMSidebarItem(
                    icon: MMIcons.document,
                    label: 'Current document',
                    selected: true,
                    selectionStyle: MMSidebarSelectionStyle.marker,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final item = find.byType(MMSidebarItem);
      expect(t.getSize(item).height, 44);
      final box = t.widget<AnimatedContainer>(find.descendant(of: item, matching: find.byType(AnimatedContainer)));
      expect((box.decoration as BoxDecoration).color, Colors.transparent);
      expect(t.widget<Text>(find.text('Current document')).style!.fontWeight, FontWeight.w600);
      expect(
        t.getSemantics(find.text('Current document')).getSemanticsData().flagsCollection.isSelected.toBoolOrNull(),
        isTrue,
      );
    } finally {
      semantics.dispose();
    }
  });
}
