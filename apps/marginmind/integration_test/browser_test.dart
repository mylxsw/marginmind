import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:mm_pdf/mm_pdf.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native browser becomes quiet, captures live DOM, and persists its app session', (tester) async {
    debugPrint('[browser] test started');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0).timeout(const Duration(seconds: 10));
    addTearDown(() => server.close(force: true).timeout(const Duration(seconds: 5)));
    final requests = <String>[];
    server.listen((request) async {
      requests.add(request.uri.path);
      if (request.uri.path == '/authenticated.png') {
        if (!request.cookies.any((c) => c.name == 'mm_browser_test')) {
          request.response.statusCode = 403;
        } else {
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jVYsAAAAASUVORK5CYII=',
            ),
          );
        }
        await request.response.close();
        return;
      }
      if (request.uri.path == '/image.svg') {
        request.response.headers.set('Content-Type', 'image/svg+xml');
        request.response.write(
          '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10"/></svg>',
        );
        await request.response.close();
        return;
      }
      if (request.uri.path == '/download' || request.uri.path == '/binary') {
        request.response.headers.contentType = ContentType.binary;
        if (request.uri.path == '/download') {
          request.response.headers.set('Content-Disposition', 'attachment; filename=blocked.bin');
        }
        request.response.write('download must be cancelled');
        await request.response.close();
        return;
      }
      if (request.uri.path.startsWith('/status/')) {
        request.response.statusCode = int.parse(request.uri.pathSegments.last);
      }
      request.response.headers.contentType = ContentType.html;
      request.response.cookies.add(Cookie('mm_browser_test', 'persisted')..maxAge = 3600);
      final persisted = request.cookies.any(
        (cookie) => cookie.name == 'mm_browser_test' && cookie.value == 'persisted',
      );
      final clickDownload = request.uri.path == '/click-download'
          ? '<a id="download" href="/download?click=1" download>Download</a>'
                '<script>setTimeout(() => { document.body.dataset.downloadAttempt = "true"; document.getElementById("download").click(); }, 2500);</script>'
          : '';
      final conversion = request.uri.path == '/conversion'
          ? '<article><h1>Conversion</h1>${List.generate(80, (i) => '<p>Paragraph $i, testing live authenticated content and real paginated printing. This passage is preserved in the offline document.</p>').join()}'
                '<img src="/authenticated.png"><p hidden>HIDDEN_SECRET</p></article><input value="FORM_SECRET">'
          : '';
      request.response.write('''<!DOCTYPE html><html><head><title>Native browser fixture</title></head>
      <body><h1 id="live">initial</h1><p>cookie:$persisted</p><img src="/image.svg">
      $clickDownload
      $conversion
      <script>setTimeout(() => document.getElementById('live').textContent = 'live DOM ready', 300);</script>
      </body></html>''');
      await request.response.close();
    });
    final uri = Uri.parse('http://localhost:${server.port}/page');
    BrowserSession? session;
    Future<void> mount([Uri? initial]) async {
      debugPrint('[browser] mounting ${(initial ?? uri).path}');
      session = BrowserSession(initial ?? uri);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MMBrowserView(session: session!)),
        ),
      );
      await tester.pump();
    }

    Future<void> ready() async {
      final elapsed = Stopwatch()..start();
      while (session!.phase != BrowserPhase.ready && elapsed.elapsed < const Duration(seconds: 30)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        session!.phase,
        BrowserPhase.ready,
        reason: 'url=${session!.url}; id=${session!.navigationId}; error=${session!.lastErrorCode}; requests=$requests',
      );
      debugPrint('[browser] ready ${session!.url.path}');
    }

    try {
      await mount();
      await ready();
      final capture = await session!.capture(navigationId: session!.navigationId);
      expect(capture.title, 'Native browser fixture');
      expect(capture.dom, contains('live DOM ready'));
      expect(capture.resources.map((url) => url.path), contains('/image.svg'));
      expect(session!.prompt, isTrue);
      await session!.navigate(uri.replace(path: '/conversion'));
      await tester.pump(const Duration(milliseconds: 200));
      await ready();
      for (final mode in BrowserDocumentMode.values) {
        debugPrint('[browser] ${mode.name}: capture begin');
        final converted = await session!.captureDocument(
          navigationId: session!.navigationId,
          mode: mode,
          onStage: (stage) => debugPrint('[browser] ${mode.name}: $stage'),
        );
        debugPrint(
          '[browser] ${mode.name}: captured resources=${converted.resources.length}, pdf=${converted.pdf?.length}',
        );
        expect(converted.html, contains('Paragraph 79'));
        expect(converted.resources, isNotEmpty);
        expect(converted.snapshot, isNot(contains('FORM_SECRET')));
        expect(converted.snapshot, isNot(contains('HIDDEN_SECRET')));
        expect(converted.snapshot, isNot(contains('<script')));
        if (mode == BrowserDocumentMode.original) {
          debugPrint('[browser] original: initialize PDF engine');
          await MMPdfEngine.initialize();
          debugPrint('[browser] original: inspect PDF');
          final info = await MMPdfEngine.inspectData(converted.pdf!);
          debugPrint('[browser] original: PDF pages=${info.pageCount}, preview=${info.preview?.length}');
          expect(info.pageCount, greaterThan(1), reason: 'Original web style must be paginated, not one tall page');
          expect(info.preview, isNotNull);
        }
      }
      debugPrint('[browser] all conversion modes complete');
      expect(requests.where((r) => r == '/conversion').length, 1, reason: 'Never re-fetch the page URL');
      final stale = session!.navigationId;
      await session!.navigate(uri.replace(path: '/second'));
      // Navigation events are delivered asynchronously by the real engine.
      await tester.pump(const Duration(seconds: 1));
      await expectLater(session!.capture(navigationId: stale), throwsStateError);
      await ready();
      for (final status in [401, 403, 404, 500]) {
        await session!.navigate(uri.replace(path: '/status/$status'));
        await tester.pump(const Duration(milliseconds: 200));
        await ready();
        expect(session!.canCapture, isTrue, reason: 'HTTP $status is a document');
        expect((await session!.capture(navigationId: session!.navigationId)).dom, contains('live DOM ready'));
      }
      session!.dismissPrompt();
      final retainedUrl = session!.url;
      for (final path in ['/download', '/binary']) {
        await session!.navigate(uri.replace(path: path));
        final elapsed = Stopwatch()..start();
        while ((session!.loading || !requests.contains(path)) && elapsed.elapsed < const Duration(seconds: 15)) {
          await tester.pump(const Duration(milliseconds: 200));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(requests, contains(path));
        expect(session!.phase, BrowserPhase.ready, reason: 'cancel $path without destroying the page');
        expect(session!.url, retainedUrl);
        expect(session!.prompt, isFalse);
        expect((await session!.capture(navigationId: session!.navigationId)).dom, contains('live DOM ready'));
      }
      await session!.navigate(uri.replace(path: '/click-download'));
      await tester.pump(const Duration(milliseconds: 200));
      await ready();
      session!.dismissPrompt();
      // Exercise a page-initiated link, which may not emit a navigation start.
      final clickElapsed = Stopwatch()..start();
      while (clickElapsed.elapsed < const Duration(seconds: 5)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(session!.phase, BrowserPhase.ready);
      expect(session!.url.path, '/click-download');
      expect(
        (await session!.capture(navigationId: session!.navigationId)).dom,
        contains('data-download-attempt="true"'),
      );
      expect(session!.prompt, isFalse);
      expect((await session!.capture(navigationId: session!.navigationId)).dom, contains('live DOM ready'));
      session!.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await mount();
      await ready();
      expect((await session!.capture(navigationId: session!.navigationId)).dom, contains('cookie:true'));
      expect(requests, containsAll(['/page', '/second']));
      await BrowserSession.clearData().timeout(const Duration(seconds: 10));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await mount();
      await ready();
      expect((await session!.capture(navigationId: session!.navigationId)).dom, contains('cookie:false'));
      session!.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await mount(uri.replace(path: '/download'));
      final elapsed = Stopwatch()..start();
      while (session!.phase != BrowserPhase.failed && elapsed.elapsed < const Duration(seconds: 15)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(session!.phase, BrowserPhase.failed);
      expect(session!.canCapture, isFalse);
    } finally {
      debugPrint('[browser] cleanup');
      session?.dispose();
      await tester.pumpWidget(const SizedBox.shrink()).timeout(const Duration(seconds: 10));
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
