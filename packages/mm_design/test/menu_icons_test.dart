import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

import 'harness.dart';

void main() {
  for (final cascading in [false, true]) {
    testWidgets('command icons survive dropdown rendering (cascading: $cascading)', (tester) async {
      String? selected;
      await tester.pumpWidget(
        harness(
          MMDropdownButton<String>(
            tooltip: 'More',
            cascading: cascading,
            onSelected: (value) => selected = value,
            itemBuilder: (_) => const [
              MMDropdownItem(value: 'import', icon: MMIcons.import, child: Text('Import')),
              MMDropdownItem(value: 'delete', enabled: false, icon: MMIcons.trash, child: Text('Delete')),
            ],
          ),
        ),
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.byIcon(MMIcons.import), findsOneWidget);
      expect(find.byIcon(MMIcons.trash), findsOneWidget);
      expect(tester.getRect(find.byIcon(MMIcons.import)).right, lessThan(tester.getRect(find.text('Import')).left));
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(find.text('Import'), findsOneWidget);
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(selected, 'import');
      expect(find.text('Import'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  for (final phone in [false, true]) {
    testWidgets('context menu preserves icons and selection (phone: $phone)', (tester) async {
      if (phone) {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
      }
      late BuildContext context;
      await tester.pumpWidget(
        harness(
          MMInput(
            touchPlatform: phone,
            child: MMContextMenuHost(
              child: Builder(
                builder: (c) {
                  context = c;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      var selected = false;
      showMMMenu(
        context,
        position: const Offset(20, 20),
        entries: [
          MMMenuItem('Document', () => selected = true, icon: MMIcons.document, checked: true),
          const MMMenuItem('Generate', null, icon: MMIcons.generateMap, badge: MMBetaBadge()),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(MMIcons.document), findsOneWidget);
      expect(find.byIcon(MMIcons.generateMap), findsOneWidget);
      expect(find.byIcon(MMIcons.check), findsOneWidget);
      expect(find.byType(MMBetaBadge), findsOneWidget);
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();
      expect(selected, isFalse);
      await tester.tap(find.text('Document'));
      await tester.pumpAndSettle();
      expect(selected, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
