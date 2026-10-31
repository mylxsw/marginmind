import 'dart:convert';

import '../content/map_generation.dart';
import '../content/models.dart';
import '../research/ports.dart';
import 'expansion.dart';
import 'proposals.dart';

enum MapLinePhase { chapter, generation, diff }

enum MapLineKind { point, add, excerpt, rename, move, remove }

/// Safe diagnostics: counts and fixed validation codes, never model/document text.
class MapGenerationFailure extends ResearchFailure {
  MapGenerationFailure(
    ResearchFailure failure, {
    required this.phase,
    required this.model,
    this.receivedLines = 0,
    this.acceptedLines = 0,
    Map<String, int> rejections = const {},
    this.stopReason,
    this.reasoningCharacters = 0,
  }) : rejections = Map.unmodifiable(rejections),
       super(failure.kind, failure.code, failure.message, failure.statusCode);
  final MapLinePhase phase;
  final String model;
  final int receivedLines, acceptedLines, reasoningCharacters;
  final Map<String, int> rejections;
  final String? stopReason;
}

/// IDs/references here are already resolved locally. Never send this to a model.
class MapLine {
  MapLine({
    required this.id,
    required this.kind,
    this.parentId,
    this.nodeId,
    this.title,
    this.source,
    this.annotationId,
    this.reason,
    this.quote,
    this.quoteSource,
    List<String> marks = const [],
    bool? kept,
  }) : marks = List.unmodifiable(marks),
       kept = kept ?? kind != MapLineKind.remove;
  final String id;
  final MapLineKind kind;
  final String? parentId, nodeId, title, annotationId, reason, quote;
  final CardSource? source, quoteSource;
  final List<String> marks;
  final bool kept;
  MapLine copyWith({bool? kept, String? title}) => MapLine(
    id: id,
    kind: kind,
    parentId: parentId,
    nodeId: nodeId,
    title: title ?? this.title,
    source: source,
    annotationId: annotationId,
    reason: reason,
    quote: quote,
    quoteSource: quoteSource,
    marks: marks,
    kept: kept ?? this.kept,
  );
  ExpansionDraft toExpansionDraft() {
    if (kind != MapLineKind.add) throw StateError('Only added topics are expansion drafts');
    return ExpansionDraft(id: id, parentRef: parentId!, title: title!, page: source?.page, kept: kept);
  }
}

/// One instance per stream. Clone for retries; prefix must be unique per call.
class MapLineContext {
  MapLineContext({
    required this.phase,
    required this.mapId,
    required this.draftPrefix,
    this.rootParentId,
    required Map<String, String> documents,
    required Map<String, Set<int>> pages,
    Map<String, String> nodes = const {},
    Map<String, String> annotations = const {},
    Set<String> protectedNodeIds = const {},
    Iterable<String> existingTitles = const [],
    this.maxDepth = 4,
    Map<String, Map<int, String>> quoteTextByPage = const {},
  }) : quoteTextByPage = Map.unmodifiable({
         for (final e in quoteTextByPage.entries) e.key: Map<int, String>.unmodifiable(e.value),
       }),
       documents = Map.unmodifiable(documents),
       pages = Map.unmodifiable({for (final e in pages.entries) e.key: Set<int>.unmodifiable(e.value)}),
       nodes = Map.unmodifiable(nodes),
       annotations = Map.unmodifiable(annotations),
       protectedNodeIds = Set.unmodifiable(protectedNodeIds),
       _initialTitles = List.unmodifiable(existingTitles),
       _titles = existingTitles.map(normalizeExpansionTitle).toSet() {
    if (mapId.isEmpty ||
        draftPrefix.isEmpty ||
        maxDepth < 1 ||
        maxDepth > 4 ||
        documents.keys.any((k) => !RegExp(r'^D[1-9][0-9]*$').hasMatch(k)) ||
        nodes.keys.any((k) => !RegExp(r'^N[1-9][0-9]*$').hasMatch(k)) ||
        annotations.keys.any((k) => !RegExp(r'^A[1-9][0-9]*$').hasMatch(k))) {
      throw ArgumentError('Invalid map line context');
    }
  }
  final Map<String, Map<int, String>> quoteTextByPage;
  final MapLinePhase phase;
  final String mapId, draftPrefix;
  final String? rootParentId;
  final Map<String, String> documents, nodes, annotations;

