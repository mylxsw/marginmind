import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('dropdown shows every row at full size in its first frame (reduced: $reduced)', (tester) async {
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: MMTheme.light(),
          home: MMAppearance(
            reduceMotion: reduced,
            child: Scaffold(
              body: MMDropdownButton<int>(
                tooltip: 'Documents',
                icon: const Icon(MMIcons.collections),
                onSelected: (value) => selected = value,
                itemBuilder: (_) => [for (var i = 0; i < 6; i++) MMDropdownItem(value: i, child: Text('Document $i'))],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Documents'));
      await tester.pump();
      final last = find.text('Document 5');
      final initialRect = tester.getRect(last);
      for (final fade in tester.widgetList<FadeTransition>(
        find.ancestor(of: last, matching: find.byType(FadeTransition)),
      )) {
        expect(fade.opacity.value, 1, reason: 'the last row must not wait for staggered fades');
      }
      expect(last.hitTestable(), findsOneWidget);
      await tester.tap(last);
      await tester.pump();
      expect(selected, 5);
      expect(last, findsNothing);

      await tester.tap(find.byTooltip('Documents'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(last), initialRect, reason: 'the menu must not grow after appearing');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(last, findsNothing);
    });
  }
}
