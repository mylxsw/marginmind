import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('$kind selects on release and double tap activates without selecting twice', (tester) async {
      var selects = 0;
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: MMInteractive(
              immediateTap: true,
              onTap: () => selects++,
              onDoubleTap: () => opens++,
              builder: (_, state) => SizedBox(width: 200, height: 100, child: Text('${state.pressed}')),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(MMInteractive), kind: kind);
      expect(selects, 1);
      expect(opens, 0);
      // Rebuilding the selected node must preserve the tap sequence.
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byType(MMInteractive), kind: kind);
      expect(selects, 1);
      expect(opens, 1);
      await tester.pump();
      expect(find.text('false'), findsOneWidget);
      // A third click starts a new pair; the timeout leaves ordinary taps alone.
      await tester.tap(find.byType(MMInteractive), kind: kind);
      expect(selects, 2);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
      await tester.tap(find.byType(MMInteractive), kind: kind);
      expect(selects, 3);
      expect(opens, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('child controls and secondary clicks do not select or activate the parent', (tester) async {
    var selects = 0;
    var opens = 0;
    var childTaps = 0;
    var menus = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MMInteractive(
            immediateTap: true,
            onTap: () => selects++,
            onDoubleTap: () => opens++,
            onSecondaryTap: () => menus++,
            builder: (_, _) => SizedBox(
              width: 200,
              height: 100,
              child: Center(
                child: GestureDetector(onTap: () => childTaps++, child: const Text('Child')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Child'));
    expect(childTaps, 1);
    expect(selects, 0);
    await tester.tap(find.byType(MMInteractive), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    expect(menus, 1);
    expect(selects, 0);
    expect(opens, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('drag and cancelled pointer do not select; distant taps do not activate', (tester) async {
    var selects = 0;
    var opens = 0;
    var drags = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GestureDetector(
          onPanUpdate: (_) => drags++,
          child: Center(
            child: MMInteractive(
              immediateTap: true,
              onTap: () => selects++,
              onDoubleTap: () => opens++,
              builder: (_, _) => const SizedBox(width: 400, height: 100),
            ),
          ),
        ),
      ),
    );
    final node = find.byType(MMInteractive);
    await tester.drag(node, const Offset(80, 0));
    expect(drags, greaterThan(0));
    expect(selects, 0);
    final cancelled = await tester.startGesture(tester.getCenter(node));
    await cancelled.cancel();
    expect(selects, 0);
    final rect = tester.getRect(node);
    await tester.tapAt(rect.centerLeft + const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(rect.centerRight - const Offset(20, 0));
    expect(selects, 2);
    expect(opens, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keyboard and accessibility activation still select; disabled surfaces ignore taps', (tester) async {
    final semantics = tester.ensureSemantics();
    var selects = 0;
    var opens = 0;
    var enabled = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return Center(
              child: MMInteractive(
                immediateTap: true,
                autofocus: true,
                enabled: enabled,
                semanticLabel: 'Node',
                onTap: () => selects++,
                onDoubleTap: () => opens++,
                builder: (_, _) => const SizedBox(width: 200, height: 100),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selects, 1);
    final node = tester.getSemantics(find.bySemanticsLabel('Node'));
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(type: SemanticsAction.tap, nodeId: node.id, viewId: tester.view.viewId),
    );
    expect(selects, 2);
    rebuild(() => enabled = false);
    await tester.pump();
    await tester.tap(find.byType(MMInteractive));
    await tester.pump(kDoubleTapTimeout);
    expect(selects, 2);
    expect(opens, 0);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });
}
