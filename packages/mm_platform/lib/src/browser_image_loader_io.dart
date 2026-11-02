import 'dart:io';
import 'dart:typed_data';

/// Public image fallback for resources which an <img> may display but browser
/// CORS prevents scripts from reading. Never shares the browser's cookies.
Future<Uint8List?> loadPublicBrowserImage(Uri url, {required Duration timeout}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    return await (() async {
      var target = url;
      for (var redirects = 0; redirects <= 3; redirects++) {
        if (!{'http', 'https'}.contains(target.scheme) || target.host.isEmpty || target.userInfo.isNotEmpty) {
          return null;
        }
        final request = await client.getUrl(target);
        request.followRedirects = false;
        final response = await request.close();
        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) return null;
          target = target.resolve(location);
          continue;
        }
        const limit = 5 * 1024 * 1024;
        if (response.statusCode != HttpStatus.ok || response.contentLength > limit) return null;
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > limit) return null;
          bytes.add(chunk);
        }
        return bytes.takeBytes();
      }
      return null;
    })().timeout(timeout);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
