import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('extracts explicit links from shared prose and rejects unsafe inputs', () {
    expect(incomingShareUrl('文章 https://example.com/article。')!.path, '/article');
    expect(incomingShareUrl('Read (https://example.com/a).')!.path, '/a');
    expect(incomingShareUrl('https://example.com/wiki/Foo_(bar)')!.path, '/wiki/Foo_(bar)');
    expect(incomingShareUrl('HTTPS://example.com/a')!.host, 'example.com');
    expect(incomingShareUrl('https://u:p@example.com https://good.example/a')!.host, 'good.example');
    for (final text in ['', 'example.com', 'javascript:alert(1)', 'file:///a.pdf', 'https://bad', 'https://a\\b.com']) {
      expect(incomingShareUrl(text), isNull, reason: text);
    }
  });

  test('decodes typed manifests, bounded files and native failure codes', () {
    final batch = MMIncomingShareBatch.fromMap({
      'id': 'batch-1',
      'title': 'A book',
      'files': [
        {'path': '/incoming/1.pdf', 'name': 'Book.PDF'},
        {'path': '/incoming/2.epub', 'name': 'Book.epub'},
      ],
    });
    expect(batch.files.length, 2);
    expect(batch.title, 'A book');
    expect(() => batch.files.add((path: '/x', name: 'x.pdf')), throwsUnsupportedError);
    expect(MMIncomingShareBatch.fromMap({'id': 'url', 'url': 'https://example.com'}).url!.host, 'example.com');
    expect(MMIncomingShareBatch.fromMap({'id': 'error', 'error': 'limit'}).error, 'limit');
    for (final map in <Map<Object?, Object?>>[
      {'id': '../bad', 'error': 'limit'},
      {'id': ''},
      {'id': 'empty'},
      {
        'id': 'files',
        'files': List.filled(21, {'path': '/a', 'name': 'a.pdf'}),
      },
      for (final name in ['', '../a.pdf', 'a\\b.pdf', 'a\n.pdf', 'a.exe'])
        {
          'id': 'files',
          'files': [
            {'path': '/a', 'name': name},
          ],
        },
      {
        'id': 'files',
        'files': [
          {'path': 'relative', 'name': 'a.pdf'},
        ],
      },
    ]) {
      expect(() => MMIncomingShareBatch.fromMap(map), throwsFormatException);
    }
    expect(() => MMIncomingShareBatch.fromMap({'id': 'x', 'url': 'file:///a'}), throwsA(isA<BrowserUrlException>()));
  });

  test('native inbox is read without consumption and acknowledged explicitly', () async {
    const channel = MethodChannel('marginmind/incoming_share');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'pending') {
        return [
          {'id': 'a', 'url': 'https://example.com'},
        ];
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final source = MMIncomingShares(supported: true);
    final changed = Completer<void>();
    final failure = Completer<Object>();
    final subscription = source.changes.listen((_) => changed.complete(), onError: failure.complete);
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('changed')),
      (_) {},
    );
    await changed.future;
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('failed')),
      (_) {},
    );
    expect(await failure.future, isA<PlatformException>());
    expect((await source.pending()).single.id, 'a');
    expect((await source.pending()).single.id, 'a');
    expect(calls.map((c) => c.method), ['pending', 'pending']);
    await source.complete('a');
    expect(calls.last.arguments, {'id': 'a'});
    await subscription.cancel();
    source.dispose();
  });

  test('desktop source stays silent and null native lists are empty', () async {
    final unsupported = MMIncomingShares(supported: false);
    expect(await unsupported.pending(), isEmpty);
    await unsupported.complete('unused');
    unsupported.dispose();
    const channel = MethodChannel('marginmind/incoming_share');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final source = MMIncomingShares(supported: true);
    expect(await source.pending(), isEmpty);
    source.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('a damaged native entry cannot poison the rest of the inbox', () async {
    const channel = MethodChannel('marginmind/incoming_share');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => [
        null,
        {'id': '../bad', 'error': 'limit'},
        {
          'id': 'broken',
          'files': [
            {'name': 'a.exe', 'path': '/tmp/a.exe'},
          ],
        },
        {'id': 'valid', 'url': 'https://example.com'},
      ],
    );
    final source = MMIncomingShares(supported: true);
    final batches = await source.pending();
    expect(batches.map((b) => b.id), ['broken', 'valid']);
    expect(batches.first.error, 'unsupported');
    source.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
}
