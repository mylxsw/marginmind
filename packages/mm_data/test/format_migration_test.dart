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
    root = await Directory.systemTemp.createTemp('mm_format_');
    file = File('${root.path}/sets/legacy.mmset/studyset.json');
    await file.parent.create(recursive: true);
    original = await File('test/fixtures/format-1.json').readAsBytes();
    await file.writeAsBytes(original);
    final pdf = File('${file.parent.path}/documents/original.pdf');
    await pdf.parent.create();
    await pdf.writeAsBytes([1, 2, 3, 4]);
  });
  tearDown(() => root.delete(recursive: true));

  test('fixed v1 package migrates once with byte-exact backup and identical exports', () async {
    final old = jsonDecode(utf8.decode(original)) as Map;
    final store = FileLibraryStore(root);
    final c = await store.load('legacy');
    final after = jsonDecode(await file.readAsString()) as Map;
    expect(after['format'], 7);
    for (final key in old.keys.where((k) => k != 'format' && k != 'content')) {
      expect(after[key], old[key]);
    }
    final before = old['content'] as Map;
    for (final key in ['documents', 'cards', 'reviews']) {
      expect(after['content'][key], before[key]);
    }
    expect(c.maps.single.id, MindMap.defaultId);
    expect(c.nodes.map((n) => n.mapId).toSet(), {MindMap.defaultId});
    expect(c.nodes.map((n) => {...n.toJson()}..remove('mapId')).toList(), before['nodes']);
    for (var i = 0; i < c.annotations.length; i++) {
      final a = c.annotations[i];
      expect(
        {...a.toJson()}..remove('pages'),
        <String, Object?>{...(before['annotations'][i] as Map).cast<String, Object?>()}
          ..remove('page')
          ..remove('rects'),
      );
      expect(a.pages.single.toJson(), {
        'page': before['annotations'][i]['page'],
        'rects': before['annotations'][i]['rects'],
      });
    }
    expect(c.reviewQueue(DateTime.utc(2026, 10, 26)).map((c) => c.id), ['excerpt', 'note']);
    final exporter = MapExporter(c, rootTitle: '旧学习集');
    expect(exporter.markdown(), await File('test/fixtures/format-1.md').readAsString());
    expect(exporter.opml(), await File('test/fixtures/format-1.opml').readAsString());
    final backup = File('${file.path}.format-1.bak');
    expect(await backup.readAsBytes(), original);
    expect(await File(store.resolveFile('legacy', c.documents.single.fileName)).readAsBytes(), [1, 2, 3, 4]);
    final migratedBytes = await file.readAsBytes();
    await store.dispose();
    final reopened = FileLibraryStore(root);
    expect((await reopened.load('legacy')).toJson(), c.toJson());
    expect(await file.readAsBytes(), migratedBytes);
    expect(await backup.readAsBytes(), original);
    await reopened.dispose();
  });

  test('interrupted migration preserves original and retries with existing backup', () async {
    final obstruction = Directory('${file.path}.tmp');
    await obstruction.create();
    final store = FileLibraryStore(root);
    expect(await store.watchAll().first, isEmpty);
    expect(store.packageLoadErrors[file.parent.path], isA<FileSystemException>());
    await expectLater(store.load('legacy'), throwsStateError);
    expect(await file.readAsBytes(), original);
    expect(await File('${file.path}.format-1.bak').readAsBytes(), original);
    await store.dispose();
    await obstruction.delete();
    final retry = FileLibraryStore(root);
    expect((await retry.load('legacy')).cards.length, 3);
    expect(jsonDecode(await file.readAsString())['format'], 7);
    await retry.dispose();
  });

  test('backup conflict or write failure skips only that package and records the error', () async {
    final healthy = File('${root.path}/sets/healthy.mmset/studyset.json');
    await healthy.parent.create(recursive: true);
    final healthyJson = jsonDecode(utf8.decode(original)) as Map;
    healthyJson['id'] = 'healthy';
    await healthy.writeAsString(jsonEncode(healthyJson));
    final backup = File('${file.path}.format-1.bak');
    await backup.writeAsString('different original');
    final obstruction = Directory('${backup.path}.tmp');

    for (final conflict in [true, false]) {
      if (!conflict) {
        await backup.delete();
        await obstruction.create();
      }
      final store = FileLibraryStore(root);
      final sets = await store.watchAll().first;
      expect(sets.map((s) => s.id), contains('healthy'));
      expect(sets.map((s) => s.id), isNot(contains('legacy')));
      expect((await store.load('healthy')).cards.length, 3);
      await expectLater(store.load('legacy'), throwsStateError);
      expect(store.isLoaded, isTrue);
      expect(store.packageLoadErrors.keys, [file.parent.path]);
      expect(store.packageLoadErrors[file.parent.path], isA<FileSystemException>());
      expect(() => store.packageLoadErrors.clear(), throwsUnsupportedError);
      expect(await file.readAsBytes(), original);
      if (conflict) {
        expect(await backup.readAsString(), 'different original');
      } else {
        expect(await backup.exists(), isFalse);
      }
      final created = await store.create(const NewStudySet(title: 'Still usable', colorIndex: 0));
      expect((await store.load(created.id)).cards, isEmpty);
      await store.rename('healthy', 'Still editable');
      expect((await store.watchAll().first).firstWhere((s) => s.id == 'healthy').title, 'Still editable');
      await store.dispose();
    }
  });

  test('root IO failure can be retried on the same store after repair', () async {
    final sets = Directory('${root.path}/sets');
    final saved = await sets.rename('${root.path}/saved-sets');
    final obstruction = File(sets.path);
    await obstruction.writeAsString('not a directory');
    final store = FileLibraryStore(root);
    await expectLater(store.watchAll().first, throwsA(isA<FileSystemException>()));
    expect(store.isLoaded, isFalse);
    await expectLater(store.load('legacy'), throwsA(isA<FileSystemException>()));
    await obstruction.delete();
    await saved.rename(sets.path);
    expect((await store.load('legacy')).cards.length, 3);
    expect(store.isLoaded, isTrue);
    expect(store.packageLoadErrors, isEmpty);
    final created = await store.create(const NewStudySet(title: 'Recovered', colorIndex: 0));
    expect((await store.watchAll().first).map((s) => s.id), containsAll(['legacy', created.id]));
    await store.dispose();
  });

  test('format 2 upgrades atomically with original backup and preserves tags after reopen', () async {
    final json = jsonDecode(utf8.decode(original)) as Map<String, Object?>;
    // Use the v1 migration to obtain valid multi-map/multi-page content.
    final seed = FileLibraryStore(root);
    final content = await seed.load('legacy');
    await seed.dispose();
    json['format'] = 2;
    json['content'] = content.toJson();
    final source = utf8.encode(jsonEncode(json));
    await file.writeAsBytes(source);
    final store = FileLibraryStore(root);
    expect((await store.load('legacy')).toJson(), content.toJson());
    expect(jsonDecode(await file.readAsString())['format'], 7);
    expect(await File('${file.path}.format-2.bak').readAsBytes(), source);
    final editor = StudySetEditor(newId: () => 'unused', now: () => DateTime.utc(2026));
    await store.update('legacy', (c) => editor.setTags(c, 'note', ['知识', 'Review']));
    await store.dispose();
    final reopened = FileLibraryStore(root);
    expect((await reopened.load('legacy')).card('note')!.tags, ['知识', 'Review']);
    expect(await File('${file.path}.format-2.bak').readAsBytes(), source);
    await reopened.dispose();
  });

  test('format 2 migration keeps source on interruption and refuses a conflicting backup', () async {
    final seed = FileLibraryStore(root);
    final content = await seed.load('legacy');
    await seed.dispose();
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final editor = StudySetEditor(newId: () => 'other', now: () => DateTime.utc(2026));
    final (mapped, _) = editor.addMap(content, title: 'Other');
    json['format'] = 2;
    json['content'] = mapped.toJson();
    final source = utf8.encode(jsonEncode(json));
    await file.writeAsBytes(source);
    final obstruction = Directory('${file.path}.tmp');
    await obstruction.create();
    final interrupted = FileLibraryStore(root);
    expect(await interrupted.watchAll().first, isEmpty);
    expect(await file.readAsBytes(), source);
    final backup = File('${file.path}.format-2.bak');
    expect(await backup.readAsBytes(), source);
    await interrupted.dispose();
    await obstruction.delete();
    await backup.writeAsString('conflict');
    final conflict = FileLibraryStore(root);
    expect(await conflict.watchAll().first, isEmpty);
    expect(await file.readAsBytes(), source);
    expect(await backup.readAsString(), 'conflict');
    await conflict.dispose();
    await backup.writeAsBytes(source);
    final retry = FileLibraryStore(root);
    expect((await retry.load('legacy')).toJson(), mapped.toJson());
    expect(jsonDecode(await file.readAsString())['format'], 7);
    await retry.dispose();
  });

  test('unknown and missing versions are left untouched', () async {
    for (final version in [null, 0, 8, '4']) {
      final json = jsonDecode(utf8.decode(original)) as Map;
      json['format'] = version;
      final text = jsonEncode(json);
      await file.writeAsString(text);
      final store = FileLibraryStore(root);
      expect(await store.watchAll().first, isEmpty);
      expect(await file.readAsString(), text);
      expect(await File('${file.path}.format-1.bak').exists(), isFalse);
      await store.dispose();
    }
  });

  test('images deduplicate by bytes, regardless of source name, and survive reopen', () async {
    final store = FileLibraryStore(root);
    final png = [137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3];
    final source = File('${root.path}/source.bin');
    await source.writeAsBytes(png);
    final other = await source.copy('${root.path}/renamed.jpeg');
    final paths = await Future.wait([
      store.importImage('legacy', source.path),
      store.importImage('legacy', other.path),
    ]);
    expect(paths[0], paths[1]);
    expect(paths[0], startsWith('images/'));
    expect(paths[0], endsWith('.png'));
    expect(await File(store.resolveFile('legacy', paths[0])).readAsBytes(), png);
    // Captured areas arrive as bytes and share the same content address.
    expect(await store.importImageBytes('legacy', png), paths[0]);
    await expectLater(store.importImageBytes('legacy', [1, 2, 3]), throwsFormatException);
    await source.writeAsBytes([255, 216, 255, 1]);
    final jpeg = await store.importImage('legacy', source.path);
    expect(jpeg, endsWith('.jpg'));
    await source.writeAsString('not an image');
    await expectLater(store.importImage('legacy', source.path), throwsFormatException);
    final editor = StudySetEditor(newId: () => 'image', now: () => DateTime.utc(2026));
    await store.update(
      'legacy',
      (c) => editor.createImage(c, imageFileName: paths[0], imageOrigin: 'file:diagram.png', title: 'Question').$1,
    );
    await source.delete();
    await other.delete();
    await store.dispose();
    final reopened = FileLibraryStore(root);
    final card = (await reopened.load('legacy')).card('image')!;
    expect(card.kind, CardKind.image);
    expect(card.annotationId, isNull);
    expect(card.imageOrigin, 'file:diagram.png');
    expect(card.title, 'Question');
    expect(card.imageFileName, paths[0]);
    expect(await File(reopened.resolveFile('legacy', card.imageFileName!)).readAsBytes(), png);
    await reopened.dispose();
  });
}
