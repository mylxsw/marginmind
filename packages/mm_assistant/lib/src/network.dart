import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart';

import 'providers.dart';
import 'services.dart';
import 'web_search.dart';

/// A fresh instance belongs to one request. Discovery never registers evidence.
class SnapshotAssistantNetwork implements AssistantNetwork {
  SnapshotAssistantNetwork({
    required this.studySetId,
    required this.snapshots,
    required this.discovery,
    required this.paperSearch,
    required this.extractor,
    this.limits = const ResearchBudget(),
    DateTime Function()? now,
    UrlPolicy? resultPolicy,
  }) : resultPolicy = resultPolicy ?? UrlPolicy(),
       now = now ?? DateTime.now,
       counter = BudgetCounter(limits);

  final UrlPolicy resultPolicy;
  final String studySetId;
  final ResearchSnapshotRepository snapshots;
  final SearchProvider discovery, paperSearch;
  final ContentExtractor extractor;
  final ResearchBudget limits;
  final DateTime Function() now;
  final BudgetCounter counter;

  @override
  Future<List<AssistantSearchResult>> search(String keywords, CancellationToken cancel) async {
    _query(keywords, cancel);
    final deadline = DateTime.now().add(limits.duration);
    final hits = await cancel.bind(discovery.search(SearchRequest(keywords, limit: 10), cancel));
    cancel.check();
    final results = <AssistantSearchResult>[];
    for (final hit in hits.take(10)) {
      cancel.check();
      try {
        await cancel.bind(resultPolicy.validate(hit.url.removeFragment()).timeout(deadline.difference(DateTime.now())));
      } on ResearchFailure catch (error) {
        if (error.kind != ResearchFailureKind.unsafeUrl) rethrow;
        continue;
      } on SocketException {
        continue;
      } on TimeoutException {
        throw const ResearchFailure(ResearchFailureKind.timeout);
      }
      results.add(AssistantSearchResult(hit.title, hit.url, hit.snippet));
    }
    cancel.check();
    return results;
  }

  @override
  Future<List<AssistantSource>> papers(String keywords, CancellationToken cancel) async {
    _query(keywords, cancel);
    final hits = await cancel.bind(paperSearch.search(SearchRequest(keywords, limit: 10), cancel));
    final sources = <AssistantSource>[];
    for (final hit in hits.take(10)) {
      cancel.check();
      if (!_publicSyntax(hit.url)) continue;
      // Explicitly label metadata: even an abstract is never paper full text.
      final metadata = jsonEncode({
        'kind': 'OpenAlex metadata',
        'title': hit.title,
        'url': hit.url.toString(),
        'doi': hit.doi,
        'authors': hit.authors,
        'publishedAt': hit.publishedAt?.toIso8601String(),
        'abstract': hit.snippet,
        'openAccess': hit.openAccess,
        'openAccessUrl': hit.openAccessUrl?.toString(),
      });
      final content = markdownArticle(
        ReadableHtml(url: hit.url, title: hit.title, html: '<p>${const HtmlEscape().convert(metadata)}</p>'),
      );
      sources.add(await _commit(content, 'openAlex', cancel));
    }
    return sources;
  }

  @override
  Future<AssistantSource> fetch(Uri url, CancellationToken cancel) async {
    cancel.check();
    counter.page();
    UrlPolicy.syntax(url.removeFragment());
    // Extractor owns DNS pinning and redirect validation; no local exception.
    final content = await cancel.bind(extractor.extract(url, cancel));
    return _commit(content, 'snapshot', cancel);
  }

