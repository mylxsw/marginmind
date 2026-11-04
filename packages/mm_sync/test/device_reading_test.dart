import 'package:mm_core/mm_core.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

void main() {
  final time = DateTime.utc(2026);
  final pdf = Document(
    id: 'pdf',
    title: 'PDF',
    fileName: 'documents/file.pdf',
    pageCount: 20,
    lastPage: 5,
    lastReadAt: time,
    importedAt: time,
  );
  final text = Document(
    id: 'text',
    title: 'Text',
    fileName: 'books/text/source.epub',
    contentManifest: 'books/text/manifest.json',
    revision: 'revision',
    pageCount: 0,
    lastReadAt: time,
    importedAt: time,
    layout: DocumentLayout.reflow,
    readingPosition: TextReadingPosition(revision: 'revision', chapterId: 'chapter', offset: 4),
  );
  final content = StudySetContent.empty.copyWith(documents: [pdf, text]);
  late SyncCommit source, base;
  Map<String, SyncCommit> graph(Iterable<SyncCommit> list) => {for (final c in list) c.id: c};
  SyncCommit reading({
    String scope = 'reading/set/device',
    String author = 'device',
    int sequence = 1,
    List<String> parents = const [],
    Map<String, Object?>? payload,
    Map<String, String>? requires,
    bool deleted = false,
  }) => SyncCommit.create(
    libraryId: 'library',
    scope: scope,
    deviceId: author,
    sequence: sequence,
    parents: parents,
    payload: deleted ? {} : payload ?? DeviceReading.fromContent(content).toJson(),
    requires: requires ?? (deleted ? {} : {source.scope: source.id}),
    deleted: deleted,
  );
  setUp(() {
    source = SyncCommit.create(
      libraryId: 'library',
      scope: 'sets/set',
      deviceId: 'source',
      sequence: 1,
      payload: {'content': sharedContent(content)},
    );
    base = reading();
  });
  test('PDF and text positions round trip with stable document identity and local guards', () {
    final data = DeviceReading.fromContent(content);
    final decoded = DeviceReading.fromJson(data.toJson());
    expect(decoded.locations, hasLength(2));
    expect(decoded.locations.first.matches(pdf), isTrue);
    expect(decoded.locations.last.matches(text), isTrue);
    expect(decoded.locations.first.matches(pdf.copyWith(fileName: 'documents/replaced.pdf')), isFalse);
    expect(decoded.locations.last.matches(text.copyWith(revision: 'changed')), isFalse);
    expect(readingDocumentVersion(pdf), readingDocumentVersion(pdf.copyWith(title: 'Renamed', lastPage: 8)));
    expect(localReadingToken(pdf), isNot(localReadingToken(pdf.copyWith(lastPage: 8))));
    expect(
      DeviceReading.fromContent(
        content.copyWith(
          documents: [Document(id: 'unread', title: 'Unread', fileName: 'x', pageCount: 1, importedAt: time)],
        ),
      ).locations,
      isEmpty,
    );
  });
  test('malformed values cannot introduce hidden fields, duplicate identities or invalid anchors', () {
    final value = DeviceReading.fromContent(content).toJson();
    final doc = (value['documents'] as List).first as Map<String, Object?>;
    for (final invalid in [
      {...value, 'extra': true},
      {...value, 'version': 2},
      {
        ...value,
        'documents': [doc, doc],
      },
      {
        ...value,
        'documents': [1],
      },
      {
        ...value,
        'documents': [
          {...doc, 'id': ''},
        ],
      },
      {
        ...value,
        'documents': [
          {...doc, 'documentVersion': 'invalid'},
        ],
      },
      {
        ...value,
        'documents': [
          {...doc, 'readAt': '2026-01-01'},
        ],
      },
      {
        ...value,
        'documents': [
          {
            ...doc,
            'position': {'type': 'pdf', 'page': -1},
          },
        ],
      },
      {
        ...value,
        'documents': [
          {
            ...doc,
            'position': {'type': 'pdf', 'page': 2, 'extra': 0},
          },
        ],
      },
    ]) {
      expect(() => DeviceReading.fromJson(invalid), throwsFormatException);
    }
  });
  test('causal snapshots fast forward, deduplicate and accept only their owning device', () {
    final next = reading(sequence: 2, parents: [base.id]);
    final known = graph([source, base, next]);
    expect(planDeviceReading(known, remote: next.id, local: base.id).adopt, isTrue);
    expect(planDeviceReading(known, remote: base.id, local: next.id).state, SyncMergeState.unchanged);
    final spoof = reading(author: 'another', parents: [next.id]);
    expect(planDeviceReading({...known, spoof.id: spoof}, remote: spoof.id, local: next.id).reason, 'invalidReading');
    final deleted = reading(sequence: 3, parents: [next.id], deleted: true);
    expect(planDeviceReading({...known, deleted.id: deleted}, remote: deleted.id, local: next.id).deleted, isTrue);
    final scope = reading(scope: 'reading/set/device/extra');
    expect(planDeviceReading(graph([source, scope]), remote: scope.id).reason, 'invalidReading');
  });
  test('missing ancestors or content wait and divergent device branches never merge by time', () {
    final next = reading(sequence: 2, parents: [base.id]);
    expect(planDeviceReading(graph([next, source]), remote: next.id).state, SyncMergeState.waiting);
    expect(planDeviceReading(graph([base]), remote: base.id).reason, 'missingContent');
    final branch = reading(sequence: 3, parents: [base.id]);
    expect(
      planDeviceReading(graph([source, base, next, branch]), remote: branch.id, local: next.id).state,
      SyncMergeState.conflict,
    );
    final merge = reading(sequence: 4, parents: [next.id, branch.id]);
    expect(planDeviceReading(graph([source, base, next, branch, merge]), remote: merge.id).reason, 'invalidHistory');
  });
  test('content dependencies and matching document versions are mandatory', () {
    for (final invalid in [
      reading(requires: {}),
      reading(
        payload: {
          'kind': 'device-reading',
          'version': 1,
          'documents': [
            {
              'id': 'missing',
              'documentVersion': readingDocumentVersion(pdf),
              'readAt': time.toIso8601String(),
              'position': {'type': 'pdf', 'page': 5},
            },
          ],
        },
      ),
      reading(
        payload: {
          'kind': 'device-reading',
          'version': 1,
          'documents': [
            {
              'id': pdf.id,
              'documentVersion': readingDocumentVersion(pdf),
              'readAt': time.toIso8601String(),
              'position': {'type': 'pdf', 'page': 50},
            },
          ],
        },
      ),
    ]) {
      expect(planDeviceReading(graph([source, invalid]), remote: invalid.id).reason, 'invalidReading');
    }
    final badSource = SyncCommit.create(
      libraryId: 'library',
      scope: 'sets/set',
      deviceId: 'source',
      sequence: 2,
      parents: [source.id],
      payload: {},
    );
    final bad = reading(requires: {badSource.scope: badSource.id});
    expect(planDeviceReading(graph([source, badSource, bad]), remote: bad.id).reason, 'invalidReading');
  });
  test('old snapshots remain ancestors but are never directly offered as verified progress', () {
    final old = reading(payload: {'lastOpenedAt': time.toIso8601String(), 'documents': []}, requires: {});
    expect(planDeviceReading(graph([old]), remote: old.id).reason, 'unsupportedReading');
    final upgrade = reading(sequence: 2, parents: [old.id]);
    expect(planDeviceReading(graph([source, old, upgrade]), remote: upgrade.id).state, SyncMergeState.ready);
  });
}
