import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart';
import 'package:test/test.dart';

import 'support.dart';

final url = Uri.parse('https://example.org/article');
Matcher fails(ResearchFailureKind kind) => isA<ResearchFailure>().having((e) => e.kind, 'kind', kind);

class Snapshots implements ResearchSnapshotRepository {
  final files = <String, String>{};
  bool fail = false;
  Completer<void>? hold;
  @override
  Future<String> writeResearchSnapshot(String studySetId, String markdown) async {
    await hold?.future;
    if (fail) throw StateError('disk');
    final file = 'research/snapshots/${markdown.hashCode}.md';
    files[file] = markdown;
    return file;
  }

  @override
  Future<String> readResearchSnapshot(String studySetId, String fileName) async => files[fileName]!;
}

class Search implements SearchProvider {
  List<SearchHit> hits = [SearchHit(url: url, title: 'Found', snippet: 'Abstract')];
  @override
  Future<List<SearchHit>> search(SearchRequest request, CancellationToken cancellation) async {
    expect(request.limit, 10);
    return hits;
  }
}

class Extractor implements ContentExtractor {
  Map<String, String>? paragraphs;
  @override
  Future<ExtractedContent> extract(Uri url, CancellationToken cancellation) async => paragraphs == null
      ? markdownArticle(ReadableHtml(url: url, title: 'Captured title', html: '<p>Real paragraph</p><p>Second</p>'))
      : ExtractedContent(url: url, title: '', paragraphs: paragraphs!);
}

class Parser implements HtmlArticleParser {
  @override
  Future<ReadableHtml> parse(Uri url, String html, CancellationToken cancellation) async =>
      ReadableHtml(url: url, title: 'Title', html: html);
}

class Provider implements AiProvider {
  Provider(this.events);
  final List<AiEvent> events;
  @override
  Stream<AiEvent> generate(AiRequest request, CancellationToken cancellation) async* {
    expect(request.context, isEmpty);
    expect(request.documents, isEmpty);
    expect(request.budget.pages, 0);
    yield* Stream.fromIterable(events);
  }
}

AiEvent event(AiEventKind kind, {ResearchCitation? citation}) =>
    AiEvent(sessionId: 's', requestId: 'r', kind: kind, text: 'Discard me', citation: citation);

