import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:test/test.dart';

final time = DateTime.utc(2026, 10, 31);
MapSource source({String fingerprint = 'text-v1', int read = 1, String id = 'doc', List<String> chapters = const []}) =>
    MapSource(documentId: id, fingerprint: fingerprint, readThrough: read, chapters: chapters);
MapGeneration metadata({Map<String, String> generated = const {}}) => MapGeneration(
  sources: [source()],
  organization: MapOrganization.chapter,
  depth: 3,
  instructions: 'Explain',
  generatedAt: time,
  generated: generated,
);
StudySetContent content() => StudySetContent(
  documents: [Document(id: 'doc', title: 'Book', fileName: 'book.pdf', pageCount: 10, importedAt: time)],
  annotations: [
    Annotation(
      id: 'mark',
      documentId: 'doc',
      page: 2,
      rects: const [],
      quote: 'Original',
      colorIndex: 0,
      createdAt: time,
    ),
  ],
);
MapLineContext context({
  MapLinePhase phase = MapLinePhase.generation,
  Set<String> protected = const {},
  Map<String, String> nodes = const {},
  Iterable<String> titles = const [],
  int depth = 4,
  Map<String, String> documents = const {'D1': 'doc'},
  Map<String, Set<int>> pages = const {
    'D1': {1, 2},
  },
}) => MapLineContext(
  phase: phase,
  mapId: 'main',
  draftPrefix: 'draft-',
  documents: documents,
  pages: pages,
  annotations: {'A1': 'mark'},
  nodes: nodes,
  protectedNodeIds: protected,
  existingTitles: titles,
  maxDepth: depth,
);
MapLine add(String id, {String parent = 'main', bool kept = true}) =>
    MapLine(id: id, kind: MapLineKind.add, title: 'Topic $id', parentId: parent, kept: kept);
MapEditProposal proposal(
  StudySetContent c,
  List<MapLine> lines, {
  String id = 'proposal',
  String mapId = 'main',
  MindMap? createMap,
}) => diffToProposal(
  proposalId: id,
  studySetId: 'set',
  mapId: mapId,
  baseRevision: assistantMapRevision(c, mapId),
  generation: metadata(),
  lines: lines,
  createMap: createMap,
);
StudySetContent apply(AssistantWrites writes, StudySetContent c, MapEditProposal p) =>
    writes.apply(c, p, p.operations.map((o) => o.id).toSet());
