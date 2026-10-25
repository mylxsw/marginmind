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

  Future<void> pump(WidgetTester tester, {bool multiline = false, int? maxLines}) async {
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
                multiline: multiline,
                maxLines: maxLines,
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
    // Nothing leaks in from the Material input theme (e.g. letter spacing).
    expect(tester.widget<EditableText>(find.byType(EditableText)).style.letterSpacing, isNull);
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

  Future<void> shiftEnter(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  testWidgets('multiline: ⇧Enter replaces the selection with a line break; Enter still submits', (tester) async {
    await pump(tester, multiline: true);
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    await shiftEnter(tester);
    expect(controller.text, 'T\nic');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    controller.selection = const TextSelection.collapsed(offset: -1);
    await shiftEnter(tester);
    expect(controller.text, 'T\nic\n');
    expect(calls, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, ['submit']);
  });

  testWidgets('single-line fields submit on ⇧Enter and keep one line', (tester) async {
    await pump(tester, maxLines: 1);
    final height = tester.getSize(find.byType(TextField)).height;
    await shiftEnter(tester);
    expect(calls, ['submit']);
    expect(controller.text, 'Topic');
    await tester.enterText(find.byType(TextField), '长标题不会换行 long title that would wrap onto more lines');
    await tester.pump();
    expect(tester.getSize(find.byType(TextField)).height, height);
  });
}
