import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

StudySetContent _tree() {
  final parents = <String, String?>{
    for (final id in ['a', 'b', 'c', 'd']) id: null,
    for (final id in ['a', 'b', 'c', 'd']) ...{'${id}1': id, '${id}2': id, '${id}11': '${id}1', '${id}12': '${id}1'},
  };
  return StudySetContent(
    cards: [
      for (final id in parents.keys) Card(id: id, kind: CardKind.topic, title: 'Topic $id', createdAt: DateTime(2026)),
    ],
    nodes: [
      for (final (i, e) in parents.entries.indexed) MapNode(cardId: e.key, parentId: e.value, order: i.toDouble()),
    ],
  );
}

void main() {
  testWidgets('clicking fold controls changes only the branch beside the clicked control', (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final transform = TransformationController();
    final focus = FocusNode();
    addTearDown(transform.dispose);
    addTearDown(focus.dispose);
    var content = _tree();
    final calls = <String>[];
    final editor = StudySetEditor(newId: () => throw UnimplementedError(), now: () => DateTime(2026));
    late StateSetter rebuild;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return MaterialApp(
            theme: MMTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MindMapCanvas(
                content: content,
                rootTitle: 'Root',
                selectedCardId: 'd',
                flashCardId: null,
                transformation: transform,
                focusNode: focus,
                onSelect: (_) {},
                onReveal: (_) {},
                onRename: (_) {},
                onDelete: () {},
                onMove: (_, _, _) {},
                onToggleCollapsed: (id) => setState(() {
                  calls.add(id);
                  content = editor.setCollapsed(content, id, collapsed: !content.node(id)!.collapsed);
                }),
                onNavigate: (_) {},
                onAddChild: () {},
                onShift: (_) {},
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    Finder controlBeside(String id) {
      final node = tester.getRect(find.byKey(ValueKey(id)));
      final controls = find.byWidgetPredicate(
        (w) => w is MMInteractive && (w.tooltip == 'Collapse' || w.tooltip == 'Expand'),
      );
      final nearest = controls.evaluate().toList()
        ..sort((a, b) {
          double distance(Element e) {
            final rect = tester.getRect(find.byWidget(e.widget));
            return (rect.center - node.center).distance;
          }

          return distance(a).compareTo(distance(b));
        });
      final result = find.byWidget(nearest.first.widget);
      final rect = tester.getRect(result);
      expect(rect.center.dy, closeTo(node.center.dy, 1));
      expect(
        (rect.center.dx - node.center.dx).abs(),
        closeTo(node.width / 2 + rect.width / 2 + 3 * mapScale(transform.value), 1),
      );
      return result;
    }

    // A previous asynchronous fold completes while the next mouse click is
    // held down. Inserting/removing controls on either side must not retarget it.
    for (final (pressed, changed, collapsed) in [
      ('c1', 'd', true),
      ('a1', 'd', true),
      ('c1', 'd', false),
      ('d1', 'a', true),
    ]) {
      rebuild(() {
        content = _tree();
        if (!collapsed) content = editor.setCollapsed(content, changed, collapsed: true);
      });
      await tester.pumpAndSettle();
      calls.clear();
      final press = await tester.startGesture(tester.getCenter(controlBeside(pressed)), kind: PointerDeviceKind.mouse);
      rebuild(() => content = editor.setCollapsed(content, changed, collapsed: collapsed));
      await tester.pump();
      await press.up();
      await tester.pumpAndSettle();
      expect(calls, [pressed], reason: 'An update to $changed must not change the pending click on $pressed');
    }
    // If the pressed node itself disappears, cancel rather than activate a
    // surviving control that happens to take its place in the widget list.
    rebuild(() => content = _tree());
    await tester.pumpAndSettle();
    calls.clear();
    final removed = await tester.startGesture(tester.getCenter(controlBeside('c1')), kind: PointerDeviceKind.mouse);
    rebuild(() => content = editor.setCollapsed(content, 'c', collapsed: true));
    await tester.pump();
    await removed.up();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);

    rebuild(() => content = _tree());
    await tester.pumpAndSettle();

    for (final id in ['a1', 'c1', 'b1', 'd1', 'a', 'c', 'b', 'd', 'b', 'a', 'd', 'c', 'd1', 'a1', 'c1', 'b1']) {
      final before = {for (final n in content.nodes) n.cardId: n.collapsed};
      await tester.tap(controlBeside(id), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(calls.last, id, reason: 'The button beside $id must dispatch $id');
      for (final n in content.nodes) {
        expect(n.collapsed, n.cardId == id ? !before[n.cardId]! : before[n.cardId]);
      }
      for (final n in content.nodes) {
        var visible = true;
        var parent = n.parentId;
        while (parent != null) {
          final ancestor = content.node(parent)!;
          if (ancestor.collapsed) visible = false;
          parent = ancestor.parentId;
        }
        expect(find.byKey(ValueKey(n.cardId)), visible ? findsOneWidget : findsNothing);
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
