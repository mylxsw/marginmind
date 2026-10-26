import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late File file;
  late List<int> original;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('mm_format5_');
    file = File('${root.path}/sets/current.mmset/studyset.json');
    await file.parent.create(recursive: true);
    original = await File('test/fixtures/format-4.json').readAsBytes();
    await file.writeAsBytes(original);
  });
  tearDown(() => root.delete(recursive: true));

  test('format 4 package migrates once to 5 with a byte-exact backup', () async {
    final before = jsonDecode(utf8.decode(original)) as Map<String, Object?>;
    final store = FileLibraryStore(root);
    final c = await store.load('current');
    final after = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    expect(after['format'], 5);
    for (final key in before.keys.where((k) => k != 'format' && k != 'content')) {
      expect(after[key], before[key]);
    }
    final content = after['content'] as Map;
    for (final key in (before['content'] as Map).keys) {
      expect(content[key], (before['content'] as Map)[key], reason: key as String);
    }
    expect(content['bookmarks'], isEmpty);
    expect(c.bookmarks, isEmpty);
    expect(c.cards.length, 3);
    expect(await File('${file.path}.format-4.bak').readAsBytes(), original);
    expect(await File('${file.path}.format-3.bak').exists(), isFalse);
    final migrated = await file.readAsBytes();
    await store.dispose();

    final reopened = FileLibraryStore(root);
    expect((await reopened.load('current')).toJson(), c.toJson());
    expect(await file.readAsBytes(), migrated, reason: 'no second migration');
    await reopened.dispose();
  });

  test('older packages migrate through every step', () async {
    await file.writeAsBytes(await File('test/fixtures/format-3.json').readAsBytes());
    final store = FileLibraryStore(root);
    final c = await store.load('current');
    expect(jsonDecode(await file.readAsString())['format'], 5);
    expect(c.bookmarks, isEmpty);
    expect(await File('${file.path}.format-3.bak').exists(), isTrue);
    await store.dispose();
  });

  test('bookmarks are saved, read back and removed with their document', () async {
    final store = FileLibraryStore(root);
    var seq = 0;
    final editor = StudySetEditor(newId: () => 'b${seq++}', now: () => DateTime.utc(2026, 10, 26));
    final doc = (await store.load('current')).documents.single;
    await store.update('current', (c) {
      final marked = editor.toggleBookmark(c, doc.id, 7);
      return editor.renameBookmark(marked, 'b0', '第一章');
    });
    await store.dispose();

    final reopened = FileLibraryStore(root);
    final read = await reopened.load('current');
    expect(read.bookmarkAt(doc.id, 7)?.title, '第一章');
    expect(jsonDecode(await file.readAsString())['format'], 5);
    await reopened.update('current', (c) => editor.removeDocument(c, doc.id));
    expect((await reopened.load('current')).bookmarks, isEmpty);
    await reopened.dispose();
  });

  test('a conflicting format 4 backup leaves the package untouched', () async {
    final backup = File('${file.path}.format-4.bak');
    await backup.writeAsString('different');
    final store = FileLibraryStore(root);
    expect(await store.watchAll().first, isEmpty);
    expect(store.packageLoadErrors[file.parent.path], isA<FileSystemException>());
    expect(await file.readAsBytes(), original);
    await store.dispose();
  });

  test('a newer format is not opened', () async {
    final json = jsonDecode(utf8.decode(original)) as Map<String, Object?>;
    json['format'] = 6;
    final text = jsonEncode(json);
    await file.writeAsString(text);
    final store = FileLibraryStore(root);
    expect(await store.watchAll().first, isEmpty);
    expect(await file.readAsString(), text);
    await store.dispose();
  });
}
