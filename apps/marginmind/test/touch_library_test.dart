import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
  for (final list in [false, true]) {
    testWidgets('long press opens the study set ${list ? 'list' : 'card'} menu and renames it', (tester) async {
      await pumpApp(tester);
      if (list) {
        await tester.tap(find.byIcon(MMIcons.list));
        await tester.pumpAndSettle();
      }
      await tester.longPress(find.text('注意力与专注').last);
      await tester.pumpAndSettle();
      expect(find.text('Rename…'), findsOneWidget);
      final row = find.ancestor(of: find.text('Rename…'), matching: find.byType(MMInteractive)).first;
      expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
      await tester.tap(find.text('Rename…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: find.byType(MMSheet), matching: find.byType(TextField)),
        'Renamed by touch',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Renamed by touch'), findsOneWidget);
    });
  }
}
