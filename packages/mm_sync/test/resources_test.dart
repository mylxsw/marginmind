import 'package:crypto/crypto.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

void main() {
  final hash = sha256.convert([1]).toString();
  final file = SyncResourceFile(hash: hash, length: 1, chunks: [hash]);
  final doc = Document(
    id: 'doc',
    title: 'Doc',
    fileName: 'documents/file.pdf',
    pageCount: 1,
    importedAt: DateTime.utc(2026),
  );
  final content = StudySetContent.empty.copyWith(documents: [doc]);
  test('descriptors have fixed chunks, portable identity and bounded size', () {
    expect(SyncResourceFile.fromJson(file.toJson()).toJson(), file.toJson());
    expect(file.chunkLength(0), 1);
    expect(() => file.chunkLength(1), throwsRangeError);
    for (final value in [
      {...file.toJson(), 'length': -1},
      {...file.toJson(), 'length': syncResourceFileLimit + 1},
      {...file.toJson(), 'chunks': []},
      {...file.toJson(), 'sha256': 'no'},
      {
        ...file.toJson(),
        'chunks': ['bad'],
      },
      {...file.toJson(), 'unknown': true},
      {...file.toJson(), 'length': 0, 'chunks': []},
    ]) {
      expect(() => SyncResourceFile.fromJson(value), throwsFormatException);
    }
    final empty = SyncResourceFile(hash: sha256.convert([]).toString(), length: 0, chunks: []);
    expect(empty.chunks, isEmpty);
  });
  test('references cannot scan a package or grant access to private files', () {
    final group = syncResourceGroups(content).single;
    final manifest = SyncResources({
      group.key: {doc.fileName: file},
    });
    manifest.validate(content);
    expect(SyncResources.fromJson(manifest.toJson()).toJson(), manifest.toJson());
    expect(manifest.retain(StudySetContent.empty).groups, isEmpty);
    for (final path in [
      '.foliarc-sync/local/a.json',
      '../secret',
      'documents/../secret',
      'documents//x',
      'documents/a.tmp',
      '/documents/a',
      'documents/a\\b',
    ]) {
      expect(validSyncResourcePath(path), isFalse);
    }
    for (final invalid in [
      SyncResources({
        'unknown': {doc.fileName: file},
      }),
      SyncResources({group.key: {}}),
      SyncResources({
        group.key: {doc.fileName: file, 'documents/private.pdf': file},
      }),
    ]) {
      expect(() => invalid.validate(content), throwsFormatException);
    }
    expect(
      () => SyncResources.fromJson({
        'version': 1,
        'groups': {for (var i = 0; i < 10001; i++) '$i': {}},
      }),
      throwsFormatException,
    );
    expect(
      () => SyncResources.fromJson({
        'version': 1,
        'groups': {
          'x': {for (var i = 0; i < 10001; i++) '$i': file.toJson()},
        },
      }),
      throwsFormatException,
    );
  });
  test('package closure checks paths and expected digests without guessing missing references', () {
    final book = SyncResourceGroup('book', ['books/id/v/manifest.json'], bookBase: 'books/id/v', webBase: 'web/id/v');
    final chapter = 'books/id/v/chapters/$hash.json';
    expect(
      syncResourceDependencies(book, 'books/id/v/manifest.json', {
        'spine': [
          {'path': chapter, 'sha256': hash},
        ],
      }),
      {chapter: hash},
    );
    expect(
      syncResourceDependencies(book, 'web/id/v/resources.json', {
        'resources': {'resources/image-1.png': hash},
        'snapshotSha256': hash,
      }),
      {'web/id/v/resources/image-1.png': hash, 'web/id/v/snapshot.html': hash},
    );
    expect(
      () => syncResourceDependencies(book, 'books/id/v/manifest.json', {
        'resources': [
          {'path': 'documents/private', 'sha256': hash},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => syncResourceDependencies(book, 'books/id/v/manifest.json', {
        'resources': [
          {'path': chapter, 'sha256': 'bad'},
        ],
      }),
      throwsFormatException,
    );
    expect(() => syncResourceDependencies(book, 'unknown', {}), throwsFormatException);
  });
  test('blob object bytes must match the exact digest key', () {
    final key = 'blobs/$hash.bin';
    checkSyncObjectData(key, [1]);
    expect(sameSyncStoredObject(key, [1], [1]), isTrue);
    expect(() => checkSyncObjectData(key, [2]), throwsA(isA<SyncTransportException>()));
    for (final key in ['blobs/../private.bin', 'blobs/$hash.json', 'commits/$hash.bin', 'blobs/$hash.bin/x']) {
      expect(() => checkSyncObjectKey(key), throwsA(isA<SyncTransportException>()));
    }
  });
}
