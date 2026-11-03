import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

// Exact legacy VM JSON, not reconstructed by the test runtime. On JS, parsing
// 1.0 loses its lexical spelling; the original identity must still survive.
const witness =
    '{"deleted":false,"deviceId":"vm","libraryId":"lib","parents":[],"payload":{"n":1.0,"text":"中文"},"protocol":1,"scope":"sets/a","sequence":1}';
Map<String, Object?> fixture() => {
  ...jsonDecode(witness) as Map<String, dynamic>,
  'id': sha256.convert(utf8.encode(witness)).toString(),
  'legacyCanonical': witness,
};

void main() {
  test('VM numeric witness keeps identity and exact bytes through JSON round trips', () {
    final c = SyncCommit.fromJson(fixture());
    expect(c.id, sha256.convert(utf8.encode(witness)).toString());
    expect(c.payload, {'n': 1, 'text': '中文'});
    expect(c.portable, true);
    expect(c.toJson()['legacyCanonical'], witness);
    expect(SyncCommit.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>).toJson(), c.toJson());
    final next = SyncCommit.create(
      libraryId: 'lib',
      scope: c.scope,
      deviceId: 'js',
      sequence: 1,
      parents: [c.id],
      payload: {'n': 2},
    );
    validatePortableSyncHistory({c.id: c, next.id: next});
    expect(next.parents.single, c.id);
    expect(next.toJson().containsKey('legacyCanonical'), false);
  });

  test('original runtime can read unwrapped v1 and attach proof without changing identity', () {
    final old = SyncCommit.create(
      libraryId: 'lib',
      scope: 'sets/a',
      deviceId: 'a',
      sequence: 1,
      protocol: 1,
      payload: {
        'nested': [1.0, -0.0, .0000001],
      },
    );
    final raw = Map<String, Object?>.of(old.toJson())..remove('legacyCanonical');
    final decoded = SyncCommit.fromJson(raw);
    expect(decoded.id, old.id);
    expect(decoded.legacyCanonical, old.legacyCanonical);
    expect(contentValueEquals(decoded.payload, old.payload), true);
  });

  test('witness substitution, altered payload, wrong protocol and malformed witness are rejected', () {
    for (final change in <Map<String, Object?>>[
      {'legacyCanonical': '{}'},
      {
        'payload': {'n': 2, 'text': '中文'},
      },
      {'protocol': 2},
      {'legacyCanonical': 42},
      {'id': syncDigest('other')},
    ]) {
      expect(() => SyncCommit.fromJson({...fixture(), ...change}), throwsFormatException);
    }
    final malformed = '{';
    expect(
      () => SyncCommit.fromJson({
        ...fixture(),
        'legacyCanonical': malformed,
        'id': sha256.convert(utf8.encode(malformed)).toString(),
      }),
      throwsFormatException,
    );
  });

  test('unsafe legacy numbers remain local and cannot be made portable by a witness', () {
    final c = SyncCommit.create(
      libraryId: 'lib',
      scope: 'sets/a',
      deviceId: 'a',
      sequence: 1,
      protocol: 1,
      payload: {'n': 1e20},
    );
    expect(c.portable, false);
    expect(c.toJson().containsKey('legacyCanonical'), false);
    expect(SyncCommit.fromJson(c.toJson()).id, c.id);
    expect(() => SyncCommit.fromJson({...c.toJson(), 'legacyCanonical': c.legacyCanonical}), throwsFormatException);
    expect(
      () => validatePortableSyncHistory({c.id: c}),
      throwsA(isA<SyncTransportException>().having((e) => e.problem, 'problem', SyncTransportProblem.legacyProtocol)),
    );
  });

  test('whole legacy graph retains branches, pending choices and cross-domain references', () {
    final root = SyncCommit.fromJson(fixture());
    SyncCommit child(String device, int value) => SyncCommit.create(
      libraryId: 'lib',
      scope: root.scope,
      deviceId: device,
      sequence: 1,
      parents: [root.id],
      payload: {'n': value},
      protocol: 1,
    );
    final a = child('a', 2), b = child('b', 3);
    final merge = SyncCommit.create(
      libraryId: 'lib',
      scope: root.scope,
      deviceId: 'c',
      sequence: 1,
      parents: [a.id, b.id],
      pending: [b.id],
      payload: a.payload,
    );
    final review = SyncCommit.create(
      libraryId: 'lib',
      scope: 'reviews/a',
      deviceId: 'a',
      sequence: 1,
      payload: {},
      requires: {root.scope: merge.id},
    );
    final graph = {
      for (final c in [root, a, b, merge, review]) c.id: c,
    };
    validatePortableSyncHistory(graph);
    final roundTrip = {
      for (final c in graph.values)
        c.id: SyncCommit.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>),
    };
    expect(roundTrip[merge.id]!.pending, [b.id]);
    expect(roundTrip[review.id]!.requires, {root.scope: merge.id});
    expect(roundTrip.keys.toSet(), graph.keys.toSet());
    expect(() => validatePortableSyncHistory(Map.of(graph)..remove(root.id)), throwsA(isA<SyncTransportException>()));
    final missing = SyncCommit.create(
      libraryId: 'lib',
      scope: 'reviews/other',
      deviceId: 'a',
      sequence: 1,
      payload: {},
      requires: {'sets/missing': syncDigest('absent')},
    );
    expect(() => validatePortableSyncHistory({...graph, missing.id: missing}), throwsA(isA<SyncTransportException>()));
    final wrongScope = SyncCommit.create(
      libraryId: 'lib',
      scope: 'reviews/wrong',
      deviceId: 'a',
      sequence: 1,
      payload: {},
      requires: {'sets/incorrect': root.id},
    );
    expect(
      () => validatePortableSyncHistory({...graph, wrongScope.id: wrongScope}),
      throwsA(isA<SyncTransportException>()),
    );
  });
}
