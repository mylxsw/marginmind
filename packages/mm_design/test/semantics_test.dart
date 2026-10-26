import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

import 'harness.dart';

/// Every semantics node under the app, in tree order.
List<SemanticsNode> _nodes(WidgetTester tester) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.renderObject(find.byType(MaterialApp)).owner!.semanticsOwner!.rootSemanticsNode!);
  return nodes;
}

/// How many nodes VoiceOver would read [text] in (label or value).
int _spoken(WidgetTester tester, String text) => _nodes(tester)
    .where((n) => n.label.split('\n').contains(text) || n.value == text)
    .fold(0, (sum, n) => sum + n.label.split('\n').where((part) => part == text).length + (n.value == text ? 1 : 0));

void main() {
  testWidgets('a button is named once, not by its label and its text', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(harness(MMButton(label: 'New Study Set', icon: MMIcons.add, onPressed: () {})));

    expect(_spoken(tester, 'New Study Set'), 1);
    expect(
      tester.getSemantics(find.byType(MMButton)),
      matchesSemantics(
        label: 'New Study Set',
        isButton: true,
        hasSelectedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a sidebar row reads its name and count once each', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      harness(
        SizedBox(
          width: 220,
          child: Column(
            children: [
              MMSidebarItem(
                icon: MMIcons.grid,
                label: 'All Study Sets',
                selected: true,
                trailing: const MMCount(6),
                onTap: () {},
              ),
              MMSidebarItem(icon: MMIcons.recent, label: 'Recent', onTap: () {}),
            ],
          ),
        ),
      ),
    );

    expect(_spoken(tester, 'All Study Sets'), 1);
    expect(_spoken(tester, '6'), 1);
    final all = tester.getSemantics(find.byType(MMSidebarItem).first);
    expect(all.label, 'All Study Sets\n6');
    expect(all.flagsCollection.isSelected, Tristate.isTrue);
    expect(all.flagsCollection.isButton, isTrue);
    expect(tester.getSemantics(find.byType(MMSidebarItem).last).label, 'Recent');
    semantics.dispose();
  });

  testWidgets('a labelled control drops its content and keeps its value', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      harness(
        MMInteractive(
          onTap: () {},
          semanticLabel: 'Quote',
          semanticValue: 'Page 3',
          builder: (_, _) => const Row(mainAxisSize: MainAxisSize.min, children: [Text('Quote'), MMCount(3)]),
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(MMInteractive));
    expect(node.label, 'Quote');
    expect(node.value, 'Page 3');
    expect(_spoken(tester, 'Quote'), 1);
    expect(_spoken(tester, '3'), 0);
    semantics.dispose();
  });

  testWidgets('without a label the content names the control and inner buttons stay reachable', (tester) async {
    final semantics = tester.ensureSemantics();
    var starred = 0;
    await tester.pumpWidget(
      harness(
        MMInteractive(
          onTap: () {},
          builder: (_, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Cognitive Science'),
              MMIconButton(icon: MMIcons.star, tooltip: 'Star', onPressed: () => starred++),
            ],
          ),
        ),
      ),
    );

    expect(_spoken(tester, 'Cognitive Science'), 1);
    expect(_spoken(tester, 'Star'), 1);
    await tester.tap(find.bySemanticsLabel('Star'));
    expect(starred, 1);
    semantics.dispose();
  });

  testWidgets('empty state can be just an icon and actions', (tester) async {
    await tester.pumpWidget(
      harness(
        MMEmptyState(
          icon: MMIcons.studySet,
          actions: [
            MMButton(label: 'New', onPressed: () {}),
            MMButton(label: 'Sample', onPressed: () {}),
          ],
        ),
      ),
    );
    expect(find.byIcon(MMIcons.studySet), findsOneWidget);
    expect(find.byType(MMButton), findsNWidgets(2));
    expect(find.byType(Text), findsNWidgets(2)); // the two button titles only
    final icon = tester.getRect(find.byIcon(MMIcons.studySet));
    final button = tester.getRect(find.byType(MMButton).first);
    expect(button.top, greaterThan(icon.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state with title and message keeps its layout', (tester) async {
    await tester.pumpWidget(
      harness(const MMEmptyState(icon: MMIcons.search, title: 'No results', message: 'Try again')),
    );
    final title = tester.getRect(find.text('No results'));
    final message = tester.getRect(find.text('Try again'));
    expect(message.top - title.bottom, closeTo(8, 0.01));
    expect(title.top - tester.getRect(find.byIcon(MMIcons.search)).bottom, greaterThanOrEqualTo(16));
  });
}
