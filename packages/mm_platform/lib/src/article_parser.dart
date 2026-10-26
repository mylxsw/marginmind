import 'dart:async';

import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart';

/// Parses a safely fetched document in a network-disabled, offscreen WebView.
class WebKitArticleParser implements HtmlArticleParser {
  WebKitArticleParser({
    MethodChannel? channel,
    Future<String> Function()? script,
    this.timeout = const Duration(seconds: 20),
  }) : _channel = channel ?? const MethodChannel('marginmind/article_parser'),
       _script = script ?? (() => rootBundle.loadString('packages/mm_platform/assets/readability/Readability.js'));
  final MethodChannel _channel;
  final Future<String> Function() _script;
  final Duration timeout;
  static int _sequence = 0;
  @override
  Future<ReadableHtml> parse(Uri url, String html, CancellationToken cancellation) async {
    if (!['http', 'https'].contains(url.scheme) || url.host.isEmpty || url.userInfo.isNotEmpty) {
      throw const ResearchFailure(ResearchFailureKind.unsafeUrl);
    }
    if (html.length > 2097152) throw const ResearchFailure(ResearchFailureKind.budget);
    cancellation.check();
    final id = '${++_sequence}';
    var started = false;
    try {
      final script = await cancellation.bind(_script()).timeout(timeout);
      cancellation.check();
      started = true;
      final result = await cancellation
          .bind(
            _channel.invokeMapMethod<String, dynamic>('parse', {
              'id': id,
              'url': url.toString(),
              'html': html,
              'script': script,
            }),
          )
          .timeout(timeout);
      if (result == null || result['html'] is! String || result['title'] is! String) {
        throw const ResearchFailure(ResearchFailureKind.protocol, 'unparseable');
      }
      return ReadableHtml(
        url: url,
        title: result['title'] as String,
        html: result['html'] as String,
        canonicalUrl: result['canonical'] is String ? url.resolve(result['canonical'] as String) : null,
      );
    } on TimeoutException {
      throw const ResearchFailure(ResearchFailureKind.timeout);
    } on PlatformException catch (e) {
      throw ResearchFailure(
        switch (e.code) {
          'login_required' => ResearchFailureKind.authentication,
          'timeout' => ResearchFailureKind.timeout,
          'cancelled' => ResearchFailureKind.cancelled,
          _ => ResearchFailureKind.protocol,
        },
        const ['login_required', 'unparseable', 'blocked', 'cancelled', 'timeout'].contains(e.code)
            ? e.code
            : 'extraction_failed',
      );
    } on MissingPluginException {
      throw const ResearchFailure(ResearchFailureKind.unsupported, 'web_content');
    } finally {
      if (started) {
        // Native cancellation is idempotent. Do not wait for an unavailable host.
        unawaited(_channel.invokeMethod<void>('cancel', {'id': id}).catchError((Object _) {}));
      }
    }
  }
}
