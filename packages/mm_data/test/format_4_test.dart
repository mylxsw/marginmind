import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_data/src/format_migration.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late File file;
  late List<int> original;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('mm_format4_');
    file = File('${root.path}/sets/current.mmset/studyset.json');
    await file.parent.create(recursive: true);
    original = await File('test/fixtures/format-3.json').readAsBytes();
    await file.writeAsBytes(original);
  });
  tearDown(() => root.delete(recursive: true));

  test('format 3 package migrates once to 4 with a byte-exact backup', () async {
    final before = jsonDecode(utf8.decode(original)) as Map<String, Object?>;
    final store = FileLibraryStore(root);
    final c = await store.load('current');
    final after = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    expect(after['format'], currentStudySetFormat);
    for (final key in before.keys.where((k) => k != 'format' && k != 'content')) {
      expect(after[key], before[key]);
    }
    final content = after['content'] as Map;
    for (final key in (before['content'] as Map).keys) {
      expect(content[key], (before['content'] as Map)[key], reason: key as String);
    }
    expect(content['relations'], isEmpty);
    expect(content['summaries'], isEmpty);
    expect(c.cards.length, 3);
    expect(c.card('note')!.tags, ['知识']);
    final backup = File('${file.path}.format-3.bak');
    expect(await backup.readAsBytes(), original);
    expect(await File('${file.path}.format-1.bak').exists(), isFalse);
    final migrated = await file.readAsBytes();
    await store.dispose();

    final reopened = FileLibraryStore(root);
    expect((await reopened.load('current')).toJson(), c.toJson());
    expect(await file.readAsBytes(), migrated, reason: 'no second migration');
    await reopened.dispose();
  });

  test('relations and summaries are saved and read back', () async {
    final store = FileLibraryStore(root);
    var seq = 0;
    final editor = StudySetEditor(newId: () => 'n${seq++}', now: () => DateTime.utc(2026, 10, 26));
    final content = await store.load('current');
    final cards = [for (final n in content.childrenOf(null)) n.cardId];
    await store.update('current', (c) {
      final (linked, _) = editor.addRelation(c, cards.first, cards.last, label: 'why');
      return editor.addSummary(linked, cards, label: 'all').$1;
    });
    await store.dispose();
    final reopened = FileLibraryStore(root);
    final read = await reopened.load('current');
    expect(read.relationsOf(MindMap.defaultId).single.label, 'why');
    expect(read.summariesOf(MindMap.defaultId).single.$2, cards);
    expect(jsonDecode(await file.readAsString())['format'], currentStudySetFormat);
    await reopened.dispose();
  });

  test('a conflicting format 3 backup leaves the package untouched', () async {
    final backup = File('${file.path}.format-3.bak');
    await backup.writeAsString('different');
    final store = FileLibraryStore(root);
    expect(await store.watchAll().first, isEmpty);
    expect(store.packageLoadErrors[file.parent.path], isA<FileSystemException>());
    expect(await file.readAsBytes(), original);
    expect(await backup.readAsString(), 'different');
    await store.dispose();
  });
}
