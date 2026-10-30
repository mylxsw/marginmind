import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final portal in [false, true]) {
    testWidgets('anchored menu aligns above the button and fits window edges (portal: $portal)', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: MMTheme.light(),
          home: MMInput(
            touchPlatform: portal,
            child: MMContextMenuHost(
              child: Builder(
                builder: (c) {
                  context = c;
                  return const Scaffold();
                },
              ),
            ),
          ),
        ),
      );
      for (final anchor in [
        const Rect.fromLTWH(650, 550, 100, 30),
        const Rect.fromLTWH(650, 10, 100, 30),
        const Rect.fromLTWH(10, 550, 100, 30),
        const Rect.fromLTWH(750, 550, 50, 30),
      ]) {
        showMMMenu(
          context,
          position: anchor.topLeft,
          anchor: anchor,
          entries: [MMMenuItem('Model', () {}), MMMenuItem('Manage', () {})],
        );
        await tester.pumpAndSettle();
        final menu = tester.getRect(find.ancestor(of: find.text('Model'), matching: find.byType(MMGlass)).first);
        expect(menu.left, greaterThanOrEqualTo(8));
        expect(menu.right, lessThanOrEqualTo(792));
        expect(menu.top, greaterThanOrEqualTo(8));
        expect(menu.bottom, lessThanOrEqualTo(592));
        if (anchor.top == 10) {
          expect(menu.top, anchor.bottom + 4);
        } else {
          expect(menu.bottom, anchor.top - 4);
        }
        if (anchor.left == 650) expect(menu.right, anchor.right);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets('menu clamps to screen, disables items, selects and dismisses', (tester) async {
    late BuildContext context;
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold(body: Text('home'));
          },
        ),
      ),
    );
    void open() {
      showMMMenu(
        context,
        position: const Offset(790, 590),
        entries: [
          MMMenuItem('Select', () => selected++, shortcut: '⌘S'),
          const MMMenuDivider(),
          const MMMenuItem('Disabled', null, disabledReason: 'Requires a common parent'),
          MMMenuItem('Delete', () => selected++, destructive: true),
        ],
      );
    }

    open();
    await tester.pump();
    for (final fade in tester.widgetList<FadeTransition>(
      find.ancestor(of: find.text('Select'), matching: find.byType(FadeTransition)),
    )) {
      expect(fade.opacity.value, 1, reason: 'context menus must be fully visible in their first frame');
    }
    final rect = tester.getRect(find.text('Select'));
    expect(rect.right, lessThanOrEqualTo(800));
    expect(rect.bottom, lessThanOrEqualTo(600));
    await tester.tap(find.text('Disabled'));
    await tester.pumpAndSettle();
    expect(selected, 0);
    expect(find.byTooltip('Requires a common parent'), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.text('Select'), findsNothing);
    open();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Select'), findsNothing);
    expect(selected, 1);
  });
}