  /// Document aliases → pages actually included in the model's input.
  final Map<String, Set<int>> pages;
  final Set<String> protectedNodeIds;
  final int maxDepth;
  final _refs = <String, String>{}, _depths = <String, int>{};
  final _marks = <String>{};
  final List<String> _initialTitles;
  final Set<String> _titles;

  /// Validation state belongs to one attempt, including after partial failures.
  MapLineContext fresh() => MapLineContext(
    phase: phase,
    mapId: mapId,
    draftPrefix: draftPrefix,
    rootParentId: rootParentId,
    documents: documents,
    pages: pages,
    nodes: nodes,
    annotations: annotations,
    protectedNodeIds: protectedNodeIds,
    existingTitles: _initialTitles,
    maxDepth: maxDepth,
    quoteTextByPage: quoteTextByPage,
  );
  int _sequence = 0;
}

/// Complete NDJSON lines only. Invalid lines never reserve references or titles.
MapLine? parseMapLine(String line, MapLineContext ctx, {void Function(String reason)? onInvalid}) {
  MapLine? reject(String reason) {
    onInvalid?.call(reason);
    return null;
  }

  Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException {
    return reject('invalidJson');
  }
  if (decoded is! Map<String, dynamic>) return reject('invalidObject');
  final j = decoded;
  final chapter = ctx.phase == MapLinePhase.chapter;
  final diff = ctx.phase == MapLinePhase.diff;
  final op = chapter ? j['k'] : (diff ? j['op'] : (j.containsKey('mark') ? 'excerpt' : 'add'));
  final kind = switch (op) {
    'point' when chapter => MapLineKind.point,
    'add' when !chapter => MapLineKind.add,
    'excerpt' when !chapter => MapLineKind.excerpt,
    'rename' when diff => MapLineKind.rename,
    'move' when diff => MapLineKind.move,
    'remove' when diff => MapLineKind.remove,
    _ => null,
  };
  if (kind == null) return reject('invalidOperation');
  final allowed = switch (kind) {
    MapLineKind.point => {'k', 'id', 'parent', 'title', 'doc', 'page', 'marks', 'quote'},
    MapLineKind.add => {'ref', 'parent', 'title', 'doc', 'page', if (diff) 'op'},
    MapLineKind.excerpt => {'mark', 'parent', if (diff) 'op'},
    MapLineKind.rename => {'op', 'node', 'title'},
    MapLineKind.move => {'op', 'node', 'parent'},
    MapLineKind.remove => {'op', 'node', 'why'},
  };
  if (j.keys.any((k) => !allowed.contains(k))) return reject('unexpectedKeys');
  bool nonempty(Object? s) => s is String && s.trim().isNotEmpty;
  final adding = kind == MapLineKind.add || kind == MapLineKind.point;
  final ref = j[chapter ? 'id' : 'ref'];
  if (adding &&
      (ref is! String ||
          !RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]{0,63}$').hasMatch(ref) ||
          ref == 'ROOT' ||
          RegExp(r'^[DNA][0-9]+$').hasMatch(ref) ||
          ctx._refs.containsKey(ref))) {
    return reject('invalidReference');
  }
  final rawTitle = j['title'];
  String? title;
  if (adding || kind == MapLineKind.rename) {
    if (!nonempty(rawTitle)) return reject('invalidTitle');
    title = (rawTitle as String).trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalizeExpansionTitle(title).isEmpty) return reject('invalidTitle');
    if (adding && ctx._titles.contains(normalizeExpansionTitle(title))) return reject('duplicateTitle');
  }
  String? parent;
  var depth = 1;
  if (adding || kind == MapLineKind.excerpt || kind == MapLineKind.move) {
    final alias = j['parent'] ?? (chapter ? 'ROOT' : null);
    if (alias is! String) return reject('invalidParent');
    parent = alias == 'ROOT' ? (ctx.rootParentId ?? ctx.mapId) : ctx._refs[alias] ?? (diff ? ctx.nodes[alias] : null);
    if (parent == null) return reject('unknownParent');
    depth = (ctx._depths[alias] ?? 0) + 1;
    if (adding && depth > ctx.maxDepth) return reject('depthExceeded');
  }
  String? node;
  if ({MapLineKind.rename, MapLineKind.move, MapLineKind.remove}.contains(kind)) {
    final alias = j['node'];
    if (alias is! String || (node = ctx.nodes[alias]) == null) return reject('unknownNode');
    if (ctx.protectedNodeIds.contains(node)) return reject('protectedNode');
    if (kind == MapLineKind.move && parent == node) return reject('invalidParent');
  }
  final reason = j['why'];
  if (kind == MapLineKind.remove && !nonempty(reason)) return reject('missingReason');
  String? annotation;
  if (kind == MapLineKind.excerpt) {
    final mark = j['mark'];
    if (mark is! String || (annotation = ctx.annotations[mark]) == null || ctx._marks.contains(annotation)) {
      return reject('invalidAnnotation');
    }
  }
  final marks = j['marks'] ?? const [];
  if (marks is! List || marks.any((m) => m is! String || !ctx.annotations.containsKey(m))) {
    return reject('invalidAnnotation');
  }
  final page = j['page'], doc = j['doc'];
  if ((page != null && page is! int) || (doc != null && doc is! String)) return reject('invalidSource');
  final docAlias = doc ?? (ctx.documents.length == 1 ? ctx.documents.keys.single : null);
  final documentId = ctx.documents[docAlias];
  final source = documentId != null && page is int && page > 0 && (ctx.pages[docAlias]?.contains(page) ?? false)
      ? CardSource(documentId: documentId, page: page)
      : null;
  final rawQuote = j['quote'];
  final quote =
      kind == MapLineKind.point &&
          documentId != null &&
          page is int &&
          page > 0 &&
          rawQuote is String &&
          rawQuote.trim().isNotEmpty &&
          (ctx.quoteTextByPage[docAlias]?[page]?.contains(rawQuote) ?? false)
      ? rawQuote
      : null;
  final id = '${ctx.draftPrefix}${++ctx._sequence}';
  if (adding) {
    ctx._refs[ref as String] = 'new:$id';
    ctx._depths[ref] = depth;
    ctx._titles.add(normalizeExpansionTitle(title!));
  }
  if (annotation != null) ctx._marks.add(annotation);
  return MapLine(
    id: id,
    kind: kind,
    parentId: parent,
    nodeId: node,
    title: title,
    source: source,
    annotationId: annotation,
    reason: reason as String?,
    quote: quote,
    quoteSource: quote != null ? CardSource(documentId: documentId!, page: page as int) : null,
    marks: [for (final m in marks) ctx.annotations[m]!],
  );
}

