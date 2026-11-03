import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('sync-setup-'));
  tearDown(() async => root.delete(recursive: true));

  test('activation intent keeps live local writes, seeds only on restart, and is idempotent', () async {
    final local = FileLibraryStore(root), words = FileVocabularyStore(root);
    final set = await local.create(const NewStudySet(title: 'Keep me', colorIndex: 2));
    await words.save([
      VocabularyEntry(
        id: 'old-link',
        term: 'Word',
        language: 'en',
        kind: VocabularyKind.word,
        forms: ['word'],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    ]);
    final activation = FileSyncSetup(root);
    expect(await activation.openLedger(), isNull);
    final selected = await activation.request(deviceName: '  Mac  ');
    expect(selected.deviceName, 'Mac');
    expect(selected.joining, false);
    expect(await FileSyncLedger.restore(root), isNull);
    await local.rename(set.id, 'Saved after preparation');
    expect(await local.syncLedger, isNull);
    await local.dispose();
    await words.dispose();

    final ledger = (await activation.openLedger())!;
    final library = FileLibraryStore(root, sync: ledger), vocabulary = FileVocabularyStore(root, sync: ledger);
    await FileSyncReceiver(library, vocabulary).validateLedger(ledger);
    expect((await library.watchAll().first).single.title, 'Saved after preparation');
    expect((await vocabulary.load()).single.term, 'Word');
    expect(await vocabulary.resolveVocabularyEntryId('old-link'), startsWith('word-'));
    final ids = (await ledger.history()).keys.toSet();
    expect(ids, isNotEmpty);
    await library.dispose();
    await vocabulary.dispose();
    final again = (await activation.openLedger())!;
    expect(again.deviceId, selected.deviceId);
    expect(again.libraryId, selected.libraryId);
    final reopened = FileLibraryStore(root, sync: again), reopenedWords = FileVocabularyStore(root, sync: again);
    await FileSyncReceiver(reopened, reopenedWords).validateLedger(again);
    expect((await again.history()).keys.toSet(), ids);
    await reopened.dispose();
    await reopenedWords.dispose();
  });

  test('join uses supplied library and fresh device; selection cannot be overwritten', () async {
    final setup = FileSyncSetup(root);
    final first = await setup.request(libraryId: 'shared-library', deviceName: 'Phone');
    expect(first.joining, isTrue);
    expect(first.libraryId, 'shared-library');
    expect(first.deviceId, isNot(first.libraryId));
    await expectLater(setup.request(libraryId: 'different', deviceName: 'Other'), throwsStateError);
    final ledger = (await setup.openLedger())!;
    await expectLater(setup.request(deviceName: 'Other'), throwsStateError);
    expect(ledger.libraryId, first.libraryId);
  });

  test('corrupt or mismatched intents never silently reset an identity', () async {
    final setup = FileSyncSetup(root);
    final selected = await setup.request(deviceName: 'Mac');
    await setup.openLedger();
    final file = File('${root.path}/.foliarc-sync/setup.json');
    await file.writeAsString(jsonEncode({...selected.toJson(), 'deviceId': 'different'}));
    await expectLater(setup.openLedger(), throwsFormatException);
    await file.writeAsString(jsonEncode({...selected.toJson(), 'version': 99}));
    await expectLater(setup.openLedger(), throwsFormatException);
    expect((await FileSyncLedger.restore(root))!.deviceId, selected.deviceId);
  });

  test('invalid inputs do not create an activation intent', () async {
    final setup = FileSyncSetup(root);
    for (final id in ['', '../other', 'a/b', 'x' * 129]) {
      await expectLater(setup.request(libraryId: id, deviceName: 'Mac'), throwsFormatException);
    }
    await expectLater(setup.request(deviceName: '   '), throwsFormatException);
    await expectLater(setup.request(deviceName: 'x' * 101), throwsFormatException);
    expect(await setup.read(), isNull);
    expect(await setup.openLedger(), isNull);
  });

  test('preexisting ledger without setup is retained', () async {
    final ledger = FileSyncLedger(root, libraryId: 'existing', deviceId: 'original');
    await ledger.snapshots();
    expect((await FileSyncSetup(root).openLedger())!.deviceId, 'original');
    await expectLater(FileSyncSetup(root).cancel(), throwsStateError);
  });

  test('cancel pending activation leaves the library local and permits a corrected code', () async {
    final setup = FileSyncSetup(root);
    await setup.cancel();
    await setup.request(libraryId: 'wrong', deviceName: 'Mac');
    await setup.cancel();
    expect(await setup.openLedger(), isNull);
    expect((await setup.request(libraryId: 'right', deviceName: 'Mac')).libraryId, 'right');
  });
}
