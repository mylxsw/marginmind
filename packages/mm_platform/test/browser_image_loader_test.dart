import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/src/browser_image_loader_io.dart';

void main() {
  test('public image download follows redirects without cookies and bounds bytes and time', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <HttpRequest>[];
    final png = Uint8List.fromList([137, 80, 78, 71]);
    server.listen((request) async {
      requests.add(request);
      switch (request.uri.path) {
        case '/redirect':
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(HttpHeaders.locationHeader, '/image');
          request.response.cookies.add(Cookie('secret', 'not-forwarded'));
        case '/image':
          request.response.add(png);
        case '/large':
          request.response.contentLength = 6 * 1024 * 1024;
        case '/stream-large':
          for (var i = 0; i < 6; i++) {
            request.response.add(Uint8List(1024 * 1024));
          }
        case '/hang':
          return;
        default:
          request.response.statusCode = HttpStatus.forbidden;
      }
      try {
        await request.response.close();
      } catch (_) {}
    });
    addTearDown(() => server.close(force: true));
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    Future<Uint8List?> load(String path) =>
        loadPublicBrowserImage(base.resolve(path), timeout: const Duration(seconds: 2));
    expect(await load('/redirect'), png);
    expect(requests.map((r) => r.uri.path), ['/redirect', '/image']);
    expect(requests.every((r) => r.headers.value(HttpHeaders.cookieHeader) == null), isTrue);
    expect(await load('/large'), isNull);
    expect(await load('/stream-large'), isNull);
    expect(await load('/forbidden'), isNull);
    expect(await load('/hang'), isNull);
    for (final url in ['file:///etc/passwd', 'data:image/png,a', 'http://u:p@127.0.0.1/']) {
      expect(await loadPublicBrowserImage(Uri.parse(url), timeout: const Duration(seconds: 1)), isNull);
    }
  });
}
