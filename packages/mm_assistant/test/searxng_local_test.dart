import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart';
import 'package:test/test.dart';

import 'network_test.dart' show Snapshots, Parser, Search, Extractor, fails;

SnapshotAssistantNetwork production(String endpoint) => productionAssistantNetwork(
  studySetId: 'set',
  snapshots: Snapshots(),
  parser: Parser(),
  model: const AssistantModel(
    provider: AssistantProvider.ollama,
    model: 'm',
    endpoint: 'http://localhost:11434/v1/chat/completions',
  ),
  key: '',
  searxngEndpoint: endpoint,
) as SnapshotAssistantNetwork;

void main() {
  test('configured loopback SearXNG uses the real pinned transport; fetch and OpenAlex stay public-only', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) async {
      requests++;
      expect(request.uri.path, '/search');
      expect(request.uri.queryParameters, {'q': 'q', 'format': 'json'});
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'results': [
            {'url': 'http://127.0.0.1/private', 'title': 'Private'},
          ],
        }),
      );
      await request.response.close();
    });
    final endpoint = 'http://127.0.0.1:${server.port}/search';
    final network = production(endpoint);
    expect(await network.search('q', CancellationToken()), isEmpty);
    await expectLater(
      network.fetch(Uri.parse(endpoint), CancellationToken()),
      throwsA(fails(ResearchFailureKind.unsafeUrl)),
    );
    final searx = (network.discovery as SearxngSearch).http as AssistantNetworkHttp;
    final papers = (network.paperSearch as OpenAlexSearch).http as AssistantNetworkHttp;
    final fetch = (network.extractor as MarkdownArticleExtractor).http as AssistantNetworkHttp;
    expect(searx.counter, same(fetch.counter));
    expect(searx.deadline, fetch.deadline);
    for (final transport in [papers, fetch]) {
      expect(transport.policy.privateEndpoint, isNull);
      await expectLater(
        transport.send(Uri.parse(endpoint), cancellation: CancellationToken()).drain<void>(),
        throwsA(fails(ResearchFailureKind.unsafeUrl)),
      );
    }
    expect(requests, 1);
  });

  test('configured LAN service resolves private addresses; scheme, host and port must match', () async {
    final endpoint = Uri.parse('http://search.lan:8080/search');
    for (final address in ['127.0.0.1', '10.1.2.3', '172.16.0.1', '192.168.1.2', '::1', 'fd00::1', 'fe80::1']) {
      final policy = UrlPolicy(privateEndpoint: endpoint, lookup: (_) async => [InternetAddress(address)]);
      var calls = 0;
      final transport = AssistantNetworkHttp(
        policy: policy,
        clientFactory: () => MockClient((_) async {
          calls++;
          return http.Response('{"results":[]}', 200);
        }),
      );
      final search = SearxngSearch(endpoint: endpoint.toString(), http: transport);
      expect(await search.search(const SearchRequest('q'), CancellationToken()), isEmpty);
      expect(calls, 1);
      // Paths/query can change within the explicitly configured origin.
      expect(await policy.validate(endpoint.resolve('/other?q=1')), hasLength(1));
      for (final other in [
        'https://search.lan:8080/search',
        'http://other.lan:8080/search',
        'http://search.lan:8081/search',
      ]) {
        await expectLater(policy.validate(Uri.parse(other)), throwsA(fails(ResearchFailureKind.unsafeUrl)));
      }
    }
    for (final address in ['0.0.0.0', '224.0.0.1', '198.18.0.1', 'ff02::1']) {
      await expectLater(
        UrlPolicy(privateEndpoint: endpoint, lookup: (_) async => [InternetAddress(address)]).validate(endpoint),
        throwsA(fails(ResearchFailureKind.unsafeUrl)),
      );
    }
    final configured = production(endpoint.toString());
    expect((configured.discovery as SearxngSearch).http.policy.privateEndpoint, endpoint);
  });

  test('redirects cannot extend the private origin exception', () async {
    final endpoint = Uri.parse('http://192.168.1.2:8080/search');
    final requested = <Uri>[];
    final transport = AssistantNetworkHttp(
      policy: UrlPolicy(privateEndpoint: endpoint),
      clientFactory: () => MockClient((request) async {
        requested.add(request.url);
        return http.Response('', 302, headers: {'location': 'http://192.168.1.3:8080/search'});
      }),
    );
    await expectLater(
      SearxngSearch(
        endpoint: endpoint.toString(),
        http: transport,
      ).search(const SearchRequest('q'), CancellationToken()),
      throwsA(fails(ResearchFailureKind.unsafeUrl)),
    );
    expect(requested, hasLength(1));
  });

  test('discovery discards literal, resolved, mixed-DNS and unresolvable private results', () async {
    final search = Search()
      ..hits = [
        for (final candidate in [
          'http://127.0.0.1/x',
          'http://192.168.1.2/x',
          'http://[::1]/x',
          'http://internal.test/x',
          'https://mixed.test/x',
          'https://missing.test/x',
          'https://public.test/article#part',
        ])
          SearchHit(url: Uri.parse(candidate), title: candidate),
      ];
    final network = SnapshotAssistantNetwork(
      studySetId: 'set',
      snapshots: Snapshots(),
      discovery: search,
      paperSearch: search,
      extractor: Extractor(),
      resultPolicy: UrlPolicy(
        lookup: (host) async => switch (host) {
          'internal.test' => [InternetAddress('10.0.0.2')],
          'mixed.test' => [InternetAddress('8.8.8.8'), InternetAddress('192.168.1.2')],
          'missing.test' => throw const SocketException('not found'),
          _ => [InternetAddress('8.8.8.8')],
        },
      ),
    );
    expect((await network.search('q', CancellationToken())).single.url.toString(), 'https://public.test/article#part');
  });

  test('result DNS lookup stays cancellable and bounded', () async {
    final pending = Completer<List<InternetAddress>>();
    final search = Search();
    final network = SnapshotAssistantNetwork(
      studySetId: 'set',
      snapshots: Snapshots(),
      discovery: search,
      paperSearch: search,
      extractor: Extractor(),
      resultPolicy: UrlPolicy(lookup: (_) => pending.future),
      limits: const ResearchBudget(duration: Duration(milliseconds: 50)),
    );
    await expectLater(network.search('q', CancellationToken()), throwsA(fails(ResearchFailureKind.timeout)));
    final cancel = CancellationToken();
    final result = network.search('q', cancel);
    cancel.cancel();
    await expectLater(result, throwsA(fails(ResearchFailureKind.cancelled)));
    pending.complete([InternetAddress('8.8.8.8')]);
  });

  test('invalid endpoints fail with a typed error; missing configuration remains unavailable', () {
    for (final endpoint in [
      'localhost:8080/search',
      '/search',
      'file:///search',
      'http://user:pass@localhost/search',
      'http://localhost/search#fragment',
      'http://[::1',
      'http://localhost:bad',
      'http://localhost:65536',
      'http://localhost:0',
      'http://local host/search',
      r'http://localhost\search',
    ]) {
      expect(() => SearxngSearch.parseEndpoint(endpoint), throwsA(fails(ResearchFailureKind.unsafeUrl)));
    }
    expect(() => SearxngSearch.parseEndpoint(''), throwsA(fails(ResearchFailureKind.unavailable)));
    for (final endpoint in [
      'http://localhost:8080/search',
      'http://[::1]:8080/search',
      'https://192.168.1.2/search?language=en',
    ]) {
      expect(SearxngSearch.parseEndpoint(endpoint).toString(), endpoint);
    }
  });
}
