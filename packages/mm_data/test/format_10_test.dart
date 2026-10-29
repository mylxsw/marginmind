import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_data/src/format_migration.dart';
import 'package:test/test.dart';

Map<String, Object?> legacy() {
  final json = (jsonDecode(File('test/fixtures/format-4.json').readAsStringSync()) as Map).cast<String, Object?>();
  json['format'] = 8;
  json['futureMetadata'] = {'preserve': true};
  final content = json['content'] as Map;
  content['unknownCollection'] = [42];
  content['summaries'] = [
    {'id': 'summary', 'mapId': 'main', 'fromId': 'topic', 'toId': 'note', 'label': '旧概要', 'extra': true},
  ];
  return json;
}

void main() {
  test('format 8 summary becomes a topic card without rewriting old fields or placements', () {
    final source = legacy();
    final before = jsonEncode(source);
    final migrated = migrateStudySet(source);
    expect(migrated['format'], currentStudySetFormat);
    expect(migrated['futureMetadata'], source['futureMetadata']);
    final old = source['content'] as Map;
    final content = migrated['content'] as Map;
    for (final key in old.keys.where((k) => k != 'cards' && k != 'summaries')) {
      expect(content[key], old[key], reason: '$key');
    }
    expect((content['cards'] as List).take(3).toList(), old['cards']);
    final summary = (content['summaries'] as List).single as Map;
    expect(summary, {...(old['summaries'] as List).single as Map, 'cardId': 'summary-topic:summary'});
    final topic = (content['cards'] as List).last as Map;
    expect(topic['id'], summary['cardId']);
    expect(topic['kind'], 'topic');
    expect(topic['title'], '旧概要');
    expect(DateTime.parse(topic['createdAt'] as String), DateTime.utc(1970));
    expect(jsonEncode(source), before);
    expect(migrateStudySet(migrated), same(migrated));
    expect(migrateStudySet(source), migrated, reason: 'deterministic retries');
  });

  test('generated ids avoid existing cards and reserved summary ids', () {
    final source = legacy();
    final content = source['content'] as Map;
    (content['cards'] as List).add({'id': 'summary-topic:summary', 'custom': true});
    (content['summaries'] as List).add({'id': 'existing', 'cardId': 'summary-topic:summary:1', 'label': 'keep'});
    final migrated = migrateStudySet(source)['content'] as Map;
    expect((migrated['summaries'] as List).first['cardId'], 'summary-topic:summary:2');
    expect((migrated['summaries'] as List).last, (content['summaries'] as List).last);
    expect((migrated['cards'] as List).length, 5);
  });

  test('missing label becomes an empty title', () {
    final source = legacy();
    ((source['content'] as Map)['summaries'] as List).single.remove('label');
    final migrated = migrateStudySet(source)['content'] as Map;
    expect((migrated['cards'] as List).last['title'], '');
  });

  test('format 8 backup is byte exact and migrated topic survives save and reopen', () async {
    final root = await Directory.systemTemp.createTemp('mm_format10_');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/sets/current.mmset/studyset.json');
    await file.parent.create(recursive: true);
    final original = utf8.encode(jsonEncode(legacy()));
    await file.writeAsBytes(original);
    var store = FileLibraryStore(root);
    final loaded = await store.load('current');
    expect(loaded.cards.last.kind, CardKind.topic);
    expect(loaded.cards.last.title, '旧概要');
    expect(loaded.summaries.single.toJson()['cardId'], loaded.cards.last.id);
    expect(loaded.nodes.length, 3, reason: 'summary topic is not a regular placement');
    expect(await File('${file.path}.format-8.bak').readAsBytes(), original);
    await store.update('current', (c) => c);
    await store.dispose();
    store = FileLibraryStore(root);
    expect((await store.load('current')).toJson(), loaded.toJson());
    expect(await File('${file.path}.format-8.bak').readAsBytes(), original);
    expect(jsonDecode(await file.readAsString())['format'], currentStudySetFormat);
    await store.dispose();
  });

  test('interrupted format 8 migration keeps source and retries using its backup', () async {
    final root = await Directory.systemTemp.createTemp('mm_format10_retry_');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/sets/current.mmset/studyset.json');
    await file.parent.create(recursive: true);
    final original = utf8.encode(jsonEncode(legacy()));
    await file.writeAsBytes(original);
    final obstruction = Directory('${file.path}.tmp');
    await obstruction.create();
    var store = FileLibraryStore(root);
    expect(await store.watchAll().first, isEmpty);
    expect(await file.readAsBytes(), original);
    expect(await File('${file.path}.format-8.bak').readAsBytes(), original);
    await store.dispose();
    await obstruction.delete();
    store = FileLibraryStore(root);
    expect((await store.load('current')).cards.last.title, '旧概要');
    expect(jsonDecode(await file.readAsString())['format'], currentStudySetFormat);
    await store.dispose();
  });
}
