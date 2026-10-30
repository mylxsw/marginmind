import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

final date = DateTime.utc(2026, 10, 30);
var serial = 0;
String id() => 'generated-${serial++}';
StudyNote note({List<NoteSection>? sections, NoteScope scope = const WholeSet()}) => StudyNote(
  id: 'note',
  title: '学习笔记',
  scope: scope,
  settings: NoteSettings(),
  createdAt: date,
  updatedAt: date,
  organizedAt: date,
  sections:
      sections ??
      [
        NoteSection(
          id: 's',
          title: 'Book',
          question: '怎么学习？',
          blocks: [
            const QuoteBlock(id: 'q', annotationId: 'a', contextOpen: true),
            const OwnBlock(id: 'o', sourceId: 'margin', source: OwnSource.marginNote),
            const TextBlock(id: 't', text: '主动回想。', kind: TextKind.summary),
            PointsBlock(id: 'p', items: ['间隔复习', '主动练习']),
            const TextBlock(id: 'task', text: '每天复习', kind: TextKind.action),
          ],
        ),
      ],
);
Annotation annotation(String id, {int page = 1, DateTime? createdAt, String quote = '记忆需要练习。'}) => Annotation(
  id: id,
  documentId: 'd',
  page: page,
  rects: const [PageRect(1, 20, 10, 10)],
  quote: quote,
  colorIndex: 0,
  createdAt: createdAt ?? date,
);
StudySetContent content({List<Annotation>? annotations}) => StudySetContent(
  documents: [Document(id: 'd', title: 'Book', fileName: 'book.pdf', pageCount: 10, importedAt: date)],
  annotations: annotations ?? [annotation('a')],
  marginNotes: [
    MarginNote(
      id: 'margin',
      documentId: 'd',
      page: 1,
      lineY: 3,
      text: '我的心得',
      colorIndex: 0,
      createdAt: date,
      updatedAt: date,
    ),
  ],
  studyNotes: [note()],
);
const texts = NoteTextSource(
  pages: {
    'd': {1: '前言。记忆需要练习。回想有帮助！下一句？'},
  },
);
const collector = NoteMaterialCollector();
const local = LocalNoteOrganizer();
final editor = StudySetEditor(newId: id, now: () => date.add(const Duration(hours: 1)));

void golden(String name, String value) {
  final file = File('test/goldens/$name');
  if (Platform.environment['UPDATE_GOLDENS'] == '1') file.writeAsStringSync(value);
  expect(value, file.readAsStringSync(), reason: name);
}

