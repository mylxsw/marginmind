import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

void main() {
  var count = 0;
  late StudySetEditor editor;
  setUp(() {
    count = 0;
    editor = StudySetEditor(newId: () => 'id${++count}', now: () => DateTime.utc(2026));
  });

  SyncCommit commit({
    String device = 'a',
    int sequence = 1,
    List<String> parents = const [],
    Map<String, Object?> payload = const {},
    bool deleted = false,
    String scope = 'set',
  }) => SyncCommit.create(
    libraryId: 'library',
    scope: scope,
    deviceId: device,
    sequence: sequence,
    parents: parents,
    payload: payload,
    deleted: deleted,
  );

  test('portable digest golden treats JSON numbers equally across VM and JavaScript', () {
    final value = {
      'numbers': [1, 1.0, -0.0, 1e-7, .1, 9007199254740991],
      'text': '中文 😀',
      'array': ['number', '3ff0000000000000'],
    };
    expect(syncDigest(value), '6f0bf311ba877f15c3c472367c24f5b75ac02ff0708c390cb104f513177099d1');
    expect(syncDigest(1), syncDigest(1.0));
    expect(syncDigest(-0.0), syncDigest(0));
    expect(syncDigest(1), isNot(syncDigest('3ff0000000000000')));
    for (final n in [double.nan, double.infinity, 1e20, Object()]) {
      expect(() => syncDigest(n), throwsFormatException);
    }
    expect(
      contentValueEquals({
        'n': [1.0, -0.0],
      }, jsonDecode('{"n":[1,0]}')),
      isTrue,
    );
    expect(contentValueEquals({'n': 1}, {'n': '1'}), isFalse);
    final old = commit(payload: {'n': 1.5}).toJson()..['protocol'] = 1;
    old['id'] = legacySyncDigest(Map<String, Object?>.of(old)..remove('id'));
    final restored = SyncCommit.fromJson(old);
    expect(restored.protocol, 1);
    expect(Map.of(restored.toJson())..remove('legacyCanonical'), old);
    expect(restored.legacyCanonical, isNotNull);
    final next = commit(sequence: 2, parents: [restored.id], payload: {'n': 2.0});
    expect(next.protocol, 2);
    expect(SyncGraph([restored, next]).ancestors(next.id), contains(restored.id));
    final conflict = SyncConflict(['n'], 1.5, 2.5, 3.5, version: 1);
    expect(SyncConflict.fromJson(conflict.toJson()).toJson(), conflict.toJson());
  });

  test('domain prerequisites are immutable, hashed and cannot self-reference or accompany deletion', () {
    final base = commit(), refs = <String, String>{'set': commit().id};
    final c = SyncCommit.create(
      libraryId: 'library',
      scope: 'reviews',
      deviceId: 'a',
      sequence: 1,
      payload: {},
      requires: refs,
    );
    refs.clear();
    expect(c.requires, {'set': base.id});
    expect(SyncCommit.fromJson(c.toJson()).requires, c.requires);
    expect(() => c.requires.clear(), throwsUnsupportedError);
    for (final invalid in [
      {'reviews': base.id},
      {'': base.id},
      {'set': 'bad'},
    ]) {
      expect(
        () => SyncCommit.create(
          libraryId: 'library',
          scope: 'reviews',
          deviceId: 'a',
          sequence: 1,
          payload: {},
          requires: invalid,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => SyncCommit.create(
        libraryId: 'library',
        scope: 'reviews',
        deviceId: 'a',
        sequence: 1,
        payload: {},
        requires: c.requires,
        deleted: true,
      ),
      throwsFormatException,
    );
    expect(
      () => SyncCommit.fromJson({
        ...c.toJson(),
        'requires': {'set': '0' * 64},
      }),
      throwsFormatException,
    );
  });

  test('commits canonicalize keys and parents, validate digest, and freeze nested values', () {
    final c = commit(
      payload: {
        'b': [
          1,
          {'nested': true},
        ],
        'a': null,
      },
    );
    final d = commit(
      payload: {
        'a': null,
        'b': [
          1,
          {'nested': true},
        ],
      },
    );
    expect(c.id, d.id);
    expect(SyncCommit.fromJson(c.toJson()).id, c.id);
    expect(() => (c.payload['b'] as List).clear(), throwsUnsupportedError);
    expect(() => SyncCommit.fromJson({...c.toJson(), 'payload': {}}), throwsFormatException);
    expect(() => SyncCommit.fromJson({...c.toJson(), 'protocol': 999}), throwsFormatException);
    expect(() => SyncCommit.fromJson({...c.toJson(), 'extra': true}), throwsFormatException);
    expect(() => SyncCommit.fromJson({...c.toJson(), 'sequence': '1'}), throwsFormatException);
    expect(() => commit(sequence: 0), throwsFormatException);
    expect(() => commit(parents: ['bad']), throwsFormatException);
    expect(() => commit(parents: [c.id, c.id]), throwsFormatException);
    expect(() => commit(payload: {'x': double.infinity}), throwsFormatException);
    expect(() => commit(deleted: true, payload: {'x': 1}), throwsFormatException);
    expect(commit(deleted: true).deleted, isTrue);
  });

  test('graph detects missing ancestors, identity forks and cross-scope parents', () {
    final base = commit();
    final a = commit(sequence: 2, parents: [base.id], payload: {'x': 1});
    final b = commit(device: 'b', parents: [base.id], payload: {'y': 2});
    final graph = SyncGraph([b, a, base, base]);
    expect(graph.mergeBases(a.id, b.id), {base.id});
    expect(graph.mergeBases(a.id, base.id), {base.id});
    expect(() => graph.ancestors('missing'), throwsFormatException);
    expect(() => SyncGraph([a]), throwsFormatException);
    expect(
      () => SyncGraph([
        base,
        commit(payload: {'fork': true}),
      ]),
      throwsFormatException,
    );
    expect(
      () => SyncGraph([
        base,
        commit(device: 'b', scope: 'other', parents: [base.id]),
      ]),
      throwsFormatException,
    );
    expect(() => SyncGraph([base, commit(sequence: 0)]), throwsFormatException);
    final earlier = commit(device: 'a', sequence: 3);
    expect(
      () => SyncGraph([
        earlier,
        commit(sequence: 2, parents: [earlier.id]),
      ]),
      throwsFormatException,
    );
    final leftMerge = commit(sequence: 3, parents: [a.id, b.id]);
    final rightMerge = commit(device: 'b', sequence: 2, parents: [b.id, a.id]);
    expect(SyncGraph([base, a, b, leftMerge, rightMerge]).mergeBases(leftMerge.id, rightMerge.id), {a.id, b.id});
    final independent = commit(sequence: 4);
    expect(() => SyncGraph([base, independent]), throwsFormatException);
    final bridge = commit(device: 'b', parents: [earlier.id]);
    final backwards = commit(sequence: 2, parents: [bridge.id]);
    expect(() => SyncGraph([earlier, bridge, backwards]), throwsFormatException);
    final forwards = commit(sequence: 4, parents: [bridge.id]);
    expect(SyncGraph([earlier, bridge, forwards]).ancestors(forwards.id), contains(earlier.id));
  });

  test('disjoint fields and cards merge regardless of delivery order', () {
    final (one, a) = editor.addTopic(StudySetContent.empty, title: 'A');
    final (base, b) = editor.addNote(one, text: 'B');
    final left = editor.rename(base, a.id, 'left');
    final right = editor.rename(base, b.id, 'right');
    final result = mergeContent(base, left, right);
    expect(result.clean, isTrue);
    expect(result.content!.card(a.id)!.title, 'left');
    expect(result.content!.card(b.id)!.title, 'right');
    expect(sharedContent(result.content!), sharedContent(mergeContent(base, right, left).content!));
    expect(mergeContent(base, left, left).clean, isTrue);
  });

  test('same-field and delete/edit conflicts retain both candidates and stable identities', () {
    final (base, a) = editor.addTopic(StudySetContent.empty, title: 'A');
    final left = editor.rename(base, a.id, 'left'), right = editor.rename(base, a.id, 'right');
    final result = mergeContent(base, left, right);
    expect(result.clean, isFalse);
    expect(result.content!.card(a.id)!.title, 'A');
    expect(result.conflicts.single.left, 'left');
    expect(result.conflicts.single.right, 'right');
    expect(result.conflicts.single.id, mergeContent(base, right, left).conflicts.single.id);
    final deleted = editor.removeMany(base, [a.id]);
    final conflict = mergeContent(base, deleted, right);
    expect(conflict.conflicts.any((c) => c.left == contentMissing), isTrue);
    expect(conflict.clean, isFalse);
    for (final c in conflict.conflicts) {
      expect(SyncConflict.fromJson(c.toJson()).id, c.id);
    }
    final c = SyncConflict(
      ['cards'],
      {
        'old': [1],
      },
      null,
      contentMissing,
    );
    expect(SyncConflict.fromJson(c.toJson()).right, contentMissing);
    expect(() => (c.base as Map).clear(), throwsUnsupportedError);
    expect(() => SyncConflict.fromJson({...c.toJson(), 'id': 'bad'}), throwsFormatException);
    expect(() => SyncConflict.fromJson({...c.toJson(), 'version': 999}), throwsFormatException);
    expect(() => SyncConflict.fromJson({...c.toJson(), 'extra': true}), throwsFormatException);
    expect(() => SyncConflict.fromJson({...c.toJson(), 'left': null}), throwsFormatException);
    expect(
      () => SyncConflict.fromJson({
        ...c.toJson(),
        'left': {'invalid': true},
      }),
      throwsFormatException,
    );
    expect(() => SyncConflict.fromJson({...c.toJson(), 'path': false}), throwsFormatException);
  });

  test('combined graph cycles fail closed and concurrent sibling inserts order consistently', () {
    final (one, a) = editor.addTopic(StudySetContent.empty, title: 'A');
    final (base, b) = editor.addTopic(one, title: 'B');
    final merged = mergeContent(base, editor.move(base, a.id, b.id), editor.move(base, b.id, a.id));
    expect(merged.content, isNull);
    expect(merged.conflicts.any((c) => c.path.contains('nodes/main/${a.id}/cycle')), isTrue);
    final (left, l) = editor.addTopic(base, title: 'left');
    final (right, r) = editor.addTopic(base, title: 'right');
    final first = mergeContent(base, left, right).content!, second = mergeContent(base, right, left).content!;
    expect(first.childrenOf(null).map((n) => n.cardId), second.childrenOf(null).map((n) => n.cardId));
    expect(first.cards.map((c) => c.id), containsAll([l.id, r.id]));
  });

  test('reading, collapsed nodes, and review state do not create content versions', () {
    final (withDoc, doc) = editor.addDocument(StudySetContent.empty, title: 'book', fileName: 'a.pdf', pageCount: 9);
    final (base, card) = editor.addNote(withDoc, text: 'question');
    final reading = editor.setLastPage(base, doc.id, 7);
    final reviewed = editor.rate(reading, card.id, Rating.good);
    final local = editor.setCollapsed(reviewed, card.id, collapsed: true);
    expect(sharedContent(local), sharedContent(base));
    final remote = editor.rename(base, card.id, 'renamed');
    final materialized = materializeShared(sharedContent(remote), local);
    expect(materialized.cards.single.title, 'renamed');
    expect(materialized.documents.single.lastPage, 7);
    expect(materialized.reviewLogs.single.id, local.reviewLogs.single.id);
    expect(materialized.nodes.single.collapsed, isTrue);
  });

  StudySetContent noteContent(List<StudyNoteBlock> blocks, {DateTime? updated}) => StudySetContent(
    studyNotes: [
      StudyNote(
        id: 'note',
        title: 'note',
        scope: const WholeSet(),
        settings: NoteSettings(),
        createdAt: DateTime.utc(2026),
        updatedAt: updated ?? DateTime.utc(2026),
        organizedAt: DateTime.utc(2026),
        sections: [NoteSection(id: 'section', title: 'section', blocks: blocks)],
      ),
    ],
  );

  test('different note blocks merge with timestamps and roundtrip through the content codec', () {
    const a = TextBlock(id: 'a', text: 'A'), b = TextBlock(id: 'b', text: 'B');
    final base = noteContent([a, b]);
    final left = noteContent([const TextBlock(id: 'a', text: 'left'), b], updated: DateTime.utc(2026, 2));
    final right = noteContent([a, const TextBlock(id: 'b', text: 'right')], updated: DateTime.utc(2026, 3));
    final result = mergeContent(base, left, right);
    expect(result.clean, isTrue);
    final note = result.content!.studyNotes.single;
    expect(note.sections.single.blocks.cast<TextBlock>().map((b) => b.text), ['left', 'right']);
    expect(note.updatedAt, DateTime.utc(2026, 3));
    expect(contentFromDocument(contentDocument(base)).toJson(), base.toJson());
  });

  test('concurrent material collection baselines are content conflicts, not latest-clock metadata', () {
    final base = noteContent([const TextBlock(id: 'a', text: 'A')]);
    final left = base.copyWith(studyNotes: [base.studyNotes.single.copyWith(organizedAt: DateTime.utc(2026, 2))]);
    final right = base.copyWith(studyNotes: [base.studyNotes.single.copyWith(organizedAt: DateTime.utc(2026, 3))]);
    final result = mergeContent(base, left, right);
    expect(result.clean, isFalse);
    expect(result.conflicts.single.path, ['studyNotes', 'note', 'organizedAt']);
    expect(result.content!.studyNotes.single.organizedAt, base.studyNotes.single.organizedAt);
    expect(mergeContent(base, right, left).conflicts.single.id, result.conflicts.single.id);
  });

  test('concurrent note insertions preserve both blocks and converge in either delivery order', () {
    const a = TextBlock(id: 'a', text: 'A'), b = TextBlock(id: 'b', text: 'B'), c = TextBlock(id: 'c', text: 'C');
    final base = noteContent([a]);
    final left = noteContent([a, b]), right = noteContent([a, c]);
    final result = mergeContent(base, left, right);
    expect(result.clean, isTrue);
    expect(result.content!.studyNotes.single.sections.single.blocks.map((b) => b.id), ['a', 'b', 'c']);
    expect(result.content!.toJson(), mergeContent(base, right, left).content!.toJson());
  });

  test('conflicting note orders and deletion against edited blocks never publish invalid notes', () {
    const a = TextBlock(id: 'a', text: 'A'), b = TextBlock(id: 'b', text: 'B'), c = TextBlock(id: 'c', text: 'C');
    final base = noteContent([a, b, c]);
    final result = mergeContent(base, noteContent([b, a, c]), noteContent([a, c, b]));
    expect(result.clean, isFalse);
    expect(result.conflicts.any((c) => c.path.last == 'order'), isTrue);
    final deleted = mergeContent(base, noteContent([a, c]), noteContent([a, const TextBlock(id: 'b', text: 'new'), c]));
    expect(deleted.content, isNull);
    expect(() => contentDocument(noteContent([a, a])), throwsFormatException);
    expect(() => contentFromDocument({'unknown': {}}), throwsFormatException);
    expect(
      () => contentFromDocument({
        'cards': {
          'wrong': {'id': 'actual'},
        },
      }),
      throwsFormatException,
    );
  });
}