void main() {
  late Snapshots snapshots;
  late Search search;
  late Extractor extractor;
  SnapshotAssistantNetwork network({ResearchBudget limits = const ResearchBudget()}) => SnapshotAssistantNetwork(
    studySetId: 'set',
    resultPolicy: UrlPolicy(lookup: (_) async => [InternetAddress('8.8.8.8')]),
    snapshots: snapshots,
    discovery: search,
    paperSearch: search,
    extractor: extractor,
    limits: limits,
    now: () => DateTime.utc(2026, 10, 27),
  );
  setUp(() {
    snapshots = Snapshots();
    search = Search();
    extractor = Extractor();
  });

  test('search discovers only; fetch commits the exact paragraphs before a citation exists', () async {
    final n = network();
    final registry = CitationRegistry(online: true);
    final tools = AssistantTools(
      reader: Reader(),
      scope: ReadScope(studySetId: 'set'),
      cancel: CancellationToken(),
      citations: registry,
      budget: RunBudget(),
      network: n,
    );
    expect(await tools.execute('web_search', {'query': 'keywords'}), isNotEmpty);
    expect(registry.items, isEmpty);
    expect(snapshots.files, isEmpty);
    expect(registry.clean('claim [source:1]'), 'claim ');
    snapshots.hold = Completer<void>();
    final fetched = tools.execute('fetch_source', {'url': url.toString()});
    await Future<void>.delayed(Duration.zero);
    expect(registry.items, isEmpty);
    snapshots.hold!.complete();
    final firstPage = await fetched as Map;
    expect(registry.items, hasLength(1));
    expect(firstPage['complete'], false);
    await tools.execute('read_more', {'cursor': firstPage['nextCursor']});
    expect(registry.items, hasLength(2));
    final c = registry.items.first;
    expect(c.title, 'Captured title');
    expect(c.fetchedAt, DateTime.utc(2026, 10, 27));
    expect(snapshotParagraphs(snapshots.files[c.snapshotFile]!)[c.paragraphId], c.quote);
    expect(Citation.fromJson(c.toJson()).snapshotFile, c.snapshotFile);
    expect(Citation.fromJson(c.toJson()).fetchedAt, c.fetchedAt);
    expect(registry.clean('claim [source:1] [source:90]'), 'claim [source:1] ');
    expect(CitationRegistry(online: true).clean('[source:1]'), '');
  });
  test('OpenAlex persists explicitly labeled metadata and never claims full text', () async {
    final n = network();
    final sources = await n.papers('keywords', CancellationToken());
    final source = sources.single;
    expect(source.kind, 'openAlex');
    expect(source.paragraphs.values.single, contains('OpenAlex metadata'));
    expect(source.paragraphs.values.single, contains('Abstract'));
    expect(snapshots.files[source.snapshotFile], encodeSnapshot(source.paragraphs));
    expect(CitationRegistry(online: true).source(source), hasLength(1));
  });
  test('failed commits, cancellation and empty extraction cannot become evidence', () async {
    snapshots.fail = true;
    final registry = CitationRegistry(online: true);
    final tools = AssistantTools(
      reader: Reader(),
      scope: ReadScope(studySetId: 'set'),
      cancel: CancellationToken(),
      citations: registry,
      budget: RunBudget(),
      network: network(),
    );
    await expectLater(tools.execute('fetch_source', {'url': url.toString()}), throwsStateError);
    expect(registry.items, isEmpty);
    snapshots.fail = false;
    extractor.paragraphs = {};
    await expectLater(network().fetch(url, CancellationToken()), throwsA(fails(ResearchFailureKind.protocol)));
    final token = CancellationToken()..cancel();
    await expectLater(network().search('query', token), throwsA(fails(ResearchFailureKind.cancelled)));
    snapshots.hold = Completer<void>();
    extractor.paragraphs = null;
    final cancel = CancellationToken();
    final pending = network().fetch(url, cancel);
    await Future<void>.delayed(Duration.zero);
    cancel.cancel();
    await expectLater(pending, throwsA(fails(ResearchFailureKind.cancelled)));
    snapshots.hold!.complete();
  });
  test('queries, URL syntax, discovery filtering, search/page/byte budgets are enforced', () async {
    for (final q in ['', 'x' * 201]) {
      await expectLater(network().search(q, CancellationToken()), throwsA(fails(ResearchFailureKind.invalidRequest)));
    }
    search.hits = [SearchHit(url: Uri.parse('file:///private'), title: 'bad'), ...search.hits];
    expect(await network().search('q', CancellationToken()), hasLength(1));
    expect(await network().papers('q', CancellationToken()), hasLength(1));
    final n = network(limits: const ResearchBudget(searches: 1, pages: 1));
    await n.search('q', CancellationToken());
    await expectLater(n.papers('q', CancellationToken()), throwsA(fails(ResearchFailureKind.budget)));
    await n.fetch(url, CancellationToken());
    await expectLater(n.fetch(url, CancellationToken()), throwsA(fails(ResearchFailureKind.budget)));
    await expectLater(
      network().fetch(Uri.parse('file:///private'), CancellationToken()),
      throwsA(fails(ResearchFailureKind.unsafeUrl)),
    );
    await expectLater(
      network(limits: const ResearchBudget(responseBytes: 1)).fetch(url, CancellationToken()),
      throwsA(fails(ResearchFailureKind.budget)),
    );
  });
  test('provider search drops answers and citations, deduplicates actual discovery results', () async {
    final candidate = ResearchCitation(url: url, title: 'Source', quote: 'Summary');
    final p = ProviderWebSearch(
      Provider([
        event(AiEventKind.text),
        event(AiEventKind.citation, citation: candidate),
        event(AiEventKind.source),
        event(AiEventKind.source, citation: candidate),
        event(AiEventKind.source, citation: candidate),
        event(AiEventKind.completed),
      ]),
    );
    final hits = await p.search(const SearchRequest('q'), CancellationToken());
    expect(hits, hasLength(1));
    expect(hits.single.snippet, 'Summary');
    await expectLater(
      ProviderWebSearch(Provider([event(AiEventKind.toolError)])).search(const SearchRequest('q'), CancellationToken()),
      throwsA(fails(ResearchFailureKind.tool)),
    );
    await expectLater(
      p.search(const SearchRequest('q'), CancellationToken()..cancel()),
      throwsA(fails(ResearchFailureKind.cancelled)),
    );
  });
  test('SearXNG uses JSON discovery only; missing/unsafe/malformed services fail explicitly', () async {
    final transport = ResearchHttp(
      policy: UrlPolicy(lookup: (_) async => [InternetAddress('8.8.8.8')]),
      clientFactory: () => MockClient((request) async {
        expect(request.url.queryParameters, {'q': 'q', 'format': 'json', 'language': 'en'});
        return http.Response(
          jsonEncode({
            'results': [
              {'url': url.toString(), 'title': 'Title', 'content': 'Snippet'},
            ],
          }),
          200,
        );
      }),
    );
    final s = SearxngSearch(endpoint: 'https://search.example/search?language=en', http: transport);
    expect((await s.search(const SearchRequest('q'), CancellationToken())).single.snippet, 'Snippet');
    await expectLater(
      SearxngSearch(endpoint: '', http: transport).search(const SearchRequest('q'), CancellationToken()),
      throwsA(fails(ResearchFailureKind.unavailable)),
    );
    await expectLater(
      SearxngSearch(
        endpoint: 'http://127.0.0.1/search',
        http: transport,
      ).search(const SearchRequest('q'), CancellationToken()),
      throwsA(fails(ResearchFailureKind.unsafeUrl)),
    );
    final bad = ResearchHttp(
      policy: UrlPolicy(lookup: (_) async => [InternetAddress('8.8.8.8')]),
      clientFactory: () => MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(
      SearxngSearch(
        endpoint: 'https://search.example/search',
        http: bad,
      ).search(const SearchRequest('q'), CancellationToken()),
      throwsA(fails(ResearchFailureKind.protocol)),
    );
  });
  test('raw HTTP bytes and deadline are shared by provider and public transports', () async {
    final policy = UrlPolicy(lookup: (_) async => [InternetAddress('8.8.8.8')]);
    final limits = const ResearchBudget(responseBytes: 4);
    final transport = AssistantNetworkHttp(
      limits: limits,
      policy: policy,
      clientFactory: () => MockClient((_) async => http.Response('ab', 200)),
    );
    expect(await transport.send(url, cancellation: CancellationToken()).expand((b) => b).toList(), [97, 98]);
    final other = AssistantNetworkHttp(
      limits: limits,
      policy: policy,
      sharedCounter: transport.counter,
      sharedDeadline: transport.deadline,
      clientFactory: () => MockClient((_) async => http.Response('cd', 200)),
    );
    await other.send(url, cancellation: CancellationToken()).drain<void>();
    await expectLater(
      transport.send(url, cancellation: CancellationToken()).drain<void>(),
      throwsA(fails(ResearchFailureKind.budget)),
    );
    final expired = AssistantNetworkHttp(sharedDeadline: DateTime(2000));
    await expectLater(
      expired.send(url, cancellation: CancellationToken()).drain<void>(),
      throwsA(fails(ResearchFailureKind.budget)),
    );
  });
  test('production chooses native search or the configured fallback', () async {
    for (final p in AssistantProvider.values) {
      final n = productionAssistantNetwork(
        studySetId: 'set',
        snapshots: snapshots,
        parser: Parser(),
        model: AssistantModel(provider: p, model: 'm', endpoint: 'https://example.org/v1/responses'),
        key: 'test',
      ) as SnapshotAssistantNetwork;
      expect(n.discovery, isA<UnavailableWebSearch>());
      expect(n.paperSearch, isA<OpenAlexSearch>());
      expect(n.extractor, isA<MarkdownArticleExtractor>());
    }
  });
}
