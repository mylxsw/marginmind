import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart';
import 'package:test/test.dart';

AssistantService service(ServiceProtocol protocol, {bool responses = false}) => AssistantService(
  id: protocol.name,
  protocol: protocol,
  name: 'Service',
  responses: responses,
  endpoint: protocol == ServiceProtocol.ollama ? 'http://localhost:11434' : 'https://example.com',
  localEnabled: true,
  models: [
    const ServiceModel(id: 'large'),
    const ServiceModel(id: 'mini'),
  ],
);
ServiceHttpFactory fake(http.Response Function(http.Request) reply) =>
    (endpoint, local) => ResearchHttp(
      policy: UrlPolicy(lookup: (_) async => [InternetAddress('8.8.8.8')], localEndpoint: local ? endpoint : null),
      clientFactory: () => MockClient((r) async => reply(r)),
      maxRetries: 0,
    );
http.Response json(Object data, [int status = 200]) => http.Response(jsonEncode(data), status);
void main() {
  test('immutable ordered defaults, CRUD, serialization and same service quick model', () {
    final a = service(ServiceProtocol.openai), b = service(ServiceProtocol.anthropic);
    var value = AssistantServices(services: [a, b]);
    expect(value.configuration!.model, 'large');
    value = value.select(ModelReference(b.id, 'mini'));
    expect(AssistantServices.fromJson(value.toJson()).configuration!.serviceId, b.id);
    value = value.upsert(b.copyWith(enabled: false));
    expect(value.configuration!.serviceId, a.id);
    value = value.upsert(a.copyWith(models: [a.models.first.copyWith(enabled: false), a.models.last]));
    expect(value.configuration!.model, 'mini');
    expect(quickModelFor(a, a.configuration(a.models.first)).model, 'mini');
    expect(quickModelFor(b, a.configuration(a.models.first)).model, 'large');
    expect(quickModelFor(a.copyWith(enabled: false), a.configuration(a.models.first)).model, 'large');
    expect(value.remove(a.id).configuration, isNull);
    expect(() => value.select(const ModelReference('absent', 'model')), throwsArgumentError);
    expect(() => value.services.add(a), throwsUnsupportedError);
    expect(() => AssistantServices(services: [a, a]), throwsArgumentError);
    expect(
      () => AssistantServices(
        services: [
          a.copyWith(models: [a.models.first, a.models.first]),
        ],
      ),
      throwsArgumentError,
    );
    expect(() => AssistantServices.fromJson({'version': 2}), throwsFormatException);
    expect(AssistantServices().upsert(a).services, [a]);
    expect(
      AssistantServices(services: [service(ServiceProtocol.ollama).copyWith(localEnabled: false)]).configuration,
      isNull,
    );
    expect(
      ServiceModel.fromJson(const ServiceModel(id: 'x', tools: ToolCapability.unsupported).toJson()).supportsTools,
      false,
    );
    expect(const ServiceModel(id: 'x').displayName, 'x');
    expect(const ServiceModel(id: 'x', name: 'Name').displayName, 'Name');
    expect(
      WebSearchSettings.fromJson(const WebSearchSettings(backend: WebSearchBackend.brave).toJson()).backend,
      WebSearchBackend.brave,
    );
  });
  for (final protocol in ServiceProtocol.values) {
    test('$protocol lists, filters, names and probes using isolated paths', () async {
      final s = service(protocol);
      final factory = fake((r) {
        expect(
          r.headers[protocol == ServiceProtocol.anthropic
              ? 'x-api-key'
              : protocol == ServiceProtocol.gemini
              ? 'x-goog-api-key'
              : 'authorization'],
          contains('secret'),
        );
        if (r.method == 'POST') {
          final body = jsonDecode(r.body);
          if (r.url.path == '/api/show') {
            return json({
              'capabilities': ['completion', 'tools'],
            });
          }
          expect(body['tools'], isNotEmpty);
          return json({'ok': true});
        }
        expect(r.url.path, switch (protocol) {
          ServiceProtocol.gemini => '/v1beta/models',
          ServiceProtocol.ollama => '/api/tags',
          _ => '/v1/models',
        });
        return json({
          protocol == ServiceProtocol.gemini || protocol == ServiceProtocol.ollama ? 'models' : 'data': [
            {'id': 'models/chat', 'display_name': 'Chat', 'supports_tools': true},
            {'id': 'unknown'},
            {'id': 'embed-small'},
            {'id': 'tts'},
            {
              'id': 'no-tools',
              'capabilities': {'tools': false},
            },
            {
              'id': 'embed-only',
              'supportedGenerationMethods': ['embedContent'],
            },
            {
              'id': 'tool-model',
              'capabilities': ['completion', 'tools'],
            },
            {
              'id': 'plain',
              'capabilities': ['completion'],
            },
            {
              'id': 'vision-only',
              'capabilities': ['vision'],
            },
            {
              'id': 'gemini',
              'supportedGenerationMethods': ['generateContent'],
            },
            {},
            'malformed',
          ],
        });
      });
      final catalog = ServiceCatalog(httpFactory: factory);
      final list = await catalog.list(s, 'secret');
      expect(list.map((m) => m.id), ['chat', 'unknown', 'no-tools', 'tool-model', 'plain', 'gemini']);
      expect(list.first.name, 'Chat');
      expect(list.first.tools, ToolCapability.supported);
      expect(list[2].supportsTools, false);
      expect((await catalog.probe(s, const ServiceModel(id: 'unknown'), 'secret')).tools, ToolCapability.supported);
      expect(await catalog.probe(s, list.first, 'secret'), same(list.first));
      expect(await catalog.check(s, 'secret'), ConnectionStatus.ok);
    });
  }
  test('Responses tool probe and conservative rejection mapping', () async {
    final s = service(ServiceProtocol.openai, responses: true);
    final probe = ServiceCatalog(
      httpFactory: fake((r) {
        expect(r.url.path, '/v1/responses');
        expect(jsonDecode(r.body)['input'], 'ping');
        return json({'ok': true});
      }),
    );
    expect((await probe.probe(s, s.models.first, 'k')).tools, ToolCapability.supported);
    for (final status in [400, 401, 403, 500]) {
      final c = ServiceCatalog(
        httpFactory: fake(
          (_) => json({
            'error': {'message': 'tools are not supported'},
          }, status),
        ),
      );
      expect(
        (await c.probe(s, s.models.first, 'k')).tools,
        status == 400 ? ToolCapability.unsupported : ToolCapability.unknown,
      );
      expect(
        await c.check(s, 'k'),
        status == 401 || status == 403 ? ConnectionStatus.authFailed : ConnectionStatus.unreachable,
      );
    }
  });
  test('pagination, cycle bounds, cancellation, malformed response and URL refusal', () async {
    for (final protocol in [ServiceProtocol.gemini, ServiceProtocol.anthropic]) {
      var calls = 0;
      final catalog = ServiceCatalog(
        httpFactory: fake((r) {
          calls++;
          if (calls == 2) expect(r.url.queryParameters.values.single, 'next');
          return json({
            protocol == ServiceProtocol.gemini ? 'models' : 'data': [
              {'id': 'm$calls'},
            ],
            if (calls == 1) ...{
              if (protocol == ServiceProtocol.gemini)
                'nextPageToken': 'next'
              else ...{
                'has_more': true,
                'last_id': 'next',
              },
            },
          });
        }),
      );
      expect((await catalog.list(service(protocol), 'k')).length, 2);
    }
    final cycle = ServiceCatalog(httpFactory: fake((_) => json({'data': [], 'has_more': true, 'last_id': 'repeat'})));
    await expectLater(cycle.list(service(ServiceProtocol.anthropic), 'k'), throwsA(isA<ResearchFailure>()));
    final malformed = ServiceCatalog(httpFactory: fake((_) => http.Response('bad', 200)));
    expect(await malformed.check(service(ServiceProtocol.openai), 'k'), ConnectionStatus.unreachable);
    final cancel = CancellationToken()..cancel();
    await expectLater(
      malformed.check(service(ServiceProtocol.openai), 'k', cancellation: cancel),
      throwsA(isA<ResearchFailure>()),
    );
    for (final endpoint in ['http://example.com', 'https://u:p@example.com', 'https://example.com?key=x']) {
      expect(
        () => serviceEndpoint(service(ServiceProtocol.openai).copyWith(endpoint: endpoint), 'models'),
        throwsA(isA<ResearchFailure>()),
      );
    }
    expect(
      () => serviceEndpoint(service(ServiceProtocol.ollama).copyWith(localEnabled: false), 'tags'),
      throwsA(isA<ResearchFailure>()),
    );
    expect(
      serviceEndpoint(
        service(ServiceProtocol.anthropic).copyWith(endpoint: 'https://example.com/v1/messages'),
        'models',
      ).path,
      '/v1/models',
    );
  });
  for (final backend in [WebSearchBackend.cloudflare, WebSearchBackend.tavily, WebSearchBackend.brave]) {
    test('$backend only extracts discovery and uses official wire format', () async {
      final search = ApiWebSearch(
        backend: backend,
        key: 'secret',
        accountId: 'account',
        httpFactory: fake((r) {
          final hits = [
            {'url': 'https://example.com/article', 'title': 'Title', 'description': 'Snippet', 'content': 'Snippet'},
          ];
          if (backend == WebSearchBackend.brave) {
            expect(r.headers['x-subscription-token'], 'secret');
            expect(r.url.queryParameters['q'], 'query');
            return json({
              'web': {'results': hits},
            });
          }
          expect(r.headers['authorization'], 'Bearer secret');
          final body = jsonDecode(r.body);
          expect(body['query'], 'query');
          if (backend == WebSearchBackend.cloudflare) {
            expect(body['options']['gateway']['id'], 'default');
            expect(r.url.path, '/client/v4/accounts/account/ai/websearch/');
            return json({
              'result': {'items': hits},
            });
          }
          expect(body['include_answer'], false);
          expect(body['include_raw_content'], false);
          return json({'results': hits, 'answer': 'ignored'});
        }),
      );
      final hits = await search.search(SearchRequest('query', limit: 1), CancellationToken());
      expect(hits.single.title, 'Title');
      expect(hits.single.snippet, 'Snippet');
      expect(hits.single.url.toString(), 'https://example.com/article');
      expect(await checkWebSearch(ApiWebSearch(backend: backend, key: '')), ConnectionStatus.authFailed);
      final denied = ApiWebSearch(backend: backend, key: 'k', accountId: 'a', httpFactory: fake((_) => json({}, 403)));
      expect(await checkWebSearch(denied), ConnectionStatus.authFailed);
    });
  }
  test('explicit backend selection never silently falls back', () async {
    final model = service(ServiceProtocol.openai).configuration(const ServiceModel(id: 'm'));
    for (final backend in WebSearchBackend.values) {
      final search = webSearchProvider(
        settings: WebSearchSettings(backend: backend, endpoint: 'http://localhost:8888/search'),
        model: model,
        modelKey: '',
      );
      if (backend == WebSearchBackend.model) expect(await checkWebSearch(search), ConnectionStatus.unreachable);
      if (backend == WebSearchBackend.searxng) {
        expect((search as SearxngSearch).http.policy.privateEndpoint!.host, 'localhost');
      }
      if (![WebSearchBackend.model, WebSearchBackend.searxng].contains(backend)) expect(search, isA<ApiWebSearch>());
    }
    for (final protocol in [ServiceProtocol.anthropic, ServiceProtocol.openai, ServiceProtocol.gemini]) {
      final m = service(protocol, responses: true).configuration(const ServiceModel(id: 'm'));
      final p = webSearchProvider(settings: const WebSearchSettings(), model: m, modelKey: 'key');
      expect(p, protocol == ServiceProtocol.gemini ? isA<GeminiWebSearch>() : isA<ProviderWebSearch>());
    }
    final gemini = GeminiWebSearch(
      service(ServiceProtocol.gemini).configuration(const ServiceModel(id: 'm')),
      'secret',
      httpFactory: fake((r) {
        expect(jsonDecode(r.body)['tools'][0], contains('google_search'));
        return json({
          'candidates': [
            {
              'content': {'text': 'not evidence'},
              'groundingMetadata': {
                'groundingChunks': [
                  {
                    'web': {'uri': 'https://example.com', 'title': 'A'},
                  },
                  {
                    'web': {'uri': 'https://example.com', 'title': 'A'},
                  },
                  {},
                ],
              },
            },
          ],
        });
      }),
    );
    expect((await gemini.search(SearchRequest('q'), CancellationToken())).single.snippet, '');
  });
}
