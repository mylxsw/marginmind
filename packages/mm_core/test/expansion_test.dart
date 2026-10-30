import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

ExpansionRequest request({ExpansionScope scope = ExpansionScope.children, int depth = 3, int breadth = 3}) =>
    ExpansionRequest(
      studySetId: 'set',
      mapId: 'main',
      targetIds: ['parent'],
      scope: scope,
      depth: depth,
      breadth: breadth,
      commonParentId: scope == ExpansionScope.group || scope == ExpansionScope.siblings ? 'main' : null,
    );
ExpansionDraft draft(String id, String parent, {bool kept = true}) =>
    ExpansionDraft(id: id, parentRef: parent, title: 'Topic $id', kept: kept);
void main() {
  test('request validation and immutable collections', () {
    final r = request();
    expect(() => r.targetIds.add('x'), throwsUnsupportedError);
    for (final args in [
      {'depth': 0},
      {'depth': 4},
      {'breadth': 4},
      {'hint': 'x' * 201},
      {'round': -1},
      {'targetIds': <String>[]},
      {
        'targetIds': ['p', 'p'],
      },
      {'studySetId': ''},
      {'scope': ExpansionScope.group},
      {
        'plan': {'p': 4},
      },
    ]) {
      expect(
        () => ExpansionRequest(
          studySetId: args['studySetId'] as String? ?? 's',
          mapId: 'm',
          targetIds: args['targetIds'] as List<String>? ?? ['p'],
          depth: args['depth'] as int? ?? 1,
          breadth: args['breadth'] as int? ?? 3,
          hint: args['hint'] as String?,
          round: args['round'] as int? ?? 0,
          scope: args['scope'] as ExpansionScope? ?? ExpansionScope.children,
          plan: args['plan'] as Map<String, int>? ?? {},
        ),
        throwsArgumentError,
      );
    }
  });
  test('NDJSON fields, Unicode normalization, truncation, refs, depth and provenance', () {
    final reasons = <String>[];
    final ctx = ExpansionLineContext(
      targets: {'T1': 'parent'},
      request: request(),
      draftPrefix: 'call-',
      pages: {47},
      existingTitles: ['ＡＩ：学习！'],
      onInvalid: reasons.add,
    );
    for (final line in [
      '',
      '{',
      '[]',
      '{"extra":1}',
      '{"ref":"T2","parent":"T1","title":"x"}',
      '{"ref":"a","parent":"missing","title":"x"}',
      '{"ref":"a","parent":"T1","title":"ＡＩ 学习"}',
      '{"ref":"a","parent":"T1","title":"x","page":"47"}',
      '{"ref":"a","parent":"T1","title":"x","tag":"bad"}',
      '{"ref":"a","parent":"T1","title":"!!!"}',
    ]) {
      expect(parseExpansionLine(line, ctx), isNull);
    }
    final a = parseExpansionLine('{"ref":"a","parent":"T1","title":"原因","tag":"why","page":47}', ctx)!;
    expect(a.id, 'call-1');
    expect(a.parentRef, 'parent');
    expect(a.page, 47);
    expect(a.tag, ExpansionDirection.why);
    final b = parseExpansionLine('{"ref":"b","parent":"a","title":"例子","page":999}', ctx)!;
    expect(b.parentRef, 'new:call-1');
    expect(b.page, isNull);
    expect(parseExpansionLine('{"ref":"a","parent":"T1","title":"重复引用"}', ctx), isNull);
    expect(parseExpansionLine('{"ref":"c","parent":"b","title":"第三层"}', ctx), isNotNull);
    expect(parseExpansionLine('{"ref":"d","parent":"c","title":"第四层"}', ctx), isNull);
    expect(expansionTitle('这是' * 30).runes.length, 24);
    expect(expansionTitle('one two three four five six seven eight nine'), 'one two three four five six seven eight');
    expect(normalizeExpansionTitle(' ＡＢＣ—，！１２３ '), 'abc123');
    expect(reasons, containsAll(['json', 'fields', 'value', 'parent', 'duplicate', 'capacity']));
    expect(() => ExpansionLineContext(targets: {'bad': 'x'}, request: request(), draftPrefix: ''), throwsArgumentError);
  });
  test('breadth, group singleton and grounded=false', () {
    for (final scope in [ExpansionScope.children, ExpansionScope.group]) {
      final ctx = ExpansionLineContext(
        targets: {'T1': 'parent'},
        request: request(scope: scope),
        draftPrefix: 'x',
      );
      final max = scope == ExpansionScope.group ? 1 : 3;
      for (var i = 0; i < max; i++) {
        expect(parseExpansionLine('{"ref":"a$i","parent":"T1","title":"Title $i"}', ctx), isNotNull);
      }
      expect(parseExpansionLine('{"ref":"z","parent":"T1","title":"overflow"}', ctx), isNull);
    }
    final ctx = ExpansionLineContext(
      targets: {'T1': 'p'},
      draftPrefix: 'x',
      pages: {1},
      request: ExpansionRequest(studySetId: 's', mapId: 'm', targetIds: ['p'], grounded: false),
    );
    expect(parseExpansionLine('{"ref":"a","parent":"T1","title":"x","page":1}', ctx)!.page, isNull);
  });
  test('cascade selection and editing restore ancestors', () {
    final drafts = [draft('c', 'new:b'), draft('b', 'new:a'), draft('a', 'parent'), draft('other', 'parent')];
    final off = selectExpansionDraft(drafts, 'a', false);
    expect(off.map((d) => d.kept), [false, false, false, true]);
    final on = selectExpansionDraft(off, 'c', true, title: 'Edited');
    expect(on.every((d) => d.kept), isTrue);
    expect(on.first.edited, isTrue);
    expect(on.first.title, 'Edited');
    expect(() => selectExpansionDraft(on, 'bad', true), throwsArgumentError);
    expect(() => selectExpansionDraft(on, 'a', true, title: ''), throwsArgumentError);
    final p = expansionToProposal(request(), drafts, proposalId: 'p', baseRevision: 1);
    expect(p.operations.map((o) => o.id), ['a', 'b', 'c', 'other']);
    expect(p.isExpansion, isTrue);
    final partial = expansionToProposal(request(), off, proposalId: 'p', baseRevision: 1);
    expect(partial.operations.single.id, 'other');
  });
  test('proposal rejects missing parents, cycles, duplicate ids and empty selection', () {
    for (final list in [
      <ExpansionDraft>[],
      [draft('a', 'new:gone')],
      [draft('a', 'new:b'), draft('b', 'new:a')],
      [draft('a', 'parent'), draft('a', 'parent')],
      [draft('a', 'foreign')],
      [const ExpansionDraft(id: 'a', parentRef: 'parent', title: '')],
    ]) {
      expect(() => expansionToProposal(request(), list, proposalId: 'p', baseRevision: 0), throwsArgumentError);
    }
  });
  test('group move, siblings validation and deselected group', () {
    final r = request(scope: ExpansionScope.group);
    final p = expansionToProposal(r, [draft('a', 'main')], proposalId: 'p', baseRevision: 0, parents: {'parent': null});
    expect(p.operations.map((o) => o.kind), [MapEditKind.addTopic, MapEditKind.move]);
    expect(p.operations.last.parentId, 'new:a');
    expect(p.operations.last.nodeId, 'parent');
    expect(() => expansionToProposal(r, [draft('a', 'main')], proposalId: 'p', baseRevision: 0), throwsArgumentError);
    expect(
      () => expansionToProposal(
        r,
        [draft('a', 'main'), draft('b', 'main')],
        proposalId: 'p',
        baseRevision: 0,
        parents: {'parent': null},
      ),
      throwsArgumentError,
    );
    expect(
      () => expansionToProposal(
        r,
        [draft('a', 'main', kept: false)],
        proposalId: 'p',
        baseRevision: 0,
        parents: {'parent': null},
      ),
      throwsArgumentError,
    );
    final sibling = expansionToProposal(
      request(scope: ExpansionScope.siblings),
      [draft('s', 'main')],
      proposalId: 's',
      baseRevision: 0,
      parents: {'parent': null},
    );
    expect(sibling.operations.single.kind, MapEditKind.addTopic);
  });
  test('more than 50 additions: one receipt, snapshot undo/redo; conversation cap remains', () {
    var seq = 0;
    final writes = AssistantWrites(studySetId: 'set', newId: () => 'id${seq++}', now: () => DateTime(2026));
    final before = StudySetEditor(
      newId: () => 'parent',
      now: () => DateTime(2026),
    ).addTopic(StudySetContent.empty, title: 'Parent').$1;
    final p = expansionToProposal(
      request(),
      [for (var i = 0; i < 100; i++) draft('d$i', 'parent')],
      proposalId: 'large',
      baseRevision: assistantMapRevision(before, 'main'),
    );
    final after = writes.apply(before, p, p.operations.map((o) => o.id).toSet());
    expect(after.cards.length, 101);
    expect(after.assistantReceipts.single.nodeIds.length, 100);
    expect(writes.apply(after, p, {'d1'}), same(after));
    final undo = StudySetEditor.restore(before, after);
    expect(undo.cards.length, 1);
    expect(StudySetEditor.restore(after, undo).cards.length, 101);
    final json = Map<String, dynamic>.from(jsonDecode(jsonEncode(p.toJson())));
    json['isExpansion'] = true;
    final untrusted = MapEditProposal.fromJson(json);
    expect(untrusted.isExpansion, isFalse);
    expect(() => writes.apply(before, untrusted, p.operations.map((o) => o.id).toSet()), throwsArgumentError);
    final bad = MapEditProposal.expansion(
      id: 'bad',
      studySetId: 'set',
      mapId: 'main',
      baseRevision: p.baseRevision,
      operations: [const MapEditOperation(id: 'rename', kind: MapEditKind.rename, nodeId: 'parent', title: 'x')],
    );
    expect(() => writes.apply(before, bad, {'rename'}), throwsArgumentError);
  });
  test('plan line contract', () {
    ExpansionPlanItem? parse(String s) =>
        parseExpansionPlanLine(s, targets: {'T1': 'main', 'T2': 'p'}, rootAlias: 'T1', breadth: 5);
    final item = parse('{"branch":"T2","add":4,"reason":"thin"}')!;
    expect(item.targetId, 'p');
    expect(item.add, 4);
    expect(item.title, isNull);
    expect(parse('{"branch":"T1","add":3,"reason":"newBranch","title":"New"}')!.title, 'New');
    for (final s in [
      '{',
      '[]',
      '{"branch":"T2","add":6,"reason":"thin"}',
      '{"branch":"T2","add":2,"reason":"thin","extra":1}',
      '{"branch":"T3","add":2,"reason":"thin"}',
      '{"branch":"T1","add":2,"reason":"thin"}',
      '{"branch":"T2","add":2,"reason":"newBranch","title":"New"}',
      '{"branch":"T1","add":2,"reason":"newBranch"}',
    ]) {
      expect(parse(s), isNull);
    }
  });
}
