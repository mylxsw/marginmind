import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  final time = DateTime(2026, 10, 27);
  setUp(() async => root = await Directory.systemTemp.createTemp('assistant-transaction'));
  tearDown(() async => root.delete(recursive: true));
  test('graph and receipt commit together, failed disk write is invisible, retry survives restart', () async {
    final store = FileLibraryStore(root, clock: () => time);
    final set = await store.create(const NewStudySet(title: 'Test', colorIndex: 0));
    final writes = AssistantWrites(studySetId: set.id, newId: () => 'node', now: () => time);
    final before = await store.load(set.id);
    final proposal = MapEditProposal(
      id: 'proposal',
      studySetId: set.id,
      mapId: 'main',
      baseRevision: assistantMapRevision(before, 'main'),
      operations: const [
        MapEditOperation(id: 'op', kind: MapEditKind.addReviewCard, parentId: 'main', question: 'Q', answer: 'A'),
      ],
    );
    final file = File(store.resolveFile(set.id, 'studyset.json'));
    final backup = await file.readAsBytes();
    await file.delete();
    final obstruction = Directory(file.path)..createSync();
    await expectLater(
      store.update(set.id, (c) => writes.apply(c, proposal, {'op'})),
      throwsA(isA<FileSystemException>()),
    );
    expect((await store.load(set.id)).toJson(), before.toJson());
    await obstruction.delete();
    await file.writeAsBytes(backup);
    await store.update(set.id, (c) => writes.apply(c, proposal, {'op'}));
    await store.dispose();
    final reopened = FileLibraryStore(root);
    final content = await reopened.load(set.id);
    expect(content.cards.single.body, 'A');
    expect(content.assistantReceipts.single.operationIds, ['op']);
    expect(writes.apply(content, proposal, {'op'}), same(content));
    expect((await reopened.watchAll().first).single.dueCount, 1);
    expect(Directory(p.dirname(file.path)).listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
    await reopened.dispose();
  });
}
