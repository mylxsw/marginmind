import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 26);
  var seq = 0;
  StudySetEditor editor([String mapId = MindMap.defaultId]) =>
      StudySetEditor(newId: () => 'id-${seq++}', now: () => now, mapId: mapId);

  /// Root topics A, B, C, D; A has children A1, A2.
  (StudySetContent, Map<String, String>) tree() {
    final e = editor();
    var c = StudySetContent.empty;
    final ids = <String, String>{};
    for (final t in ['A', 'B', 'C', 'D']) {
      final (next, card) = e.addTopic(c, title: t);
      c = next;
      ids[t] = card.id;
    }
    for (final t in ['A1', 'A2']) {
      final (next, card) = e.addTopic(c, title: t, parentId: ids['A']);
      c = next;
      ids[t] = card.id;
    }
    return (c, ids);
  }

  group('relations', () {
    test('create, relabel and delete; invalid ends are rejected', () {
      final e = editor();
      final (c, ids) = tree();
      final (linked, r) = e.addRelation(c, ids['A1']!, ids['D']!, label: ' causes ');
      expect(r!.label, 'causes');
      expect(linked.relationsOf(MindMap.defaultId).single.toId, ids['D']);
      expect(e.addRelation(linked, ids['A1']!, ids['D']!).$2, same(r), reason: 'select existing line');
      expect(e.addRelation(linked, ids['D']!, ids['A1']!).$2, same(r), reason: 'unordered pair has one line');
      expect(e.addRelation(c, ids['A']!, ids['A']!).$2, isNull);
      expect(e.addRelation(c, ids['A']!, 'missing').$2, isNull);
      expect(editor('other').addRelation(c, ids['A']!, ids['B']!).$2, isNull, reason: 'not placed in that map');

      final relabeled = e.relabelRelation(linked, r.id, ' leads to ');
      expect(relabeled.relations.single.label, 'leads to');
      expect(e.removeRelation(relabeled, r.id).relations, isEmpty);
    });

    test('follow moves and go away with either card', () {
      final e = editor();
      final (c, ids) = tree();
      final (linked, r) = e.addRelation(c, ids['A1']!, ids['B']!);
      final moved = e.move(linked, ids['A1']!, ids['C']);
      expect(moved.relationsOf(MindMap.defaultId).single.id, r!.id);
      expect(e.removeMany(moved, [ids['C']!]).relations, isEmpty, reason: 'source inside a removed subtree');
      expect(e.removeFromMap(linked, ids['B']!).relations, isEmpty);
      expect(e.removeMany(linked, [ids['D']!]).relations.single.id, r.id);
    });

    test('belong to one map and are removed with it; restore brings them back', () {
      final e = editor();
      final (c, ids) = tree();
      final (withMap, map) = e.addMap(c, title: 'Second');
      final other = editor(map.id);
      var placed = other.placeCard(withMap, ids['A']!);
      placed = other.placeCard(placed, ids['B']!);
      final (linked, r) = other.addRelation(placed, ids['A']!, ids['B']!);
      expect(linked.relationsOf(MindMap.defaultId), isEmpty);
      expect(linked.relationsOf(map.id).single.id, r!.id);
      // Removing the card from the main map keeps the other map's line.
      expect(e.removeFromMap(linked, ids['A']!).relationsOf(map.id), hasLength(1));
      final removed = e.removeMap(linked, map.id);
      expect(removed.relations, isEmpty);
      expect(StudySetEditor.restore(linked, removed).relations.single.id, r.id);
    });
  });

  group('summaries', () {
    test('cover the span of selected siblings in display order', () {
      final e = editor();
      final (c, ids) = tree();
      final (summed, s) = e.addSummary(c, [ids['C']!, ids['A']!], label: ' Early ');
      expect(s!.label, 'Early');
      expect(s.parentId, isNull);
      expect((s.fromId, s.toId), (ids['A'], ids['C']));
      expect(summed.summariesOf(MindMap.defaultId).single.$2, [ids['A'], ids['B'], ids['C']]);
      expect(e.addSummary(summed, [ids['A']!, ids['C']!]).$2, isNull, reason: 'identical range');
      expect(e.addSummary(summed, [ids['A']!, ids['B']!]).$2, isNull, reason: 'overlapping range');
      expect(e.addSummary(c, [ids['A']!, ids['A1']!]).$2, isNull, reason: 'different parents');
      expect(e.addSummary(c, const []).$2, isNull);
      expect(e.addSummary(c, ['missing']).$2, isNull);
      final (child, inner) = e.addSummary(c, [ids['A2']!]);
      expect(inner!.parentId, ids['A']);
      expect(child.summariesOf(MindMap.defaultId).single.$2, [ids['A2']]);

      final relabeled = e.relabelSummary(summed, s.id, ' Later ');
      expect(relabeled.summaries.single.label, 'Later');
      expect(e.removeSummary(relabeled, s.id).summaries, isEmpty);
    });

    test('reordering keeps the range; moving an end out shrinks it', () {
      final e = editor();
      final (c, ids) = tree();
      final (summed, s) = e.addSummary(c, [ids['A']!, ids['C']!]);
      final shifted = e.shift(summed, ids['C']!, 1);
      expect(shifted.summariesOf(MindMap.defaultId).single.$2, [ids['A'], ids['B'], ids['D'], ids['C']]);

      final movedOut = e.move(summed, ids['A']!, ids['D']);
      expect(movedOut.summaries.single.id, s!.id);
      expect(movedOut.summariesOf(MindMap.defaultId).single.$2, [ids['B'], ids['C']]);

      final batch = e.moveMany(summed, [ids['A']!, ids['C']!], ids['D']);
      expect(batch.summariesOf(MindMap.defaultId).single.$2, [ids['B']]);

      final (single, _) = e.addSummary(c, [ids['B']!]);
      expect(e.move(single, ids['B']!, ids['A']).summaries, isEmpty);
      expect(e.promote(single, ids['B']!), same(single), reason: 'root children cannot be promoted');
      final (inner, _) = e.addSummary(c, [ids['A1']!]);
      expect(e.promote(inner, ids['A1']!).summaries, isEmpty);
    });

    test('removing covered siblings shrinks the range or removes it', () {
      final e = editor();
      final (c, ids) = tree();
      final (summed, _) = e.addSummary(c, [ids['A']!, ids['C']!]);
      expect(e.removeMany(summed, [ids['A']!]).summariesOf(MindMap.defaultId).single.$2, [ids['B'], ids['C']]);
      expect(e.removeMany(summed, [ids['B']!]).summariesOf(MindMap.defaultId).single.$2, [ids['A'], ids['C']]);
      expect(e.removeMany(summed, [ids['A']!, ids['B']!, ids['C']!]).summaries, isEmpty);
      final (inner, _) = e.addSummary(c, [ids['A1']!, ids['A2']!]);
      expect(e.removeFromMap(inner, ids['A']!).summaries, isEmpty, reason: 'parent removed');
      expect(e.removeMany(summed, [ids['A1']!]).summaries, summed.summaries, reason: 'unrelated edit');
    });

    test('a node wrapped in a new parent hands its place in the range to it', () {
      final e = editor();
      final (c, ids) = tree();
      final (summed, _) = e.addSummary(c, [ids['A']!, ids['B']!]);
      final (wrapped, parent) = e.insertParent(summed, ids['A']!, title: 'P');
      expect(wrapped.summariesOf(MindMap.defaultId).single.$2, [parent!.id, ids['B']]);
    });

    test('are removed with their map', () {
      final e = editor();
      final (c, ids) = tree();
      final (withMap, map) = e.addMap(c, title: 'Second');
      final placed = editor(map.id).placeCard(withMap, ids['A']!);
      final (summed, _) = editor(map.id).addSummary(placed, [ids['A']!]);
      final (both, _) = e.addSummary(summed, [ids['A']!]);
      expect(e.removeMap(both, map.id).summaries.single.mapId, MindMap.defaultId);
    });
  });

  test('relations and summaries survive JSON and restore', () {
    final e = editor();
    final (c, ids) = tree();
    final (linked, _) = e.addRelation(c, ids['A1']!, ids['D']!, label: 'x');
    final (summed, _) = e.addSummary(linked, [ids['A1']!, ids['A2']!]);
    final json = jsonDecode(jsonEncode(summed.toJson())) as Map<String, Object?>;
    expect(StudySetContent.fromJson(json).toJson(), summed.toJson());
    expect((json['summaries'] as List).single, isNot(contains('label')), reason: 'empty label omitted');
    final legacy = {...json}
      ..remove('relations')
      ..remove('summaries');
    final read = StudySetContent.fromJson(legacy);
    expect(read.relations, isEmpty);
    expect(read.summaries, isEmpty);
    expect(StudySetEditor.restore(c, summed).toJson(), c.toJson());
    // Dangling ends are kept in the data but not shown.
    final dangling = summed.copyWith(
      nodes: [
        for (final n in summed.nodes)
          if (n.cardId != ids['D']) n,
      ],
    );
    expect(dangling.relationsOf(MindMap.defaultId), isEmpty);
    expect(dangling.relations, hasLength(1));
  });

  group('export', () {
    late StudySetContent content;
    late Map<String, String> ids;
    setUp(() {
      final e = editor();
      final (c, t) = tree();
      ids = t;
      var next = e.addRelation(c, ids['A1']!, ids['D']!, label: 'leads <to>').$1;
      next = e.addRelation(next, ids['B']!, ids['C']!).$1;
      next = e.addSummary(next, [ids['A']!, ids['B']!], label: 'Early "half"').$1;
      next = e.addSummary(next, [ids['A1']!, ids['A2']!]).$1;
      content = next;
    });

    test('markdown lists summaries after their range and relations at the end', () {
      expect(
        MapExporter(content, rootTitle: 'Root').markdown(),
        '# Root\n\n'
        '- **A**\n'
        '  - **A1**\n'
        '  - **A2**\n'
        '  - *Summary*\n'
        '- **B**\n'
        '- *Summary: Early "half"*\n'
        '- **C**\n'
        '- **D**\n'
        '\n## Relationships\n\n'
        '- A1 → D — leads <to>\n'
        '- B → C\n',
      );
      final localized = MapExporter(
        content,
        rootTitle: 'Root',
        summary: (label) => '概要：$label',
        relationsTitle: '关联',
      ).markdown();
      expect(localized, contains('- *概要：Early "half"*'));
      expect(localized, contains('## 关联'));
    });

    test('opml keeps both in custom attributes', () {
      final opml = MapExporter(content, rootTitle: 'Root').opml();
      String attr(String line, String name) {
        final match = RegExp('$name="([^"]*)"').firstMatch(line)!;
        return match[1]!
            .replaceAll('&quot;', '"')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&amp;', '&');
      }

      final lines = opml.split('\n');
      final root = lines.firstWhere((l) => l.contains('text="Root"') && l.contains('<outline'));
      expect(jsonDecode(attr(root, '_mmSummaries')), [
        {'from': ids['A'], 'to': ids['B'], 'label': 'Early "half"'},
      ]);
      final a = lines.firstWhere((l) => l.contains('text="A"'));
      expect(attr(a, '_mmId'), ids['A']);
      expect(jsonDecode(attr(a, '_mmSummaries')), [
        {'from': ids['A1'], 'to': ids['A2']},
      ]);
      final a1 = lines.firstWhere((l) => l.contains('text="A1"'));
      expect(jsonDecode(attr(a1, '_mmRelations')), [
        {'to': ids['D'], 'label': 'leads <to>'},
      ]);
      final d = lines.firstWhere((l) => l.contains('text="D"'));
      expect(attr(d, '_mmId'), ids['D']);
      expect(d, isNot(contains('_mmRelations')));
    });

    test('maps without relations or summaries export as before', () {
      final (c, _) = tree();
      final opml = MapExporter(c, rootTitle: 'Root').opml();
      expect(opml, isNot(contains('_mm')));
      expect(MapExporter(c, rootTitle: 'Root').markdown(), isNot(contains('##')));
    });

    test('relations name untitled excerpts by their quote', () {
      final e = editor();
      final (withDoc, doc) = e.addDocument(
        StudySetContent.empty,
        title: 'Book',
        fileName: 'documents/b.pdf',
        pageCount: 3,
      );
      final (withExcerpt, excerpt) = e.createExcerpt(
        withDoc,
        documentId: doc.id,
        page: 1,
        rects: const [PageRect(0, 10, 10, 0)],
        quote: 'A\nquote',
        colorIndex: 0,
      );
      final (withNote, note) = e.addNote(withExcerpt, text: 'Note');
      final (linked, _) = e.addRelation(withNote, excerpt.id, note.id);
      expect(MapExporter(linked, rootTitle: 'R').markdown(), endsWith('- A quote → Note\n'));
    });
  });
}