  Future<AssistantSource> _commit(ExtractedContent content, String kind, CancellationToken cancel) async {
    cancel.check();
    if (content.paragraphs.isEmpty) throw const ResearchFailure(ResearchFailureKind.protocol);
    final markdown = encodeSnapshot(content.paragraphs);
    counter.addBytes(utf8.encode(markdown).length);
    final stamp = now().toUtc();
    final file = await cancel.bind(snapshots.writeResearchSnapshot(studySetId, markdown));
    cancel.check();
    // Content-addressed snapshot identity makes each version immutable, even
    // when another conversation fetches the same URL again with different text.
    return AssistantSource(
      id: file,
      version: 1,
      kind: kind,
      title: content.title,
      url: content.url,
      paragraphs: content.paragraphs,
      fetchedAt: stamp,
      snapshotFile: file,
    );
  }

  void _query(String query, CancellationToken cancel) {
    cancel.check();
    if (query.trim().isEmpty || query.length > 200) throw const ResearchFailure(ResearchFailureKind.invalidRequest);
    counter.search();
  }

  bool _publicSyntax(Uri url) {
    try {
      UrlPolicy.syntax(url.removeFragment());
      return true;
    } on ResearchFailure {
      return false;
    }
  }
}

/// All HTTP operations in a request share raw-byte and wall-clock budgets.
class AssistantNetworkHttp extends ResearchHttp {
  AssistantNetworkHttp({
    this.limits = const ResearchBudget(),
    super.policy,
    super.clientFactory,
    BudgetCounter? sharedCounter,
    DateTime? sharedDeadline,
  }) : counter = sharedCounter ?? BudgetCounter(limits),
       deadline = sharedDeadline ?? DateTime.now().add(limits.duration),
       super(maxRetries: 0);
  final ResearchBudget limits;
  final BudgetCounter counter;
  final DateTime deadline;

  @override
  Stream<List<int>> send(
    Uri url, {
    required CancellationToken cancellation,
    ResearchBudget budget = const ResearchBudget(),
    String method = 'GET',
    Map<String, String> headers = const {},
    Object? body,
    void Function(Uri, Map<String, String>)? onResponse,
  }) async* {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero || counter.bytes >= limits.responseBytes) {
      throw const ResearchFailure(ResearchFailureKind.budget);
    }
    await for (final bytes in super.send(
      url,
      cancellation: cancellation,
      budget: ResearchBudget(
        searches: budget.searches,
        pages: budget.pages,
        outputTokens: budget.outputTokens,
        inputCharacters: budget.inputCharacters,
        duration: remaining < budget.duration ? remaining : budget.duration,
        responseBytes: limits.responseBytes - counter.bytes,
      ),
      method: method,
      headers: headers,
      body: body,
      onResponse: onResponse,
    )) {
      counter.addBytes(bytes.length);
      yield bytes;
    }
  }
}

/// Provider searches yield candidates only; generated answers and provider
/// citations are deliberately discarded. No document context is sent.
class ProviderWebSearch implements SearchProvider {
  ProviderWebSearch(this.provider);
  final AiProvider provider;
  @override
  Future<List<SearchHit>> search(SearchRequest request, CancellationToken cancellation) async {
    final hits = <String, SearchHit>{};
    await for (final event in provider.generate(
      AiRequest(
        sessionId: 'discovery',
        requestId: 'discovery',
        question: request.query,
        mode: ResearchMode.web,
        budget: const ResearchBudget(searches: 1, pages: 0, outputTokens: 1024),
      ),
      cancellation,
    )) {
      if (event.kind == AiEventKind.toolError) throw const ResearchFailure(ResearchFailureKind.tool);
      if (event.kind != AiEventKind.source) continue;
      final candidate = event.citation;
      if (candidate?.url case final url?) {
        hits[url.toString()] = SearchHit(url: url, title: candidate!.title, snippet: candidate.quote ?? '');
      }
    }
    cancellation.check();
    return hits.values.take(request.limit).toList();
  }
}

class SearxngSearch implements SearchProvider {
  SearxngSearch({required this.endpoint, required this.http});
  final String endpoint;
  final ResearchHttp http;

