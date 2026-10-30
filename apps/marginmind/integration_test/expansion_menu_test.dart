import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mm_platform/mm_platform.dart';

import '../test/assistant_support.dart';
import '../test/expansion_test.dart' show capture;
import '../test/map_keyboard_test.dart' show focusMap;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native expansion submenu matches selected design and remains interactive', (tester) async {
    await DesktopWindow.initialize(
      title: 'MarginMind — Expansion UI Check',
      minimumSize: const Size(1000, 700),
      initialSize: const Size(1280, 900),
    );
    final app = await openAssistantApp(
      tester,
      size: const Size(1280, 900),
      prefs: {'settings.appearance': 'dark', 'expansion.demo-1.depth': 2},
    );
    app.workspace.selectCard('c3');
    await focusMap(tester);
    await tester.tap(find.byKey(const ValueKey('node-bar-assistant')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-expand-ideas')));
    await tester.pumpAndSettle();
    final menu = tester.getRect(find.byKey(const ValueKey('assistant-quick-actions')));
    final settings = tester.getRect(find.byKey(const ValueKey('expansion-settings')));
    expect(settings.left - menu.right, closeTo(8, .01));
    expect(settings.top, menu.top);
    expect(settings.right, lessThanOrEqualTo(1280));
    expect(find.text('2 层'), findsOneWidget);
    await capture(tester, 'native-options-dark', clip: menu.expandToInclude(settings).inflate(8));
    await tester.tap(find.byKey(const ValueKey('expansion-direction-example')));
    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey('expansion-settings')), matching: find.byType(TextField)),
      '给出具体例子',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('expansion-settings')), findsNothing);
    expect(find.byKey(const ValueKey('assistant-quick-actions')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quick-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
