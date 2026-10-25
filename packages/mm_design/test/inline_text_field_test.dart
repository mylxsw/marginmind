import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

import 'harness.dart';

void main() {
  late TextEditingController controller;
  late FocusNode focus;
  late List<String> calls;

  setUp(() {
    controller = TextEditingController(text: 'Topic');
    focus = FocusNode();
    calls = [];
  });
  tearDown(() {
    controller.dispose();
    focus.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      harness(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 200,
              child: MMInlineTextField(
                controller: controller,
                focusNode: focus,
                style: MMTypography.headline,
                semanticLabel: 'Topic',
                onSubmitted: () => calls.add('submit'),
                onCancel: () => calls.add('cancel'),
                onTapOutside: () => calls.add('outside'),
              ),
            ),
            const SizedBox(width: 200, height: 100),
          ],
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
  }

  testWidgets('Enter and keypad Enter submit, Esc cancels, other keys type', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(calls, ['submit', 'submit', 'cancel']);
    expect(focus.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField), '长标题会换行 long title that wraps onto more lines');
    await tester.pump();
    expect(tester.getSize(find.byType(TextField)).height, greaterThan(30));
    expect(find.bySemanticsLabel('Topic'), findsOneWidget);
  });

  testWidgets('while an input method composes, Enter and Esc belong to it', (tester) async {
    await pump(tester);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'zhong',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      ),
    );
    await tester.pump();
    expect(MMInlineTextField.isComposing(controller.value), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(calls, isEmpty);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: '中', selection: TextSelection.collapsed(offset: 1)),
    );
    await tester.pump();
    expect(MMInlineTextField.isComposing(controller.value), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, ['submit']);
    expect(controller.text, '中');
  });

  testWidgets('a click outside the focused field is reported', (tester) async {
    await pump(tester);
    await tester.tapAt(tester.getBottomLeft(find.byType(Column)) + const Offset(10, -10));
    await tester.pump();
    expect(calls, ['outside']);
  });
}
