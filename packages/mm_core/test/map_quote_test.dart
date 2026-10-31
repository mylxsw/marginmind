import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  test('chapter quotes require exact input substring and valid source; keep point on mismatch', () {
    MapLine? parse(String quote, {int page = 1, bool enabled = true}) => parseMapLine(
      '{"k":"point","id":"p","title":"Topic","page":$page,"quote":"$quote"}',
      MapLineContext(
        phase: MapLinePhase.chapter,
        mapId: 'main',
        draftPrefix: 'run-',
        documents: {'D1': 'doc'},
        pages: {
          'D1': {1},
        },
        quoteTextByPage: enabled
            ? {
                'D1': {1: 'Exact quote here'},
              }
            : {},
      ),
    );
    expect(parse('Exact quote')!.quote, 'Exact quote');
    expect(parse('Exact quote')!.copyWith(kept: false).quote, 'Exact quote');
    for (final quote in ['exact quote', 'invented', '']) {
      expect(parse(quote)!.quote, isNull);
    }
    expect(parse('Exact quote', enabled: false)!.quote, isNull);
    expect(parse('Exact quote', page: 2)!.quote, isNull);
  });

  test('staged excerpts are selected, created and attached in same transaction, omitted from JSON', () {
    final time = DateTime.utc(2026);
    final before = StudySetContent(
      documents: [Document(id: 'doc', title: 'Doc', fileName: 'doc.pdf', pageCount: 2, importedAt: time)],
    );
    Annotation mark({String doc = 'doc', int page = 1, AnnotationLineStyle style = AnnotationLineStyle.dashed}) =>
        Annotation(
          id: 'mark',
          documentId: doc,
          page: page,
          rects: [const PageRect(0, 20, 50, 10)],
          quote: 'Exact quote',
          colorIndex: 0,
          createdAt: time,
          kind: AnnotationKind.underline,
          lineStyle: style,
        );
    MapEditProposal proposal(Annotation staged, {bool kept = true}) => generationToProposal(
      proposalId: 'p',
      studySetId: 'set',
      mapId: 'new-map',
      baseRevision: assistantMapRevision(before, 'new-map'),
      generation: MapGeneration(
        sources: [MapSource(documentId: 'doc', fingerprint: 'f', readThrough: 1)],
        organization: MapOrganization.chapter,
        depth: 3,
        generatedAt: time,
      ),
      createMap: const MindMap(id: 'new-map', title: 'Generated'),
      excerptAnnotations: [staged],
      lines: [
        MapLine(id: 't', kind: MapLineKind.add, parentId: 'new-map', title: 'Topic'),
        MapLine(id: 'e', kind: MapLineKind.excerpt, parentId: 'new:t', annotationId: 'mark', kept: kept),
      ],
    );
    var id = 0;
    final writes = AssistantWrites(studySetId: 'set', newId: () => 'id-${id++}', now: () => time);
    final p = proposal(mark());
    expect(p.toJson().containsKey('excerptAnnotations'), isFalse);
    final after = writes.apply(before, p, {'t', 'e'});
    expect(after.annotations.single.quote, 'Exact quote');
    expect(after.cardForAnnotation('mark'), isNotNull);
    expect(after.nodes, hasLength(2));
    expect(after.assistantReceipts, hasLength(1));
    final unselected = writes.apply(before, proposal(mark(), kept: false), {'t'});
    expect(unselected.annotations, isEmpty);
    expect(unselected.nodes, hasLength(1));
    for (final invalid in [mark(doc: 'missing'), mark(page: 3), mark(style: AnnotationLineStyle.solid)]) {
      final invalidProposal = proposal(invalid);
      expect(() => writes.apply(before, invalidProposal, {'t', 'e'}), throwsArgumentError);
      expect(before.annotations, isEmpty);
    }
  });
}
