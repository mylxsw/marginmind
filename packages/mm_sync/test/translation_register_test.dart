import 'package:mm_core/mm_core.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

final version = syncDigest('document');
TranslationSegment segment(String text, {String key = 'key', TranslationOrigin origin = TranslationOrigin.edited}) =>
    TranslationSegment(
      key: key,
      fingerprint: 'fp',
      page: 1,
      index: 0,
      text: text,
      model: 'm',
      profile: 'p',
      origin: origin,
      at: DateTime.utc(2026),
    );
void main() {
  test('manual values survive late AI and independent paragraphs merge', () {
    final empty = TranslationRegister.empty();
    final a = empty.append(version, segment('human'), 'a', 'a');
    final b = empty
        .append(version, segment('ai', origin: TranslationOrigin.ai), 'b', 'b')
        .append(version, segment('another', key: 'other'), 'b', 'c');
    final joined = a.join(b);
    expect(joined.snapshot(version).segments['key']!.text, 'human');
    expect(joined.snapshot(version).segments['other']!.text, 'another');
    expect(joined.toJson(), b.join(a).toJson());
    expect(joined.snapshot(syncDigest('replacement')).segments, isEmpty);
    expect(TranslationRegister.fromJson(joined.toJson()).toJson(), joined.toJson());
    expect(empty.token(version, 'key'), 'absent:$version');
  });
  test('concurrent human edits and choices retain candidates; ordinary typing does not clear unseen text', () {
    final base = TranslationRegister.empty().append(version, segment('base'), 'a', 'base');
    final a = base.append(version, segment('a'), 'a', 'a', observed: true),
        b = base.append(version, segment('b'), 'b', 'b', observed: true);
    final merged = a.join(b), snapshot = a.join(b).snapshot(version);
    expect(snapshot.conflicts['key'], hasLength(2));
    final typed = merged.append(version, segment('typed'), 'a', 'type', observed: true);
    expect(typed.snapshot(version).conflicts['key'], hasLength(2));
    final x = merged.choose(version, 'key', snapshot.conflicts['key']!.first.id, 'a', 'x');
    final y = merged.choose(version, 'key', snapshot.conflicts['key']!.last.id, 'b', 'y');
    expect(x.snapshot(version).conflicts, isEmpty);
    expect(x.join(y).snapshot(version).conflicts['key'], hasLength(2));
    final clear = merged.clear(version, 'a', 'clear');
    expect(clear.snapshot(version).segments, isEmpty);
    expect(clear.join(typed).snapshot(version).conflicts['key'], hasLength(2));
    expect(
      clear.append(version, segment('late', origin: TranslationOrigin.ai), 'b', 'late').snapshot(version).segments,
      isEmpty,
    );
    expect(() => merged.choose(version, 'key', 'unknown', 'a', 'x'), throwsFormatException);
  });
  test('immutable writes reject altered authors, forgotten values and unknown schemas', () {
    final a = TranslationRegister.empty().append(version, segment('a'), 'a', 'a');
    final b = a.append(version, segment('b'), 'b', 'b', observed: true);
    a.validateSuccessor(b, 'b');
    expect(() => a.validateSuccessor(b, 'a'), throwsFormatException);
    expect(() => b.validateSuccessor(a, 'a'), throwsFormatException);
    final broken = TranslationRegister.fromJson(a.toJson());
    broken.writes[broken.writes.keys.single]!['key'] = 'other';
    expect(() => a.join(broken), throwsFormatException);
    expect(() => TranslationRegister.fromJson({...a.toJson(), 'version': 2}), throwsFormatException);
    expect(
      () => TranslationRegister.fromJson({
        ...a.toJson(),
        'removed': ['missing'],
      }),
      throwsFormatException,
    );
    expect(() => a.append(version, segment('again'), 'a', 'a'), throwsFormatException);
  });
  test('causal protocol validates content dependencies, missing ancestors and integration payload', () {
    final doc = Document(
      id: 'doc',
      title: 'Book',
      fileName: 'documents/a.pdf',
      pageCount: 3,
      importedAt: DateTime.utc(2026),
    );
    final content = StudySetContent(documents: [doc]);
    final parent = SyncCommit.create(
      libraryId: 'lib',
      scope: 'sets/set',
      deviceId: 'a',
      sequence: 1,
      payload: {'content': sharedContent(content)},
    );
    const scope = 'translated/set/doc/zh';
    final root = translationBaseline('lib', scope);
    final a = SyncCommit.create(
      libraryId: 'lib',
      scope: scope,
      deviceId: 'a',
      sequence: 1,
      parents: [root.id],
      requires: {'sets/set': parent.id},
      payload: TranslationRegister.empty().append(readingDocumentVersion(doc), segment('a'), 'a', 'a').toJson(),
    );
    final b = SyncCommit.create(
      libraryId: 'lib',
      scope: scope,
      deviceId: 'b',
      sequence: 1,
      parents: [root.id],
      requires: {'sets/set': parent.id},
      payload: TranslationRegister.empty().append(readingDocumentVersion(doc), segment('b'), 'b', 'b').toJson(),
    );
    final known = {
      for (final c in [parent, root, a, b]) c.id: c,
    };
    expect(planTranslationMerge(known, remote: a.id, acceptedContent: {}).reason, 'missingContent');
    expect(
      planTranslationMerge({...known}..remove(root.id), remote: a.id, acceptedContent: {parent.id}).state,
      SyncMergeState.waiting,
    );
    final merged = planTranslationMerge(known, remote: a.id, local: b.id, acceptedContent: {parent.id});
    expect(merged.state, SyncMergeState.ready);
    expect(
      TranslationRegister.fromJson(merged.payload!).snapshot(readingDocumentVersion(doc)).conflicts['key'],
      hasLength(2),
    );
    expect(
      planTranslationMerge(known, remote: root.id, local: a.id, acceptedContent: {parent.id}).state,
      SyncMergeState.unchanged,
    );
    final fake = SyncCommit.create(
      libraryId: 'lib',
      scope: scope,
      deviceId: 'c',
      sequence: 1,
      parents: [a.id, b.id],
      requires: {'sets/set': parent.id},
      payload: a.payload,
    );
    expect(
      planTranslationMerge({...known, fake.id: fake}, remote: fake.id, acceptedContent: {parent.id}).state,
      SyncMergeState.conflict,
    );
  });
}
