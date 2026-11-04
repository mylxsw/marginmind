@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/io_client.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

import 'webdav_integration_test.dart' show Device;

/// Launched by tool/webdav_acceptance.py, not a configurable real-account test.
/// The dedicated client trusts the public TEST certificate only.
void main() {
  final url = Platform.environment['FOLIARC_TEST_DAV_URL'];
  test(
    'WsgiDAV HTTPS: peers, resources, versioned ratings, service copy and restart',
    () async {
      final base = Uri.parse(url!);
      expect(base.scheme, 'https');
      expect(base.host, '127.0.0.1');
      expect(base.userInfo, isEmpty);
      final root = await Directory.systemTemp.createTemp('dav-real-repositories-');
      final devices = <Device>[];
      final clients = <IOClient>[];
      addTearDown(() async {
        for (final client in clients) {
          client.close();
        }
        for (final device in devices) {
          await device.close();
        }
        await root.delete(recursive: true);
      });
      Device device(String name) {
        final value = Device(FileSyncLedger(Directory('${root.path}/$name'), libraryId: 'lib', deviceId: name));
        devices.add(value);
        return value;
      }

      WebDavSyncTransport transport(String directory) {
        final context = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates('test/fixtures/dav_tls/certificate.pem');
        final client = IOClient(HttpClient(context: context)..findProxy = (_) => 'DIRECT');
        clients.add(client);
        return WebDavSyncTransport(
          client: client,
          directory: base.resolveUri(Uri(path: '$directory/')),
          account: 'test',
          libraryId: 'lib',
          authorization: 'Basic dGVzdDpvbmx5',
        );
      }

      final a = device('a'), b = device('b');
      final source = transport('source space & 中文'), destination = transport('destination');
      await a.start(source);
      await b.start(transport('source space & 中文'));
      final now = DateTime.utc(2026);
      var serial = 0;
      final editor = StudySetEditor(newId: () => 'item-${++serial}', now: () => now);
      final id = (await a.library.create(const NewStudySet(title: 'Synthetic set', colorIndex: 0))).id;
      await a.library.update(id, (c) => editor.addNote(c, text: 'Question').$1);
      await a.words.save([
        VocabularyEntry(
          id: 'old-word',
          term: 'Word',
          forms: ['word'],
          language: 'en',
          kind: VocabularyKind.word,
          createdAt: now,
          updatedAt: now,
          note: 'Synthetic source note',
        ),
      ]);
      final bytes = List<int>.generate(syncResourceChunkSize + 13, (i) => i % 251);
      await a.library.importDocumentPackage(
        id,
        DocumentPackage(
          document: Document(
            id: 'doc',
            title: 'Synthetic resource',
            fileName: 'documents/file.pdf',
            pageCount: 1,
            importedAt: now,
          ),
          files: {'documents/file.pdf': bytes},
        ),
      );
      await a.engine.run();
      await b.engine.run();
      expect((await b.library.syncResources()).single.availability, SyncResourceAvailability.missing);
      expect((await b.words.load()).single.note, 'Synthetic source note');
      final card = (await b.library.load(id)).cards.single.id;
      await a.library.rename(id, 'Changed on A');
      await b.library.update(id, (c) => editor.rename(c, card, 'Changed on B'));
      await a.library.update(id, (c) => editor.rate(c, card, Rating.good));
      await b.library.update(id, (c) => editor.rate(c, card, Rating.easy));
      for (var i = 0; i < 2; i++) {
        await a.engine.run();
        await b.engine.run();
      }
      expect((await b.library.watchAll().first).single.title, 'Changed on A');
      expect((await a.library.load(id)).cards.single.title, 'Changed on B');
      expect((await b.library.load(id)).reviewLogs, hasLength(2));
      expect(
        normalizeReviewData(reviewData(await a.library.load(id))),
        normalizeReviewData(reviewData(await b.library.load(id))),
      );
      await b.engine.download((await b.library.syncResources()).single);
      expect(await File(b.library.resolveFile(id, 'documents/file.pdf')).readAsBytes(), bytes);
      // Explicitly reviewed forwarding must preserve the remote author's ancestry.
      await a.engine.bind(destination);
      expect(await destination.read('library.json'), isNull);
      final plan = await a.engine.previewHistoryCopy();
      expect(plan.otherDeviceCommits, greaterThan(0));
      expect(await destination.read('library.json'), isNull);
      await a.engine.copyHistory(plan);
      expect(await a.pending(destination), isEmpty);
      final c = device('c');
      await c.start(transport('destination'));
      await c.engine.run();
      await c.engine.download((await c.library.syncResources()).single);
      expect(await File(c.library.resolveFile(id, 'documents/file.pdf')).readAsBytes(), bytes);
      expect((await c.library.load(id)).reviewLogs, hasLength(2));
      expect((await c.words.load()).single.note, 'Synthetic source note');
      final before = (await destination.listCommits()).toSet();
      await c.close();
      devices.remove(c);
      final restarted = Device((await FileSyncLedger.restore(c.ledger.root))!);
      devices.add(restarted);
      await restarted.start(transport('destination'));
      await restarted.engine.run();
      await restarted.engine.run();
      expect((await destination.listCommits()).toSet(), before);
      expect((await restarted.library.load(id)).reviewLogs, hasLength(2));
      for (final commitId in before) {
        final raw = utf8.decode((await destination.read('commits/$commitId.json'))!);
        expect(raw, isNot(contains('.foliarc-sync/local')));
        expect(raw, isNot(contains('Basic dGVzdDpvbmx5')));
      }
    },
    skip: url == null ? 'Run tool/webdav_acceptance.py for the isolated HTTPS service' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
