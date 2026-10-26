import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'edit_transaction_test.dart' show FailingRepository;
import 'helpers.dart';
import 'mind_map_cache_test.dart' show fixture;
import 'workspace_test.dart' show openFirstSet;

final _field = find.byType(MMInlineTextField);
const _excerpt = '这条先陡后平的曲线，被称为遗忘曲线。';

TextEditingController _text(WidgetTester tester) => tester.widget<MMInlineTextField>(_field).controller;

/// Selects a node with a single click (which waits out the double-click).
Future<void> _select(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

String _json(StudySetContent c) => jsonEncode(c.toJson());

void main() {
  testWidgets('corner plus creates and edits one child under its marked node', (tester) async {
    final container = await openFirstSet(tester);
    final provider = workspaceProvider('demo-1');
    final controller = container.read(provider.notifier);
    final topic = controller.content.cards.firstWhere((c) => c.title == '对策一：间隔重复');
    final canvas = tester.widget<MindMapCanvas>(find.byType(MindMapCanvas));
    for (final parent in [null, topic.id]) {
      for (final scale in [0.5, 1.17]) {
        controller.selectCard(parent);
        await tester.pumpAndSettle();
        final transform = canvas.transformation;
        transform.value = zoomMapAt(
          transform.value,
          tester.getSize(find.byType(MindMapCanvas)).center(Offset.zero),
          scale / mapScale(transform.value),
        );
        await tester.pumpAndSettle();
        final before = controller.content.cards.map((c) => c.id).toSet();
        final plus = find.byKey(const ValueKey('excerpt-target'));
        // Exercise the padded area outside the visible blue circle as well.
        final bounds = tester.getRect(plus);
        await tester.tapAt(bounds.center + Offset(0, -bounds.height * 0.4));
        await tester.pumpAndSettle();
        final added = controller.content.cards.where((c) => !before.contains(c.id)).toList();
        expect(added, hasLength(1));
        expect(controller.content.node(added.single.id)!.parentId, parent);
        expect(container.read(provider).editingCardId, added.single.id);
        expect(_field, findsOneWidget);
        tester.testTextInput.enterText('Corner child $parent $scale');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(controller.content.card(added.single.id)!.title, 'Corner child $parent $scale');
      }
    }
    await settleHud(tester);
  });

  group('E-01 the node becomes a text field and the map follows it', () {
    testWidgets('no dialog; the node widens and its neighbors move smoothly', (tester) async {
      final container = await openFirstSet(tester);
      final excerptLeft = tester.getTopLeft(find.text(_excerpt)).dx;
      await doubleTap(tester, find.text('遗忘的规律'));
      expect(_field, findsOneWidget);
      expect(find.byType(MMSheet), findsNothing);
      expect(container.read(workspaceProvider('demo-1')).editingCardId, 'c3');
      expect(_text(tester).selection, const TextSelection(baseOffset: 0, extentOffset: 5));
      final width = tester.getSize(_field).width;
      // The field lays out exactly like the measured title: no early wrap.
      expect(tester.getSize(_field).height, lessThan(20));

      tester.testTextInput.enterText('遗忘的规律与记忆巩固');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final midway = tester.getTopLeft(find.text(_excerpt)).dx;
      // Retarget an animation before it finishes: its first frame must start
      // at the currently displayed position, not the previous layout target.
      tester.testTextInput.enterText('遗忘的规律与记忆巩固和练习');
      await tester.pump();
      expect(tester.getTopLeft(find.text(_excerpt)).dx, closeTo(midway, 0.01));
      await tester.pumpAndSettle();
      final settled = tester.getTopLeft(find.text(_excerpt)).dx;
      expect(tester.getSize(_field).width, greaterThan(width));
      expect(settled, greaterThan(excerptLeft));
      expect(midway, greaterThan(excerptLeft));
      expect(midway, lessThan(settled));

      // Wrapping makes the node taller; the field still fits its text.
      tester.testTextInput.enterText('遗忘的规律与记忆巩固，以及间隔重复为什么比集中练习更有效');
      await tester.pumpAndSettle();
      expect(tester.getSize(_field).height, greaterThan(30));
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_field, findsNothing);
      expect(find.text('遗忘的规律与记忆巩固，以及间隔重复为什么比集中练习更有效'), findsOneWidget);
      await settleHud(tester);
    });
  });

  group('E-02 entering and leaving', () {
    testWidgets('F2 and Space open the field; Esc restores the title', (tester) async {
      final container = await openFirstSet(tester);
      final state = container.read(workspaceProvider('demo-1').notifier);
      for (final key in [LogicalKeyboardKey.f2, LogicalKeyboardKey.space]) {
        await _select(tester, '对策一：间隔重复');
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(_field, findsOneWidget, reason: '$key');
        tester.testTextInput.enterText('临时');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(_field, findsNothing);
        expect(find.text('对策一：间隔重复'), findsOneWidget);
      }
      expect(container.read(workspaceProvider('demo-1')).canUndo, isFalse);
      expect(state.content.card('c4')!.title, '对策一：间隔重复');
      // The map keeps keyboard focus: arrows still move the selection.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(container.read(workspaceProvider('demo-1')).selectedCardId, 'c3');
      await settleHud(tester);
    });

    testWidgets('typing on a selected topic replaces its title', (tester) async {
      final container = await openFirstSet(tester);
      await _select(tester, '对策一：间隔重复');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pumpAndSettle();
      expect(_text(tester).text, 'r');
      expect(_text(tester).selection, const TextSelection.collapsed(offset: 1));
      tester.testTextInput.enterText('retrieval');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1').notifier).content.card('c4')!.title, 'retrieval');
      // Shortcuts with ⌘ / Ctrl are not typing.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(_field, findsNothing);
      await settleHud(tester);
    });

    testWidgets('clicking elsewhere confirms', (tester) async {
      final container = await openFirstSet(tester);
      await doubleTap(tester, find.text('对策一：间隔重复'));
      tester.testTextInput.enterText('点别处确认');
      await tester.pump();
      await tester.tap(find.text('遗忘的规律'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(_field, findsNothing);
      final content = container.read(workspaceProvider('demo-1').notifier).content;
      expect(content.card('c4')!.title, '点别处确认');
      expect(container.read(workspaceProvider('demo-1')).selectedCardId, 'c3');
      await settleHud(tester);
    });
  });

  testWidgets('the context menu edits in place', (tester) async {
    await openFirstSet(tester);
    await tester.tap(find.text('对策一：间隔重复'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(_field, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_field, findsNothing);
    await settleHud(tester);
  });

  testWidgets('review fixes: switching fields, menu commands, hidden map', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    // Straight from one field to a new one: typing reaches the new field.
    await doubleTap(tester, find.text('对策一：间隔重复'));
    await tester.tap(find.byIcon(MMIcons.addTopic));
    await tester.pumpAndSettle();
    expect(_text(tester).text, 'New Topic');
    tester.testTextInput.enterText('第二个');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.content.cards.where((c) => c.title == '第二个'), hasLength(1));

    // Commands that change content wait while a title is typed.
    final cards = controller.content.cards.length;
    await tester.tap(find.byIcon(MMIcons.addTopic));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.content.cards.length, cards);

    // Hiding the map confirms the edit instead of keeping an unseen field.
    await doubleTap(tester, find.text('第二个'));
    tester.testTextInput.enterText('藏起来');
    await tester.tap(find.byIcon(MMIcons.layoutReader));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).editingCardId, isNull);
    expect(controller.content.cards.where((c) => c.title == '藏起来'), hasLength(1));
    await settleHud(tester);
  });

  group('E-03 input methods', () {
    testWidgets('Enter picks a candidate while pinyin is composing', (tester) async {
      final container = await openFirstSet(tester);
      await doubleTap(tester, find.text('对策一：间隔重复'));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'jian',
          selection: TextSelection.collapsed(offset: 4),
          composing: TextRange(start: 0, end: 4),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_field, findsOneWidget);
      expect(container.read(workspaceProvider('demo-1').notifier).content.card('c4')!.title, '对策一：间隔重复');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: '间隔', selection: TextSelection.collapsed(offset: 2)),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_field, findsNothing);
      expect(container.read(workspaceProvider('demo-1').notifier).content.card('c4')!.title, '间隔');
      await settleHud(tester);
    });
  });

  group('E-05 a new topic left empty is not created', () {
    testWidgets('Esc right after adding leaves no node and no undo step', (tester) async {
      final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
      final container = await openFirstSet(tester, content: repo);
      final before = _json(await repo.load('demo-1'));
      await _select(tester, '遗忘的规律');
      await tester.tap(find.byIcon(MMIcons.addTopic));
      await tester.pumpAndSettle();
      expect(_text(tester).text, 'New Topic');
      expect(_text(tester).selection, const TextSelection(baseOffset: 0, extentOffset: 9));
      expect(container.read(workspaceProvider('demo-1')).canUndo, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_field, findsNothing);
      expect(find.text('New Topic'), findsNothing);
      expect(_json(await repo.load('demo-1')), before);
      final state = container.read(workspaceProvider('demo-1'));
      expect(state.canUndo, isFalse);
      expect(state.selectedCardId, 'c3');
      await settleHud(tester);
    });

    testWidgets('Tab adds a child that commits with its title as one undo step', (tester) async {
      final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
      final container = await openFirstSet(tester, content: repo);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      final before = _json(await repo.load('demo-1'));
      await _select(tester, '对策一：间隔重复');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      tester.testTextInput.enterText('提取练习');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final created = controller.content.cards.singleWhere((c) => c.title == '提取练习');
      expect(controller.content.node(created.id)!.parentId, 'c4');
      expect(container.read(workspaceProvider('demo-1')).canUndo, isTrue);
      await controller.undo();
      await tester.pumpAndSettle();
      expect(_json(await repo.load('demo-1')), before);
      expect(container.read(workspaceProvider('demo-1')).canUndo, isFalse);

      // Clearing the text and confirming also drops the new node.
      await tester.tap(find.byIcon(MMIcons.addTopic));
      await tester.pumpAndSettle();
      tester.testTextInput.enterText('  ');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_json(await repo.load('demo-1')), before);
      await settleHud(tester);
    });
  });

  testWidgets('a new topic stays open while the content stream lags behind the write', (tester) async {
    final repo = _LaggingRepository({'demo-1': demoContent()});
    final container = await openFirstSet(tester, content: repo);
    await tester.tap(find.byIcon(MMIcons.addTopic));
    await tester.pump();
    await tester.pump();
    expect(_text(tester).text, 'New Topic');
    await tester.pumpAndSettle();
    expect(_field, findsOneWidget);
    tester.testTextInput.enterText('慢一点');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      container.read(workspaceProvider('demo-1').notifier).content.cards.where((c) => c.title == '慢一点'),
      hasLength(1),
    );
    await settleHud(tester);
  });

  group('E-07 undo granularity', () {
    testWidgets('one edit is one undo step; ⌘Z while typing only undoes text', (tester) async {
      final container = await openFirstSet(tester);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      await doubleTap(tester, find.text('对策一：间隔重复'));
      for (final text in ['间', '间隔', '间隔重复']) {
        tester.testTextInput.enterText(text);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.content.card('c4')!.title, '间隔重复');

      await doubleTap(tester, find.text('间隔重复'));
      // Text undo records a change made after the field settles in.
      await tester.pump(const Duration(seconds: 1));
      tester.testTextInput.enterText('间隔重复法');
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(_field, findsOneWidget);
      expect(_text(tester).text, '间隔重复');
      expect(controller.content.card('c4')!.title, '间隔重复');
      expect(container.read(workspaceProvider('demo-1')).canUndo, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await controller.undo();
      await tester.pumpAndSettle();
      expect(controller.content.card('c4')!.title, '对策一：间隔重复');
      expect(container.read(workspaceProvider('demo-1')).canUndo, isFalse);
      await settleHud(tester);
    });
  });

  group('controller', () {
    late ProviderContainer container;
    late FailingRepository repo;
    late WorkspaceController controller;
    WorkspaceState state() => container.read(workspaceProvider('demo-1'));

    setUp(() async {
      repo = FailingRepository({'demo-1': demoContent()});
      container = ProviderContainer(overrides: await testOverrides(content: repo));
      container.listen(workspaceProvider('demo-1'), (_, _) {});
      await container.read(contentProvider('demo-1').future);
      controller = container.read(workspaceProvider('demo-1').notifier);
    });
    tearDown(() => container.dispose());

    test('only existing cards open; one edit at a time; blank or unchanged text writes nothing', () async {
      controller.beginEditing('c5');
      controller.beginEditing('missing');
      expect(state().editingCardId, isNull);
      controller.beginEditing('c3');
      controller.beginEditing('c4');
      expect(state().editingCardId, 'c3');
      expect(state().selectedCardId, 'c3');
      expect(await controller.addTopicAndEdit('New'), isNull);
      await controller.finishEditing('   ');
      expect(state().editingCardId, isNull);
      controller.beginEditing('c3');
      await controller.finishEditing(' 遗忘的规律 ');
      await controller.finishEditing('again');
      await controller.cancelEditing();
      expect(state().canUndo, isFalse);
      expect(controller.content.card('c3')!.title, '遗忘的规律');
    });

    test('structural creation handles root, missing selection and write failures without a transaction leak', () async {
      controller.selectCard(null);
      expect(await controller.addTopicAndEdit('New', siblingBefore: false), isNull);
      expect(await controller.addTopicAndEdit('New', asParent: true), isNull);
      await controller.promoteSelected();
      controller.selectCard('missing');
      expect(await controller.addTopicAndEdit('New', siblingBefore: true), isNull);
      controller.selectCard('c3');
      repo.failNext = true;
      await expectLater(controller.addTopicAndEdit('New', asParent: true), throwsStateError);
      expect(state().editingCardId, isNull);
      await controller.rename('c3', 'still undoable');
      expect(state().canUndo, isTrue);
    });

    test('a second creation while the first is still writing is ignored', () async {
      final first = controller.addTopicAndEdit('A');
      final second = controller.addTopicAndEdit('B');
      controller.beginEditing('c3');
      expect(await second, isNull);
      final card = (await first)!;
      expect(state().editingCardId, card.id);
      await controller.finishEditing('A');
      expect(state().canUndo, isTrue);
      expect(controller.content.cards.where((c) => c.title == 'B'), isEmpty);
    });

    test('a node that fails to be created leaves no transaction open', () async {
      repo.failNext = true;
      await expectLater(controller.addTopicAndEdit('New'), throwsStateError);
      expect(state().editingCardId, isNull);
      await controller.rename('c3', 'still undoable');
      expect(state().canUndo, isTrue);
    });

    test('a failed title write still ends the edit and keeps the new node', () async {
      final card = (await controller.addTopicAndEdit('New'))!;
      expect(state().editingCardId, card.id);
      repo.failNext = true;
      await expectLater(controller.finishEditing('Named'), throwsStateError);
      expect(state().editingCardId, isNull);
      expect(state().canUndo, isTrue);
      expect(controller.content.card(card.id)!.title, 'New');
    });

    test('dropping a new node returns the selection to where it was', () async {
      controller.selectCard('c4');
      await controller.addTopicAndEdit('New', asChild: true);
      await controller.cancelEditing();
      expect(state().selectedCardId, 'c4');
      await controller.removeCards(['c4']);
      await controller.addTopicAndEdit('New');
      controller.selectCard(null);
      await controller.finishEditing('');
      expect(state().selectedCardId, isNull);
    });
  });

  group('canvas', () {
    late TransformationController transform;
    late FocusNode focus;
    setUp(() {
      transform = TransformationController();
      focus = FocusNode();
    });
    tearDown(() {
      transform.dispose();
      focus.dispose();
    });

    Future<void> pump(
      WidgetTester tester, {
      required StudySetContent content,
      String? editing,
      List<String>? log,
      bool reduceMotion = false,
      bool show = true,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MMAppearance(
          reduceMotion: reduceMotion,
          child: Scaffold(
            body: show
                ? MindMapCanvas(
                    content: content,
                    rootTitle: 'Root',
                    selectedCardId: editing,
                    flashCardId: null,
                    transformation: transform,
                    focusNode: focus,
                    editingCardId: editing,
                    onEditDone: (text) => log?.add('done:$text'),
                    onEditCancel: () => log?.add('cancel'),
                    onSelect: (_) {},
                    onReveal: (_) {},
                    onRename: (_) {},
                    onDelete: () {},
                    onMove: (_, _, _) {},
                    onToggleCollapsed: (_) {},
                    onNavigate: (_) {},
                    onAddChild: () {},
                    onShift: (_) {},
                  )
                : const SizedBox(),
          ),
        ),
      ),
    );

    testWidgets('a node removed while edited cancels; closing the map confirms', (tester) async {
      final log = <String>[];
      final content = fixture(4);
      await pump(tester, content: content, editing: 'c0', log: log);
      await tester.pumpAndSettle();
      expect(_field, findsOneWidget);
      // Keys typed into the field never reach the map's own shortcuts.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(log, isEmpty);
      final removed = content.copyWith(nodes: content.nodes.where((n) => n.cardId != 'c0').toList());
      await pump(tester, content: removed, editing: 'c0', log: log);
      await tester.pumpAndSettle();
      expect(log, ['cancel']);

      log.clear();
      await pump(tester, content: content, editing: 'c3', log: log);
      await tester.pumpAndSettle();
      tester.testTextInput.enterText('kept');
      await pump(tester, content: content, editing: 'c3', log: log, show: false);
      await tester.pumpAndSettle();
      expect(log, ['done:kept']);
    });

    testWidgets('switching to another app keeps the edit open', (tester) async {
      final log = <String>[];
      await pump(tester, content: fixture(4), editing: 'c0', log: log);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(log, isEmpty);
      expect(_field, findsOneWidget);
    });

    testWidgets('with reduced motion the layout changes at once', (tester) async {
      final content = fixture(4);
      await pump(tester, content: content, editing: 'c0', reduceMotion: true);
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.text('Node 3 中文')).dy;
      tester.testTextInput.enterText('A title long enough to wrap onto a second line in the node');
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.getTopLeft(find.text('Node 3 中文')).dy, greaterThan(before));
    });
  });
}

/// Delivers stream events a moment after each write, like the file store.
class _LaggingRepository extends InMemoryStudySetContentRepository {
  _LaggingRepository(super.initial);

  @override
  Stream<StudySetContent> watch(String studySetId) => super
      .watch(studySetId)
      .asyncMap((c) => Future<StudySetContent>.delayed(const Duration(milliseconds: 200), () => c));
}
