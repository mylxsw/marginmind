import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';
import 'workspace_test.dart' show openFirstSet;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late InMemoryStudySetContentRepository repo;
  late WorkspaceController controller;
  var serial = 0;
  final remote = StudySetEditor(newId: () => 'remote-${++serial}', now: () => testNow);
  setUp(() async {
    repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    container = ProviderContainer(overrides: await testOverrides(content: repo));
    container.listen(workspaceProvider('demo-1'), (_, _) {});
    await container.read(contentProvider('demo-1').future);
    controller = container.read(workspaceProvider('demo-1').notifier);
  });
  tearDown(() => container.dispose());

  test('undo and redo preserve external additions across repository notifications', () async {
    await controller.rename('c3', 'local title');
    late Card added;
    await repo.update('demo-1', (c) {
      final result = remote.addTopic(c, title: 'other device');
      added = result.$2;
      return result.$1;
    });
    expect((await controller.undo())!.conflict, isFalse);
    expect(controller.content.card('c3')!.title, '遗忘的规律');
    expect(controller.content.card(added.id)!.title, 'other device');
    await controller.redo();
    expect(controller.content.card('c3')!.title, 'local title');
    expect(controller.content.card(added.id), isNotNull);
  });

  test('same-field conflict keeps history and returns a user-visible notice', () async {
    await controller.rename('c3', 'local title');
    await repo.update('demo-1', (c) => remote.rename(c, 'c3', 'remote title'));
    final result = await controller.undo();
    expect(result!.conflict, isTrue);
    expect((await repo.load('demo-1')).card('c3')!.title, 'remote title');
    expect(container.read(workspaceProvider('demo-1')).canUndo, isTrue);
    expect(container.read(workspaceProvider('demo-1')).canRedo, isFalse);
  });

  test('transaction abort and undo do not capture unrelated updates', () async {
    await controller.beginTransaction();
    await controller.rename('c3', 'first');
    await repo.update('demo-1', (c) => remote.rename(c, 'c4', 'remote title'));
    await controller.rename('c3', 'second');
    await controller.abortTransaction();
    expect(controller.content.card('c3')!.title, '遗忘的规律');
    expect(controller.content.card('c4')!.title, 'remote title');
    await controller.beginTransaction();
    await controller.rename('c3', 'committed');
    await repo.update('demo-1', (c) => remote.rename(c, 'c4', 'another remote title'));
    await controller.commitTransaction();
    await controller.undo();
    expect(controller.content.card('c4')!.title, 'another remote title');
  });

  test('undo rejects deleting a parent referenced by a remote addition', () async {
    final parent = await controller.addTopic('local parent');
    await repo.update('demo-1', (c) => remote.addTopic(c, title: 'remote child', parentId: parent.id).$1);
    expect((await controller.undo())!.conflict, isTrue);
    expect((await repo.load('demo-1')).card(parent.id), isNotNull);
  });

  test('a conflicting cancellation retains the edit and releases the transaction for further work', () async {
    await controller.beginTransaction();
    final parent = await controller.addTopic('local parent');
    await repo.update('demo-1', (c) => remote.addTopic(c, title: 'remote child', parentId: parent.id).$1);
    await controller.abortTransaction();
    final state = container.read(workspaceProvider('demo-1'));
    expect(state.historyConflictVersion, 1);
    expect(state.canUndo, isTrue);
    expect(controller.content.card(parent.id), isNotNull);
    await controller.rename('c3', 'independent edit');
    expect((await controller.undo())!.conflict, isFalse);
    expect(controller.content.card('c3')!.title, '遗忘的规律');
    expect(controller.content.card(parent.id), isNotNull);
  });

  testWidgets('ignored undo notices still display the conflict in the workspace', (tester) async {
    final repository = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final app = await openFirstSet(tester, content: repository);
    final owner = app.read(workspaceProvider('demo-1').notifier);
    await owner.rename('c3', 'local');
    await repository.update('demo-1', (c) => remote.rename(c, 'c3', 'external'));
    await owner.undo(); // The HUD/native shortcut need not inspect the result.
    await tester.pump();
    expect(
      find.text('This step can’t be applied because related content has changed. The current content has been kept.'),
      findsOneWidget,
    );
    expect((await repository.load('demo-1')).card('c3')!.title, 'external');
    await settleHud(tester);
  });
}