MapEditProposal generationToProposal({
  required String proposalId,
  required String studySetId,
  required String mapId,
  required int baseRevision,
  required MapGeneration generation,
  required List<MapLine> lines,
  MindMap? createMap,
  List<Annotation> excerptAnnotations = const [],
}) {
  if (lines.any((l) => l.kind != MapLineKind.add && l.kind != MapLineKind.excerpt)) {
    throw ArgumentError('Generation only accepts additions');
  }
  return diffToProposal(
    proposalId: proposalId,
    studySetId: studySetId,
    mapId: mapId,
    baseRevision: baseRevision,
    generation: generation,
    lines: lines,
    createMap: createMap,
    excerptAnnotations: excerptAnnotations,
  );
}

/// Selection dependency closure and topological order; mutations still revalidate at commit.
MapEditProposal diffToProposal({
  required String proposalId,
  required String studySetId,
  required String mapId,
  required int baseRevision,
  required MapGeneration generation,
  required List<MapLine> lines,
  MindMap? createMap,
  List<Annotation> excerptAnnotations = const [],
}) {
  final byId = {for (final l in lines) l.id: l};
  if (byId.length != lines.length || lines.any((l) => l.id.isEmpty || l.id.startsWith('new:'))) {
    throw ArgumentError('Invalid line IDs');
  }
  final state = <String, bool>{}, visiting = <String>{};
  final ordered = <MapLine>[];
  bool visit(MapLine l) {
    if (state.containsKey(l.id)) return state[l.id]!;
    if (!visiting.add(l.id)) throw ArgumentError('Draft cycle');
    var keep = l.kept;
    if (l.parentId?.startsWith('new:') ?? false) {
      final parent = byId[l.parentId!.substring(4)];
      if (parent == null || parent.kind != MapLineKind.add) throw ArgumentError('Missing topic parent');
      keep = visit(parent) && keep;
    }
    visiting.remove(l.id);
    state[l.id] = keep;
    if (keep) ordered.add(l);
    return keep;
  }

  for (final l in lines) {
    visit(l);
  }
  if (ordered.isEmpty) throw ArgumentError('No selected changes');
  final ops = <MapEditOperation>[];
  for (final l in ordered) {
    final kind = switch (l.kind) {
      MapLineKind.add => MapEditKind.addTopic,
      MapLineKind.excerpt => MapEditKind.addExcerpt,
      MapLineKind.rename => MapEditKind.rename,
      MapLineKind.move => MapEditKind.move,
      MapLineKind.remove => MapEditKind.remove,
      MapLineKind.point => throw ArgumentError('Chapter point is not a map edit'),
    };
    final op = MapEditOperation(
      id: l.id,
      kind: kind,
      parentId: l.parentId,
      nodeId: l.nodeId,
      title: kind == MapEditKind.addTopic || kind == MapEditKind.rename ? l.title : null,
      source: kind == MapEditKind.addTopic ? l.source : null,
      annotationId: l.annotationId,
      reason: l.reason,
    );
    MapEditOperation.fromJson(op.toJson(), documentGeneration: true);
    ops.add(op);
  }
  return MapEditProposal.document(
    id: proposalId,
    studySetId: studySetId,
    mapId: mapId,
    baseRevision: baseRevision,
    operations: ops,
    generation: generation,
    createMap: createMap,
    excerptAnnotations: excerptAnnotations,
  );
}

