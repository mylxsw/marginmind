import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'study_notes_test.dart' as f;

void main() {
  const collector = NoteMaterialCollector();
  test('incremental insertion follows source positions including insertion before old quotes', () async {
    final later = f.date.add(const Duration(seconds: 1));
    final c = f.content(
      annotations: [
        f.annotation('a', page: 5),
        f.annotation('before', page: 2, createdAt: later),
        f.annotation('after', page: 8, createdAt: later),
      ],
    );
    final all = collector.collect(c, const WholeSet(), NoteSettings(marginNotes: false), now: later);
    final preview = await const NoteUpdater().preview(const LocalNoteOrganizer(), all, f.note());
    final next = const NoteUpdater().apply(f.note(), preview, newId: f.id);
    expect(next.sections.single.blocks.whereType<QuoteBlock>().map((b) => b.annotationId), ['before', 'a', 'after']);
    expect(preview.placements.items.first.beforeBlockId, 'q');
  });

  test('new chapters with identical titles stay separate and new own notes follow their quotes', () async {
    final all = NoteMaterials([
      NoteMaterial(
        ref: 'h1',
        sourceId: 'new1',
        annotationId: 'new1',
        text: 'First',
        groupKey: 'd1:c1',
        groupTitle: 'Same',
        createdAt: f.date,
      ),
      NoteMaterial(
        ref: 'h2',
        sourceId: 'new2',
        annotationId: 'new2',
        text: 'Second',
        groupKey: 'd2:c1',
        groupTitle: 'Same',
        createdAt: f.date,
      ),
      NoteMaterial(
        ref: 'n1',
        sourceId: 'own',
        annotationId: 'new1',
        source: OwnSource.marginNote,
        text: 'Own',
        groupKey: 'd1:c1',
        groupTitle: 'Same',
        createdAt: f.date,
      ),
    ], collectedAt: f.date);
    final n = f.note(sections: []);
    final plan = await const LocalNoteOrganizer().place(all, n);
    final result = const NoteUpdater().apply(
      n,
      NoteUpdatePreview(base: n, materials: all, placements: plan),
      newId: f.id,
    );
    expect(result.sections, hasLength(2));
    expect(result.sections.first.blocks.map((b) => b.runtimeType), [QuoteBlock, OwnBlock]);
    expect(result.sections.last.blocks.single, isA<QuoteBlock>());
  });

  test('placement creates sections, rejects stale targets and reports omitted highlights', () {
    final all = collector.collect(
      f.content(
        annotations: [
          f.annotation('b', createdAt: f.date.add(const Duration(seconds: 1))),
          f.annotation('c', createdAt: f.date.add(const Duration(seconds: 1))),
        ],
      ),
      const WholeSet(),
      NoteSettings(),
      now: f.date,
    );
    final n = f.note();
    NoteUpdatePreview preview(List<NotePlacement> ps) =>
        NoteUpdatePreview(base: n, materials: all, placements: NotePlacements(ps));
    const p = NotePlacement(ref: 'h1', title: 'New', why: 'reason');
    final merged = const NoteUpdater().apply(
      n,
      preview([p, p, const NotePlacement(ref: 'bad', title: 'Bad', why: 'reason')]),
      newId: f.id,
    );
    expect(merged.sections.last.title, 'New');
    expect(merged.unusedAnnotationIds, ['c']);
    expect(
      () => const NoteUpdater().apply(
        n,
        preview([const NotePlacement(ref: 'h1', sectionId: 'missing', title: 'New', why: 'reason')]),
        newId: f.id,
      ),
      throwsStateError,
    );
    expect(
      () => const NoteUpdater().apply(
        n,
        preview([const NotePlacement(ref: 'h1', sectionId: 's', afterBlockId: 'missing', title: 'New', why: 'reason')]),
        newId: f.id,
      ),
      throwsStateError,
    );
    expect(
      () => const NoteUpdater().apply(
        n,
        preview([
          const NotePlacement(ref: 'h1', sectionId: 's', beforeBlockId: 'missing', title: 'New', why: 'reason'),
        ]),
        newId: f.id,
      ),
      throwsStateError,
    );
    expect(
      () => NotePlacements.fromJson({
        'placements': [false],
      }),
      throwsFormatException,
    );
  });

  test('locked own, quote, xref and points survive regeneration and source duplication', () {
    final locked = <StudyNoteBlock>[
      const QuoteBlock(id: 'q', annotationId: 'a', edited: true),
      const OwnBlock(id: 'o', sourceId: 'margin', source: OwnSource.marginNote, edited: true),
      PointsBlock(id: 'p', items: ['Locked'], edited: true),
      const XrefBlock(id: 'x', toSectionId: 's', text: 'Locked link', edited: true),
    ];
    final n = f.note(
      sections: [NoteSection(id: 's', title: 'Old', blocks: locked)],
    );
    final assembly = NoteAssembly(
      sections: [
        NoteSection(
          id: 's',
          title: 'New',
          blocks: [
            const QuoteBlock(id: 'newq', annotationId: 'a'),
            const OwnBlock(id: 'newo', sourceId: 'margin', source: OwnSource.marginNote),
            const TextBlock(id: 'newt', text: 'New text'),
          ],
        ),
      ],
      unusedAnnotationIds: ['a', 'b'],
      rejectedRefs: [],
      usedHighlights: 1,
    );
    final result = const NoteUpdater().reorganize(n, assembly, organizedAt: f.date);
    expect(result.sections.single.blocks.take(4), locked);
    expect(result.sections.single.blocks.whereType<QuoteBlock>().length, 1);
    expect(result.unusedAnnotationIds, ['b']);
  });

  test('archive retained until last note reference disappears, duplicates rejected', () {
    final second = StudyNote.fromJson({...f.note().toJson(), 'id': 'second'});
    var c = f.content().copyWith(studyNotes: [f.note(), second]);
    c = f.editor.deleteAnnotation(c, 'a');
    c = f.editor.deleteStudyNote(c, 'note');
    expect(c.noteSourceArchive, hasLength(1));
    c = f.editor.deleteStudyNote(c, 'second');
    expect(c.noteSourceArchive, isEmpty);
    expect(
      () => f.editor.saveStudyNote(f.content(), f.note(sections: [f.note().sections.single, f.note().sections.single])),
      throwsArgumentError,
    );
    expect(
      () => f.editor.saveStudyNote(
        f.content(),
        f.note(
          sections: [
            NoteSection(
              id: 's',
              title: 'x',
              blocks: [
                const QuoteBlock(id: 'duplicate', annotationId: 'a'),
                const TextBlock(id: 'duplicate', text: 'x'),
              ],
            ),
          ],
        ),
      ),
      throwsArgumentError,
    );
  });

  test('rich source edits and exporter resolve cards, saved AI, images and cross-links', () {
    final n = f.note(
      sections: [
        NoteSection(
          id: 's',
          title: 'A [title]',
          blocks: [
            const QuoteBlock(id: 'q', annotationId: 'a'),
            const OwnBlock(id: 'card', sourceId: 'card', source: OwnSource.card),
            const OwnBlock(id: 'research', sourceId: 'r', source: OwnSource.researchNote, origin: NoteOrigin.ai),
            const OwnBlock(id: 'image', sourceId: 'image', source: OwnSource.image),
            const XrefBlock(id: 'link', toSectionId: 's', text: 'See section'),
            const XrefBlock(id: 'missing', toSectionId: 'missing', text: 'missing'),
            const TextBlock(id: 'mixed', text: 'Edited AI', origin: NoteOrigin.mixed, edited: true),
          ],
        ),
      ],
    );
    var c = f.content().copyWith(
      studyNotes: [n],
      cards: [
        Card(
          id: 'card',
          kind: CardKind.note,
          title: '**Bold**',
          body: 'Body',
          textFormat: TextFormat.markdown,
          createdAt: f.date,
        ),
        Card(id: 'image', kind: CardKind.image, imageFileName: 'images/hash.png', createdAt: f.date),
      ],
      researchNotes: [
        ResearchNote(
          id: 'r',
          title: 'Research',
          body: 'AI note',
          origin: NoteOrigin.ai,
          createdAt: f.date,
          updatedAt: f.date,
        ),
      ],
    );
    final result = NoteExporter(c).export(n, format: NoteExportFormat.obsidian);
    expect(result.attachments, {'attachments/hash.png': 'images/hash.png'});
    expect(result.text, contains('AI · 已改'));
    expect(result.text, contains('[See section](#section-1)'));
    expect(result.text, isNot(contains('[missing]')));
    expect(result.text, contains('Bold\n> Body'));
    expect(NoteExporter(c).export(n).text, contains('![](attachments/hash.png)'));
    c = f.editor.editStudyNoteBlock(c, 'note', 'card', text: 'New card');
    c = f.editor.editStudyNoteBlock(c, 'note', 'research', text: 'New research');
    c = f.editor.editStudyNoteBlock(c, 'note', 'link', text: 'New link');
    expect(c.card('card')!.title, 'New card');
    expect(c.card('card')!.body, isEmpty);
    expect(c.researchNote('r')!.origin, NoteOrigin.mixed);
    expect(c.studyNote('note')!.sections.single.blocks.whereType<XrefBlock>().first.text, 'New link');
    expect(() => f.editor.editStudyNoteBlock(c, 'note', 'image', text: 'bad'), throwsArgumentError);
    expect(() => f.editor.editStudyNoteBlock(c.copyWith(cards: []), 'note', 'card', text: 'bad'), throwsStateError);
    expect(
      () => f.editor.editStudyNoteBlock(c.copyWith(researchNotes: []), 'note', 'research', text: 'bad'),
      throwsStateError,
    );
    expect(
      () => f.editor.editStudyNoteBlock(f.content().copyWith(marginNotes: []), 'note', 'o', text: 'bad'),
      throwsStateError,
    );
    expect(() => f.editor.editStudyNoteBlock(f.content(), 'note', 'o'), throwsArgumentError);
  });

  test('selected and branch collection attach anchored margin notes and descendant own notes', () {
    final a = f.annotation('a');
    final c = f.content().copyWith(
      cards: [
        Card(id: 'excerpt', kind: CardKind.excerpt, annotationId: 'a', createdAt: f.date),
        Card(id: 'own', kind: CardKind.note, title: 'Own', createdAt: f.date),
        Card(id: 'image', kind: CardKind.image, annotationId: 'a', imageFileName: 'images/a.png', createdAt: f.date),
        Card(id: 'research', kind: CardKind.research, researchNoteId: 'r', createdAt: f.date),
      ],
      nodes: const [
        MapNode(cardId: 'excerpt', order: 0),
        MapNode(cardId: 'own', parentId: 'excerpt', order: 0),
        MapNode(cardId: 'image', parentId: 'excerpt', order: 1),
        MapNode(cardId: 'research', parentId: 'excerpt', order: 2),
      ],
      researchNotes: [
        ResearchNote(
          id: 'r',
          title: 'R',
          body: 'Research',
          origin: NoteOrigin.ai,
          createdAt: f.date,
          updatedAt: f.date,
        ),
        ResearchNote(id: 'unmapped', title: 'U', body: 'Unmapped', createdAt: f.date, updatedAt: f.date),
      ],
      marginNotes: [
        MarginNote(
          id: 'margin',
          documentId: 'd',
          page: 1,
          anchor: AnnotationAnchor(pages: a.pages, quote: a.quote),
          text: 'Anchored',
          colorIndex: 0,
          createdAt: f.date,
          updatedAt: f.date,
        ),
      ],
    );
    final settings = NoteSettings(researchNotes: true, images: true);
    final all = collector.collect(c, SelectedAnnotations(['a']), settings, now: f.date);
    expect(all.items.map((m) => m.sourceId), containsAll(['a', 'margin', 'own', 'image', 'r']));
    expect(all.items.where((m) => !m.isHighlight).every((m) => m.annotationId == 'a'), isTrue);
    final whole = collector.collect(c, const WholeSet(), settings, now: f.date);
    expect(whole.items.where((m) => m.sourceId == 'r'), hasLength(1));
    expect(whole.items.any((m) => m.sourceId == 'unmapped'), isTrue);
    final assembled = const NoteAssembler().assemble(
      NoteDraft.fromJson({
        'sections': [
          {
            'title': 'S',
            'blocks': [
              {'type': 'quote', 'ref': 'h1'},
              {'type': 'own', 'ref': 'n1'},
            ],
          },
        ],
      }),
      all,
      newId: f.id,
    );
    expect(assembled.sections.single.blocks.whereType<OwnBlock>(), hasLength(4));
    final removed = f.editor.removeFromMap(f.editor.saveStudyNote(c, f.note()), 'image');
    expect(removed.noteSourceArchive.single.annotation.id, 'a');
  });

  test('multi-page PDF quotes use exact page text and at most three surrounding sentences', () {
    final a = Annotation(
      id: 'multi',
      documentId: 'd',
      pages: const [
        AnnotationPage(page: 3, rects: [PageRect(1, 20, 10, 10)]),
        AnnotationPage(page: 4, rects: [PageRect(1, 20, 10, 10)]),
      ],
      quote: 'first half\nsecond half.',
      colorIndex: 0,
      createdAt: f.date,
    );
    const text = NoteTextSource(
      pages: {
        'd': {
          1: 'One.',
          2: 'Two.',
          3: 'Three.first half',
          4: 'second half.After one.',
          5: 'After two.',
          6: 'After three.',
          7: 'After four.',
        },
      },
    );
    final context = collector.contextFor(f.content(), a, 3, text: text);
    expect(context.before.replaceAll('\n', ''), 'One.Two.Three.');
    expect(context.after.replaceAll('\n', ''), 'After one.After two.After three.');
    final blocked = f.content().copyWith(
      documentOutlines: [
        const DocumentOutline(
          documentId: 'd',
          items: [PdfOutlineEntry(id: 'next', title: 'Next', page: 4)],
        ),
      ],
    );
    expect(collector.contextFor(blocked, a, 3, text: text).unresolved, isTrue);
  });

  test('saved research notes follow PDF/text/card targets without duplicates', () {
    final a = f.annotation('a');
    final anchor = TextAnchor('ch', 0, 2, '原文', revision: 'v');
    final c = f.content().copyWith(
      researchNotes: [
        for (final id in ['pdf', 'text', 'card'])
          ResearchNote(id: id, title: id, body: id, createdAt: f.date, updatedAt: f.date),
      ],
      cards: [Card(id: 'c', kind: CardKind.note, title: 'My note', createdAt: f.date)],
      nodes: const [MapNode(cardId: 'c', order: 0)],
      noteAttachments: [
        NoteAttachment(
          id: '1',
          noteId: 'pdf',
          target: PdfTarget(documentId: 'd', pages: a.pages, quote: a.quote),
        ),
        NoteAttachment(
          id: '2',
          noteId: 'text',
          target: TextTarget(documentId: 'd', textAnchors: [anchor]),
        ),
        const NoteAttachment(
          id: '3',
          noteId: 'card',
          target: CardTarget(cardId: 'c'),
        ),
      ],
    );
    final items = collector.collect(c, const WholeSet(), NoteSettings(researchNotes: true), now: f.date).items;
    expect(items.where((m) => m.source == OwnSource.researchNote).map((m) => m.sourceId), ['pdf', 'text', 'card']);
    expect(
      collector
          .collect(c, const DocumentScope('d'), NoteSettings(researchNotes: true), now: f.date)
          .items
          .where((m) => m.source == OwnSource.researchNote)
          .map((m) => m.sourceId),
      ['pdf', 'text'],
    );
  });

  test('PDF adjacent pages cannot leak past the next chapter', () {
    final c = f.content().copyWith(
      documentOutlines: [
        const DocumentOutline(
          documentId: 'd',
          items: [
            PdfOutlineEntry(id: 's', title: 'First', page: 1),
            PdfOutlineEntry(id: 't', title: 'Second', page: 2),
          ],
        ),
      ],
    );
    final context = collector.contextFor(
      c,
      f.annotation('a'),
      3,
      text: const NoteTextSource(
        pages: {
          'd': {1: 'Before.记忆需要练习。After.', 2: 'Next chapter must not appear.'},
        },
      ),
    );
    expect(context.after, 'After.');
    expect(NoteExporter(c).export(f.note()).text, contains('无原文文本'));
    final missing = c.copyWith(annotations: [], documents: []);
    expect(NoteExporter(missing).export(f.note()).text, contains('划线已删除'));
  });
}
