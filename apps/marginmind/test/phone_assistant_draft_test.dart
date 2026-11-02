import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';

import 'assistant_support.dart';

void main() {
  testWidgets('phone assistant closes without losing its unsent draft', (tester) async {
    final app = await openAssistantApp(
      tester,
      size: const Size(393, 852),
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    app.workspace.openDocument('c1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('assistant-input'));
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, false);
    await tester.enterText(input, 'Keep this unsent question');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assistant-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    expect(find.text('Keep this unsent question'), findsOneWidget);
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, false);
    expect(tester.takeException(), isNull);
  });
}
