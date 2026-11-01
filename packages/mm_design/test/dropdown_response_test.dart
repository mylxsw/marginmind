import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('plain dropdown matches an icon button before and after opening (dark: $dark)', (tester) async {
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? MMTheme.dark() : MMTheme.light(),
          home: Scaffold(
            body: Row(
              children: [
                MMIconButton(icon: MMIcons.add, tooltip: 'Map', onPressed: () {}),
                MMDropdownButton<int>(
                  plainIcon: true,
                  tooltip: 'Documents',
                  icon: const Icon(MMIcons.add),
                  onSelected: (value) => selected = value,
                  itemBuilder: (_) => [const MMDropdownItem(value: 1, child: Text('Import'))],
                ),
              ],
            ),
          ),
        ),
      );
      final buttons = find.byType(MMIconButton);
      void expectSameAppearance() {
        final frames = [
          for (final element in buttons.evaluate())
            tester.widget<AnimatedContainer>(
              find.descendant(of: find.byWidget(element.widget), matching: find.byType(AnimatedContainer)),
            ),
        ];
        expect(frames[0].constraints, frames[1].constraints);
        expect(frames[0].decoration, frames[1].decoration);
        final icons = tester
            .widgetList<RichText>(find.descendant(of: find.byIcon(MMIcons.add), matching: find.byType(RichText)))
            .toList();
        expect(icons, hasLength(2));
        expect(icons[0].text.style, icons[1].text.style);
      }

      expectSameAppearance();
      await tester.tap(find.byTooltip('Documents').last);
      await tester.pumpAndSettle();
      expect(find.text('Import'), findsOneWidget);
      expectSameAppearance();
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expectSameAppearance();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a closed More menu lets Escape reach the owning pane', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        home: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => dismissed++},
          child: Scaffold(
            body: MMDropdownMenuButton<int>(
              tooltip: 'More',
              icon: MMIcons.more,
              itemBuilder: (_) => [const MMDropdownItem(value: 1, child: Text('Action'))],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Action'), findsNothing);
    expect(dismissed, 0, reason: 'the first Escape closes the open menu only');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(dismissed, 1, reason: 'the closed menu must not swallow the pane command');
  });

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
