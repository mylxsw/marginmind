@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

import 'support/dav_server.dart';

Matcher problem(SyncTransportProblem value) =>
    throwsA(isA<SyncTransportException>().having((e) => e.problem, 'problem', value));

class Device {
  Device(this.ledger) {
    library = FileLibraryStore(ledger.root, sync: ledger);
    words = FileVocabularyStore(ledger.root, sync: ledger);
    engine = FileSyncEngine(ledger, FileSyncReceiver(library, words));
  }
  final FileSyncLedger ledger;
  late final FileLibraryStore library;
  late final FileVocabularyStore words;
  late final FileSyncEngine engine;
  Future<void> start(WebDavSyncTransport remote) async {
    await engine.bind(remote);
    await engine.resume();
  }

  Future<List<SyncCommit>> pending(WebDavSyncTransport remote) async =>
      (await ledger.pending(target: remote.target.key)).where((c) => isSyncWireScope(c.scope)).toList();
  Future<void> close() async {
    await library.dispose();
    await words.dispose();
  }
}

void main() {
  late Directory root;
  late DavServer server;
  late Device a, b;
  late WebDavSyncTransport ra, rb;
  final devices = <Device>[];
  var serial = 0;
  final now = DateTime.utc(2026);
  late StudySetEditor editor;
  Device device(String name) {
    final value = Device(FileSyncLedger(Directory('${root.path}/$name'), libraryId: 'lib', deviceId: name));
    devices.add(value);
    return value;
  }

  Future<Device> reopen(Device old) async {
    await old.close();
    devices.remove(old);
    final value = Device((await FileSyncLedger.restore(old.ledger.root))!);
    devices.add(value);
    return value;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dav-integration-');
    server = await DavServer.start();
    a = device('a');
    b = device('b');
    ra = server.transport();
    rb = server.transport();
    editor = StudySetEditor(newId: () => 'item-${++serial}', now: () => now);
    await a.start(ra);
    await b.start(rb);
  });
  tearDown(() async {
    // Teardown owns all clients, blocked handlers and sockets even on assertion
    // failure. No daemon, external account, or background service survives.
    await server.close();
    for (final device in devices) {
      await device.close();
    }
    devices.clear();
    await root.delete(recursive: true);
    expect(server.errors, isEmpty);
  });

  Future<String> seed() async {
    final id = (await a.library.create(const NewStudySet(title: 'Synthetic notes', colorIndex: 0))).id;
    await a.library.update(id, (c) => editor.addNote(c, text: 'Original question').$1);
    return id;
  }

  Future<void> exchange() async {
    await a.engine.run();
    await b.engine.run();
    await a.engine.run();
    await b.engine.run();
  }

  test('real HTTPS peers merge offline edits and ratings; conflicts survive third-device restart', () async {
    final id = await seed();
    await exchange();
    final card = (await a.library.load(id)).cards.single.id;
    await a.library.rename(id, 'A renamed the set');
    await b.library.update(id, (c) => editor.rename(c, card, 'B edited the card'));
    await a.library.update(id, (c) => editor.rate(c, card, Rating.good));
    await b.library.update(id, (c) => editor.rate(c, card, Rating.easy));
    server.absoluteHrefs = true; // Both RFC 4918 forms, escaped Unicode/spaces/&.
    await exchange();
    expect((await b.library.watchAll().first).single.title, 'A renamed the set');
    expect((await a.library.load(id)).cards.single.title, 'B edited the card');
    expect((await a.library.load(id)).reviewLogs, hasLength(2));
    expect(
      normalizeReviewData(reviewData(await a.library.load(id))),
      normalizeReviewData(reviewData(await b.library.load(id))),
    );
    expect(await a.library.syncConflicts(id), isEmpty);
    await a.library.update(id, (c) => editor.rename(c, card, 'Candidate A'));
    await b.library.update(id, (c) => editor.rename(c, card, 'Candidate B'));
    await exchange();
    final pending = (await a.library.syncConflicts(id)).single.transaction;
    expect((await b.library.syncConflicts(id)).single.transaction, pending);
    var third = device('third');
    await third.start(server.transport());
    await third.engine.run();
    third = await reopen(third);
    expect((await third.library.syncConflicts(id)).single.transaction, pending);
    final head = (await third.ledger.snapshots())['sets/$id']!;
    await third.library.resolveSyncConflict(id, pending, expectedRevision: head.revision, useCandidate: true);
    await third.start(server.transport());
    await third.engine.run();
    await exchange();
    expect(await a.library.syncConflicts(id), isEmpty);
    expect((await a.library.load(id)).cards.single.toJson(), (await third.library.load(id)).cards.single.toJson());
    final count = server.objects.length;
    await exchange();
    expect(server.objects.length, count);
    expect((await b.library.load(id)).reviewLogs, hasLength(2));
    expect(await a.pending(ra), isEmpty);
    expect(server.requests.map((r) => r.method).toSet(), containsAll(['GET', 'PUT', 'MKCOL', 'PROPFIND']));
    expect(server.objects.keys.any((p) => p.contains('.foliarc-sync')), isFalse);
  });

  test('committed PUT with lost reply keeps outbox; reopen verifies bytes without a second PUT', () async {
    final id = await seed();
    server.dropNextCommitReply = true;
    await expectLater(a.engine.run(), problem(SyncTransportProblem.unavailable));
    final saved = server.objects.keys.singleWhere((p) => p.contains('/commits/'));
    final commit = SyncCommit.fromJson((jsonDecode(utf8.decode(server.objects[saved]!)) as Map).cast());
    expect((await a.pending(ra)).map((c) => c.id), contains(commit.id));
    a = await reopen(a);
    await a.start(ra);
    await exchange();
    expect(await a.pending(ra), isEmpty);
    expect((await b.library.load(id)).cards.single.title, 'Original question');
    expect(server.requests.where((r) => r.method == 'PUT' && r.path == saved), hasLength(1));
  });

  test('notes arrive before large resources; interrupted download resumes durable chunks after reopen', () async {
    final id = await seed();
    final bytes = List<int>.generate(syncResourceChunkSize + 37, (i) => i % 251);
    await a.library.importDocumentPackage(
      id,
      DocumentPackage(
        document: Document(
          id: 'doc',
          title: 'Synthetic bytes',
          fileName: 'documents/paper.pdf',
          pageCount: 1,
          importedAt: now,
        ),
        files: {'documents/paper.pdf': bytes},
      ),
    );
    await File(a.library.resolveFile(id, 'documents/private.txt')).writeAsString('PRIVATE SENTINEL');
    await exchange();
    final missing = (await b.library.syncResources()).single;
    expect(missing.availability, SyncResourceAvailability.missing);
    expect((await b.library.load(id)).cards.single.title, 'Original question');
    final blobs = server.objects.keys.where((p) => p.contains('/blobs/')).toList();
    expect(blobs, hasLength(2));
    var reads = 0;
    String? cachedPath;
    server.intercept = (request, _) async {
      if (request.method == 'GET' && request.uri.path.contains('/blobs/')) {
        if (++reads == 1) cachedPath = request.uri.path;
        if (reads == 2) {
          await DavServer.reply(request, 503);
          return true;
        }
      }
      return false;
    };
    await expectLater(b.engine.download(missing), problem(SyncTransportProblem.unavailable));
    expect(await File(b.library.resolveFile(id, 'documents/paper.pdf')).exists(), isFalse);
    b = await reopen(b);
    await b.start(rb);
    server.intercept = null;
    server.objects.remove(cachedPath); // Resume must use the already verified on-disk chunk.
    await b.engine.download((await b.library.syncResources()).single);
    expect(await File(b.library.resolveFile(id, 'documents/paper.pdf')).readAsBytes(), bytes);
    expect((await b.library.syncResources()).single.availability, SyncResourceAvailability.available);
    expect(
      server.objects.values.any((v) => utf8.decode(v, allowMalformed: true).contains('PRIVATE SENTINEL')),
      isFalse,
    );
  });

  test('account switch while PUT waits never acknowledges old or new destination', () async {
    await seed();
    final gate = server.hold((r) => r.method == 'PUT' && r.uri.path.contains('/commits/'));
    final rejected = expectLater(a.engine.run(), problem(SyncTransportProblem.paused));
    await gate.entered.future.timeout(const Duration(seconds: 5));
    final other = server.transport(name: 'second destination', account: 'other-test-principal');
    await a.engine.bind(other);
    gate.open();
    await rejected;
    expect((await a.ledger.transportConnection())!.paused, isTrue);
    expect(await a.pending(ra), isNotEmpty);
    expect(await a.pending(other), isNotEmpty);
    expect(server.requests.any((r) => r.path.startsWith(other.directory.path)), isFalse);
    await a.engine.resume();
    await a.engine.run();
    expect(await a.pending(other), isEmpty);
    expect(await a.pending(ra), isNotEmpty);
  });

  test('conditional creation race reads winning bytes and refuses different content', () async {
    await ra.prepare();
    final first = server.hold((r) => r.method == 'PUT');
    final rejected = expectLater(
      ra.create('library.json', utf8.encode('{"value":1}')),
      problem(SyncTransportProblem.collision),
    );
    await first.entered.future.timeout(const Duration(seconds: 5));
    expect(await rb.create('library.json', utf8.encode('{"value":2}')), SyncDelivery.confirmed);
    first.open();
    await rejected;
    expect(jsonDecode(utf8.decode((await ra.read('library.json'))!)), {'value': 2});
    expect(server.requests.where((r) => r.method == 'PUT'), hasLength(2));
  });

  test('TLS trust, authentication, quota and redirect failures never become delivery', () async {
    await seed();
    final untrusted = server.transport(trust: false);
    await expectLater(untrusted.read('library.json'), problem(SyncTransportProblem.unavailable));
    expect(server.requests, isEmpty);
    await expectLater(
      server.transport(credentials: 'Basic invalid').read('library.json'),
      problem(SyncTransportProblem.authentication),
    );
    server.intercept = (request, _) async {
      if (request.method == 'PUT') {
        await DavServer.reply(request, 507);
        return true;
      }
      return false;
    };
    await expectLater(a.engine.run(), problem(SyncTransportProblem.quota));
    expect(await a.pending(ra), isNotEmpty);
    expect(server.objects, isEmpty);
    server.intercept = (request, _) async {
      request.response.headers.set(HttpHeaders.locationHeader, '${server.directory('redirect sink')}library.json');
      await DavServer.reply(request, 307);
      return true;
    };
    await expectLater(ra.read('library.json'), problem(SyncTransportProblem.invalidResponse));
    expect(server.requests.any((r) => r.path.contains('redirect')), isFalse);
    server.intercept = null;
    await exchange();
    expect(await a.pending(ra), isEmpty);
  });

  test('socket deadline aborts the caller; late server write remains unacknowledged until verified', () async {
    final remote = server.transport(timeout: const Duration(milliseconds: 150));
    await remote.prepare();
    final gate = server.hold((r) => r.method == 'PUT');
    final rejected = expectLater(
      remote.create('library.json', syncLibraryManifest('lib')),
      problem(SyncTransportProblem.unavailable),
    );
    await gate.entered.future.timeout(const Duration(seconds: 5));
    await rejected.timeout(const Duration(seconds: 5));
    gate.open();
    // No assumption that aborting the client reverses a server-side write.
    expect(await ra.create('library.json', syncLibraryManifest('lib')), SyncDelivery.confirmed);
  });

  test('truncated HTTP response is unavailable and corrupt blob never reaches the package', () async {
    final id = await seed();
    await a.library.importDocumentPackage(
      id,
      DocumentPackage(
        document: Document(id: 'doc', title: 'Resource', fileName: 'documents/file.pdf', pageCount: 1, importedAt: now),
        files: {
          'documents/file.pdf': [1, 2, 3],
        },
      ),
    );
    await exchange();
    final path = server.objects.keys.singleWhere((p) => p.contains('/blobs/'));
    server.intercept = (request, _) async {
      if (request.method != 'GET' || request.uri.path != path) return false;
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.add(ascii.encode('HTTP/1.1 200 OK\r\nContent-Length: 100\r\nConnection: close\r\n\r\nx'));
      await socket.flush();
      await socket.close();
      return true;
    };
    await expectLater(
      b.engine.download((await b.library.syncResources()).single),
      problem(SyncTransportProblem.unavailable),
    );
    server.intercept = null;
    server.objects[path] = [9, 9, 9];
    await expectLater(
      b.engine.download((await b.library.syncResources()).single),
      problem(SyncTransportProblem.invalidResponse),
    );
    expect(await File(b.library.resolveFile(id, 'documents/file.pdf')).exists(), isFalse);
    server.objects[path] = [1, 2, 3];
    await b.engine.download((await b.library.syncResources()).single);
    expect(await b.library.watchDocumentResources(id, 'doc').first, DocumentResourceAvailability.ready);
  });
}
