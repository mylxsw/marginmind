import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
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
          const MMMenuItem('Disabled', null),
          MMMenuItem('Delete', () => selected++, destructive: true),
        ],
      );
    }

    open();
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.text('Select'));
    expect(rect.right, lessThanOrEqualTo(800));
    expect(rect.bottom, lessThanOrEqualTo(600));
    await tester.tap(find.text('Disabled'));
    await tester.pumpAndSettle();
    expect(selected, 0);
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
