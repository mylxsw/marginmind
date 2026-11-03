import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late FileSyncLedger ledger;
  late FailingLibraryStore repo;
  late ProviderContainer container;
  late WorkspaceController controller;
  const id = 'demo-1', scope = 'sets/demo-1';
  setUp(() async {
    root = await Directory.systemTemp.createTemp('workspace-sync-edit-');
    ledger = FileSyncLedger(root, libraryId: 'library', deviceId: 'local');
    repo = FailingLibraryStore(root, sync: ledger, idGenerator: () => id, clock: () => testNow);
    await repo.create(const NewStudySet(title: 'Demo', colorIndex: 0));
    await repo.update(id, (_) => demoContent());
    container = ProviderContainer(overrides: await testOverrides(content: repo));
    container.listen(workspaceProvider(id), (_, _) {});
    await container.read(contentProvider(id).future);
    controller = container.read(workspaceProvider(id).notifier);
  });
  tearDown(() async {
    container.dispose();
    await repo.dispose();
    await root.delete(recursive: true);
  });

  Future<SyncCommit> head() async => (await ledger.snapshots())[scope]!.commit;
  Future<void> remoteRename(SyncCommit base, String title) => repo
      .receiveSync([
        SyncCommit.create(
          libraryId: 'library',
          scope: scope,
          deviceId: 'remote',
          sequence: 1,
          parents: [base.id],
          payload: {
            ...base.payload,
            'content': sharedContent(
              StudySetEditor(
                newId: () => 'remote',
                now: () => testNow,
              ).rename(contentFromDocument((base.payload['content'] as Map).cast<String, Object?>()), 'c3', title),
            ),
          },
        ),
      ])
      .then((_) {});

  test('workspace creation and typing publish one transaction; cancellation publishes none', () async {
    final before = (await ledger.history()).values.where((c) => c.scope == scope).length;
    final card = await controller.addTopicAndEdit('');
    expect(card, isNotNull);
    expect((await ledger.snapshots())[scope]!.draft, isTrue);
    expect((await ledger.pending()).where((c) => c.scope == scope), isEmpty);
    await controller.finishEditing('Finished');
    expect((await repo.load(id)).card(card!.id)!.title, 'Finished');
    expect((await ledger.history()).values.where((c) => c.scope == scope), hasLength(before + 1));
    final committed = (await head()).id;
    await controller.addTopicAndEdit('');
    await controller.cancelEditing();
    expect((await head()).id, committed);
    expect((await ledger.snapshots())[scope]!.draft, isFalse);
    await controller.undo();
    expect((await repo.load(id)).card(card.id), isNull);
  });

  test('inline input defers remote text and cancellation applies the received version', () async {
    final base = await head();
    await controller.beginEditing('c3');
    await remoteRename(base, 'Remote while typing');
    expect((await repo.load(id)).card('c3')!.title, '遗忘的规律');
    await controller.cancelEditing();
    expect((await repo.load(id)).card('c3')!.title, 'Remote while typing');
    expect(await ledger.issues(), isEmpty);
  });

  test('saving an inline edit preserves both conflicting texts and keeps conditional undo', () async {
    final base = await head();
    await controller.beginEditing('c3');
    await remoteRename(base, 'Remote candidate');
    await controller.finishEditing('Local candidate');
    expect((await head()).pending, hasLength(1));
    final history = await ledger.history();
    expect(
      history.values
          .where((c) => c.scope == scope)
          .map((c) => ((c.payload['content'] as Map)['cards'] as Map)['c3']?['title']),
      containsAll(['Local candidate', 'Remote candidate']),
    );
    expect(container.read(workspaceProvider(id)).canUndo, isTrue);
  });

  test('summary creation and label editing share one transaction and release their lease', () async {
    final before = (await ledger.history()).values.where((c) => c.scope == scope).length;
    controller.selectCards(['c3', 'c4']);
    await controller.addSummaryAndEdit('Initial');
    final mark = controller.content.summaries.single.id;
    expect((await ledger.snapshots())[scope]!.draft, isTrue);
    await controller.finishMarkEditing('Final');
    expect((await ledger.history()).values.where((c) => c.scope == scope), hasLength(before + 1));
    await controller.beginMarkEditing(mark);
    await controller.cancelMarkEditing();
    await controller.beginMarkEditing(mark);
    await controller.finishMarkEditing('Updated');
    expect((await repo.load(id)).summaries.single.label, 'Updated');
    controller.selectCard('c3');
    await controller.addSummaryAndEdit('Cancelled');
    await controller.cancelMarkEditing();
    expect((await ledger.snapshots())[scope]!.draft, isFalse);
  });

  test('relation creation waits until its protected label input is ready', () async {
    controller.selectCards(['c3', 'c4']);
    await controller.addRelation();
    expect(container.read(workspaceProvider(id)).editingMarkId, controller.content.relations.single.id);
    await controller.finishMarkEditing('Ready immediately');
    expect((await repo.load(id)).relations.single.label, 'Ready immediately');
  });

  test('a failed inverse keeps the draft until cancellation can be retried', () async {
    await controller.beginTransaction();
    await controller.rename('c3', 'Draft');
    final identity = File('${root.path}/.foliarc-sync/identity.json');
    final identityBytes = await identity.readAsBytes();
    // Fail before the abort write. The transaction and local draft survive.
    await identity.writeAsString('{}');
    await expectLater(controller.abortTransaction(), throwsFormatException);
    await identity.writeAsBytes(identityBytes);
    await controller.abortTransaction();
    expect((await repo.load(id)).card('c3')!.title, '遗忘的规律');
    expect((await ledger.snapshots())[scope]!.draft, isFalse);
    await controller.rename('c3', 'After recovery');
    expect((await repo.load(id)).card('c3')!.title, 'After recovery');
  });
  test('failure after the inverse does not repeat that inverse on cancellation retry', () async {
    await controller.beginTransaction();
    await controller.rename('c3', 'Draft');
    repo.failEnd = true;
    await expectLater(controller.abortTransaction(), throwsStateError);
    expect((await repo.load(id)).card('c3')!.title, '遗忘的规律');
    expect((await ledger.snapshots())[scope]!.draft, isTrue);
    await controller.abortTransaction();
    expect((await ledger.snapshots())[scope]!.draft, isFalse);
    expect(container.read(workspaceProvider(id)).historyConflictVersion, 0);
    expect(container.read(workspaceProvider(id)).canUndo, isFalse);
  });
}

class FailingLibraryStore extends FileLibraryStore {
  FailingLibraryStore(super.root, {super.sync, super.idGenerator, super.clock});
  bool failEnd = false;
  @override
  Future<void> endContentTransaction(String id) async {
    if (failEnd) {
      failEnd = false;
      throw StateError('Simulated final publication failure');
    }
    await super.endContentTransaction(id);
  }
}
