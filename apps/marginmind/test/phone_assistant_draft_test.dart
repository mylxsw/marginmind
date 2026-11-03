import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:mm_design/mm_design.dart';

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
    expect(find.byKey(const ValueKey('assistant-close')), findsNothing);
    final model = tester.getRect(find.byKey(const ValueKey('assistant-model')));
    final send = tester.getRect(find.byKey(const ValueKey('assistant-send')));
    final voice = tester.getRect(find.byKey(const ValueKey('assistant-voice')));
    expect(model.center.dy, closeTo(send.center.dy, 1));
    expect(voice.center.dy, closeTo(send.center.dy, 1));
    await tester.fling(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, 700), 1400);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    expect(find.text('Keep this unsent question'), findsOneWidget);
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, false);
    await tester.tap(find.byKey(const ValueKey('assistant-phone-options')));
    await tester.pumpAndSettle();
    expect(find.byType(MMBottomSheet), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
