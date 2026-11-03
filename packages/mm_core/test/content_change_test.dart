import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  late StudySetEditor editor;
  var count = 0;
  setUp(() {
    count = 0;
    editor = StudySetEditor(newId: () => 'id${++count}', now: () => DateTime.utc(2026));
  });

  test('nested immutable generation metadata supports conditional undo without changing input snapshots', () {
    final (withDoc, doc) = editor.addDocument(StudySetContent.empty, title: 'Book', fileName: 'a.pdf', pageCount: 1);
    final (content, card) = editor.addTopic(withDoc, title: 'Topic');
    final generation = MapGeneration(
      sources: [MapSource(documentId: doc.id, fingerprint: 'source', readThrough: 1)],
      organization: MapOrganization.chapter,
      depth: 3,
      generatedAt: DateTime.utc(2026),
      generated: {card.id: 'old'},
    );
    StudySetContent withVersions(Map<String, String> values) =>
        content.copyWith(maps: [content.maps.single.copyWith(generation: generation.withGenerated(values))]);
    final before = withVersions({card.id: 'old'});
    final after = withVersions({card.id: 'new', 'added': 'local'});
    final current = withVersions({card.id: 'new', 'added': 'local', 'remote': 'retained'});
    final change = ContentChange.between(before, after);
    final undone = change.reversed.apply(current);
    expect(undone.maps.single.generation!.generated, {card.id: 'old', 'remote': 'retained'});
    expect(change.apply(undone).toJson(), current.toJson());
    expect(current.maps.single.generation!.generated, {card.id: 'new', 'added': 'local', 'remote': 'retained'});
    expect(after.maps.single.generation!.generated, {card.id: 'new', 'added': 'local'});
    expect(before.maps.single.generation!.generated, {card.id: 'old'});
    expect(change.followedBy(change.reversed).isEmpty, isTrue);

    // The inverse removes its added key before noticing this later conflict.
    // Failed staging must leave both the remote and original maps untouched.
    final conflicted = withVersions({card.id: 'remote value', 'added': 'local'});
    expect(() => change.reversed.apply(conflicted), throwsA(isA<ContentChangeConflict>()));
    expect(conflicted.maps.single.generation!.generated, {card.id: 'remote value', 'added': 'local'});
  });

  test('undo and redo only change owned fields; unrelated remote additions survive', () {
    final (base, card) = editor.addNote(StudySetContent.empty, text: 'original');
    final edited = editor.rename(base, card.id, 'local');
    final change = ContentChange.between(base, edited);
    final (remote, extra) = editor.addTopic(edited, title: 'remote');
    final undone = change.reversed.apply(remote);
    expect(undone.card(card.id)!.title, 'original');
    expect(undone.card(extra.id)!.title, 'remote');
    expect(change.apply(undone).toJson(), remote.toJson());
  });

  test('same field changed remotely rejects whole inverse, retaining both inputs', () {
    final (base, card) = editor.addTopic(StudySetContent.empty, title: 'original');
    final edited = editor.rename(base, card.id, 'local');
    final remote = editor.rename(edited, card.id, 'remote');
    final change = ContentChange.between(base, edited);
    expect(() => change.reversed.apply(remote), throwsA(isA<ContentChangeConflict>()));
    expect(remote.card(card.id)!.title, 'remote');
    expect(edited.card(card.id)!.title, 'local');
    expect(change.fields.single.path, ['cards', card.id, 'title']);
  });

  test('different fields on the same card remain independent', () {
    final (base, card) = editor.addNote(StudySetContent.empty, text: 'old');
    final edited = editor.rename(base, card.id, 'local');
    final remote = edited.copyWith(cards: [edited.cards.single.copyWith(body: 'remote body')]);
    final undone = ContentChange.between(base, edited).reversed.apply(remote);
    expect(undone.cards.single.title, 'old');
    expect(undone.cards.single.body, 'remote body');
  });

  test('an inverse cannot remove a parent used by a new remote child', () {
    final base = StudySetContent.empty;
    final (edited, parent) = editor.addTopic(base, title: 'parent');
    final (remote, child) = editor.addTopic(edited, title: 'remote child', parentId: parent.id);
    expect(() => ContentChange.between(base, edited).reversed.apply(remote), throwsA(isA<ContentChangeConflict>()));
    expect(remote.node(child.id)!.parentId, parent.id);
  });

  test('compound excerpt is all-or-nothing when its annotation changed', () {
    final (base, doc) = editor.addDocument(StudySetContent.empty, title: 'book', fileName: 'a.pdf', pageCount: 9);
    final (edited, card) = editor.createExcerpt(
      base,
      documentId: doc.id,
      page: 1,
      rects: const [PageRect(1, 10, 30, 2)],
      quote: 'quote',
      colorIndex: 0,
    );
    final remote = editor.recolor(edited, card.annotationId!, 2);
    expect(() => ContentChange.between(base, edited).reversed.apply(remote), throwsA(isA<ContentChangeConflict>()));
    expect(remote.cards, hasLength(1));
    expect(remote.annotations.single.colorIndex, 2);
  });

  test('review and reading changes are excluded from history and retained by undo', () {
    final (withDoc, doc) = editor.addDocument(StudySetContent.empty, title: 'book', fileName: 'a.pdf', pageCount: 9);
    final (base, card) = editor.addNote(withDoc, text: 'question');
    final edited = editor.rename(base, card.id, 'edited');
    final later = editor.rate(editor.setLastPage(edited, doc.id, 7), card.id, Rating.good);
    expect(ContentChange.between(edited, later).isEmpty, isTrue);
    final undone = ContentChange.between(base, edited).reversed.apply(later);
    expect(undone.documents.single.lastPage, 7);
    expect(undone.reviewLogs.single.id, later.reviewLogs.single.id);
    expect(undone.cards.single.title, 'question');
    // Reading a just-created document must not prevent undoing its import.
    final read = editor.setLastPage(withDoc, doc.id, 4);
    expect(ContentChange.between(StudySetContent.empty, withDoc).reversed.apply(read).documents, isEmpty);
  });

  test('composed transaction does not capture intervening remote changes', () {
    final (base, a) = editor.addTopic(StudySetContent.empty, title: 'A');
    final one = editor.rename(base, a.id, 'one');
    final (remote, b) = editor.addTopic(one, title: 'B remote');
    final two = editor.rename(remote, a.id, 'two');
    final change = ContentChange.between(base, one).followedBy(ContentChange.between(remote, two));
    final undone = change.reversed.apply(two);
    expect(undone.card(a.id)!.title, 'A');
    expect(undone.card(b.id)!.title, 'B remote');
    expect(change.apply(undone).toJson(), two.toJson());
  });

  test('intervening same-field edit in a transaction cannot be silently undone', () {
    final (base, a) = editor.addTopic(StudySetContent.empty, title: 'A');
    final one = editor.rename(base, a.id, 'one');
    final remote = editor.rename(one, a.id, 'remote');
    final two = editor.rename(remote, a.id, 'A');
    final change = ContentChange.between(base, one).followedBy(ContentChange.between(remote, two));
    expect(change.isEmpty, isFalse);
    expect(() => change.reversed.apply(two), throwsA(isA<ContentChangeConflict>()));
  });

  test('create, rename, delete composes to a no-op; changes are immutable', () {
    final base = StudySetContent.empty;
    final (created, a) = editor.addTopic(base, title: 'A');
    final renamed = editor.rename(created, a.id, 'renamed');
    final removed = editor.removeMany(renamed, [a.id]);
    final change = ContentChange.between(
      base,
      created,
    ).followedBy(ContentChange.between(created, renamed)).followedBy(ContentChange.between(renamed, removed));
    expect(change.isEmpty, isTrue);
    expect(ContentChange.between(base, base).isEmpty, isTrue);
    expect(() => (change.fields.first.after as Map)['id'] = 'mutated', throwsUnsupportedError);
    expect(() => change.fields.clear(), throwsUnsupportedError);
  });

  test('document codec roundtrips content and rejects duplicate identities', () {
    final sample = editor.addNote(StudySetContent.empty, text: 'sample').$1;
    expect(contentFromDocument(contentDocument(sample), order: sample).toJson(), sample.toJson());
    final (created, _) = editor.addTopic(StudySetContent.empty, title: 'A');
    expect(() => contentDocument(created.copyWith(cards: [...created.cards, ...created.cards])), throwsFormatException);
    expect(contentValueEquals({'b': 1, 'a': null}, {'a': null, 'b': 1}), isTrue);
    expect(contentValueEquals(contentMissing, null), isFalse);
    expect(ContentChangeConflict(['cards', 'x']).toString(), contains('cards/x'));
  });

  test('note block inverses preserve other blocks and their later modification time', () {
    final at = DateTime.utc(2026);
    final note = StudyNote(
      id: 'n',
      title: 'N',
      scope: const WholeSet(),
      settings: NoteSettings(),
      createdAt: at,
      updatedAt: at,
      organizedAt: at,
      sections: [
        NoteSection(
          id: 's',
          title: 'S',
          blocks: [
            const TextBlock(id: 'a', text: 'A'),
            const TextBlock(id: 'b', text: 'B'),
          ],
        ),
      ],
    );
    final base = StudySetContent(studyNotes: [note]);
    final edited = base.copyWith(
      studyNotes: [
        note.copyWith(
          updatedAt: DateTime.utc(2026, 2),
          sections: [
            note.sections.single.copyWith(
              blocks: [
                const TextBlock(id: 'a', text: 'local'),
                note.sections.single.blocks.last,
              ],
            ),
          ],
        ),
      ],
    );
    final remote = edited.copyWith(
      studyNotes: [
        edited.studyNotes.single.copyWith(
          updatedAt: DateTime.utc(2026, 3),
          sections: [
            note.sections.single.copyWith(
              blocks: [
                const TextBlock(id: 'a', text: 'local'),
                const TextBlock(id: 'b', text: 'remote'),
              ],
            ),
          ],
        ),
      ],
    );
    final undone = ContentChange.between(base, edited).reversed.apply(remote);
    expect(undone.studyNotes.single.sections.single.blocks.cast<TextBlock>().map((b) => b.text), ['A', 'remote']);
    expect(undone.studyNotes.single.updatedAt, DateTime.utc(2026, 3));
    final added = ContentChange.between(StudySetContent.empty, base);
    final touched = base.copyWith(studyNotes: [note.copyWith(updatedAt: DateTime.utc(2026, 4))]);
    expect(added.reversed.apply(touched).studyNotes, isEmpty);
    final inverse = ContentChange.between(base, edited).reversed;
    expect(inverse.apply(edited).studyNotes.single.toJson(), note.toJson());
    // Equal clock values do not prove that another block was not edited.
    final equalClock = remote.copyWith(
      studyNotes: [remote.studyNotes.single.copyWith(updatedAt: edited.studyNotes.single.updatedAt)],
    );
    expect(inverse.apply(equalClock).studyNotes.single.updatedAt, edited.studyNotes.single.updatedAt);
    final organized = edited.copyWith(
      studyNotes: [edited.studyNotes.single.copyWith(organizedAt: DateTime.utc(2026, 2))],
    );
    final organizedChange = ContentChange.between(base, organized);
    expect(organizedChange.fields.map((f) => f.path), contains(equals(['studyNotes', 'n', 'organizedAt'])));
    expect(organizedChange.reversed.apply(organized).studyNotes.single.toJson(), note.toJson());
    final reorganized = organized.copyWith(
      studyNotes: [organized.studyNotes.single.copyWith(organizedAt: DateTime.utc(2026, 3))],
    );
    expect(() => organizedChange.reversed.apply(reorganized), throwsA(isA<ContentChangeConflict>()));
    expect(() => added.reversed.apply(organized), throwsA(isA<ContentChangeConflict>()));
  });

  test('compound codec identities roundtrip and referential errors are explicit', () {
    final (withDoc, doc) = editor.addDocument(StudySetContent.empty, title: 'D', fileName: 'a.pdf', pageCount: 3);
    final (content, card) = editor.createExcerpt(
      withDoc,
      documentId: doc.id,
      page: 1,
      rects: const [PageRect(1, 10, 20, 2)],
      quote: 'Q',
      colorIndex: 0,
    );
    final sample = editor
        .rate(content, card.id, Rating.good)
        .copyWith(
          documentOutlines: [DocumentOutline(documentId: doc.id, items: const [])],
          translationCaches: [
            TranslationCache(documentId: doc.id, targetLang: 'en', model: 'm', createdAt: DateTime.utc(2026)),
          ],
          noteSourceArchive: [NoteSourceArchive(annotation: content.annotations.single, documentTitle: 'D')],
          assistantReceipts: [
            MapEditReceipt(proposalId: 'p', revision: 1, undoHandle: 'u', operationIds: [], nodeIds: []),
          ],
        );
    expect(contentFromDocument(contentDocument(sample), order: sample).toJson(), sample.toJson());
    final broken = sample.copyWith(
      documents: [],
      maps: [],
      cards: [Card(id: card.id, kind: CardKind.research, createdAt: DateTime.utc(2026), researchNoteId: 'missing')],
      nodes: [MapNode(cardId: card.id, parentId: 'absent', order: 1)],
      relations: [MapRelation(id: 'r', fromId: card.id, toId: 'absent')],
      summaries: [MapSummary(id: 's', fromId: 'absent', toId: 'absent')],
      bookmarks: [Bookmark(id: 'b', documentId: doc.id, page: 1, createdAt: DateTime.utc(2026))],
      noteAttachments: [
        NoteAttachment(
          id: 'a',
          noteId: 'absent',
          target: const CardTarget(cardId: 'absent'),
        ),
        NoteAttachment(
          id: 'b',
          noteId: 'absent',
          target: PdfTarget(documentId: 'absent', pages: []),
        ),
      ],
      inkStrokes: [InkStroke(id: 'i', documentId: 'absent', page: 1, tool: InkTool.pen, colorIndex: 0, width: 1)],
    );
    expect(
      contentIntegrityErrors(broken),
      containsAll([
        'maps/empty',
        'nodes/main/${card.id}/reference',
        'nodes/main/${card.id}/parent',
        'annotations/${sample.annotations.single.id}/document',
        'cards/${card.id}/researchNote',
        'relations/r/endpoint',
        'summaries/s/range',
        'bookmarks/b/document',
        'outlines/${doc.id}/document',
        'attachments/a/target',
        'attachments/b/target',
        'ink/i/document',
      ]),
    );
    expect(contentIntegrityErrors(sample.copyWith(annotations: [])), contains('cards/${card.id}/annotation'));
  });

  test('summary cards are valid parents and relation endpoints; decoding never repairs missing cards', () {
    final (one, a) = editor.addTopic(StudySetContent.empty, title: 'A');
    final (two, b) = editor.addTopic(one, title: 'B');
    final (summaryContent, summary) = editor.addSummary(two, [a.id, b.id], label: 'Summary');
    final (childContent, child) = editor.addTopic(summaryContent, title: 'Child', parentId: summary!.cardId);
    final (content, relation) = editor.addRelation(childContent, summary.cardId!, a.id);
    expect(relation, isNotNull);
    expect(content.node(child.id)!.parentId, summary.cardId);
    expect(contentIntegrityErrors(content), isEmpty);
    final change = ContentChange.between(two, content);
    expect(change.reversed.apply(content).toJson(), two.toJson());
    expect(change.apply(two).toJson(), content.toJson());
    final missing = content.copyWith(cards: content.cards.where((c) => c.id != summary.cardId).toList());
    final decoded = contentFromDocument(contentDocument(missing));
    expect(decoded.card(summary.cardId!), isNull);
    expect(contentIntegrityErrors(decoded), contains('summaries/${summary.id}/card'));
  });

  test('undo cannot orphan live sources introduced by another writer', () {
    final at = DateTime.utc(2026);
    final (base, doc) = editor.addDocument(StudySetContent.empty, title: 'D', fileName: 'd.pdf', pageCount: 3);
    final (created, card) = editor.createExcerpt(
      base,
      documentId: doc.id,
      page: 1,
      rects: const [PageRect(1, 10, 20, 2)],
      quote: 'Must survive',
      colorIndex: 0,
    );
    final remote = created.copyWith(
      studyNotes: [
        StudyNote(
          id: 'note',
          title: 'Remote note',
          scope: const WholeSet(),
          settings: NoteSettings(),
          createdAt: at,
          updatedAt: at,
          organizedAt: at,
          sections: [
            NoteSection(
              id: 'section',
              title: 'S',
              blocks: [
                QuoteBlock(id: 'quote', annotationId: card.annotationId!),
                OwnBlock(id: 'own', sourceId: card.id, source: OwnSource.card),
              ],
            ),
          ],
        ),
      ],
    );
    expect(contentIntegrityErrors(remote), isEmpty);
    expect(() => ContentChange.between(base, created).reversed.apply(remote), throwsA(isA<ContentChangeConflict>()));
    final invalid = remote.copyWith(cards: [], nodes: [], annotations: []);
    expect(
      contentIntegrityErrors(invalid),
      containsAll(['studyNotes/note/section/quote/source', 'studyNotes/note/section/own/source']),
    );
    final json = contentDocument(remote);
    final sections = ((json['studyNotes'] as Map)['note'] as Map)['sections'] as Map;
    ((sections['items'] as Map)['section'] as Map)['id'] = 'different';
    expect(() => contentFromDocument(json), throwsFormatException);
  });
}
