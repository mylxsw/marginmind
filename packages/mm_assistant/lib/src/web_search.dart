import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart';

import 'network.dart';
import 'providers.dart';
import 'service_catalog.dart';
import 'services.dart';

class ApiWebSearch implements SearchProvider {
  ApiWebSearch({required this.backend, required this.key, this.accountId = '', this.httpFactory = serviceHttp});
  final WebSearchBackend backend;
  final String key, accountId;
  final ServiceHttpFactory httpFactory;
  @override
  Future<List<SearchHit>> search(SearchRequest request, CancellationToken cancellation) async {
    if (key.isEmpty) throw const ResearchFailure(ResearchFailureKind.authentication);
    if (backend == WebSearchBackend.cloudflare && !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(accountId)) {
      throw const ResearchFailure(ResearchFailureKind.invalidRequest);
    }
    final limit = request.limit.clamp(1, 20);
    final url = switch (backend) {
      WebSearchBackend.cloudflare => Uri.parse(
        'https://api.cloudflare.com/client/v4/accounts/$accountId/ai/websearch/',
      ),
      WebSearchBackend.tavily => Uri.parse('https://api.tavily.com/search'),
      WebSearchBackend.brave => Uri.https('api.search.brave.com', '/res/v1/web/search', {
        'q': request.query,
        'count': '$limit',
      }),
      _ => throw const ResearchFailure(ResearchFailureKind.unavailable),
    };
    final data = await serviceJson(
      httpFactory(url, false),
      url,
      cancellation,
      method: backend == WebSearchBackend.brave ? 'GET' : 'POST',
      headers: {
        backend == WebSearchBackend.brave ? 'x-subscription-token' : 'authorization': backend == WebSearchBackend.brave
            ? key
            : 'Bearer $key',
      },
      body: switch (backend) {
        WebSearchBackend.cloudflare => {
          'query': request.query,
          'limit': limit,
          'options': {
            'gateway': {'id': 'default'},
          },
        },
        WebSearchBackend.tavily => {
          'query': request.query,
          'max_results': limit,
          'include_answer': false,
          'include_raw_content': false,
        },
        _ => null,
      },
    );
    final rows = switch (backend) {
      WebSearchBackend.cloudflare => (data['result'] ?? data)['items'],
      WebSearchBackend.tavily => data['results'],
      _ => data['web']?['results'] ?? [],
    };
    if (rows is! List) throw const ResearchFailure(ResearchFailureKind.protocol);
    try {
      return [
        for (final row in rows.take(limit))
          SearchHit(
            url: Uri.parse(row['url']),
            title: row['title'] ?? '',
            snippet: row['description'] ?? row['content'] ?? '',
          ),
      ];
    } catch (_) {
      throw const ResearchFailure(ResearchFailureKind.protocol);
    }
  }
}

class GeminiWebSearch implements SearchProvider {
  GeminiWebSearch(this.model, this.key, {this.httpFactory = serviceHttp});
  final AssistantModel model;
  final String key;
  final ServiceHttpFactory httpFactory;
  @override
  Future<List<SearchHit>> search(SearchRequest request, CancellationToken cancellation) async {
    final service = AssistantService(id: '', protocol: ServiceProtocol.gemini, name: '', endpoint: model.endpoint);
    final url = serviceEndpoint(service, 'models/${model.model}:generateContent');
    final data = await serviceJson(
      httpFactory(url, false),
      url,
      cancellation,
      method: 'POST',
      headers: {'x-goog-api-key': key},
      body: {
        'contents': [
          {
            'parts': [
              {'text': request.query},
            ],
          },
        ],
        'tools': [
          {'google_search': <String, dynamic>{}},
        ],
        'generationConfig': {'maxOutputTokens': 1024},
      },
    );
    final hits = <String, SearchHit>{};
    for (final candidate in data['candidates'] as List? ?? []) {
      for (final chunk in candidate['groundingMetadata']?['groundingChunks'] as List? ?? []) {
        final web = chunk['web'];
        if (web is Map && web['uri'] is String) {
          hits[web['uri']] = SearchHit(url: Uri.parse(web['uri']), title: web['title'] ?? '', snippet: '');
        }
      }
    }
    return hits.values.take(request.limit).toList();
  }
}

SearchProvider webSearchProvider({
  required WebSearchSettings settings,
  required AssistantModel model,
  required String modelKey,
  String key = '',
  String accountId = '',
  ServiceHttpFactory httpFactory = serviceHttp,
  ResearchHttp? searxngHttp,
  SearchProvider? nativeSearch,
}) {
  if (hasNativeWebSearch(model)) {
    // Model-backed discovery needs a parent-derived Runtime substep. Never
    // silently create an untracked provider request here.
    return nativeSearch ?? const UnavailableWebSearch();
  }
  return configuredWebSearchProvider(
    settings: settings,
    key: key,
    accountId: accountId,
    httpFactory: httpFactory,
    searxngHttp: searxngHttp,
  );
}

bool hasNativeWebSearch(AssistantModel model) => switch (model.provider) {
  AssistantProvider.claude || AssistantProvider.responses || AssistantProvider.gemini => true,
  _ => false,
};

/// The external fallback, also used to check exactly the service being edited.
SearchProvider configuredWebSearchProvider({
  required WebSearchSettings settings,
  String key = '',
  String accountId = '',
  ServiceHttpFactory httpFactory = serviceHttp,
  ResearchHttp? searxngHttp,
}) {
  switch (settings.backend) {
    case WebSearchBackend.none:
      return const UnavailableWebSearch();
    case WebSearchBackend.searxng:
      if (settings.endpoint.trim().isEmpty) return const UnavailableWebSearch();
      final endpoint = SearxngSearch.parseEndpoint(settings.endpoint);
      return SearxngSearch(
        endpoint: settings.endpoint,
        http: searxngHttp ?? AssistantNetworkHttp(policy: UrlPolicy(privateEndpoint: endpoint)),
      );
    default:
      return ApiWebSearch(backend: settings.backend, key: key, accountId: accountId, httpFactory: httpFactory);
  }
}

class UnavailableWebSearch implements SearchProvider {
  const UnavailableWebSearch();
  @override
  Future<List<SearchHit>> search(SearchRequest request, CancellationToken cancellation) async =>
      throw const ResearchFailure(ResearchFailureKind.unavailable);
}

Future<ConnectionStatus> checkWebSearch(SearchProvider provider, {CancellationToken? cancellation}) async {
  try {
    await provider.search(SearchRequest('connection test', limit: 1), cancellation ?? CancellationToken());
    return ConnectionStatus.ok;
  } on ResearchFailure catch (e) {
    if (e.kind == ResearchFailureKind.cancelled) rethrow;
    return e.kind == ResearchFailureKind.authentication ? ConnectionStatus.authFailed : ConnectionStatus.unreachable;
  } catch (_) {
    return ConnectionStatus.unreachable;
  }
}
