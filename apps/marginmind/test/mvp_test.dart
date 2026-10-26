import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/library/library_controller.dart';
import 'package:marginmind/features/review/review_controller.dart';
import 'package:marginmind/features/review/review_screen.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';

void main() {
  group('workspace editing', () {
    late ProviderContainer container;
    late InMemoryStudySetContentRepository repo;
    late WorkspaceController controller;

    setUp(() async {
      repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
      container = ProviderContainer(overrides: await testOverrides(content: repo));
      container.listen(workspaceProvider('demo-1'), (_, _) {});
      await container.read(contentProvider('demo-1').future);
      controller = container.read(workspaceProvider('demo-1').notifier);
    });
    tearDown(() => container.dispose());

    WorkspaceState state() => container.read(workspaceProvider('demo-1'));
    Card topic(String title) => controller.content.cards.firstWhere((c) => c.title == title);

    test('undo and redo edits, but not reading position', () async {
      expect(state().canUndo, isFalse);
      final card = await controller.addTopic('新主题');
      expect(state().canUndo, isTrue);
      controller.recordPage('c1', 9);
      await Future<void>.delayed(const Duration(milliseconds: 900));

      await controller.undo();
      var c = await repo.load('demo-1');
      expect(c.card(card.id), isNull);
      expect(c.document('c1')!.lastPage, 9, reason: 'reading position is not undone');
      expect(state().canUndo, isFalse);
      expect(state().canRedo, isTrue);

      await controller.redo();
      c = await repo.load('demo-1');
      expect(c.card(card.id)!.title, '新主题');
      expect(state().canRedo, isFalse);
    });

    test('drag to reparent, reorder with ⌘↑ and fold', () async {
      final first = topic('遗忘的规律');
      final second = topic('对策一：间隔重复');
      await controller.moveCard(second.id, first.id, index: 0);
      expect(controller.content.node(second.id)!.parentId, first.id);
      expect(controller.content.childrenOf(first.id).first.cardId, second.id);

      await controller.shiftSelected(1);
      expect(controller.content.childrenOf(first.id).last.cardId, second.id);

      await controller.toggleCollapsed(first.id);
      expect(controller.content.node(first.id)!.collapsed, isTrue);
      // → on a collapsed node expands it and selects the first child.
      controller.selectCard(first.id);
      controller.selectNeighbor(AxisDirection.right);
      await Future<void>.delayed(Duration.zero);
      expect(controller.content.node(first.id)!.collapsed, isFalse);
      expect(state().selectedCardId, controller.content.childrenOf(first.id).first.cardId);
      controller.selectNeighbor(AxisDirection.left);
      expect(state().selectedCardId, first.id);
      controller.selectNeighbor(AxisDirection.left);
      expect(state().selectedCardId, isNull);
    });

    test('removing a document closes its tab and can be undone', () async {
      controller.openDocument('c1');
      await controller.removeDocument('c1');
      expect(controller.content.document('c1'), isNull);
      expect(controller.content.excerptCount, 0);
      expect(state().openDocumentIds, isNot(contains('c1')));
      await controller.undo();
      expect(controller.content.document('c1'), isNotNull);
      expect(controller.content.excerptCount, 1);
    });

    test('export lists topics and excerpts', () {
      final md = controller.export(opml: false, rootTitle: '认知科学入门', source: (d, p) => '${d.title} p$p');
      expect(md, startsWith('# 认知科学入门'));
      expect(md, contains('- **遗忘的规律**'));
      expect(md, contains('  - “这条先陡后平的曲线，被称为遗忘曲线。” *(学习的底层逻辑 p24)*'));
    });
  });

  group('review session', () {
    test('rates cards, repeats "again" and saves the schedule', () async {
      final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
      final container = ProviderContainer(overrides: await testOverrides(content: repo));
      addTearDown(container.dispose);
      container.listen(contentProvider('demo-1'), (_, _) {});
      await container.read(contentProvider('demo-1').future);
      final provider = reviewSessionProvider('demo-1');
      container.listen(provider, (_, _) {});
      final session = container.read(provider.notifier);

      expect(container.read(provider).queue, hasLength(1));
      await session.rate(Rating.good);
      expect(container.read(provider).index, 0, reason: 'rating needs the answer first');

      session.reveal();
      await session.rate(Rating.again);
      expect(container.read(provider).remaining, 1, reason: '"again" comes back in the same session');
      session.reveal();
      await session.rate(Rating.good);
      expect(container.read(provider).finished, isTrue);
      expect(container.read(provider).reviewed, 2);

      final c = await repo.load('demo-1');
      final review = c.reviewOf(c.cards.firstWhere((x) => x.kind == CardKind.excerpt).id)!;
      expect(review.lapses, 0);
      expect(review.due.isAfter(testNow), isTrue);
      expect(c.dueCount(testNow), 0);
    });

    testWidgets('review screen: show answer with Space, rate with keys', (tester) async {
      final container = await pumpApp(tester);
      container.read(navigationProvider.notifier).startReview('demo-1');
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(tester.element(find.byType(ReviewScreen)));

      expect(find.byKey(const ValueKey('page-prompt')), findsOneWidget);
      expect(find.text('这条先陡后平的曲线，被称为遗忘曲线。'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('这条先陡后平的曲线，被称为遗忘曲线。'), findsOneWidget);
      expect(find.text(l.rateGood), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.pumpAndSettle();
      expect(find.text(l.reviewDoneTitle), findsOneWidget);

      await tester.tap(find.text(l.backToStudySet));
      await tester.pumpAndSettle();
      expect(container.read(navigationProvider), isA<WorkspaceRoute>());
    });
  });

  test('library deletes a study set', () async {
    final container = ProviderContainer(overrides: await testOverrides());
    addTearDown(container.dispose);
    container.listen(studySetsProvider, (_, _) {});
    await container.read(studySetsProvider.future);
    final before = container.read(studySetsProvider).value!.length;
    container.read(libraryViewProvider.notifier).select('demo-1');
    await container.read(libraryViewProvider.notifier).delete('demo-1');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(studySetsProvider).value, hasLength(before - 1));
    expect(container.read(libraryViewProvider).selectedId, isNull);
  });
}
