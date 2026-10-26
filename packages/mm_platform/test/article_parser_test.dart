import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('marginmind/article_parser');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final url = Uri.parse('https://example.com');
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('bundled Readability is injected; successful result and cancellation use one ID', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'parse') {
        expect(call.arguments['script'], contains('function Readability'));
        return {'title': 'A', 'html': '<p>text</p>'};
      }
      return null;
    });
    final article = await WebKitArticleParser().parse(url, '<p>raw</p>', CancellationToken());
    await Future<void>.delayed(Duration.zero);
    expect(article.html, '<p>text</p>');
    expect(article.title, 'A');
    expect(article.url, url);
    expect(calls.map((c) => c.method), ['parse', 'cancel']);
    expect(calls.first.arguments['id'], calls.last.arguments['id']);
  });
  test('timeout and cancellation release a silent native job', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'parse') return Completer<Object?>().future;
      return null;
    });
    final parser = WebKitArticleParser(script: () async => 'script', timeout: const Duration(milliseconds: 10));
    await expectLater(
      parser.parse(url, '', CancellationToken()),
      throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.timeout)),
    );
    final token = CancellationToken();
    final pending = parser.parse(url, '', token);
    await Future<void>.delayed(Duration.zero);
    token.cancel();
    await expectLater(pending, throwsA(isA<ResearchFailure>()));
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((c) => c.method == 'cancel'), hasLength(2));
  });
  test('native reasons, invalid result, unsupported host and validation remain explicit', () async {
    final parser = WebKitArticleParser(script: () async => 'script');
    for (final reason in ['login_required', 'unparseable', 'blocked', 'cancelled', 'timeout', 'unexpected']) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'parse') throw PlatformException(code: reason, message: 'private diagnostic');
        return null;
      });
      await expectLater(
        parser.parse(url, '', CancellationToken()),
        throwsA(
          isA<ResearchFailure>().having((e) => e.code, 'code', reason == 'unexpected' ? 'extraction_failed' : reason),
        ),
      );
    }
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    await expectLater(parser.parse(url, '', CancellationToken()), throwsA(isA<ResearchFailure>()));
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(
      parser.parse(url, '', CancellationToken()),
      throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.unsupported)),
    );
    for (final uri in [Uri.parse('file:///tmp/a'), Uri.parse('https://u:p@example.com')]) {
      await expectLater(parser.parse(uri, '', CancellationToken()), throwsA(isA<ResearchFailure>()));
    }
    await expectLater(parser.parse(url, 'a' * 2097153, CancellationToken()), throwsA(isA<ResearchFailure>()));
  });
}
