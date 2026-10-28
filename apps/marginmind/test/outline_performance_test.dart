import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/outline_view.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

final _now = DateTime(2026);
StudySetContent _fixture(int count) => StudySetContent(
  cards: [for (var i = 0; i < count; i++) Card(id: 'c$i', kind: CardKind.topic, title: 'Row $i', createdAt: _now)],
  nodes: [for (var i = 0; i < count; i++) MapNode(cardId: 'c$i', parentId: null, order: i.toDouble())],
);

class _CountingContent extends StudySetContent {
  _CountingContent(StudySetContent content) : super(cards: content.cards, nodes: content.nodes);
  final _lookups = [0];
  int get lookups => _lookups[0];
  set lookups(int value) => _lookups[0] = value;
  @override
  Card? card(String id) {
    lookups++;
    return super.card(id);
  }

  @override
  List<MapNode> childrenOf(String? parentId, {String mapId = MindMap.defaultId}) {
    lookups++;
    return super.childrenOf(parentId, mapId: mapId);
  }
}

class _Harness {
  _Harness(this.tester) {
    addTearDown(focus.dispose);
  }
  final WidgetTester tester;
  final focus = FocusNode();
  final key = GlobalKey();
  String? selection;
  Set<String> selections = {};
  int selectCalls = 0;
  int toggles = 0;
  String? editing;
  Locale locale = const Locale('en');
  Future<void> pump(StudySetContent content, {String mapId = MindMap.defaultId, String title = 'Root'}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => OutlineView(
              key: key,
              content: content,
              mapId: mapId,
              rootTitle: title,
              selectedCardId: selection,
              selectedCardIds: selections,
              focusNode: focus,
              onSelect: (id) => setState(() {
                selection = id;
                selectCalls++;
              }),
              onToggleSelection: (id) => setState(() {
                toggles++;
                selections = selections.contains(id) ? selections.difference({id}) : {...selections, id};
              }),
              onReveal: (_) {},
              onRename: (id) => setState(() => editing = id),
              onDelete: () {},
              onAddChild: () {},
              onShift: (_) {},
              editingCardId: editing,
              onEditDone: (_, _) => setState(() => editing = null),
              onEditCancel: () => setState(() => editing = null),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('mouse selection is immediate, toggles once and keeps double-click editing', (tester) async {
    final h = _Harness(tester);
    await h.pump(_fixture(8));
    final first = tester.getCenter(find.text('Row 0'));
    final mouse = await tester.startGesture(first, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(h.selection, 'c0', reason: 'selection must not wait for tap/double-tap recognition');
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 350));
    expect(h.selectCalls, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(find.text('Row 1'), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(h.selections, {'c1'});
    expect(h.toggles, 1);
    await tester.tap(find.text('Row 1'), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await tester.pump(const Duration(milliseconds: 350));
    expect(h.selectCalls, 1, reason: 'right click must not select');
    await tester.tap(find.text('Row 2'), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('Row 2'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(h.editing, 'c2');
    expect(find.byType(MMInlineTextField), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.editing, isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('selection reuses tree data and untouched row widgets in a 500-node outline', (tester) async {
    final h = _Harness(tester);
    final content = _CountingContent(_fixture(500));
    await h.pump(content);
    final untouched = tester.widget<Text>(find.text('Row 3'));
    content.lookups = 0;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(h.selection, 'c0');
    expect(content.lookups, 0, reason: 'moving the selection must not scan the tree or look up each card again');
    expect(identical(tester.widget<Text>(find.text('Row 3')), untouched), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(h.selection, 'c1');
    expect(content.lookups, 0);
    expect(identical(tester.widget<Text>(find.text('Row 3')), untouched), isTrue);
  });

  testWidgets('touch scrolling does not select rows and touch taps still select', (tester) async {
    final h = _Harness(tester);
    await h.pump(_fixture(80));
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(h.selection, isNull);
    expect(h.selectCalls, 0);
    final row = find.text('Row 10');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(h.selection, 'c10');
    expect(h.selectCalls, 1);
  });

  testWidgets('cached rows refresh after edits, map switches and root title changes', (tester) async {
    final h = _Harness(tester);
    final content = _fixture(3);
    await h.pump(content);
    final updated = content.copyWith(
      cards: [
        content.cards.first.copyWith(title: 'Changed'),
        ...content.cards.skip(1),
      ],
      nodes: [
        ...content.nodes,
        const MapNode(cardId: 'c2', mapId: 'other', parentId: null, order: 0),
      ],
    );
    await h.pump(updated, title: 'New root');
    expect(find.text('Changed'), findsOneWidget);
    expect(find.text('Row 0'), findsNothing);
    expect(find.text('New root'), findsOneWidget);
    await h.pump(updated, mapId: 'other');
    expect(find.text('Row 2'), findsOneWidget);
    expect(find.text('Changed'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(h.selection, 'c2');
  });
}
