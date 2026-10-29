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
      request.response.headers.contentType = ContentType.html;
      request.response.cookies.add(Cookie('mm_browser_test', 'persisted')..maxAge = 3600);
      final persisted = request.cookies.any(
        (cookie) => cookie.name == 'mm_browser_test' && cookie.value == 'persisted',
      );
      request.response.write('''<!DOCTYPE html><html><head><title>Native browser fixture</title></head>
      <body><h1 id="live">initial</h1><p>cookie:$persisted</p><img src="/image.svg">
      <script>setTimeout(() => document.getElementById('live').textContent = 'live DOM ready', 300);</script>
      </body></html>''');
      await request.response.close();
    });
    final uri = Uri.parse('http://localhost:${server.port}/page');
    BrowserSession? session;
    Future<void> mount() async {
      session = BrowserSession(uri);
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
    } finally {
      session?.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await server.close(force: true);
    }
  });
}
