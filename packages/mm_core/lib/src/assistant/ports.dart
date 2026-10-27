import '../research/ports.dart';

/// Explicit visible context is the only source of read authority. An empty
/// scope authorizes nothing; auto context has exactly the same authority.
class ReadScope {
  ReadScope({
    required this.studySetId,
    Map<String, Set<int>> pages = const {},
    Set<String> documents = const {},
    Set<String> selections = const {},
    Map<String, Set<String>> branches = const {},
    Set<String> maps = const {},
  }) : pages = Map.unmodifiable(pages.map((k, v) => MapEntry(k, Set<int>.unmodifiable(v)))),
       documents = Set.unmodifiable(documents),
       selections = Set.unmodifiable(selections),
       branches = Map.unmodifiable(branches.map((k, v) => MapEntry(k, Set<String>.unmodifiable(v)))),
       maps = Set.unmodifiable(maps);
  final String studySetId;
  final Map<String, Set<int>> pages;
  final Set<String> documents, selections, maps;
  final Map<String, Set<String>> branches;
  bool allowsPage(String document, int page) =>
      page > 0 && (documents.contains(document) || (pages[document]?.contains(page) ?? false));
  bool allowsBranch(String map, String node) => maps.contains(map) || (branches[map]?.contains(node) ?? false);
}

class ReadPage {
  const ReadPage(this.documentId, this.page, this.text);
  final String documentId, text;
  final int page;
  Map<String, Object?> toJson() => {'documentId': documentId, 'page': page, 'text': text};
}

class StudySearchHit {
  const StudySearchHit({required this.title, required this.locator});
  final String title;

  /// An opaque locator, not page evidence. Readers must filter to scope.
  final String locator;
  Map<String, Object?> toJson() => {'title': title, 'locator': locator};
}

class BranchNode {
  const BranchNode({required this.id, required this.title, this.parentId, this.body = ''});
  final String id, title, body;
  final String? parentId;
  Map<String, Object?> toJson() => {'id': id, 'parentId': parentId, 'title': title, 'body': body};
}

abstract interface class StudySetReader {
  Future<List<ReadPage>> readSelection(String selectionId, ReadScope scope, CancellationToken cancel);
  Future<List<ReadPage>> readPages(String documentId, int from, int to, ReadScope scope, CancellationToken cancel);
  Future<List<StudySearchHit>> searchStudySet(String query, int limit, ReadScope scope, CancellationToken cancel);
  Future<List<BranchNode>> readBranch(String mapId, String nodeId, ReadScope scope, CancellationToken cancel);
}

/// Search results are discovery only and must never be registered as evidence.
class AssistantSearchResult {
  const AssistantSearchResult(this.title, this.url, this.summary);
  final String title, summary;
  final Uri url;
  Map<String, Object?> toJson() => {'title': title, 'url': url.toString(), 'summary': summary};
}

/// Implementations return this only after committing the immutable snapshot.
/// OpenAlex metadata uses kind=openAlex; never claim it is full text.
class AssistantSource {
  AssistantSource({
    required this.id,
    required this.version,
    required this.kind,
    required this.title,
    required this.url,
    required Map<String, String> paragraphs,
  }) : paragraphs = Map.unmodifiable(paragraphs);
  final String id, kind, title;
  final int version;
  final Uri url;
  final Map<String, String> paragraphs;
}

abstract interface class AssistantNetwork {
  Future<List<AssistantSearchResult>> search(String keywords, CancellationToken cancel);
  Future<List<AssistantSource>> papers(String keywords, CancellationToken cancel);
  Future<AssistantSource> fetch(Uri url, CancellationToken cancel);
}
