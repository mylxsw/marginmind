import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/map_selection_bar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'map_keyboard_test.dart' show focusMap, key;
import 'workspace_test.dart' show openFirstSet;

bool enabled(WidgetTester tester, String action) {
  final button = tester.widget(find.byKey(ValueKey('map-command-$action')));
  return switch (button) {
    MMToolbarButton() => button.onPressed != null,
    MMToolbarPreviewButton() => button.onPressed != null,
    _ => throw StateError('Unexpected toolbar button'),
  };
}

class _SlowRepository extends InMemoryStudySetContentRepository {
  _SlowRepository() : super({'demo-1': demoContent()});
  bool slow = false;

  @override
  Future<StudySetContent> update(String id, StudySetContent Function(StudySetContent) change) async {
    if (slow) await Future<void>.delayed(const Duration(milliseconds: 100));
    return super.update(id, change);
  }
}

void commandBarTests({bool native = false}) {
  for (final child in [true, false]) {
    testWidgets('new ${child ? 'child' : 'sibling'} keeps its toolbar while the text field has focus', (tester) async {
      final container = await openFirstSet(tester, showMapCommandBar: true);
      final provider = workspaceProvider('demo-1');
      final controller = container.read(provider.notifier);
      controller.selectCard('c3');
      await focusMap(tester);
      final top = tester.getRect(find.byType(MapCommandBar));
      await key(tester, child ? LogicalKeyboardKey.tab : LogicalKeyboardKey.enter);
      final id = container.read(provider).editingCardId!;
      expect(container.read(provider).selectedCardId, id);
      expect(controller.content.node(id)!.parentId, child ? 'c3' : null);
      expect(find.byType(MapNodeBar), findsOneWidget);
      expect(tester.widget<MMInlineTextField>(find.byType(MMInlineTextField)).focusNode.hasFocus, isTrue);
      expect(tester.getRect(find.byType(MapCommandBar)), top);
      final local = tester.getRect(find.byType(MapNodeBar));
      expect(local.top, greaterThanOrEqualTo(top.bottom + MMSpacing.s));
      expect(local.overlaps(tester.getRect(find.byKey(ValueKey(id)))), isFalse);
      await tester.enterText(find.byType(MMInlineTextField), 'New node');
      await key(tester, LogicalKeyboardKey.enter);
      expect(find.byType(MapNodeBar), findsOneWidget);
      expect(controller.content.card(id)!.title, 'New node');
      await settleHud(tester);
    }, semanticsEnabled: !native);
  }

  testWidgets('fixed actions follow no selection, root, single node, multiple nodes and connection mode', (
    tester,
  ) async {
    final container = await openFirstSet(tester, showMapCommandBar: true);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    expect(find.byType(MapCommandBar), findsOneWidget);
    final top = tester.getRect(find.byType(MapCommandBar));
    void expectActions(Set<String> available) {
      for (final action in ['child', 'sibling', 'relation', 'summary', 'note', 'image', 'tags', 'details']) {
        expect(enabled(tester, action), available.contains(action), reason: action);
      }
      expect(tester.getRect(find.byType(MapCommandBar)), top);
    }

    expectActions({'child', 'image'});
    controller.selectMapRoot();
    await tester.pumpAndSettle();
    expectActions({'child', 'image'});
    controller.selectCard('c3');
    await tester.pumpAndSettle();
    expectActions({'child', 'sibling', 'relation', 'summary', 'note', 'image', 'tags', 'details'});
    controller.selectCards(['c3', 'c4']);
    await tester.pumpAndSettle();
    expectActions({'relation', 'summary'});
    controller.selectCards(['c3', 'c6']);
    await tester.pumpAndSettle();
    expectActions({'relation'});
    // An unavailable action cannot start an edit or create a summary.
    await tester.tap(find.byKey(const ValueKey('map-command-summary')));
    await tester.pumpAndSettle();
    expect(controller.content.summaries, isEmpty);
    controller.selectCard('c3');
    await controller.addRelation();
    await tester.pumpAndSettle();
    expectActions({});
    controller.cancelConnecting();
    await settleHud(tester);
  }, semanticsEnabled: !native);

  for (final prefix in ['node-bar', 'map-command']) {
    testWidgets('$prefix saves edited text before adding another node over slow storage', (tester) async {
      final repository = _SlowRepository();
      final container = await openFirstSet(tester, content: repository, showMapCommandBar: true);
      final provider = workspaceProvider('demo-1');
      final controller = container.read(provider.notifier);
      controller.selectCard('c3');
      await controller.addTopicAndEdit('New topic', asChild: true);
      await tester.pumpAndSettle();
      final first = container.read(provider).editingCardId!;
      await tester.enterText(find.byType(MMInlineTextField), 'Keep this title');
      repository.slow = true;
      await tester.tap(find.byKey(ValueKey('$prefix-child')));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final second = container.read(provider).editingCardId!;
      expect(second, isNot(first));
      expect(controller.content.card(first)!.title, 'Keep this title');
      expect(controller.content.node(second)!.parentId, first);
      expect(find.byType(MapNodeBar), findsOneWidget);
      repository.slow = false;
      await controller.cancelEditing();
      await tester.pumpAndSettle();
      expect(controller.content.card(second), isNull);
      expect(controller.content.card(first)!.title, 'Keep this title');
      await controller.undo();
      await tester.pumpAndSettle();
      expect(controller.content.card(first), isNull, reason: 'creation plus typed text remains one undo step');
      await settleHud(tester);
    }, semanticsEnabled: !native);

    testWidgets('$prefix does not apply a command to the old selection after discarding an empty draft', (
      tester,
    ) async {
      final container = await openFirstSet(tester, showMapCommandBar: true);
      final provider = workspaceProvider('demo-1');
      final controller = container.read(provider.notifier);
      controller.selectCard('c3');
      final count = controller.content.cards.length;
      await controller.addTopicAndEdit('New topic', asChild: true);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(MMInlineTextField), '');
      await tester.tap(find.byKey(ValueKey('$prefix-child')));
      await tester.pumpAndSettle();
      expect(controller.content.cards, hasLength(count));
      expect(container.read(provider).editingCardId, isNull);
      expect(container.read(provider).selectedCardId, 'c3');
      await settleHud(tester);
    }, semanticsEnabled: !native);
  }
}

void main() => commandBarTests();
