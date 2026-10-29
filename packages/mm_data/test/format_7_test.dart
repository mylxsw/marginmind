import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_data/src/format_migration.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late File file;
  late List<int> bytes;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('format7_');
    file = File('${root.path}/sets/legacy.mmset/studyset.json');
    await file.parent.create(recursive: true);
    bytes = await File('test/fixtures/format-6.json').readAsBytes();
    await file.writeAsBytes(bytes);
  });
  tearDown(() => root.delete(recursive: true));

  test('session enumeration survives restart, sorts updates and never scans snapshots', () async {
    final store = FileLibraryStore(root);
    await store.load('legacy');
    expect(await store.listResearchSessions('legacy'), isEmpty);
    final now = DateTime.utc(2026);
    for (final id in ['first', 'second']) {
      await store.saveResearchSession(
        'legacy',
        ResearchSession(
          id: id,
          question: id,
          status: 'running',
          createdAt: now,
          updatedAt: id == 'first' ? now : now.add(const Duration(seconds: 1)),
        ),
      );
    }
    final snapshot = await store.writeResearchSnapshot('legacy', 'retained');
    final reopened = FileLibraryStore(root);
    expect((await reopened.listResearchSessions('legacy')).map((s) => s.id), ['second', 'first']);
    expect(await reopened.readResearchSnapshot('legacy', snapshot), 'retained');
    expect((jsonDecode(await file.readAsString()) as Map)['format'], currentStudySetFormat);
  });

  test('deleting a research session persists and preserves snapshots', () async {
    final store = FileLibraryStore(root);
    final now = DateTime.utc(2026);
    await store.saveResearchSession(
      'legacy',
      ResearchSession(id: 'delete-me', question: 'Question', createdAt: now, updatedAt: now),
    );
    final snapshot = await store.writeResearchSnapshot('legacy', 'saved evidence');
    await store.deleteResearchSession('legacy', 'delete-me');
    await store.deleteResearchSession('legacy', 'delete-me');
    final reopened = FileLibraryStore(root);
    expect(await reopened.listResearchSessions('legacy'), isEmpty);
    expect(await reopened.readResearchSnapshot('legacy', snapshot), 'saved evidence');
    await expectLater(store.deleteResearchSession('legacy', '../escape'), throwsA(anything));
    await store.dispose();
    await reopened.dispose();
  });

  test('fixed format 6 preserves all prior fields and 365 daily due counts', () async {
    final original = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
    final before = StudySetContent.fromJson((original['content'] as Map).cast());
    final store = FileLibraryStore(root);
    final content = await store.load('legacy');
    final migrated = jsonDecode(await file.readAsString()) as Map;
    expect(migrated['format'], currentStudySetFormat);
    for (final entry in (original['content'] as Map).entries.where(
      (e) => e.key != 'cards' && e.key != 'summaries',
    )) {
      expect(migrated['content'][entry.key], entry.value, reason: '${entry.key} unchanged');
    }
    expect(content.cards.map((card) => card.toJson()), before.cards.map((card) => card.toJson()));
    expect(content.summaries.map((s) => s.toJson()), before.summaries.map((s) => s.toJson()));
    for (var day = 0; day < 365; day++) {
      final now = DateTime.utc(2026, 10, 20 + day);
      expect(content.dueCount(now), before.dueCount(now));
      expect(content.reviewQueue(now).map((c) => c.id), before.reviewQueue(now).map((c) => c.id));
    }
    expect(content.cards.every((c) => c.textFormat == TextFormat.plain), isTrue);
    expect(content.maps.every((m) => m.density == MapDensity.full), isTrue);
    expect(content.researchNotes, isEmpty);
    expect(content.inkStrokes, isEmpty);
    expect(await File('${file.path}.format-6.bak').readAsBytes(), bytes);
    final currentBytes = await file.readAsBytes();
    await store.dispose();
    final reopened = FileLibraryStore(root);
    expect((await reopened.load('legacy')).toJson(), content.toJson());
    expect(await file.readAsBytes(), currentBytes);
    await reopened.dispose();
  });

  test('interrupted replacement resumes and conflicting backup aborts', () async {
    final obstruction = Directory('${file.path}.tmp');
    await obstruction.create();
    var store = FileLibraryStore(root);
    expect(await store.watchAll().first, isEmpty);
    expect(store.packageLoadErrors, isNotEmpty);
    expect(await file.readAsBytes(), bytes);
    final backup = File('${file.path}.format-6.bak');
    expect(await backup.readAsBytes(), bytes);
    await store.dispose();
    await obstruction.delete();
    await backup.writeAsString('conflict');
    store = FileLibraryStore(root);
    expect(await store.watchAll().first, isEmpty);
    expect(await file.readAsBytes(), bytes);
    expect(await backup.readAsString(), 'conflict');
    await store.dispose();
    await backup.writeAsBytes(bytes);
    store = FileLibraryStore(root);
    expect((await store.load('legacy')).cards.length, 5);
    expect(jsonDecode(await file.readAsString())['format'], currentStudySetFormat);
    await store.dispose();
  });

  test('sessions and immutable snapshots survive reopen, undo and failed writes', () async {
    var store = FileLibraryStore(root);
    await store.load('legacy');
    final now = DateTime.utc(2026, 10, 26);
    final session = ResearchSession(
      id: 'session',
      question: 'why?',
      createdAt: now,
      updatedAt: now,
      history: [
        {'query': 'one'},
      ],
    );
    await store.saveResearchSession('legacy', session);
    expect(await store.loadResearchSession('legacy', 'missing'), isNull);
    final snapshot = await store.writeResearchSnapshot('legacy', '# source\nbody');
    expect(await store.readResearchSnapshot('legacy', snapshot), '# source\nbody');
    final snapshotFile = File(store.resolveFile('legacy', snapshot));
    final modified = (await snapshotFile.stat()).modified;
    await Future.wait(List.generate(8, (_) => store.writeResearchSnapshot('legacy', '# source\nbody')));
    expect((await snapshotFile.stat()).modified, modified);
    await snapshotFile.writeAsString('corruption');
    await expectLater(store.writeResearchSnapshot('legacy', '# source\nbody'), throwsA(isA<FileSystemException>()));
    await expectLater(store.readResearchSnapshot('legacy', snapshot), throwsFormatException);
    await snapshotFile.delete();
    expect(await store.writeResearchSnapshot('legacy', '# source\nbody'), snapshot);
    await expectLater(store.readResearchSnapshot('legacy', '../studyset.json'), throwsArgumentError);
    await expectLater(store.loadResearchSession('legacy', '../other'), throwsArgumentError);
    final obstruction = Directory('${store.resolveFile('legacy', 'research/sessions/session.json')}.tmp');
    await obstruction.create();
    await expectLater(store.saveResearchSession('legacy', session), throwsA(isA<FileSystemException>()));
    await obstruction.delete();
    await store.saveResearchSession('legacy', session);
    final before = await store.load('legacy');
    final editor = StudySetEditor(newId: () => 'id', now: () => now);
    final note = ResearchNote(
      id: 'note',
      title: 'Finding',
      body: 'body',
      sessionId: 'session',
      createdAt: now,
      updatedAt: now,
    );
    final after = await store.update('legacy', (c) => editor.saveResearchNote(c, note));
    expect((await store.loadResearchSession('legacy', 'session'))!.savedNoteIds, ['note']);
    await store.update('legacy', (c) => StudySetEditor.restore(before, c));
    expect((await store.loadResearchSession('legacy', 'session'))!.savedNoteIds, isEmpty);
    final sessionFile = File(store.resolveFile('legacy', 'research/sessions/session.json'));
    expect(jsonDecode(await sessionFile.readAsString())['savedNoteIds'], isEmpty);
    await store.update('legacy', (c) => StudySetEditor.restore(after, c));
    expect((await store.loadResearchSession('legacy', 'session'))!.savedNoteIds, ['note']);
    await store.dispose();
    store = FileLibraryStore(root);
    expect((await store.loadResearchSession('legacy', 'session'))!.history, session.history);
    expect((await store.load('legacy')).researchNotes.single.toJson(), note.toJson());
    expect(await store.readResearchSnapshot('legacy', snapshot), '# source\nbody');
    await store.dispose();
  });
  test('invalid model data never overwrites source or creates a backup', () async {
    final raw = jsonDecode(utf8.decode(bytes)) as Map;
    raw['content']['cards'][0]['kind'] = 'unknown';
    final invalid = jsonEncode(raw);
    await file.writeAsString(invalid);
    final store = FileLibraryStore(root);
    expect(await store.watchAll().first, isEmpty);
    expect(store.packageLoadErrors.values.single, isA<FormatException>());
    expect(await file.readAsString(), invalid);
    expect(await File('${file.path}.format-6.bak').exists(), isFalse);
    await store.dispose();
  });

  test('session sync failure cannot erase a committed note or its undo boundary', () async {
    final store = FileLibraryStore(root);
    final now = DateTime.utc(2026, 10, 26);
    await store.saveResearchSession(
      'legacy',
      ResearchSession(id: 's', question: 'why', createdAt: now, updatedAt: now),
    );
    final sessionPath = store.resolveFile('legacy', 'research/sessions/s.json');
    final obstruction = Directory('$sessionPath.tmp');
    await obstruction.create();
    final editor = StudySetEditor(newId: () => 'id', now: () => now);
    final note = ResearchNote(id: 'n', title: 'n', body: 'body', sessionId: 's', createdAt: now, updatedAt: now);
    await store.update('legacy', (c) => editor.saveResearchNote(c, note));
    expect(store.researchSessionSyncErrors[sessionPath], isA<FileSystemException>());
    expect((await store.loadResearchSession('legacy', 's'))!.savedNoteIds, ['n']);
    await obstruction.delete();
    await store.update('legacy', (c) => editor.setNoteFormat(c, 'n', TextFormat.markdown));
    expect(store.researchSessionSyncErrors, isEmpty);
    expect(jsonDecode(await File(sessionPath).readAsString())['savedNoteIds'], ['n']);
    await store.dispose();
  });
}