void main() {
  late AssistantWrites writes;
  late StudySetEditor editor;
  setUp(() {
    var id = 0;
    String nextId() => 'card-${id++}';
    writes = AssistantWrites(studySetId: 'set', newId: nextId, now: () => time);
    editor = StudySetEditor(newId: nextId, now: () => time);
  });
  test('optional models round trip, legacy nulls and explicit clearing', () {
    final map = MindMap.main.copyWith(generation: metadata());
    final restored = MindMap.fromJson(jsonDecode(jsonEncode(map.toJson())));
    expect(restored.toJson(), map.toJson());
    expect(restored.copyWith(title: 'Other').generation, same(restored.generation));
    expect(restored.copyWith(generation: null).generation, isNull);
    expect(MindMap.fromJson({'id': 'old', 'title': 'Legacy'}).generation, isNull);
    final card = Card(
      id: 'card',
      kind: CardKind.topic,
      createdAt: time,
      source: CardSource(documentId: 'doc', page: 2),
    );
    final roundtrip = Card.fromJson(jsonDecode(jsonEncode(card.toJson())));
    expect(roundtrip.toJson(), card.toJson());
    expect(roundtrip.copyWith(title: 'Renamed').source, same(roundtrip.source));
    expect(roundtrip.copyWith(source: null).source, isNull);
    expect(Card.fromJson({...card.toJson()}..remove('source')).source, isNull);
    expect(() => metadata().generated['x'] = 'x', throwsUnsupportedError);
    expect(() => metadata().sources.clear(), throwsUnsupportedError);
    expect(() => source().chapters.add('a'), throwsUnsupportedError);
    expect(() => CardSource(documentId: 'doc', page: 0), throwsArgumentError);
    expect(() => source(read: 0), throwsArgumentError);
    for (final depth in [1, 5]) {
      expect(
        () => MapGeneration(sources: [source()], organization: MapOrganization.topic, depth: depth, generatedAt: time),
        throwsArgumentError,
      );
    }
    expect(
      () => MapGeneration(sources: [], organization: MapOrganization.topic, depth: 3, generatedAt: time),
      throwsArgumentError,
    );
  });
  test('fingerprints canonicalize objects; all source changes and cache inputs matter', () {
    String fingerprint({int pages = 10, String text = 'text', Map<String, Object?> notes = const {}}) =>
        mapSourceFingerprint(pageCount: pages, textHash: text, annotations: {'b': 2, 'a': 1}, notes: notes);
    expect(fingerprint(), mapSourceFingerprint(pageCount: 10, textHash: 'text', annotations: {'a': 1, 'b': 2}));
    expect(fingerprint(pages: 11), isNot(fingerprint()));
    expect(fingerprint(text: 'ocr'), isNot(fingerprint()));
    expect(fingerprint(notes: {'note': 'new'}), isNot(fingerprint()));
    expect(mapSourcesChanged(metadata(), [source()]), isFalse);
    for (final current in [
      <MapSource>[],
      [source(id: 'other')],
      [source(fingerprint: 'v2')],
      [source(read: 2)],
      [
        source(chapters: ['a']),
      ],
    ]) {
      expect(mapSourcesChanged(metadata(), current), isTrue);
    }
    String key({String model = 'local:model', String chapter = 'a', String? hint}) => mapDigestCacheKey(
      source: source(),
      chapterId: chapter,
      chapterFingerprint: 'chapter-text-and-marks',
      model: model,
      organization: MapOrganization.chapter,
      instructions: hint,
    );
    expect(key().length, 64);
    expect(key(), key());
    expect({key(), key(model: 'b'), key(chapter: 'b'), key(hint: 'new')}.length, 4);
  });
  test('three NDJSON phases, provenance bound to document, marks and preview adapter', () {
    final chapter = context(phase: MapLinePhase.chapter);
    final p = parseMapLine('{"k":"point","id":"p1","title":"Encoding","page":2,"marks":["A1"]}', chapter)!;
    expect(p.kind, MapLineKind.point);
    expect(p.marks, ['mark']);
    expect(p.source!.documentId, 'doc');
    expect(parseMapLine('{"k":"point","id":"p2","parent":"p1","title":"Child"}', chapter)!.parentId, 'new:${p.id}');
    final ctx = context(
      documents: {'D1': 'doc', 'D2': 'other'},
      pages: {
        'D1': {1},
        'D2': {2},
      },
    );
    final a = parseMapLine('{"ref":"a","parent":"ROOT","title":"Encoding","page":2,"doc":"D1"}', ctx)!;
    expect(a.source, isNull);
    final b = parseMapLine('{"ref":"b","parent":"a","title":"Memory","page":2,"doc":"D2"}', ctx)!;
    expect(b.source!.documentId, 'other');
    expect(b.toExpansionDraft().parentRef, 'new:${a.id}');
    expect(b.copyWith(kept: false, title: 'Edited').title, 'Edited');
    expect(b.copyWith(kept: false).toExpansionDraft().kept, isFalse);
    expect(parseMapLine('{"ref":"c","parent":"ROOT","title":"Ambiguous","page":2}', ctx)!.source, isNull);
    final mark = parseMapLine('{"mark":"A1","parent":"b"}', ctx)!;
    expect(mark.annotationId, 'mark');
    expect(() => mark.toExpansionDraft(), throwsStateError);
    expect(parseMapLine('{"mark":"A1","parent":"b"}', ctx), isNull);
    final diff = context(phase: MapLinePhase.diff, nodes: {'N1': 'existing'});
    expect(parseMapLine('{"op":"rename","node":"N1","title":"Renamed"}', diff)!.nodeId, 'existing');
    expect(parseMapLine('{"op":"move","node":"N1","parent":"ROOT"}', diff)!.parentId, 'main');
    expect(parseMapLine('{"op":"remove","node":"N1","why":"Duplicate"}', diff)!.kept, isFalse);
    expect(parseMapLine('{"op":"excerpt","mark":"A1","parent":"N1"}', diff)!.parentId, 'existing');
  });
  test('invalid lines skip without poisoning references, protected targets are rejected', () {
    final ctx = context(titles: ['ＡＢＣ！'], depth: 1);
    for (final line in [
      '',
      '{',
      '[]',
      'x' * 65537,
      '{"ref":"a","parent":"ROOT","title":"ABC"}',
      '{"ref":"a","parent":"ROOT","title":"!!!"}',
      '{"ref":"ROOT","parent":"ROOT","title":"New"}',
      '{"ref":"N1","parent":"ROOT","title":"New"}',
      '{"ref":"a","parent":"later","title":"New"}',
      '{"ref":"a","parent":3,"title":"New"}',
      '{"ref":"a","parent":"ROOT","title":null}',
      '{"ref":"a","parent":"ROOT","title":"New","page":"2"}',
      '{"ref":"a","parent":"ROOT","title":"New","doc":2}',
      '{"ref":"a","parent":"ROOT","title":"New","extra":1}',
      '{"mark":"A9","parent":"ROOT"}',
      '{"op":"remove","node":"N1","why":"No"}',
    ]) {
      expect(parseMapLine(line, ctx), isNull, reason: line.substring(0, line.length.clamp(0, 100)));
    }
    expect(parseMapLine('{"ref":"a","parent":"ROOT","title":"New","page":99}', ctx)!.source, isNull);
    expect(parseMapLine('{"ref":"a","parent":"ROOT","title":"Duplicate ref"}', ctx), isNull);
    expect(parseMapLine('{"ref":"b","parent":"a","title":"Too deep"}', ctx), isNull);
    final protected = context(phase: MapLinePhase.diff, nodes: {'N1': 'locked'}, protected: {'locked'});
    for (final line in [
      '{"op":"rename","node":"N1","title":"New"}',
      '{"op":"move","node":"N1","parent":"ROOT"}',
      '{"op":"remove","node":"N1","why":"No"}',
      '{"op":"remove","node":"N9","why":"No"}',
    ]) {
      expect(parseMapLine(line, protected), isNull);
    }
    expect(parseMapLine('{"op":"add","ref":"a","parent":"N1","title":"Allowed"}', protected), isNotNull);
    final unprotected = context(phase: MapLinePhase.diff, nodes: {'N1': 'node'});
    expect(parseMapLine('{"op":"remove","node":"N1","why":""}', unprotected), isNull);
    expect(parseMapLine('{"op":"move","node":"N1","parent":"N1"}', unprotected), isNull);
    expect(
      parseMapLine('{"k":"point","id":"p","title":"P","marks":[1]}', context(phase: MapLinePhase.chapter)),
      isNull,
    );
    expect(() => context(depth: 0), throwsArgumentError);
    expect(() => context(nodes: {'real-id': 'node'}), throwsArgumentError);
  });
  test('proposal ordering, selection cascade, missing parents, cycle and duplicate rejection', () {
    final c = content();
    final p = proposal(c, [add('child', parent: 'new:parent'), add('parent')]);
    expect(p.operations.map((o) => o.id), ['parent', 'child']);
    final selected = proposal(c, [add('child', parent: 'new:parent'), add('parent', kept: false), add('other')]);
    expect(selected.operations.single.id, 'other');
    for (final lines in [
      <MapLine>[],
      [add('a'), add('a')],
      [add('a', parent: 'new:missing')],
      [add('a', parent: 'new:b'), add('b', parent: 'new:a')],
      [add('new:a')],
      [MapLine(id: 'p', kind: MapLineKind.point, title: 'point')],
    ]) {
      expect(() => proposal(c, lines), throwsArgumentError);
    }
    expect(
      () => generationToProposal(
        proposalId: 'p',
        studySetId: 'set',
        mapId: 'main',
        baseRevision: 1,
        generation: metadata(),
        lines: [MapLine(id: 'r', kind: MapLineKind.rename, nodeId: 'n', title: 'x')],
      ),
      throwsArgumentError,
    );
  });
  test('new map, 80 topics, annotation reuse, source and metadata in one undo snapshot', () {
    final before = editor.attachCard(content(), 'mark').$1;
    final existing = before.cardForAnnotation('mark')!;
    final p = generationToProposal(
      proposalId: 'new-map',
      studySetId: 'set',
      mapId: 'generated',
      baseRevision: assistantMapRevision(before, 'generated'),
      generation: metadata(),
      createMap: const MindMap(id: 'generated', title: 'Book'),
      lines: [
        for (var i = 0; i < 80; i++)
          MapLine(
            id: 't$i',
            kind: MapLineKind.add,
            parentId: 'generated',
            title: 'Topic $i',
            source: CardSource(documentId: 'doc', page: 2),
          ),
        MapLine(id: 'excerpt', kind: MapLineKind.excerpt, annotationId: 'mark', parentId: 'new:t0'),
      ],
    );
    final after = apply(writes, before, p);
    expect(after.cards.length, 81);
    expect(after.node(existing.id, mapId: 'generated')!.parentId, after.assistantReceipts.single.nodeIds.first);
    expect(after.cards.where((c) => c.kind == CardKind.topic).every((c) => c.source?.page == 2), isTrue);
    expect(after.map('generated')!.generation!.generated.length, 80);
    expect(after.assistantReceipts.single.operationIds.length, 81);
    expect(writes.apply(after, p, {'t0'}), same(after));
    final undo = StudySetEditor.restore(before, after);
    expect(undo.map('generated'), isNull);
    expect(undo.cards.length, 1);
    final redo = StudySetEditor.restore(after, undo);
    expect(redo.map('generated')!.generation!.toJson(), after.map('generated')!.generation!.toJson());
    expect(
      () => apply(
        writes,
        after,
        proposal(
          after,
          [add('x')],
          mapId: 'generated',
          createMap: const MindMap(id: 'generated', title: 'bad'),
        ),
      ),
      throwsArgumentError,
    );
  });
  test('user renamed, moved, manually added and non-topic nodes remain protected after update', () {
    var c = apply(writes, content(), proposal(content(), [add('a'), add('b')]));
    final a = c.cards.first.id, b = c.cards.last.id;
    expect(isMapNodeProtected(c, 'main', a), isFalse);
    c = editor.rename(c, a, 'My name');
    c = editor.move(c, b, a);
    final manual = editor.addTopic(c, title: 'Mine');
    c = manual.$1;
    expect(isMapNodeProtected(c, 'main', a), isTrue);
    expect(isMapNodeProtected(c, 'main', b), isTrue);
    expect(isMapNodeProtected(c, 'main', manual.$2.id), isTrue);
    expect(isMapNodeProtected(c, 'main', 'missing'), isTrue);
    final p = proposal(c, [
      MapLine(id: 'r', kind: MapLineKind.rename, nodeId: a, title: 'Bad'),
      MapLine(id: 'm', kind: MapLineKind.move, nodeId: b, parentId: 'main'),
      MapLine(id: 'd', kind: MapLineKind.remove, nodeId: manual.$2.id, reason: 'Bad', kept: true),
      add('new', parent: a),
    ], id: 'update');
    final after = apply(writes, c, p);
    expect(after.assistantReceipts.last.skipped.keys, containsAll(['r', 'm', 'd']));
    expect(after.card(a)!.title, 'My name');
    expect(isMapNodeProtected(after, 'main', a), isTrue);
    expect(isMapNodeProtected(after, 'main', b), isTrue);
    expect(isMapNodeProtected(after, 'main', manual.$2.id), isTrue);
    final restored = StudySetEditor.restore(c, after);
    expect(restored.map('main')!.generation!.toJson(), c.map('main')!.generation!.toJson());
  });
  test('diff rename/move rebaseline, delete requires explicit children, shared cards survive', () {
    var c = apply(writes, content(), proposal(content(), [add('a'), add('b', parent: 'new:a'), add('c')]));
    final a = c.cards[0].id, b = c.cards[1].id, other = c.cards[2].id;
    c = c.copyWith(
      maps: [
        ...c.maps,
        const MindMap(id: 'other', title: 'Other'),
      ],
    );
    c = StudySetEditor(newId: () => 'unused', now: () => time, mapId: 'other').placeCard(c, b);
    c = apply(
      writes,
      c,
      proposal(c, [
        MapLine(id: 'r', kind: MapLineKind.rename, nodeId: a, title: 'AI renamed'),
        MapLine(id: 'm', kind: MapLineKind.move, nodeId: other, parentId: a),
      ], id: 'rename-move'),
    );
    expect(isMapNodeProtected(c, 'main', a), isFalse);
    expect(isMapNodeProtected(c, 'main', other), isFalse);
    expect(
      () => apply(
        writes,
        c,
        proposal(c, [
          MapLine(id: 'd', kind: MapLineKind.remove, nodeId: a, reason: 'Parent', kept: true),
        ], id: 'unsafe'),
      ),
      throwsStateError,
    );
    final after = apply(
      writes,
      c,
      proposal(c, [
        for (final id in [a, b, other])
          MapLine(id: 'del-$id', kind: MapLineKind.remove, nodeId: id, reason: 'Obsolete', kept: true),
      ], id: 'delete'),
    );
    expect(after.nodes.where((n) => n.mapId == 'main'), isEmpty);
    expect(after.card(b), isNotNull);
    expect(after.map('main')!.generation!.generated, isEmpty);
  });
  test('forged JSON cannot grant document capability and ordinary proposals keep 50 cap', () {
    final c = content();
    final p = proposal(c, [for (var i = 0; i < 51; i++) add('a$i')]);
    final decoded = MapEditProposal.fromJson({
      ...p.toJson(),
      'isDocumentGeneration': true,
      'generation': metadata().toJson(),
    });
    expect(decoded.isDocumentGeneration, isFalse);
    expect(() => apply(writes, c, decoded), throwsArgumentError);
    for (final op in [
      MapEditOperation(id: 'e', kind: MapEditKind.addExcerpt, parentId: 'main', annotationId: 'mark'),
      MapEditOperation(id: 'd', kind: MapEditKind.remove, nodeId: 'node', reason: 'bad'),
    ]) {
      expect(() => MapEditOperation.fromJson(op.toJson()), throwsFormatException);
      final forged = MapEditProposal(
        id: 'forged',
        studySetId: 'set',
        mapId: 'main',
        baseRevision: assistantMapRevision(c, 'main'),
        operations: [op],
      );
      expect(() => apply(writes, c, forged), throwsFormatException);
    }
    final stale = proposal(c, [add('a')]);
    expect(() => apply(writes, editor.addTopic(c, title: 'Manual').$1, stale), throwsStateError);
  });
  test('branch root, safe excerpt skips, absent sources and shared rename guard', () {
    var c = editor.addTopic(content(), title: 'Manual parent').$1;
    final parent = c.cards.single.id;
    final ctx = MapLineContext(
      phase: MapLinePhase.generation,
      mapId: 'main',
      draftPrefix: 'branch-',
      rootParentId: parent,
      documents: {'D1': 'doc'},
      pages: {
        'D1': {2},
      },
    );
    final line = parseMapLine('{"ref":"a","parent":"ROOT","title":"Branch child"}', ctx)!;
    expect(line.parentId, parent);
    c = apply(
      writes,
      c,
      proposal(c, [
        line,
        MapLine(id: 'mark', kind: MapLineKind.excerpt, annotationId: 'mark', parentId: 'new:${line.id}'),
      ], id: 'branch'),
    );
    final excerpt = c.cardForAnnotation('mark')!;
    expect(isMapNodeProtected(c, 'main', excerpt.id), isTrue);
    final after = apply(
      writes,
      c,
      proposal(c, [
        add('fresh'),
        MapLine(id: 'again', kind: MapLineKind.excerpt, annotationId: 'mark', parentId: 'main'),
        MapLine(id: 'missing', kind: MapLineKind.excerpt, annotationId: 'gone', parentId: 'main'),
        MapLine(
          id: 'bad-source',
          kind: MapLineKind.add,
          parentId: 'main',
          title: 'Bad source',
          source: CardSource(documentId: 'unknown', page: 1),
        ),
      ], id: 'skips'),
    );
    expect(after.assistantReceipts.last.skipped.keys, containsAll(['again', 'missing']));
    expect(after.cards.last.source, isNull);
    expect(after.node(excerpt.id)!.parentId, c.node(excerpt.id)!.parentId);
    final noDoc = content().copyWith(documents: []);
    expect(() => apply(writes, noDoc, proposal(noDoc, [add('a')])), throwsStateError);
    final ai = c.cards.firstWhere((card) => card.title == 'Branch child').id;
    c = c.copyWith(
      maps: [
        ...c.maps,
        const MindMap(id: 'shared', title: 'Shared'),
      ],
    );
    c = StudySetEditor(newId: () => 'unused', now: () => time, mapId: 'shared').placeCard(c, ai);
    expect(
      () => apply(
        writes,
        c,
        proposal(c, [MapLine(id: 'r', kind: MapLineKind.rename, nodeId: ai, title: 'Bad shared edit')], id: 'shared'),
      ),
      throwsStateError,
    );
  });
  test('fake supports streaming, isolated chapter retry, partial failure, cancellation and close', () async {
    final fake = FakeMapGenerator(
      chapters: {
        'a': ['{"k":"point","id":"a","title":"Point"}'],
      },
      chapterFailures: {'a': const ResearchFailure(ResearchFailureKind.timeout)},
      generation: ['{"ref":"a","parent":"ROOT","title":"Generated"}'],
      diff: ['{"op":"add","ref":"a","parent":"ROOT","title":"Updated"}'],
    );
    MapChapterInput chapter() => MapChapterInput(
      chapterId: 'a',
      documentAlias: 'D1',
      context: context(phase: MapLinePhase.chapter),
      textByPage: {1: 'Text'},
    );
    final points = <MapLine>[];
    await expectLater(
      fake.readChapter(chapter(), CancellationToken()).forEach(points.add),
      throwsA(isA<ResearchFailure>()),
    );
    expect(points.single.title, 'Point');
    fake.chapterFailures.clear();
    expect(await fake.readChapter(chapter(), CancellationToken()).length, 1);
    MapBuildInput build(MapLinePhase phase) => MapBuildInput(
      title: 'Book',
      generation: metadata(),
      context: context(phase: phase),
      points: points,
    );
    expect(await fake.generate(build(MapLinePhase.generation), CancellationToken()).length, 1);
    expect(await fake.update(build(MapLinePhase.diff), CancellationToken()).length, 1);
    expect(fake.calls, ['chapter:a', 'chapter:a', 'generate', 'update']);
    final cancel = CancellationToken()..cancel();
    await expectLater(
      fake.generate(build(MapLinePhase.generation), cancel).drain<void>(),
      throwsA(isA<ResearchFailure>()),
    );
    final slow = FakeMapGenerator(generation: fake.generation, delay: const Duration(seconds: 10));
    final token = CancellationToken();
    final waiting = slow.generate(build(MapLinePhase.generation), token).drain<void>();
    token.cancel();
    await expectLater(waiting, throwsA(isA<ResearchFailure>()));
    await fake.close();
    await expectLater(fake.update(build(MapLinePhase.diff), CancellationToken()).drain<void>(), throwsStateError);
    await slow.close();
  });
}
