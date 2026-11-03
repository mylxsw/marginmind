import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

Matcher problem(SyncTransportProblem value) =>
    throwsA(isA<SyncTransportException>().having((e) => e.problem, 'problem', value));
final objectId = syncDigest('object');
void main() {
  WebDavSyncTransport dav(http.Client client) => WebDavSyncTransport(
    client: client,
    directory: Uri.parse('https://dav.example/user/'),
    account: 'alice',
    libraryId: 'library',
    authorization: 'Bearer private',
  );
  test('target identity round-trips without credentials and excludes legacy aggregate scopes', () {
    final target = SyncTarget(
      service: 'webdav',
      account: 'alice',
      location: 'https://dav.example/',
      libraryId: 'library',
    );
    expect(SyncTarget.fromJson(target.toJson()).key, target.key);
    expect(
      SyncTarget(service: 'webdav', account: 'bob', location: target.location, libraryId: 'library').key,
      isNot(target.key),
    );
    expect(() => SyncTarget(service: '', account: 'a', location: 'x', libraryId: 'l'), throwsArgumentError);
    expect(isSyncWireScope('sets/set'), isTrue);
    for (final scope in ['library', 'vocabulary', 'translations/set/doc/zh', '.foliarc-sync/local']) {
      expect(isSyncWireScope(scope), isFalse);
    }
    validateSyncLibrary(syncLibraryManifest('library'), 'library');
  });
  test('DAV immutable create and DAV namespace listing use bounded same-origin requests', () async {
    final objects = <String, List<int>>{}, calls = <http.Request>[];
    final client = MockClient((request) async {
      calls.add(request);
      expect(request.followRedirects, isFalse);
      expect(request.headers['authorization'], 'Bearer private');
      final path = request.url.path;
      if (request.method == 'MKCOL') return http.Response('', 201);
      if (request.method == 'GET') {
        return http.Response.bytes(objects[path] ?? [], objects.containsKey(path) ? 200 : 404);
      }
      if (request.method == 'PUT') {
        expect(request.headers['if-none-match'], '*');
        objects[path] = request.bodyBytes;
        return http.Response('', 201);
      }
      expect(request.headers['depth'], '1');
      return http.Response(
        '<d:multistatus xmlns:d="DAV:"><d:response><d:href>${request.url.path}</d:href></d:response><d:response><d:href>${request.url.path}$objectId.json</d:href><d:propstat><d:prop/><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>',
        207,
      );
    });
    final remote = dav(client);
    await remote.prepare();
    expect(await remote.create('commits/$objectId.json', utf8.encode('{"v":1.0}')), SyncDelivery.confirmed);
    expect(await remote.create('commits/$objectId.json', utf8.encode('{"v":1}')), SyncDelivery.confirmed);
    expect(calls.where((c) => c.method == 'PUT'), hasLength(1));
    expect(await remote.listCommits(), [objectId]);
    final binary = [0, 255, 128], key = 'blobs/${sha256.convert([0, 255, 128])}.bin';
    expect(await remote.create(key, binary), SyncDelivery.confirmed);
    expect(calls.lastWhere((c) => c.method == 'PUT').headers['content-type'], 'application/octet-stream');
    expect(await remote.read(key), binary);
    await expectLater(remote.create(key, [0]), problem(SyncTransportProblem.invalidResponse));
    await expectLater(
      remote.create('commits/$objectId.json', utf8.encode('{"v":2}')),
      problem(SyncTransportProblem.collision),
    );
    await expectLater(remote.read('../local/private.json'), problem(SyncTransportProblem.invalidResponse));
    await expectLater(
      remote.create('library.json', List.filled(syncObjectLimit + 1, 0)),
      problem(SyncTransportProblem.tooLarge),
    );
    client.close();
  });
  for (final entry in {
    401: SyncTransportProblem.authentication,
    403: SyncTransportProblem.permission,
    507: SyncTransportProblem.quota,
    429: SyncTransportProblem.throttled,
    503: SyncTransportProblem.unavailable,
    423: SyncTransportProblem.unavailable,
    302: SyncTransportProblem.invalidResponse,
  }.entries) {
    test('DAV maps ${entry.key} without exposing server response or credentials', () async {
      final remote = dav(MockClient((_) async => http.Response('private response', entry.key)));
      await expectLater(remote.read('library.json'), problem(entry.value));
      expect(SyncTransportException(entry.value).toString(), isNot(contains('private')));
    });
  }
  test('DAV malformed responses, redirects and unknown status never count as success', () async {
    for (final body in [
      '<wrong/>',
      '<!DOCTYPE x><d:multistatus xmlns:d="DAV:"/>',
      '<d:multistatus xmlns:d="DAV:"><d:response><d:href>https://other.example/file</d:href></d:response></d:multistatus>',
      '<d:multistatus xmlns:d="DAV:"><d:response/></d:multistatus>',
    ]) {
      await expectLater(
        dav(MockClient((_) async => http.Response(body, 207))).listCommits(),
        problem(SyncTransportProblem.invalidResponse),
      );
    }
    await expectLater(
      dav(MockClient((_) async => http.Response('', 409))).prepare(),
      problem(SyncTransportProblem.invalidResponse),
    );
    await expectLater(
      dav(MockClient((_) async => http.Response('', 204))).read('library.json'),
      problem(SyncTransportProblem.invalidResponse),
    );
    await expectLater(
      dav(MockClient((_) async => throw http.ClientException('private'))).read('library.json'),
      problem(SyncTransportProblem.unavailable),
    );
    for (final uri in [
      'http://dav.example/',
      'https://u:p@dav.example/',
      'https://dav.example/?token=secret',
      'https://dav.example/a%2fb/',
    ]) {
      expect(
        () => WebDavSyncTransport(
          client: MockClient((_) async => http.Response('', 200)),
          directory: Uri.parse(uri),
          account: 'a',
          libraryId: 'l',
          authorization: 'secret',
        ),
        throwsArgumentError,
      );
    }
    final remote = WebDavSyncTransport(
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return http.Response('', 200);
      }),
      directory: Uri.parse('https://dav.example'),
      account: 'a',
      libraryId: 'l',
      authorization: 'secret',
      timeout: const Duration(milliseconds: 1),
    );
    await expectLater(remote.read('library.json'), problem(SyncTransportProblem.unavailable));
    await Future<void>.delayed(const Duration(milliseconds: 15));
  });
  test('racing PUT compares the winner and rejects differing or truncated readback', () async {
    var reads = 0;
    final remote = dav(
      MockClient((r) async {
        if (r.method == 'GET') return ++reads == 1 ? http.Response('', 404) : http.Response('{"v":2}', 200);
        return http.Response('', 412);
      }),
    );
    await expectLater(remote.create('library.json', utf8.encode('{"v":1}')), problem(SyncTransportProblem.collision));
    expect(() => sameSyncObject([255], [1]), problem(SyncTransportProblem.invalidResponse));
    expect(
      () => validateSyncLibrary(syncLibraryManifest('other'), 'library'),
      problem(SyncTransportProblem.wrongLibrary),
    );
  });
  test('iCloud staging stays unconfirmed and an account change invalidates in-flight IO', () async {
    final port = Drive();
    expect(
      () => ICloudSyncTransport(port: port, account: 'a', container: 'other', libraryId: 'library'),
      throwsArgumentError,
    );
    final remote = ICloudSyncTransport(port: port, account: 'a', container: 'iCloud.app', libraryId: 'library');
    await remote.prepare();
    expect(await remote.read('library.json'), isNull);
    expect(await remote.create('library.json', syncLibraryManifest('library')), SyncDelivery.staged);
    port.confirmed = true;
    expect(await remote.create('library.json', syncLibraryManifest('library')), SyncDelivery.confirmed);
    await remote.create('commits/$objectId.json', utf8.encode('{}'));
    expect(await remote.listCommits(), [objectId]);
    final binary = [0, 255, 128], key = 'blobs/${sha256.convert([0, 255, 128])}.bin';
    expect(await remote.create(key, binary), SyncDelivery.confirmed);
    expect(await remote.read(key), binary);
    await expectLater(remote.create(key, [0]), problem(SyncTransportProblem.invalidResponse));
    await expectLater(
      remote.create('library.json', syncLibraryManifest('wrong')),
      problem(SyncTransportProblem.collision),
    );
    port.switchOnRead = true;
    await expectLater(remote.read('library.json'), problem(SyncTransportProblem.accountChanged));
    await expectLater(remote.prepare(), problem(SyncTransportProblem.accountChanged));
  });
}

class Drive implements ICloudDrivePort {
  @override
  String get containerIdentifier => 'iCloud.app';
  String? account = 'a';
  bool confirmed = false, switchOnRead = false;
  final objects = <String, List<int>>{};
  @override
  Future<String?> accountIdentity() async => account;
  @override
  Future<void> prepare(String p, String a) async {}
  @override
  Future<List<String>> list(String p, String a) async =>
      objects.keys.where((k) => k.startsWith('$p/')).map((k) => k.substring(p.length + 1)).toList();
  @override
  Future<List<int>?> read(String p, String a) async {
    if (switchOnRead) account = 'b';
    return objects[p];
  }

  @override
  Future<void> create(String p, List<int> b, String a) async {
    objects.putIfAbsent(p, () => b);
  }

  @override
  Future<bool> uploaded(String p, List<int> expected, String a) async =>
      confirmed && sameSyncStoredObject(p.substring(p.indexOf('/', 'foliarc-v2/'.length) + 1), objects[p]!, expected);
}
