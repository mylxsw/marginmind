import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<BrowserSession> setup({
    bool fail = false,
    bool stale = false,
    bool missing = false,
    bool badPdf = false,
    bool changeOnPrint = false,
    bool pendingStages = false,
  }) async {
    final session = BrowserSession(Uri.parse('https://example.com/'));
    var printed = false;
    var polls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannel('marginmind/browser/${session.id}'),
      (call) async {
        if (call.method == 'printPdf') {
          printed = true;
          return Uint8List.fromList(ascii.encode(badPdf ? 'broken' : '%PDF-test'));
        }
        if (call.method != 'evaluate') return null;
        final script = (call.arguments as Map)['script'] as String;
        if (script == 'JSON.stringify({url:location.href})') {
          return jsonEncode({'url': printed && changeOnPrint ? 'https://example.com/new' : session.url.toString()});
        }
        if (script.startsWith('JSON.stringify(globalThis[')) {
          if (pendingStages && polls++ < 2) return jsonEncode({'pending': true, 'stage': 'images'});
          return jsonEncode(
            fail
                ? {'error': 'capture_failed'}
                : {
                    'url': stale ? 'https://example.com/new' : session.url.toString(),
                    'title': 'Live title',
                    'html': '<p>Live article</p>',
                    'snapshot': '<p>Snapshot</p>',
                    'resources': {
                      'resources/image-1.png': base64Encode([137, 80, 78, 71]),
                    },
                    'diagnostics': ['image_unavailable'],
                  },
          );
        }
        if (script.contains('function Readability')) {
          expect(script, contains('document.cloneNode(true)'));
          expect(script, contains("credentials:'include'"));
          expect(script, contains('AbortController'));
          return missing ? null : '{}';
        }
        return '{}';
      },
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'marginmind/browser/${session.id}',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('event', {'kind': 'loaded', 'navigationId': 1, 'url': session.url.toString()}),
      ),
      (_) {},
    );
    return session;
  }

  test('live extraction includes resources, original PDF and capture identity', () async {
    final s = await setup();
    addTearDown(s.dispose);
    final capture = await s.captureDocument(navigationId: s.navigationId);
    expect(capture.title, 'Live title');
    expect(capture.url, s.url);
    expect(capture.html, contains('Live article'));
    expect(capture.resources.keys, ['resources/image-1.png']);
    expect(capture.diagnostics, ['image_unavailable']);
    expect(capture.pdf, isNull);
    expect(capture.capturedAt.isUtc, isTrue);
    final pdf = await s.captureDocument(navigationId: s.navigationId, mode: BrowserDocumentMode.original);
    expect(ascii.decode(pdf.pdf!), '%PDF-test');
    expect(
      (await s.captureDocument(navigationId: s.navigationId, mode: BrowserDocumentMode.markdown)).snapshot,
      '<p>Snapshot</p>',
    );
  });
  test('capture diagnostics report changing stages once, including the native print boundary', () async {
    final s = await setup(pendingStages: true);
    addTearDown(s.dispose);
    final stages = <String>[];
    await s.captureDocument(navigationId: s.navigationId, mode: BrowserDocumentMode.original, onStage: stages.add);
    expect(stages, ['loading-reader', 'extracting', 'images', 'printing', 'complete']);
  });
  test('errors, stale data, invalid PDF and cancellation never yield partial captures', () async {
    for (final options in [0, 1, 2, 3, 4]) {
      final s = await setup(
        fail: options == 0,
        stale: options == 1,
        missing: options == 2,
        badPdf: options == 3,
        changeOnPrint: options == 4,
      );
      try {
        await expectLater(
          s.captureDocument(navigationId: s.navigationId, mode: BrowserDocumentMode.original),
          throwsStateError,
        );
      } finally {
        s.dispose();
      }
    }
    final s = await setup();
    await expectLater(s.captureDocument(navigationId: s.navigationId + 1), throwsStateError);
    await expectLater(s.captureDocument(navigationId: s.navigationId, cancelled: () => true), throwsStateError);
    s.dispose();
    await expectLater(s.captureDocument(navigationId: s.navigationId), throwsStateError);
    final loading = BrowserSession(Uri.parse('https://example.com/'));
    await expectLater(loading.captureDocument(navigationId: loading.navigationId), throwsStateError);
    loading.dispose();
  });
}
