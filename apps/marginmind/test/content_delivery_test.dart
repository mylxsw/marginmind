import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';
import 'workspace_test.dart' show openFirstSet;

/// Writes complete immediately; events remain queued until explicitly released.
class DelayedContentRepository extends InMemoryStudySetContentRepository {
  DelayedContentRepository(super.initial);
  final events = StreamController<StudySetContent>.broadcast();
  final pending = <StudySetContent>[];
  bool failNext = false;
  Completer<void>? holdNextLoad;
  Completer<void>? holdNextWrite;

  @override
  Future<StudySetContent> load(String id) async {
    final gate = holdNextLoad;
    holdNextLoad = null;
    final snapshot = await super.load(id);
    if (gate != null) await gate.future;
    return snapshot;
  }

  @override
  Stream<StudySetContent> watch(String studySetId) async* {
    yield await load(studySetId);
    yield* events.stream;
  }

  @override
  Future<StudySetContent> update(String studySetId, StudySetContent Function(StudySetContent) change) async {
    if (failNext) {
      failNext = false;
      throw StateError('write failed');
    }
    final next = await super.update(studySetId, change);
    pending.add(next);
    final gate = holdNextWrite;
    holdNextWrite = null;
    if (gate != null) await gate.future;
    return next;
  }

  void deliverOldest() => events.add(pending.removeAt(0));
}

void main() {
  testWidgets('a write completing after closing the workspace does not read a disposed provider', (tester) async {
    final repo = DelayedContentRepository({'demo-1': demoContent()});
    addTearDown(repo.events.close);
    final container = await openFirstSet(tester, content: repo);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final gate = repo.holdNextWrite = Completer<void>();
    final write = controller.rename('c3', 'saved after closing');
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await write;
    expect((await repo.load('demo-1')).card('c3')!.title, 'saved after closing');
    expect(tester.takeException(), isNull);
  });

  testWidgets('older asynchronous refresh cannot replace a newer write or publish after disposal', (tester) async {
    final repo = DelayedContentRepository({'demo-1': demoContent()});
    addTearDown(repo.events.close);
    final container = await openFirstSet(tester, content: repo);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    await controller.rename('c3', 'first');
    final gate = repo.holdNextLoad = Completer<void>();
    repo.deliverOldest();
    await tester.pump();
    await controller.rename('c3', 'latest');
    gate.complete();
    await tester.pump();
    expect(controller.content.card('c3')!.title, 'latest');
    final closing = repo.holdNextLoad = Completer<void>();
    repo.deliverOldest();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    closing.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed titles never regress while old events arrive, including undo and redo', (tester) async {
    final repo = DelayedContentRepository({'demo-1': demoContent()});
    addTearDown(repo.events.close);
    final container = await openFirstSet(tester, content: repo);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    Future<void> assertFrames(String title) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.widget<MindMapCanvas>(find.byType(MindMapCanvas)).content.card('c3')!.title, title);
        expect(controller.content.card('c3')!.title, title);
        expect(find.text(title), findsWidgets);
      }
    }

    await controller.rename('c3', 'first');
    controller.beginEditing('c3');
    await tester.pump();
    await controller.finishEditing('final');
    await assertFrames('final');
    repo.deliverOldest(); // The first write returns AFTER editing the second.
    await assertFrames('final');
    repo.deliverOldest();
    await assertFrames('final');
    await controller.undo();
    await assertFrames('first');
    await controller.redo();
    repo.deliverOldest(); // Delayed undo must not undo the redo visually.
    await assertFrames('final');
    repo.deliverOldest();
    await assertFrames('final');
    await settleHud(tester);
  });

  testWidgets('creation, cancellation, failed writes and external updates survive delayed delivery', (tester) async {
    final repo = DelayedContentRepository({'demo-1': demoContent()});
    addTearDown(repo.events.close);
    final container = await openFirstSet(tester, content: repo);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    await controller.beginTransaction();
    final card = await controller.addTopic('temporary');
    await controller.abortTransaction();
    repo.deliverOldest();
    await tester.pump();
    expect(controller.content.card(card.id), isNull);
    expect(tester.widget<MindMapCanvas>(find.byType(MindMapCanvas)).content.card(card.id), isNull);
    repo.deliverOldest();
    await tester.pump();
    repo.failNext = true;
    await expectLater(controller.rename('c3', 'failed'), throwsStateError);
    await tester.pump();
    expect(controller.content.card('c3')!.title, '遗忘的规律');
    await controller.rename('c3', 'retry');
    await repo.update(
      'demo-1',
      (c) => c.copyWith(cards: [for (final card in c.cards) card.id == 'c3' ? card.copyWith(title: 'external') : card]),
    );
    // A coalescing repository may skip our write's event entirely.
    repo.pending.removeAt(0);
    repo.deliverOldest();
    await tester.pump();
    await tester.pump();
    expect(controller.content.card('c3')!.title, 'external');
    await settleHud(tester);
  });
}
