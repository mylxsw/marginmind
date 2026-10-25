import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
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

  test('creation and repeated text edits commit as one undo step', () async {
    await controller.beginTransaction();
    final card = await controller.addTopic('');
    await controller.rename(card.id, 'a');
    await controller.rename(card.id, 'abc');
    expect(state().canUndo, isFalse);
    expect(await controller.undo(), isNull);
    await controller.commitTransaction();
    await controller.commitTransaction();
    expect(state().canUndo, isTrue);
    await controller.undo();
    expect(controller.content.card(card.id), isNull);
    expect(state().canUndo, isFalse);
    await controller.redo();
    expect(controller.content.card(card.id)!.title, 'abc');
  });

  test('abort restores content and preserves preexisting redo', () async {
    final card = await controller.addTopic('saved');
    await controller.undo();
    final before = controller.content.toJson();
    await controller.beginTransaction();
    await controller.addTopic('');
    await controller.abortTransaction();
    await controller.abortTransaction();
    expect(controller.content.toJson(), before);
    expect(state().canUndo, isFalse);
    expect(state().canRedo, isTrue);
    expect(state().selectedCardId, isNull);
    await controller.redo();
    expect(controller.content.card(card.id)!.title, 'saved');
  });

  test('nested scopes commit once and abort cancels all scopes', () async {
    await controller.beginTransaction();
    await controller.beginTransaction();
    final card = await controller.addTopic('nested');
    await controller.commitTransaction();
    expect(state().canUndo, isFalse);
    await controller.commitTransaction();
    await controller.undo();
    expect(controller.content.card(card.id), isNull);
    expect(state().canUndo, isFalse);
    await controller.beginTransaction();
    await controller.beginTransaction();
    await controller.addTopic('cancelled');
    await controller.abortTransaction();
    await controller.commitTransaction();
    expect(controller.content.cards.any((c) => c.title == 'cancelled'), isFalse);
    expect(state().canUndo, isFalse);
  });

  test('empty and net-zero transactions do not erase redo', () async {
    final card = await controller.addTopic('saved');
    await controller.undo();
    await controller.beginTransaction();
    await controller.commitTransaction();
    await controller.beginTransaction();
    await controller.rename('c3', 'temporary');
    await controller.rename('c3', '遗忘的规律');
    await controller.commitTransaction();
    expect(state().canUndo, isFalse);
    expect(state().canRedo, isTrue);
    await controller.redo();
    expect(controller.content.card(card.id), isNotNull);
  });

  test('queued edits finish before commit and history remains ordered', () async {
    final begin = controller.beginTransaction();
    final rename = controller.rename('c3', 'new');
    final commit = controller.commitTransaction();
    await Future.wait([begin, rename, commit]);
    await controller.undo();
    expect(controller.content.card('c3')!.title, '遗忘的规律');
    expect(state().canUndo, isFalse);
  });

  test('abort and undo retain reviews and reading position', () async {
    final editor = container.read(editorProvider);
    final excerpt = controller.content.cards.firstWhere((c) => c.kind == CardKind.excerpt);
    for (final abort in [true, false]) {
      await controller.beginTransaction();
      await controller.rename('c3', 'changed');
      await repo.update('demo-1', (c) => editor.rate(editor.setLastPage(c, 'c1', 9), excerpt.id, Rating.good));
      if (abort) {
        await controller.abortTransaction();
      } else {
        await controller.commitTransaction();
        await controller.undo();
      }
      expect(controller.content.document('c1')!.lastPage, 9);
      expect(controller.content.reviewOf(excerpt.id), isNotNull);
      expect(controller.content.card('c3')!.title, '遗忘的规律');
    }
  });

  test('failed writes and restores preserve history and allow retry', () async {
    await controller.beginTransaction();
    repo.failNext = true;
    await expectLater(controller.rename('c3', 'failed'), throwsStateError);
    await controller.rename('c3', 'saved');
    repo.failNext = true;
    await expectLater(controller.abortTransaction(), throwsStateError);
    expect(controller.content.card('c3')!.title, 'saved');
    await controller.abortTransaction();
    expect(controller.content.card('c3')!.title, '遗忘的规律');
    expect(state().canUndo, isFalse);
    await controller.rename('c3', 'undoable');
    repo.failNext = true;
    await expectLater(controller.undo(), throwsStateError);
    expect(state().canUndo, isTrue);
    await controller.undo();
    expect(controller.content.card('c3')!.title, '遗忘的规律');
  });

  test('history is capped at 100 committed edits', () async {
    for (var i = 0; i < 101; i++) {
      await controller.rename('c3', 'title $i');
    }
    for (var i = 0; i < 100; i++) {
      expect(await controller.undo(), isNotNull);
    }
    expect(await controller.undo(), isNull);
    expect(controller.content.card('c3')!.title, 'title 0');
  });

  test('each batch is one step; no-op batches do not create history', () async {
    final before = controller.content.toJson();
    await controller.moveCards(['c3', 'c4'], null, index: 0);
    expect(state().canUndo, isFalse);
    await controller.moveCards(['c4'], 'c3');
    await controller.undo();
    expect(controller.content.toJson(), before);
    expect(state().canUndo, isFalse);
    final excerpts = controller.content.cards.where((c) => c.kind == CardKind.excerpt).map((c) => c.id).toList();
    await controller.recolorCards(excerpts, MMAnnotationColor.blue);
    await controller.undo();
    expect(controller.content.toJson(), before);
    await controller.removeCards(['c3', 'c4']);
    expect(controller.content.cards, isEmpty);
    await controller.undo();
    expect(controller.content.toJson(), before);
    expect(state().canUndo, isFalse);
    await controller.removeCards([]);
    expect(state().canUndo, isFalse);
  });
}

class FailingRepository extends InMemoryStudySetContentRepository {
  FailingRepository(super.initial);

  bool failNext = false;

  @override
  Future<StudySetContent> update(String studySetId, StudySetContent Function(StudySetContent) change) {
    if (failNext) {
      failNext = false;
      return Future.error(StateError('write failed'));
    }
    return super.update(studySetId, change);
  }
}