class MapChapterInput {
  MapChapterInput({
    required this.chapterId,
    required this.documentAlias,
    required this.context,
    required Map<int, String> textByPage,
    Map<String, String> annotations = const {},
    this.extractQuotes = false,
    this.organization = MapOrganization.chapter,
    this.instructions,
  }) : textByPage = Map.unmodifiable(textByPage),
       annotations = Map.unmodifiable(annotations);
  final String chapterId, documentAlias;
  final MapLineContext context;
  final Map<int, String> textByPage;

  /// Annotation alias → quote and user comment, included in full by the host.
  final Map<String, String> annotations;
  final bool extractQuotes;
  final MapOrganization organization;
  final String? instructions;
}

class MapBuildInput {
  MapBuildInput({
    required this.title,
    required this.generation,
    required this.context,
    required List<MapLine> points,
    Map<String, String> existingTitles = const {},
    Map<String, String> existingParents = const {},
    this.onlyNewContent = true,
    List<String> titleConstraints = const [],
  }) : titleConstraints = List.unmodifiable(titleConstraints),
       points = List.unmodifiable(points),
       existingTitles = Map.unmodifiable(existingTitles),
       existingParents = Map.unmodifiable(existingParents);
  final String title;
  final MapGeneration generation;
  final MapLineContext context;
  final List<MapLine> points;
  final bool onlyNewContent;
  final List<String> titleConstraints;

  /// Node aliases only, ROOT denotes the virtual root.
  final Map<String, String> existingTitles, existingParents;
}

/// Caller owns concurrency (max 3 chapter calls), retries and cancellation tokens.
/// Each stream yields validated lines; failure after yields preserves those lines.
abstract interface class MapGenerator {
  Stream<MapLine> readChapter(MapChapterInput input, CancellationToken cancel);
  Stream<MapLine> generate(MapBuildInput input, CancellationToken cancel);
  Stream<MapLine> update(MapBuildInput input, CancellationToken cancel);
  Future<void> close();
}
