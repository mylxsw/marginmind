import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native browser becomes quiet, captures live DOM, and persists its app session', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    server.listen((request) async {
      requests.add(request.uri.path);
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
      request.response.write('''<!DOCTYPE html><html><head><title>Native browser fixture</title></head>
      <body><h1 id="live">initial</h1><p>cookie:$persisted</p><img src="/image.svg">
      $clickDownload
      <script>setTimeout(() => document.getElementById('live').textContent = 'live DOM ready', 300);</script>
      </body></html>''');
      await request.response.close();
    });
    final uri = Uri.parse('http://localhost:${server.port}/page');
    BrowserSession? session;
    Future<void> mount([Uri? initial]) async {
      session = BrowserSession(initial ?? uri);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MMBrowserView(session: session!)),
        ),
      );
      await tester.pump();
    }

    Future<void> ready() async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (session!.phase != BrowserPhase.ready && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        session!.phase,
        BrowserPhase.ready,
        reason: 'url=${session!.url}; id=${session!.navigationId}; error=${session!.lastErrorCode}; requests=$requests',
      );
    }

    try {
      await mount();
      await ready();
      final capture = await session!.capture(navigationId: session!.navigationId);
      expect(capture.title, 'Native browser fixture');
      expect(capture.dom, contains('live DOM ready'));
      expect(capture.resources.map((url) => url.path), contains('/image.svg'));
      expect(session!.prompt, isTrue);
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
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while ((session!.loading || !requests.contains(path)) && DateTime.now().isBefore(deadline)) {
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
      final clickDeadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(clickDeadline)) {
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
      await BrowserSession.clearData();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await mount();
      await ready();
      expect((await session!.capture(navigationId: session!.navigationId)).dom, contains('cookie:false'));
      session!.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await mount(uri.replace(path: '/download'));
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (session!.phase != BrowserPhase.failed && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(session!.phase, BrowserPhase.failed);
      expect(session!.canCapture, isFalse);
    } finally {
      session?.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await server.close(force: true);
    }
  });
}
