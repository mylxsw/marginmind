import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';

import 'ipad_adaptation_test.dart' show tablet;

void main() {
  for (final size in [const Size(834, 1194), const Size(744, 1133), const Size(1194, 834), const Size(600, 900)]) {
    for (final mode in [MMSplitMode.split, MMSplitMode.secondary]) {
      for (final action in ['child', 'sibling']) {
        testWidgets('iPad $size $mode $action keeps the new node focused through keyboard animation', (tester) async {
          addTearDown(tester.view.resetViewInsets);
          final container = await tablet(tester, size);
          final provider = workspaceProvider('demo-1');
          final controller = container.read(provider.notifier);
          controller.setLayout(mode);
          controller.selectCard('c3');
          await tester.pumpAndSettle();
          final split = find.byType(MMSplitView);
          final axis = tester.widget<MMSplitView>(split).axis;
          await tester.tap(find.byKey(ValueKey('node-bar-$action')));
          await tester.pumpAndSettle();
          final id = container.read(provider).editingCardId;
          expect(id, isNotNull);
          final canvasState = tester.state(find.byType(MindMapCanvas));
          final editable = find.byType(EditableText);
          final focus = tester.widget<EditableText>(editable).focusNode;
          expect(focus.hasFocus, isTrue);
          tester.testTextInput.log.clear();
          for (final inset in [120.0, 240.0, 360.0, 420.0]) {
            tester.view.viewInsets = FakeViewPadding(bottom: inset);
            await tester.pumpAndSettle();
            expect(tester.widget<MMSplitView>(split).axis, axis, reason: 'keyboard does not rotate the window');
            expect(tester.state(find.byType(MindMapCanvas)), same(canvasState));
            expect(container.read(provider).editingCardId, id);
            expect(focus.hasFocus, isTrue);
            expect(tester.testTextInput.isVisible, isTrue);
            expect(tester.takeException(), isNull);
          }
          expect(tester.testTextInput.log.where((call) => call.method == 'TextInput.hide'), isEmpty);
          tester.testTextInput.enterText('Keyboard stays open');
          final textController = tester.widget<EditableText>(editable).controller;
          final value = textController.value;
          for (final inset in [360.0, 240.0, 120.0, 0.0]) {
            tester.view.viewInsets = FakeViewPadding(bottom: inset);
            await tester.pumpAndSettle();
            expect(tester.state(find.byType(MindMapCanvas)), same(canvasState));
            expect(tester.widget<EditableText>(editable).focusNode, same(focus));
            expect(textController.value, value);
            expect(container.read(provider).editingCardId, id);
            expect(focus.hasFocus, isTrue);
          }
          expect(tester.testTextInput.log.where((call) => call.method == 'TextInput.hide'), isEmpty);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(controller.content.card(id!)!.title, 'Keyboard stays open');
        });
      }
    }
  }
}