  /// Shared by settings validation and the request transport.
  static Uri parseEndpoint(String endpoint) {
    if (endpoint.isEmpty) throw const ResearchFailure(ResearchFailureKind.unavailable);
    try {
      final url = Uri.parse(endpoint);
      UrlPolicy.syntax(url);
      if (RegExp(r'\s|\\').hasMatch(endpoint) || url.port < 1 || url.port > 65535) {
        throw const FormatException('Invalid endpoint');
      }
      return url;
    } on FormatException {
      throw const ResearchFailure(ResearchFailureKind.unsafeUrl);
    }
  }

  @override
  Future<List<SearchHit>> search(SearchRequest request, CancellationToken cancellation) async {
    final url = parseEndpoint(endpoint);
    final bytes = await http
        .send(
          url.replace(queryParameters: {...url.queryParameters, 'q': request.query, 'format': 'json'}),
          cancellation: cancellation,
          headers: {'accept': 'application/json'},
        )
        .expand((b) => b)
        .toList();
    try {
      final results = (jsonDecode(utf8.decode(bytes)) as Map)['results'] as List;
      return [
        for (final raw in results.take(request.limit))
          SearchHit(
            url: Uri.parse(raw['url'] as String),
            title: raw['title'] as String? ?? '',
            snippet: raw['content'] as String? ?? '',
          ),
      ];
    } catch (_) {
      throw const ResearchFailure(ResearchFailureKind.protocol);
    }
  }
}

/// Provider API credentials are used only by the provider search transport;
/// webpages and OpenAlex share a public-only transport. SearXNG has an
/// isolated exception for its explicitly configured origin.
AssistantNetwork productionAssistantNetwork({
  required String studySetId,
  required ResearchSnapshotRepository snapshots,
  required HtmlArticleParser parser,
  required AssistantModel model,
  required String key,
  String searxngEndpoint = '',
  WebSearchSettings? searchSettings,
  String searchKey = '',
  String searchAccountId = '',
  ResearchDocumentCache? cache,
}) {
  final http = AssistantNetworkHttp();
  final endpoint = Uri.parse(model.endpoint);
  final providerHttp = AssistantNetworkHttp(
    policy: UrlPolicy(providerEndpoint: endpoint),
    sharedCounter: http.counter,
    sharedDeadline: http.deadline,
  );
  final SearchProvider discovery = searchSettings != null
      ? webSearchProvider(
          settings: searchSettings,
          searxngHttp: searchSettings.backend == WebSearchBackend.searxng
              ? AssistantNetworkHttp(
                  policy: UrlPolicy(privateEndpoint: SearxngSearch.parseEndpoint(searchSettings.endpoint)),
                  sharedCounter: http.counter,
                  sharedDeadline: http.deadline,
                )
              : null,
          model: model,
          modelKey: key,
          key: searchKey,
          accountId: searchAccountId,
          httpFactory: (url, local) => AssistantNetworkHttp(
            policy: UrlPolicy(providerEndpoint: url),
            sharedCounter: http.counter,
            sharedDeadline: http.deadline,
          ),
        )
      : switch (model.provider) {
          AssistantProvider.claude => ProviderWebSearch(
            AnthropicProvider(apiKey: key, model: model.model, endpoint: endpoint, http: providerHttp),
          ),
          AssistantProvider.responses => ProviderWebSearch(
            OpenAiResponsesProvider(apiKey: key, model: model.model, endpoint: endpoint, http: providerHttp),
          ),
          _ => SearxngSearch(
            endpoint: searxngEndpoint,
            http: AssistantNetworkHttp(
              policy: UrlPolicy(
                privateEndpoint: searxngEndpoint.isEmpty ? null : SearxngSearch.parseEndpoint(searxngEndpoint),
              ),
              sharedCounter: http.counter,
              sharedDeadline: http.deadline,
            ),
          ),
        };
  return SnapshotAssistantNetwork(
    studySetId: studySetId,
    snapshots: snapshots,
    discovery: discovery,
    paperSearch: OpenAlexSearch(http: http),
    extractor: MarkdownArticleExtractor(parser: parser, http: http, cache: cache),
  );
}
