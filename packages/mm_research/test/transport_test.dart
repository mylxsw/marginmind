import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart';
import 'package:test/test.dart';

Matcher failure(ResearchFailureKind kind) => isA<ResearchFailure>().having((e) => e.kind, 'kind', kind);
void main() {
  final url = Uri.parse('https://example.com/page');
  UrlPolicy publicPolicy() => UrlPolicy(lookup: (_) async => [InternetAddress('8.8.8.8')]);
  test('rejects private, metadata, non-global IPv4 and IPv6, mixed DNS', () async {
    for (final address in [
      '0.0.0.0',
      '10.0.0.1',
      '127.1.2.3',
      '169.254.169.254',
      '172.16.0.1',
      '172.31.255.1',
      '192.168.1.1',
      '100.100.100.200',
      '224.0.0.1',
      '255.255.255.255',
      '198.18.0.1',
      '192.0.2.1',
      '203.0.113.1',
      '::',
      '::1',
      '::ffff:127.0.0.1',
      'fc00::1',
      'fe80::1',
      'ff02::1',
      '2001:db8::1',
      '64:ff9b::a00:1',
      '2002:7f00:1::',
    ]) {
      expect(UrlPolicy.publicAddress(InternetAddress(address)), isFalse, reason: address);
      await expectLater(
        UrlPolicy(lookup: (_) async => [InternetAddress('8.8.8.8'), InternetAddress(address)]).validate(url),
        throwsA(failure(ResearchFailureKind.unsafeUrl)),
      );
    }
    for (final address in ['8.8.8.8', '1.1.1.1', '2606:4700:4700::1111']) {
      expect(UrlPolicy.publicAddress(InternetAddress(address)), isTrue);
    }
    for (final value in [
      'file:///etc/passwd',
      'ftp://example.com',
      'https://user:pass@example.com',
      'https://example.com/#frag',
      'javascript:alert(1)',
      'http://[fe80::1%25en0]',
    ]) {
      await expectLater(publicPolicy().validate(Uri.parse(value)), throwsA(failure(ResearchFailureKind.unsafeUrl)));
    }
    await expectLater(
      UrlPolicy(lookup: (_) async => []).validate(url),
      throwsA(failure(ResearchFailureKind.unsafeUrl)),
    );
  });
  test('local provider exception is exact and does not admit private LAN', () async {
    final local = Uri.parse('http://127.0.0.1:11434/v1/chat/completions');
    expect(await UrlPolicy(localEndpoint: local).validate(local), hasLength(1));
    await expectLater(
      UrlPolicy(localEndpoint: local).validate(local.resolve('/admin')),
      throwsA(failure(ResearchFailureKind.unsafeUrl)),
    );
    final lan = Uri.parse('http://192.168.1.1/v1/chat/completions');
    await expectLater(UrlPolicy(localEndpoint: lan).validate(lan), throwsA(failure(ResearchFailureKind.unsafeUrl)));
  });
  for (final status in [429, 500, 503]) {
    test('retries $status before streaming, bounded attempts', () async {
      var calls = 0;
      final transport = ResearchHttp(
        policy: publicPolicy(),
        retryDelay: Duration.zero,
        clientFactory: () => MockClient(
          (_) async =>
              ++calls < 3 ? http.Response('', status, headers: {'retry-after': '0'}) : http.Response('ok', 200),
        ),
      );
      final bytes = await transport.send(url, cancellation: CancellationToken()).expand((b) => b).toList();
      expect(utf8.decode(bytes), 'ok');
      expect(calls, 3);
    });
  }
  for (final entry in {
    401: ResearchFailureKind.authentication,
    403: ResearchFailureKind.authentication,
    400: ResearchFailureKind.invalidRequest,
    429: ResearchFailureKind.rateLimited,
    500: ResearchFailureKind.unavailable,
  }.entries) {
    test('maps HTTP ${entry.key} and caps retries', () async {
      var calls = 0;
      final transport = ResearchHttp(
        policy: publicPolicy(),
        retryDelay: Duration.zero,
        clientFactory: () => MockClient((_) async {
          calls++;
          return http.Response('SECRET', entry.key);
        }),
      );
      await expectLater(transport.send(url, cancellation: CancellationToken()).toList(), throwsA(failure(entry.value)));
      expect(calls, entry.key == 429 || entry.key == 500 ? 3 : 1);
    });
  }
  test('checks every redirect and never forwards credentials', () async {
    var calls = 0;
    final transport = ResearchHttp(
      policy: publicPolicy(),
      clientFactory: () => MockClient((r) async {
        calls++;
        return http.Response('', 302, headers: {'location': 'http://127.0.0.1/secret'});
      }),
    );
    await expectLater(
      transport.send(url, cancellation: CancellationToken()).toList(),
      throwsA(failure(ResearchFailureKind.unsafeUrl)),
    );
    expect(calls, 1);
    await expectLater(
      transport
          .send(url, cancellation: CancellationToken(), method: 'POST', headers: {'authorization': 'SECRET'})
          .toList(),
      throwsA(failure(ResearchFailureKind.unsafeUrl)),
    );
    expect(calls, 2);
  });
  test('public relative redirects allowed, loops capped', () async {
    var calls = 0;
    final transport = ResearchHttp(
      policy: publicPolicy(),
      clientFactory: () => MockClient((r) async {
        calls++;
        return r.url.path == '/end' ? http.Response('ok', 200) : http.Response('', 302, headers: {'location': '/end'});
      }),
    );
    expect(await transport.send(url, cancellation: CancellationToken()).toList(), isNotEmpty);
    expect(calls, 2);
    final loop = ResearchHttp(
      policy: publicPolicy(),
      clientFactory: () => MockClient((_) async => http.Response('', 302, headers: {'location': '/page'})),
    );
    await expectLater(
      loop.send(url, cancellation: CancellationToken()).toList(),
      throwsA(failure(ResearchFailureKind.unsafeUrl)),
    );
  });
  test('size limit checks declared length and streaming bytes', () async {
    for (final length in [null, 10]) {
      final transport = ResearchHttp(
        policy: publicPolicy(),
        clientFactory: () => MockClient.streaming(
          (_, _) async => http.StreamedResponse(Stream.value(List.filled(10, 65)), 200, contentLength: length),
        ),
      );
      await expectLater(
        transport.send(url, cancellation: CancellationToken(), budget: const ResearchBudget(responseBytes: 5)).toList(),
        throwsA(failure(ResearchFailureKind.budget)),
      );
    }
  });
  test('deadline and cancellation interrupt blocked headers', () async {
    for (final cancel in [false, true]) {
      final token = CancellationToken();
      final transport = ResearchHttp(
        policy: publicPolicy(),
        clientFactory: () => MockClient.streaming((_, _) => Completer<http.StreamedResponse>().future),
      );
      final future = transport
          .send(
            url,
            cancellation: token,
            budget: const ResearchBudget(duration: Duration(milliseconds: 20)),
          )
          .toList();
      if (cancel) Timer(const Duration(milliseconds: 5), token.cancel);
      await expectLater(future, throwsA(failure(cancel ? ResearchFailureKind.cancelled : ResearchFailureKind.timeout)));
    }
  });
  test('cancel streaming closes client and does not restart request', () async {
    final token = CancellationToken();
    final stream = StreamController<List<int>>();
    final transport = ResearchHttp(
      policy: publicPolicy(),
      clientFactory: () => MockClient.streaming((_, _) async => http.StreamedResponse(stream.stream, 200)),
    );
    final future = transport.send(url, cancellation: token).toList();
    Timer(const Duration(milliseconds: 5), token.cancel);
    await expectLater(future, throwsA(failure(ResearchFailureKind.cancelled)));
    await stream.close();
  });
  test('real IO client supports explicitly configured local endpoint', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final endpoint = Uri.parse('http://127.0.0.1:${server.port}/api');
    final subscription = server.listen((r) {
      r.response.write('ok');
      r.response.close();
    });
    try {
      final bytes = await ResearchHttp(policy: UrlPolicy(localEndpoint: endpoint))
          .send(endpoint, cancellation: CancellationToken())
          .expand((e) => e)
          .toList();
      expect(utf8.decode(bytes), 'ok');
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
  test('budget counters and cancellation remain deterministic', () async {
    final counter = BudgetCounter(const ResearchBudget(searches: 1, pages: 1, responseBytes: 1));
    counter.search();
    counter.page();
    counter.addBytes(1);
    expect(counter.search, throwsA(failure(ResearchFailureKind.budget)));
    expect(counter.page, throwsA(failure(ResearchFailureKind.budget)));
    expect(() => counter.addBytes(1), throwsA(failure(ResearchFailureKind.budget)));
    expect(
      () => BudgetCounter(const ResearchBudget(outputTokens: 0)),
      throwsA(failure(ResearchFailureKind.invalidRequest)),
    );
    final token = CancellationToken();
    expect(await token.bind(Future.value(2)), 2);
    token.cancel();
    token.cancel();
    expect(token.isCancelled, isTrue);
    expect(() => token.bind(Future.value(3)), throwsA(failure(ResearchFailureKind.cancelled)));
    expect(const ResearchFailure(ResearchFailureKind.tool).toString(), 'ResearchFailure(tool)');
  });
}
