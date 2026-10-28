import 'dart:async';

enum ResearchMode { offline, sources, web }

enum ResearchFailureKind {
  cancelled,
  timeout,
  budget,
  unsafeUrl,
  authentication,
  rateLimited,
  unavailable,
  network,
  toolProtocol,
  loop,
  invalidRequest,
  protocol,
  tool,
  refusal,
  unsupported,
}

/// Structured diagnostic fields; message must be bounded and redacted by the transport.
class ResearchFailure implements Exception {
  const ResearchFailure(this.kind, [this.code, this.message, this.statusCode]);
  final String? message;
  final int? statusCode;
  final ResearchFailureKind kind;
  final String? code;
  @override
  String toString() => 'ResearchFailure(${kind.name})';
}

class CancellationToken {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  void check() {
    if (isCancelled) throw const ResearchFailure(ResearchFailureKind.cancelled);
  }

  Future<T> bind<T>(Future<T> work) {
    check();
    return Future.any([work, whenCancelled.then<T>((_) => throw const ResearchFailure(ResearchFailureKind.cancelled))]);
  }
}

class ResearchBudget {
  const ResearchBudget({
    this.searches = 3,
    this.pages = 5,
    this.outputTokens = 4096,
    this.inputCharacters = 60000,
    this.responseBytes = 2097152,
    this.duration = const Duration(seconds: 90),
  });
  final int searches, pages, outputTokens, inputCharacters, responseBytes;
  final Duration duration;
  void validate() {
    if (searches < 0 ||
        pages < 0 ||
        outputTokens < 1 ||
        inputCharacters < 1 ||
        responseBytes < 1 ||
        duration <= Duration.zero) {
      throw const ResearchFailure(ResearchFailureKind.invalidRequest);
    }
  }
}

/// A caller-selected, immutable paragraph. IDs refer to an existing snapshot.
class ResearchDocument {
  const ResearchDocument({
    required this.sourceId,
    required this.version,
    required this.paragraphId,
    required this.title,
    required this.text,
  });
  final String sourceId, paragraphId, title, text;
  final int version;
}

class AiRequest {
  AiRequest({
    required this.sessionId,
    required this.requestId,
    required this.question,
    required this.mode,
    this.context = '',
    Iterable<ResearchDocument> documents = const [],
    this.budget = const ResearchBudget(),
  }) : documents = List.unmodifiable(documents);
  final String sessionId, requestId, question, context;
  final ResearchMode mode;
  final List<ResearchDocument> documents;
  final ResearchBudget budget;
}

/// Provider citation candidate, not a persisted Evidence. A URL alone is not a quote.
class ResearchCitation {
  const ResearchCitation({
    this.url,
    this.title = '',
    this.quote,
    this.sourceId,
    this.version,
    this.paragraphId,
    this.start,
    this.end,
  });
  final Uri? url;
  final String title;
  final String? quote, sourceId, paragraphId;
  final int? version, start, end;
}

enum AiEventKind { text, citation, source, toolError, usage, completed }

class AiEvent {
  const AiEvent({
    required this.sessionId,
    required this.requestId,
    required this.kind,
    this.text,
    this.citation,
    this.inputTokens,
    this.outputTokens,
  });
  final String sessionId, requestId;
  final AiEventKind kind;
  final String? text;
  final ResearchCitation? citation;
  final int? inputTokens, outputTokens;
}

abstract interface class AiProvider {
  Stream<AiEvent> generate(AiRequest request, CancellationToken cancellation);
}

class SearchRequest {
  const SearchRequest(this.query, {this.limit = 10});
  final String query;
  final int limit;
}

class SearchHit {
  const SearchHit({
    required this.url,
    required this.title,
    this.snippet = '',
    this.kind = 'web',
    this.doi,
    this.authors = const [],
    this.publishedAt,
    this.openAccess,
    this.openAccessUrl,
  });
  final Uri url;
  final String title, snippet, kind;
  final String? doi;
  final List<String> authors;
  final DateTime? publishedAt;
  final bool? openAccess;
  final Uri? openAccessUrl;
}

abstract interface class SearchProvider {
  Future<List<SearchHit>> search(SearchRequest request, CancellationToken cancellation);
}

class ExtractedContent {
  ExtractedContent({required this.url, required this.title, this.canonicalUrl, required Map<String, String> paragraphs})
    : paragraphs = Map.unmodifiable(paragraphs);
  final Uri url;
  final String title;
  final Map<String, String> paragraphs;
  final Uri? canonicalUrl;
}

abstract interface class ContentExtractor {
  Future<ExtractedContent> extract(Uri url, CancellationToken cancellation);
}

abstract interface class SecretStore {
  Future<String?> read(String account);
  Future<void> write(String account, String value);
  Future<void> delete(String account);
}

extension VerifiedSecretStore on SecretStore {
  /// A successful write alone does not guarantee the credential is readable.
  Future<void> writeVerified(String account, String value) async {
    await write(account, value);
    if (await read(account) != value) {
      throw const ResearchFailure(ResearchFailureKind.unavailable, 'secret_store');
    }
  }
}

/// Platform returns Readability HTML; Markdown and paragraph IDs belong to research.
class ReadableHtml {
  const ReadableHtml({required this.url, required this.title, required this.html, this.canonicalUrl});
  final Uri url;
  final String title, html;
  final Uri? canonicalUrl;
}

abstract interface class HtmlArticleParser {
  Future<ReadableHtml> parse(Uri url, String html, CancellationToken cancellation);
}

/// Disposable downloaded HTML, never source snapshots or evidence.
abstract interface class ResearchDocumentCache {
  Future<String?> read(Uri url);
  Future<void> write(Uri url, String html);
  Future<void> clear();
}