void main() {
  setUp(() => serial = 0);
  test('legacy JSON is empty; all entities and scopes round trip without quote copies', () {
    expect(StudySetContent.fromJson({}).studyNotes, isEmpty);
    expect(StudySetContent.empty.toJson().containsKey('studyNotes'), isFalse);
    final scopes = <NoteScope>[
      SelectedAnnotations(['a']),
      const WholeSet(),
      const DocumentScope('d'),
      const BranchScope('main', 'root'),
      SinceScope(date),
    ];
    for (final scope in scopes) {
      final n = note(scope: scope).copyWith(
        template: NoteTemplate.cornell,
        unusedAnnotationIds: ['unused'],
        sections: [
          ...note().sections,
          NoteSection(
            id: 'other',
            title: 'Other',
            blocks: [
              const XrefBlock(id: 'x', toSectionId: 's', text: '相关'),
              const TextBlock(
                id: 'g',
                text: '它是记忆',
                kind: TextKind.gloss,
                annotationId: 'a',
                origin: NoteOrigin.mixed,
                edited: true,
              ),
            ],
          ),
        ],
      );
      final c = content().copyWith(
        studyNotes: [n],
        noteSourceArchive: [NoteSourceArchive(annotation: annotation('old'), documentTitle: 'Old')],
      );
      final encoded = jsonEncode(c.toJson());
      expect(jsonEncode(StudySetContent.fromJson(jsonDecode(encoded)).toJson()), encoded);
    }
    expect(const QuoteBlock(id: 'q', annotationId: 'a').toJson().containsKey('quote'), isFalse);
    expect(() => note().sections.clear(), throwsUnsupportedError);
    expect(() => NoteSettings(contextSentences: 4), throwsArgumentError);
    expect(() => NoteScope.fromJson({'type': 'bad'}), throwsFormatException);
    expect(() => StudyNoteBlock.fromJson({'type': 'bad', 'id': 'b', 'origin': 'ai'}), throwsFormatException);
    expect(NoteSettings(depth: NoteDepth.none).effectiveOrganization, NoteOrganization.source);
  });

  test('source deletion archives only referenced quotes and undo restores live reading', () {
    final before = content(annotations: [annotation('a'), annotation('unused')]);
    final after = editor.deleteAnnotation(before, 'a');
    expect(after.noteSourceArchive.single.annotation.quote, '记忆需要练习。');
    expect(resolveNoteSource(after, 'a').status, NoteSourceStatus.annotationDeleted);
    expect(NoteExporter(after).export(note()).text, contains('记忆需要练习。'));
    expect(collector.collect(after, const WholeSet(), NoteSettings(), now: date).highlights.single.sourceId, 'unused');
    final restored = StudySetEditor.restore(before, after);
    expect(restored.noteSourceArchive, isEmpty);
    expect(resolveNoteSource(restored, 'a').status, NoteSourceStatus.available);
    final changed = restored.copyWith(annotations: [annotation('a').copyWith(colorIndex: 2)]);
    expect(resolveNoteSource(changed, 'a').annotation!.colorIndex, 2);
    expect(editor.deleteAnnotation(before, 'unused').noteSourceArchive, isEmpty);
    expect(editor.deleteStudyNote(after, 'note').noteSourceArchive, isEmpty);
    expect(editor.saveStudyNote(after, note(sections: [])).noteSourceArchive, isEmpty);
    final removed = editor.removeDocument(before, 'd');
    expect(resolveNoteSource(removed, 'a').status, NoteSourceStatus.documentRemoved);
    expect(resolveNoteSource(removed, 'a').documentTitle, 'Book');
    expect(resolveNoteSource(before, 'unknown').status, NoteSourceStatus.missing);
  });

  test('edits sync own notes, mark mixed, and can be restored atomically', () {
    final c = content();
    final edited = editor.editStudyNoteBlock(c, 'note', 't', text: '我的理解');
    final block = edited.studyNotes.single.sections.single.blocks.whereType<TextBlock>().first;
    expect(block.origin, NoteOrigin.mixed);
    expect(block.edited, isTrue);
    final own = editor.editStudyNoteBlock(edited, 'note', 'o', text: '新心得');
    expect(own.marginNotes.single.text, '新心得');
    expect(NoteExporter(own).export(own.studyNotes.single).text, contains('新心得'));
    expect(StudySetEditor.restore(c, own).marginNotes.single.text, '我的心得');
    expect(() => editor.editStudyNoteBlock(c, 'note', 'q', text: 'forged'), throwsArgumentError);
    expect(() => editor.editStudyNoteBlock(c, 'missing', 'q'), throwsArgumentError);
    expect(() => editor.editStudyNoteBlock(c, 'note', 'missing'), throwsArgumentError);
    final points = editor.editStudyNoteBlock(c, 'note', 'p', items: ['新的要点']);
    expect(points.studyNotes.single.sections.single.blocks.whereType<PointsBlock>().single.items, ['新的要点']);
  });

  test('context handles punctuation, paragraphs, 0–3 sentences and chapter boundaries', () {
    const body = 'Outside.\n第一句。Second!\n记忆需要练习。After?最后一句。Outside end.';
    final start = body.indexOf('记忆'), end = start + '记忆需要练习。'.length;
    final a = Annotation(
      id: 'a',
      documentId: 'd',
      textAnchors: [TextAnchor('ch', start, end, '记忆需要练习。', revision: 'v')],
      quote: '记忆需要练习。',
      colorIndex: 0,
      createdAt: date,
    );
    final c = content(annotations: [a]).copyWith(
      documentOutlines: [
        DocumentOutline(
          documentId: 'd',
          items: [
            PdfOutlineEntry(
              id: 'chapter',
              title: 'Chapter',
              position: TextReadingPosition(revision: 'v', chapterId: 'ch', offset: body.indexOf('第一')),
            ),
            PdfOutlineEntry(
              id: 'next',
              title: 'Next',
              position: TextReadingPosition(revision: 'v', chapterId: 'ch', offset: body.indexOf('Outside end')),
            ),
          ],
        ),
      ],
    );
    const source = NoteTextSource(
      chapters: {
        'd': {'ch': body},
      },
    );
    for (var n = 0; n <= 3; n++) {
      final ctx = collector.contextFor(c, a, n, text: source);
      expect(ctx.noText, isFalse);
      expect(ctx.unresolved, isFalse);
      expect('${ctx.before}${ctx.after}', isNot(contains('Outside')));
      if (n == 0) {
        expect(ctx.before, isEmpty);
        expect(ctx.after, isEmpty);
      }
      if (n == 1) {
        expect(ctx.before, 'Second!');
        expect(ctx.after, 'After?');
      }
      if (n >= 2) {
        expect(ctx.before, '第一句。Second!');
        expect(ctx.after, 'After?最后一句。');
      }
    }
    expect(
      collector.collect(c, const WholeSet(), NoteSettings(), now: date, text: source).highlights.single.groupTitle,
      'Chapter',
    );
    expect(collector.contextFor(c, a, 1).noText, isTrue);
    expect(
      collector
          .contextFor(
            c,
            a,
            1,
            text: const NoteTextSource(
              chapters: {
                'd': {'ch': 'stale'},
              },
            ),
          )
          .unresolved,
      isTrue,
    );
    expect(() => collector.contextFor(c, a, -1), throwsArgumentError);
  });

  test('PDF text ambiguity, no text and chapter boundary never borrow guessed text', () {
    final a = annotation('a');
    final c = content();
    expect(collector.contextFor(c, a, 1, text: texts).before, '前言。');
    expect(collector.contextFor(c, a, 1, text: texts).after, '回想有帮助！');
    expect(collector.contextFor(c, a, 1).noText, isTrue);
    expect(
      collector
          .contextFor(
            c,
            a,
            1,
            text: const NoteTextSource(
              pages: {
                'd': {1: '记忆需要练习。记忆需要练习。'},
              },
            ),
          )
          .unresolved,
      isTrue,
    );
    final boundary = c.copyWith(
      documentOutlines: [
        const DocumentOutline(
          documentId: 'd',
          items: [PdfOutlineEntry(id: 'new', title: 'new', page: 2)],
        ),
      ],
    );
    expect(
      collector
          .contextFor(
            boundary,
            annotation('a', page: 2),
            3,
            text: const NoteTextSource(
              pages: {
                'd': {2: '前章。记忆需要练习。后文。'},
              },
            ),
          )
          .unresolved,
      isTrue,
    );
  });

  test('fragment rules are local and deterministic', () {
    for (final quote in ['短句', '这是一条足够长但有指代的句子。', '因此需要采用更加复杂的学习方法。', '上述研究证明了学习的方法有效。']) {
      expect(NoteMaterialCollector.isFragment(quote), isTrue);
    }
    expect(NoteMaterialCollector.isFragment('长期练习能够有效改善人们的记忆能力。'), isFalse);
  });

  test('all scopes and cutoff preserve material IDs and reading order', () {
    final c = content(
      annotations: [
        annotation('late', page: 4, createdAt: date.add(const Duration(seconds: 1))),
        annotation('a'),
      ],
    );
    final all = collector.collect(c, const WholeSet(), NoteSettings(), now: date.add(const Duration(days: 1)));
    expect(all.highlights.map((m) => m.sourceId), ['a', 'late']);
    expect(all.since(date).highlights.single.ref, 'h2');
    expect(
      collector.collect(c, SelectedAnnotations(['late']), NoteSettings(), now: date).highlights.single.sourceId,
      'late',
    );
    expect(collector.collect(c, const DocumentScope('other'), NoteSettings(), now: date).items, isEmpty);
    expect(
      collector
          .collect(c, SinceScope(date.add(const Duration(seconds: 1))), NoteSettings(), now: date)
          .items
          .single
          .sourceId,
      'late',
    );
    expect(collector.collect(c, const BranchScope('main', 'missing'), NoteSettings(), now: date).items, isEmpty);
    expect(() => NoteMaterials([all.items.first, all.items.first], collectedAt: date), throwsArgumentError);
  });

  test('local organizer groups source chapters and ordered map branches', () async {
    final c = content(annotations: [annotation('b', page: 3), annotation('a')]).copyWith(
      cards: [
        Card(id: 'root', kind: CardKind.topic, title: 'Root', createdAt: date),
        Card(id: 'ca', kind: CardKind.excerpt, annotationId: 'a', createdAt: date),
        Card(id: 'cb', kind: CardKind.excerpt, annotationId: 'b', createdAt: date),
        Card(id: 'own', kind: CardKind.note, title: 'Map note', createdAt: date),
      ],
      nodes: const [
        MapNode(cardId: 'root', order: 0),
        MapNode(cardId: 'cb', parentId: 'root', order: 0),
        MapNode(cardId: 'ca', parentId: 'root', order: 1),
        MapNode(cardId: 'own', parentId: 'root', order: 2),
      ],
      documentOutlines: [
        const DocumentOutline(
          documentId: 'd',
          items: [
            PdfOutlineEntry(id: 'first', title: 'First', page: 1),
            PdfOutlineEntry(id: 'second', title: 'Second', page: 3),
          ],
        ),
      ],
    );
    final settings = NoteSettings(organization: NoteOrganization.map, depth: NoteDepth.none, marginNotes: false);
    final materials = collector.collect(c, const BranchScope(MindMap.defaultId, 'root'), settings, now: date);
    final outline = await local.outline(materials, settings);
    expect(outline.sections.single.title, 'Root');
    expect(outline.sections.single.refs, ['h2', 'h1', 'n1']);
    final source = await local.outline(materials, NoteSettings(organization: NoteOrganization.source));
    expect(source.sections.map((s) => s.title), containsAll(['First', 'Second']));
    final draft = await local.write(materials, outline, settings);
    expect(draft.sections.single.blocks.first.ref, 'h2');
    expect(NoteOutline.fromJson(outline.toJson()).toJson(), outline.toJson());
    expect(NoteDraft.fromJson(draft.toJson()).toJson(), draft.toJson());
  });

  test('assembler rejects unknown IDs, deduplicates, skips empty sections and resolves xrefs', () {
    final materials = collector.collect(
      content(annotations: [annotation('a'), annotation('b')]),
      const WholeSet(),
      NoteSettings(),
      now: date,
    );
    final draft = NoteDraft.fromJson({
      'sections': [
        {
          'title': 'Empty',
          'blocks': [
            {'type': 'quote', 'ref': 'unknown'},
          ],
        },
        {
          'title': 'First',
          'blocks': [
            {'type': 'quote', 'ref': 'h1'},
            {'type': 'quote', 'ref': 'h1'},
            {'type': 'gloss', 'ref': 'h1', 'text': '解释'},
            {'type': 'xref', 'to': 0, 'text': '失效链接'},
            {'type': 'xref', 'to': 2, 'text': '另见'},
            {
              'type': 'points',
              'items': ['要点'],
            },
          ],
        },
        {
          'title': 'Last',
          'blocks': [
            {'type': 'summary', 'text': '总结'},
            {'type': 'own', 'ref': 'n1'},
            {'type': 'quote', 'ref': 'n1'},
            {'type': 'xref', 'to': 90, 'text': 'bad'},
          ],
        },
      ],
    });
    final result = const NoteAssembler().assemble(draft, materials, newId: id);
    expect(result.sections.map((s) => s.title), ['First', 'Last']);
    expect(result.usedHighlights, 1);
    expect(result.unusedAnnotationIds, ['b']);
    expect(result.rejectedRefs, containsAll(['unknown', 'n1', 'section:90']));
    final links = result.sections.expand((s) => s.blocks).whereType<XrefBlock>();
    expect(links.single.toSectionId, result.sections.last.id);
  });

  test('schema rejects fabricated quote text; retries once then deterministic fallback', () async {
    expect(
      () => NoteDraft.fromJson({
        'sections': [
          {
            'title': 'bad',
            'blocks': [
              {'type': 'quote', 'ref': 'h1', 'text': 'forged'},
            ],
          },
        ],
      }),
      throwsFormatException,
    );
    for (final j in <Map<String, Object?>>[
      {},
      {'sections': 'bad'},
      {
        'sections': [1],
      },
      {'extra': 1, 'sections': []},
      {
        'sections': [
          {'title': '', 'blocks': []},
        ],
      },
      {
        'sections': [
          {
            'title': 'bad',
            'blocks': [
              {'type': 'unknown'},
            ],
          },
        ],
      },
      {
        'sections': [
          {
            'title': 'bad',
            'blocks': [
              {'type': 'xref', 'to': -1, 'text': 'bad'},
            ],
          },
        ],
      },
      {
        'sections': [
          {
            'title': 'bad',
            'blocks': [
              {'type': 'points', 'items': []},
            ],
          },
        ],
      },
    ]) {
      expect(() => NoteDraft.fromJson(j), throwsFormatException);
    }
    final fake = BadOrganizer();
    final materials = collector.collect(content(), const WholeSet(), NoteSettings(), now: date);
    final result = await const NoteOrganizationRunner().run(fake, materials, NoteSettings(), newId: id);
    expect(fake.attempts, 2);
    expect(result.usedFallback, isTrue);
    expect(result.assembly.usedHighlights, 1);
    final noAi = await const NoteOrganizationRunner().run(
      fake,
      materials,
      NoteSettings(depth: NoteDepth.none),
      newId: id,
    );
    expect(fake.attempts, 2);
    expect(noAi.usedFallback, isFalse);
    final success = await const NoteOrganizationRunner().run(local, materials, NoteSettings(), newId: id);
    expect(success.usedFallback, isFalse);
  });

  test('incremental merge locks edited blocks, rejects stale previews, cutoff is collection time', () async {
    final old = editor.editStudyNoteBlock(content(), 'note', 't', text: 'Do not overwrite').studyNotes.single;
    final materials = collector.collect(
      content(
        annotations: [
          annotation('a'),
          annotation('b', createdAt: date.add(const Duration(seconds: 1))),
        ],
      ),
      const WholeSet(),
      NoteSettings(),
      now: date.add(const Duration(seconds: 5)),
    );
    final preview = await const NoteUpdater().preview(local, materials, old);
    expect(preview.materials.highlights.single.sourceId, 'b');
    expect(NotePlacements.fromJson(preview.placements.toJson()).toJson(), preview.placements.toJson());
    final merged = const NoteUpdater().apply(old, preview, newId: id);
    expect(merged.sections.single.blocks.whereType<QuoteBlock>().map((b) => b.annotationId), ['a', 'b']);
    expect(
      merged.sections.single.blocks.where((b) => b.id == 't').single,
      same(old.sections.single.blocks.where((b) => b.id == 't').single),
    );
    expect(merged.organizedAt, materials.collectedAt);
    expect(() => const NoteUpdater().apply(old.copyWith(title: 'changed'), preview, newId: id), throwsStateError);
    final assembly = const NoteAssembler().assemble(
      await local.write(materials, await local.outline(materials, old.settings), old.settings),
      materials,
      newId: id,
    );
    final reorganized = const NoteUpdater().reorganize(old, assembly, organizedAt: materials.collectedAt);
    expect(reorganized.sections.expand((s) => s.blocks).whereType<TextBlock>().single.text, 'Do not overwrite');
  });

  test('export goldens cover both formats, three citation styles and every switch combination', () {
    final exporter = NoteExporter(content(), textSource: texts);
    final matrix = <String, String>{};
    for (final format in NoteExportFormat.values) {
      for (final style in NoteCitationStyle.values) {
        golden(
          'study_note_${format.name}_${style.name}.md',
          exporter
              .export(
                note(),
                format: format,
                options: NoteExportOptions(citations: style),
              )
              .text,
        );
        for (var bits = 0; bits < 64; bits++) {
          bool on(int n) => bits & (1 << n) != 0;
          final result = exporter.export(
            note(),
            format: format,
            options: NoteExportOptions(
              citations: style,
              context: on(0),
              ownNotes: on(1),
              aiContent: on(2),
              questions: on(3),
              sources: on(4),
              markAi: on(5),
            ),
          );
          expect(result.text.contains('我的心得'), on(1));
          expect(result.text.contains('主动回想。'), on(2));
          expect(result.text.contains('怎么学习？'), on(3));
          expect(result.text.contains('## 出处'), on(4));
          expect(result.text.contains('前言。'), on(0));
          if (!on(5)) expect(result.text, isNot(contains('AI 整理')));
          matrix['${format.name}/${style.name}/$bits'] = sha256.convert(utf8.encode(result.text)).toString();
        }
      }
    }
    golden('study_note_switches.json', '${const JsonEncoder.withIndent('  ').convert(matrix)}\n');
  });
}

class BadOrganizer implements NoteOrganizer {
  int attempts = 0;
  @override
  Future<NoteOutline> outline(NoteMaterials materials, NoteSettings settings) async {
    attempts++;
    throw const FormatException('bad schema');
  }

  @override
  Future<NoteDraft> write(NoteMaterials materials, NoteOutline outline, NoteSettings settings) =>
      throw UnimplementedError();
  @override
  Future<NotePlacements> place(NoteMaterials materials, StudyNote note) => throw UnimplementedError();
}
