import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'map_quote.dart';

import '../../app/providers.dart';
import '../assistant/map_task_factory.dart';
import '../assistant/assistant_controller.dart';
import '../assistant/assistant_reader.dart';
import '../assistant/assistant_scope.dart';
import '../assistant/assistant_writes.dart';
import '../assistant/expansion_controller.dart';
import '../assistant/map_generation_cache.dart';
import '../assistant/map_generation_context.dart';
import '../workspace/workspace_controller.dart';
import '../workspace/reflow_document.dart';
import '../workspace/reader_ocr.dart';

enum MapGenerationDestination { newMap, branch, update }

class MapDocumentSelection {
  const MapDocumentSelection({required this.documentId, this.chapters = const []});
  final String documentId;
  final List<String> chapters;

  Map<String, Object?> toJson() => {'documentId': documentId, 'chapters': chapters};
}

class MapGenerationRequest {
  const MapGenerationRequest({
    required this.studySetId,
    required this.mapId,
    required this.title,
    required this.sources,
    this.organization = MapOrganization.chapter,
    this.depth = 3,
    this.instructions,
    this.includeAnnotations = true,
    this.extractQuotes = false,
    this.destination = MapGenerationDestination.newMap,
    this.parentId,
    this.onlyNewContent = true,
    this.round = 0,
  });

  final String studySetId;
  final String mapId;
  final String title;
  final List<MapDocumentSelection> sources;
  final MapOrganization organization;
  final int depth;
  final String? instructions;
  final bool includeAnnotations;
  final bool extractQuotes;
  final MapGenerationDestination destination;
  final String? parentId;
  final bool onlyNewContent;
  final int round;

  MapGenerationRequest copyWith({
    String? title,
    List<MapDocumentSelection>? sources,
    MapOrganization? organization,
    int? depth,
    String? instructions,
    bool? includeAnnotations,
    bool? extractQuotes,
    MapGenerationDestination? destination,
    String? parentId,
    bool? onlyNewContent,
    int? round,
  }) => MapGenerationRequest(
    studySetId: studySetId,
    mapId: mapId,
    title: title ?? this.title,
    sources: sources ?? this.sources,
    organization: organization ?? this.organization,
    depth: depth ?? this.depth,
    instructions: instructions ?? this.instructions,
    includeAnnotations: includeAnnotations ?? this.includeAnnotations,
    extractQuotes: extractQuotes ?? this.extractQuotes,
    destination: destination ?? this.destination,
    parentId: parentId ?? this.parentId,
    onlyNewContent: onlyNewContent ?? this.onlyNewContent,
    round: round ?? this.round,
  );
}

enum MapChapterStatus { pending, reading, done, failed }

enum MapGenerationPhase { reading, streaming, review, kept, discarded, failed, stopped, update, diff, applied }

class MapSkeletonItem {
  const MapSkeletonItem({required this.id, required this.title, this.isCurrent = false, this.isDone = false});

  final String id;
  final String title;
  final bool isCurrent;
  final bool isDone;

  MapSkeletonItem copyWith({bool? isCurrent, bool? isDone}) =>
      MapSkeletonItem(id: id, title: title, isCurrent: isCurrent ?? this.isCurrent, isDone: isDone ?? this.isDone);
}

class MapGenerationPreview {
  MapGenerationPreview({
    required this.request,
    required this.baseRevision,
    required this.proposalId,
    required this.generation,
    this.phase = MapGenerationPhase.reading,
    this.lines = const [],
    this.chapterProgress = const {},
    this.chapterFailures = const {},
    this.skeletons = const [],
    this.currentChapterIndex = 0,
    this.round = 0,
    this.isApplying = false,
    this.failure,
    this.editedTitles = const {},
    this.needsTextDocumentId,
  });

  final String? needsTextDocumentId;
  final MapGenerationRequest request;
  final int baseRevision;
  final String proposalId;
  final MapGeneration generation;
  final MapGenerationPhase phase;
  final List<MapLine> lines;
  final Map<String, MapChapterStatus> chapterProgress;
  final Map<String, ResearchFailure> chapterFailures;
  final List<MapSkeletonItem> skeletons;
  final int currentChapterIndex;
  final int round;
  final bool isApplying;
  final ResearchFailure? failure;
  final Map<String, String> editedTitles;

  List<ExpansionDraft> get drafts => [
    for (final l in lines)
      if (l.kind == MapLineKind.add) l.toExpansionDraft(),
  ];

  ExpansionPreview? toExpansionPreview({StudySetContent? content}) {
    final targetId = request.destination == MapGenerationDestination.newMap
        ? request.mapId
        : (request.parentId ?? request.mapId);
    if (phase == MapGenerationPhase.reading) {
      return ExpansionPreview(
        request: ExpansionRequest(
          studySetId: request.studySetId,
          mapId: request.mapId,
          targetIds: [targetId],
          scope: ExpansionScope.map,
        ),
        baseRevision: baseRevision,
        proposalId: proposalId,
        phase: ExpansionPhase.generating,
        drafts: [for (final s in skeletons) ExpansionDraft(id: s.id, parentRef: targetId, title: s.title)],
      );
    }
    if (phase == MapGenerationPhase.streaming ||
        phase == MapGenerationPhase.review ||
        phase == MapGenerationPhase.diff ||
        phase == MapGenerationPhase.stopped) {
      return ExpansionPreview(
        request: ExpansionRequest(
          studySetId: request.studySetId,
          mapId: request.mapId,
          targetIds: [targetId],
          scope: ExpansionScope.map,
        ),
        baseRevision: baseRevision,
        proposalId: proposalId,
        phase: phase == MapGenerationPhase.streaming ? ExpansionPhase.generating : ExpansionPhase.review,
        drafts: [
          ...drafts,
          if (content != null)
            for (final line in lines.where((l) => l.kind == MapLineKind.excerpt))
              ExpansionDraft(
                id: line.id,
                parentRef: line.parentId!,
                kept: line.kept,
                title: expansionTitle(line.title ?? content.annotation(line.annotationId!)?.quote ?? ''),
                page: line.source?.page,
              ),
        ],
        failure: failure,
        isApplying: isApplying,
      );
    }
    return null;
  }

  int get selectedCount => lines.where((l) => l.kept).length;
  int get topicCount => lines.where((l) => l.kind == MapLineKind.add).length;

  String? get failedChapterTitle {
    final failedId = chapterFailures.keys.firstOrNull;
    if (failedId == null) return null;
    return skeletons.where((s) => s.id == failedId).firstOrNull?.title ?? failedId;
  }

  MapGenerationPreview copyWith({
    MapGenerationPhase? phase,
    List<MapLine>? lines,
    Map<String, MapChapterStatus>? chapterProgress,
    Map<String, ResearchFailure>? chapterFailures,
    List<MapSkeletonItem>? skeletons,
    int? currentChapterIndex,
    int? round,
    bool? isApplying,
    ResearchFailure? failure,
    Map<String, String>? editedTitles,
  }) => MapGenerationPreview(
    request: request,
    baseRevision: baseRevision,
    proposalId: proposalId,
    generation: generation,
    phase: phase ?? this.phase,
    lines: lines ?? this.lines,
    chapterProgress: chapterProgress ?? this.chapterProgress,
    chapterFailures: chapterFailures ?? this.chapterFailures,
    skeletons: skeletons ?? this.skeletons,
    currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
    round: round ?? this.round,
    isApplying: isApplying ?? this.isApplying,
    failure:
        failure ?? (phase == MapGenerationPhase.streaming || phase == MapGenerationPhase.reading ? null : this.failure),
    editedTitles: editedTitles ?? this.editedTitles,
    needsTextDocumentId: needsTextDocumentId,
  );
}

final mapDocumentOutlineProvider = FutureProvider.family<List<PdfOutlineEntry>, (String, String)>((ref, key) async {
  final (studySetId, documentId) = key;
  final content =
      ref.watch(workspaceContentProvider(studySetId)) ?? ref.read(workspaceProvider(studySetId).notifier).content;
  final saved = content.outlineOn(documentId);
  if (saved != null) return OutlineTree.flatten(saved.items).toList();
  final doc = content.document(documentId);
  if (doc == null) return [];
  try {
    if (doc.contentManifest != null) {
      final repo = ref.read(contentRepositoryProvider);
      if (repo is! DocumentRepository) return [];
      final book = await ReflowDocument.load(repo as DocumentRepository, studySetId, doc);
      PdfOutlineEntry convert(String id) {
        final entry = book.outline.firstWhere((e) => e.id == id);
        return PdfOutlineEntry(
          id: entry.id,
          title: entry.title,
          position: book.position(entry.chapterId, entry.offset),
          children: [for (final child in entry.children) convert(child.id)],
        );
      }

      return OutlineTree.flatten([for (final entry in book.toc) convert(entry.id)]).toList();
    }
    if (!ref.read(pdfRenderingEnabledProvider)) return [];
    final workspace = ref.read(workspaceProvider(studySetId).notifier);
    return OutlineTree.flatten((await MMPdfEngine.outline(workspace.filePath(doc), doc.id)).items).toList();
  } catch (_) {
    return [];
  }
}, dependencies: [workspaceContentProvider, workspaceProvider]);

final documentDigestBuilderProvider = Provider.family<DocumentDigestBuilder, String>((ref, studySetId) {
  final workspace = ref.read(workspaceProvider(studySetId).notifier);
  final repo = ref.read(contentRepositoryProvider);
  final reader = WorkspaceReader(
    content: () => workspace.content,
    contexts: const [],
    filePath: workspace.filePath,
    pageText: (path, page) async {
      if (ref.read(pdfOcrServiceProvider).supported) await ref.read(readerOcrProvider(path).notifier).inspect();
      final recognized = ref.read(readerOcrProvider(path)).document?.path ?? path;
      return ref.read(assistantPageTextProvider)(recognized, page);
    },
  );
  return DocumentDigestBuilder(
    reader,
    repository: repo is DocumentRepository ? repo as DocumentRepository : null,
    loadOutline: (doc, cancel) async {
      if (!ref.read(pdfRenderingEnabledProvider)) return null;
      try {
        return await cancel.bind(MMPdfEngine.outline(workspace.filePath(doc), doc.id));
      } on ResearchFailure {
        rethrow;
      } catch (_) {
        return null;
      }
    },
  );
}, dependencies: [workspaceProvider]);

final mapQuotePageProvider = Provider<Future<TranslationPage?> Function(String, int)>((ref) => MMPdfEngine.quotePage);

// Optional injection; there is no legacy model fallback in production.
final mapGeneratorProvider = Provider<Future<MapGenerator> Function()?>((ref) => null);

final mapGenerationControllerProvider = NotifierProvider.autoDispose
    .family<MapGenerationController, MapGenerationPreview?, String>(
      MapGenerationController.new,
      dependencies: [assistantMapEditExecutorProvider, documentDigestBuilderProvider, workspaceProvider],
    );

class _ChapterTask {
  _ChapterTask({
    required this.id,
    required this.title,
    required this.pages,
    required this.input,
    required this.fingerprint,
    required this.source,
  });
  final String id;
  final String title;
  final Set<int> pages;
  final MapChapterInput input;
  final String fingerprint;
  final MapSource source;
}

class MapGenerationController extends Notifier<MapGenerationPreview?> {
  MapGenerationController(this.arg);
  final String arg;

  ProviderSubscription<ReaderOcrState>? _ocrSubscription;
  CancellationToken? _cancel;
  MapGenerator? _generator;
  String _cacheModelKey = '';
  MapTaskSession? _taskSession;
  int _generation = 0;
  bool _disposed = false;
  bool _ownsBusy = false;
  final List<Annotation> _excerptAnnotations = [];
  final List<MapLine> _collectedPoints = [];
  final Map<String, _ChapterTask> _tasks = {};
  Map<String, MapChapterInput> get chapterInputs => {for (final e in _tasks.entries) e.key: e.value.input};

  @override
  MapGenerationPreview? build() {
    final workspace = ref.read(workspaceProvider(arg).notifier);
    final busy = ref.read(expansionBusyProvider.notifier);

    listenSelf((_, next) => workspace.expansionPreviewActive = next != null);

    ref.onDispose(() {
      _disposed = true;
      _ocrSubscription?.close();
      workspace.expansionPreviewActive = false;
      if (_ownsBusy) {
        Future.microtask(() {
          if (busy.ref.mounted) busy.set(false);
        });
      }
      _cancel?.cancel();
      _generator?.close();
    });

    return null;
  }

  Future<void> start(MapGenerationRequest request) async {
    if ((state != null && state!.phase != MapGenerationPhase.failed) ||
        ref.read(assistantControllerProvider.notifier).busy ||
        ref.read(expansionBusyProvider)) {
      throw StateError('Assistant is busy');
    }
    state = null;
    _ocrSubscription?.close();
    _ocrSubscription = null;
    _cancel?.cancel();
    _generator?.close();
    _excerptAnnotations.clear();
    _collectedPoints.clear();
    _tasks.clear();

    final workspace = ref.read(workspaceProvider(arg).notifier);
    final snapshot = workspace.content;
    final proposalId = 'map-gen-${DateTime.now().microsecondsSinceEpoch}';

    final builder = ref.read(documentDigestBuilderProvider(arg));
    final cancel = _cancel = CancellationToken();

    final pendingSources = [
      for (final selection in request.sources)
        MapSource(
          documentId: selection.documentId,
          chapters: selection.chapters,
          fingerprint: 'pending',
          readThrough: snapshot.document(selection.documentId)?.lastPage ?? 1,
        ),
    ];
    if (pendingSources.isEmpty) throw ArgumentError('No source documents');
    final preparationEpoch = ++_generation;
    _ownsBusy = true;
    ref.read(expansionBusyProvider.notifier).set(true);
    state = MapGenerationPreview(
      request: request,
      baseRevision: assistantMapRevision(snapshot, request.mapId),
      proposalId: proposalId,
      generation: MapGeneration(
        sources: pendingSources,
        organization: request.organization,
        depth: request.depth,
        instructions: request.instructions,
        generatedAt: DateTime.now().toUtc(),
      ),
    );

    final skeletons = <MapSkeletonItem>[];
    final chapterProgress = <String, MapChapterStatus>{};
    final sources = <MapSource>[];

    try {
      for (final (docIndex, sel) in request.sources.indexed) {
        cancel.check();
        final doc = snapshot.document(sel.documentId);
        if (doc == null) continue;
        final docAlias = 'D${docIndex + 1}';
        final draftPrefix = '$proposalId-$docAlias-';

        final digest = await builder.build(
          snapshot,
          studySetId: request.studySetId,
          documentId: sel.documentId,
          mapId: request.mapId,
          draftPrefix: draftPrefix,
          documentAlias: docAlias,
          chapters: sel.chapters,
          includeAnnotations: request.includeAnnotations,
          extractQuotes: request.extractQuotes,
          organization: request.organization,
          instructions: request.instructions,
          cancellation: cancel,
        );

        if (_disposed || preparationEpoch != _generation) return;
        sources.add(digest.source);

        final outline = snapshot.outlineOn(doc.id);
        final outlineEntries = outline != null ? OutlineTree.flatten(outline.items) : <PdfOutlineEntry>[];

        for (final ch in digest.chapters) {
          final input = ch.input;
          final chId = input.chapterId;
          final parts = chId.split(':');
          final rangeId = parts.length > 1 ? parts[1] : '';
          final partIndex = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;

          String title;
          if (rangeId == 'preface') {
            title = '前言';
          } else if (rangeId.startsWith('page-')) {
            title = digest.chapters.length == 1 ? doc.title : '第 ${rangeId.substring(5)} 页';
          } else {
            final entry = outlineEntries.where((e) => e.id == rangeId).firstOrNull;
            title = entry?.title ?? (digest.chapters.length == 1 ? doc.title : rangeId);
          }
          if (partIndex > 0) {
            title = '$title ($partIndex)';
          }

          skeletons.add(MapSkeletonItem(id: chId, title: title));
          chapterProgress[chId] = MapChapterStatus.pending;
          _tasks[chId] = _ChapterTask(
            id: chId,
            title: title,
            pages: input.textByPage.keys.toSet(),
            input: input,
            fingerprint: ch.fingerprint,
            source: digest.source,
          );
        }
      }
    } on MapDigestNeedsText catch (e) {
      if (_disposed || preparationEpoch != _generation) return;
      state = MapGenerationPreview(
        request: request,
        baseRevision: assistantMapRevision(snapshot, request.mapId),
        proposalId: proposalId,
        generation: MapGeneration(
          sources: pendingSources,
          organization: request.organization,
          depth: request.depth,
          instructions: request.instructions,
          generatedAt: DateTime.now().toUtc(),
        ),
        phase: MapGenerationPhase.failed,
        needsTextDocumentId: e.documentId,
        failure: const ResearchFailure(ResearchFailureKind.protocol, '需先识别文字'),
      );
      final doc = snapshot.document(e.documentId)!;
      _ocrSubscription = ref.listen(readerOcrProvider(workspace.filePath(doc)), (before, after) {
        if (before?.running == true &&
            !after.running &&
            !after.failed &&
            !after.cancelled &&
            after.revision > (before?.revision ?? 0)) {
          Future.microtask(() {
            if (!_disposed && preparationEpoch == _generation && state?.needsTextDocumentId == e.documentId) retry();
          });
        }
      });
      return;
    } catch (e) {
      if (_disposed || preparationEpoch != _generation) return;
      _ownsBusy = false;
      ref.read(expansionBusyProvider.notifier).set(false);
      final failure = e is ResearchFailure ? e : const ResearchFailure(ResearchFailureKind.unavailable);
      state = MapGenerationPreview(
        request: request,
        baseRevision: assistantMapRevision(snapshot, request.mapId),
        proposalId: proposalId,
        generation: MapGeneration(
          sources: pendingSources,
          organization: request.organization,
          depth: request.depth,
          instructions: request.instructions,
          generatedAt: DateTime.now().toUtc(),
        ),
        phase: MapGenerationPhase.failed,
        failure: failure,
      );
      return;
    }

    if (_disposed || preparationEpoch != _generation) return;
    final generation = MapGeneration(
      sources: sources,
      organization: request.organization,
      depth: request.depth,
      instructions: request.instructions,
      generatedAt: DateTime.now().toUtc(),
    );

    state = MapGenerationPreview(
      request: request,
      baseRevision: assistantMapRevision(snapshot, request.mapId),
      proposalId: proposalId,
      generation: generation,
      phase: MapGenerationPhase.reading,
      skeletons: List.unmodifiable(skeletons),
      chapterProgress: Map.unmodifiable(chapterProgress),
    );

    await _runGeneration(request);
  }

  Future<void> _runGeneration(MapGenerationRequest request) async {
    final epoch = ++_generation;
    final cancel = _cancel = CancellationToken();
    _ownsBusy = true;
    ref.read(expansionBusyProvider.notifier).set(true);

    try {
      final injected = ref.read(mapGeneratorProvider);
      final MapGenerator generator;
      if (injected != null) {
        generator = await injected();
        _cacheModelKey = 'injected-map-engine';
        _taskSession = null;
      } else {
        final session = _taskSession = MapTaskSession(ref, request.studySetId, mapGenerateSpec);
        _cacheModelKey = await session.cacheIdentity();
        generator = ModelMapGenerator.runtime(session.execute);
      }
      _generator = generator;
      cancel.check();
      final cache = ref.read(mapDigestCacheProvider(request.studySetId));
      final modelKey = _cacheModelKey;

      // Phase 1: Read chapters concurrently (up to 3)
      final taskQueue = _tasks.values.toList();
      var queueIndex = 0;
      final failures = <String, ResearchFailure>{};

      Future<void> readWorker() async {
        while (queueIndex < taskQueue.length && !cancel.isCancelled && epoch == _generation) {
          final task = taskQueue[queueIndex++];
          _updateChapter(task.id, MapChapterStatus.reading);

          try {
            final cacheKey = mapDigestCacheKey(
              source: task.source,
              chapterId: task.input.chapterId,
              chapterFingerprint: task.fingerprint,
              model: modelKey,
              organization: task.input.organization,
              instructions: task.input.instructions,
            );

            final cached = await cache.read(cacheKey, context: task.input.context);
            if (cached != null) {
              if (_disposed || epoch != _generation) return;
              for (final raw in cached) {
                final line = parseMapLine(raw, task.input.context);
                if (line != null) {
                  _collectedPoints.add(line);
                }
              }
              _updateChapter(task.id, MapChapterStatus.done);
            } else {
              final readLines = <MapLine>[];
              await for (final line in generator.readChapter(task.input, cancel)) {
                if (_disposed || epoch != _generation) return;
                readLines.add(line);
                _collectedPoints.add(line);
              }
              cancel.check();
              if (readLines.isNotEmpty) {
                final rawLines = mapPointCacheLines(readLines, task.input.context);
                await cache.write(cacheKey, rawLines, context: task.input.context);
              }
              _updateChapter(task.id, MapChapterStatus.done);
            }
          } catch (e) {
            final failure = e is ResearchFailure ? e : const ResearchFailure(ResearchFailureKind.unavailable);
            failures[task.id] = failure;
            _updateChapter(task.id, MapChapterStatus.failed, failure: failure);
          }
        }
      }

      await Future.wait([for (var i = 0; i < taskQueue.length.clamp(1, 3); i++) readWorker()]);
      cancel.check();

      if (_collectedPoints.isEmpty && failures.isNotEmpty) {
        final firstFailure = failures.values.first;
        if (!_disposed && epoch == _generation) {
          state = state!.copyWith(phase: MapGenerationPhase.failed, failure: firstFailure);
        }
        return;
      }

      // Phase 2: Streaming map generation
      if (!_disposed && epoch == _generation) {
        state = state!.copyWith(
          phase: MapGenerationPhase.streaming,
          skeletons: state!.skeletons.map((s) => s.copyWith(isDone: true)).toList(),
        );
      }

      await _streamBuild(request, cancel, epoch);
    } catch (error) {
      if (!_disposed && epoch == _generation) {
        final failure = error is ResearchFailure ? error : const ResearchFailure(ResearchFailureKind.unavailable);
        state = state!.copyWith(
          phase: state!.lines.isEmpty ? MapGenerationPhase.failed : MapGenerationPhase.stopped,
          failure: failure,
        );
      }
    } finally {
      if (!_disposed && epoch == _generation) {
        _ownsBusy = false;
        ref.read(expansionBusyProvider.notifier).set(false);
      }
    }
  }

  Future<void> _streamBuild(MapGenerationRequest request, CancellationToken cancel, int epoch) async {
    final generator = _generator!;
    _taskSession?.missingRangeIds = state!.chapterFailures.keys.toSet();
    final pages = <String, Set<int>>{};
    final updating = request.destination == MapGenerationDestination.update;
    final snapshot = ref.read(workspaceProvider(arg).notifier).content;
    final nodes = snapshot.nodes.where((n) => n.mapId == request.mapId).toList();
    final aliases = {for (final (i, n) in nodes.indexed) 'N${i + 1}': n.cardId};
    final reverse = {for (final e in aliases.entries) e.value: e.key};
    final titles = {for (final e in aliases.entries) e.key: snapshot.card(e.value)?.title ?? ''};
    final annotations = <String, String>{};
    final documents = <String, String>{};
    for (final task in _tasks.values) {
      final hasPoints = _collectedPoints.any(
        (point) => point.source?.documentId == task.source.documentId && task.pages.contains(point.source?.page),
      );
      if (state!.chapterProgress[task.id] != MapChapterStatus.done && !hasPoints) continue;
      documents.addAll(task.input.context.documents);
      for (final entry in task.input.context.pages.entries) {
        pages.putIfAbsent(entry.key, () => <int>{}).addAll(entry.value);
      }
      for (final id in task.input.context.annotations.values) {
        if (!annotations.containsValue(id)) annotations['A${annotations.length + 1}'] = id;
      }
    }
    _excerptAnnotations.clear();
    if (request.extractQuotes) {
      final workspace = ref.read(workspaceProvider(arg).notifier);
      final loaded = <String, TranslationPage?>{};
      final seen = <String>{};
      final books = <String, ReflowDocument>{};
      for (final point in _collectedPoints) {
        final source = point.quoteSource ?? point.source;
        if (source == null || point.quote == null) continue;
        final doc = snapshot.document(source.documentId);
        if (doc == null) continue;
        final key = '${source.documentId}:${source.page}';
        if (!seen.add('$key:${point.quote}')) continue;
        final id = '${state!.proposalId}-quote-${_excerptAnnotations.length}';
        final now = DateTime.now().toUtc();
        if (doc.contentManifest != null) {
          final repo = ref.read(contentRepositoryProvider);
          if (repo is! DocumentRepository) continue;
          books[doc.id] ??= await cancel.bind(ReflowDocument.load(repo as DocumentRepository, request.studySetId, doc));
          if (_disposed || epoch != _generation) return;
          final mark = mapTextQuoteAnnotation(books[doc.id]!, point, id, now);
          if (mark != null) {
            _excerptAnnotations.add(mark);
            annotations['A${annotations.length + 1}'] = mark.id;
          }
          continue;
        }
        if (!loaded.containsKey(key)) {
          try {
            loaded[key] = await cancel.bind(
              ref.read(mapQuotePageProvider)(
                ref.read(readerOcrProvider(workspace.filePath(doc))).document?.path ?? workspace.filePath(doc),
                source.page,
              ),
            );
          } on ResearchFailure {
            rethrow;
          } catch (_) {
            loaded[key] = null;
          }
        }
        cancel.check();
        if (_disposed || epoch != _generation) return;
        final page = loaded[key];
        if (page == null) continue;
        final mark = mapQuoteAnnotation(page, point, id, now);
        if (mark == null) continue;
        _excerptAnnotations.add(mark);
        annotations['A${annotations.length + 1}'] = mark.id;
      }
    }
    final buildContext = MapLineContext(
      phase: updating ? MapLinePhase.diff : MapLinePhase.generation,
      nodes: updating ? aliases : const {},
      protectedNodeIds: {
        for (final n in nodes)
          if (isMapNodeProtected(snapshot, request.mapId, n.cardId)) n.cardId,
      },
      mapId: request.mapId,
      draftPrefix: '${state!.proposalId}-gen-${state!.round}-',
      documents: documents,
      pages: pages,
      annotations: annotations,
      maxDepth: request.depth,
      rootParentId: request.parentId,
      existingTitles: titles.values,
    );

    final buildInput = MapBuildInput(
      title: request.title,
      onlyNewContent: request.onlyNewContent,
      titleConstraints: state!.editedTitles.values.toList(),
      generation: state!.generation,
      context: buildContext,
      points: [
        for (final p in _collectedPoints)
          MapLine(
            id: p.id,
            kind: p.kind,
            parentId: p.parentId,
            title: p.title,
            source: p.source,
            marks: [
              ...p.marks,
              for (final a in _excerptAnnotations)
                if (a.documentId == (p.quoteSource ?? p.source)?.documentId && a.quote == p.quote) a.id,
            ],
          ),
      ],
      existingTitles: updating ? titles : state!.editedTitles,
      existingParents: updating ? {for (final n in nodes) reverse[n.cardId]!: reverse[n.parentId] ?? 'ROOT'} : const {},
    );

    final lines = <MapLine>[];
    await for (final line
        in (updating ? generator.update(buildInput, cancel) : generator.generate(buildInput, cancel))) {
      if (_disposed || epoch != _generation) return;
      final mark = _excerptAnnotations.where((a) => a.id == line.annotationId).firstOrNull;
      lines.add(
        mark == null
            ? line
            : MapLine(
                id: line.id,
                kind: line.kind,
                parentId: line.parentId,
                annotationId: line.annotationId,
                title: mark.quote,
                source: mark.isText ? null : CardSource(documentId: mark.documentId, page: mark.page),
              ),
      );
      state = state!.copyWith(lines: List.unmodifiable(lines));
    }

    if (!_disposed && epoch == _generation) {
      if (lines.isEmpty) {
        state = state!.copyWith(
          phase: MapGenerationPhase.failed,
          failure: const ResearchFailure(ResearchFailureKind.protocol, 'noValidMapContent'),
        );
      } else {
        state = state!.copyWith(
          phase: state!.chapterFailures.isEmpty
              ? (updating ? MapGenerationPhase.diff : MapGenerationPhase.review)
              : MapGenerationPhase.stopped,
          failure: state!.chapterFailures.isEmpty
              ? null
              : const ResearchFailure(ResearchFailureKind.protocol, 'incompleteChapters'),
        );
      }
    }
  }

  void _updateChapter(String id, MapChapterStatus status, {ResearchFailure? failure}) {
    if (_disposed || state == null) return;
    final progress = Map<String, MapChapterStatus>.from(state!.chapterProgress);
    progress[id] = status;
    final failures = Map<String, ResearchFailure>.from(state!.chapterFailures);
    if (failure != null) {
      failures[id] = failure;
    } else {
      failures.remove(id);
    }
    final skeletons = state!.skeletons.map((s) {
      if (s.id == id) {
        return s.copyWith(isCurrent: status == MapChapterStatus.reading, isDone: status == MapChapterStatus.done);
      }
      return s;
    }).toList();

    state = state!.copyWith(
      chapterProgress: Map.unmodifiable(progress),
      chapterFailures: Map.unmodifiable(failures),
      skeletons: List.unmodifiable(skeletons),
    );
  }

  Future<void> retryChapter(String chapterId) async {
    final task = _tasks[chapterId];
    if (task == null || state == null || _generator == null) return;
    final epoch = ++_generation;
    final cancel = _cancel = CancellationToken();
    _ownsBusy = true;
    ref.read(expansionBusyProvider.notifier).set(true);

    _collectedPoints.removeWhere((point) => point.id.startsWith(task.input.context.draftPrefix));
    final cache = ref.read(mapDigestCacheProvider(state!.request.studySetId));
    final modelKey = _cacheModelKey;

    var chapterRead = false;
    _taskSession?.missingRangeIds = {};
    try {
      _updateChapter(chapterId, MapChapterStatus.reading);
      final cacheKey = mapDigestCacheKey(
        source: task.source,
        chapterId: task.input.chapterId,
        chapterFingerprint: task.fingerprint,
        model: modelKey,
        organization: task.input.organization,
        instructions: task.input.instructions,
      );

      final cached = await cache.read(cacheKey, context: task.input.context);
      if (cached != null) {
        if (_disposed || epoch != _generation) return;
        for (final raw in cached) {
          final line = parseMapLine(raw, task.input.context);
          if (line != null) {
            _collectedPoints.add(line);
          }
        }
        _updateChapter(chapterId, MapChapterStatus.done);
      } else {
        final readLines = <MapLine>[];
        await for (final line in _generator!.readChapter(task.input, cancel)) {
          if (_disposed || epoch != _generation) return;
          readLines.add(line);
          _collectedPoints.add(line);
        }
        if (readLines.isNotEmpty) {
          final rawLines = mapPointCacheLines(readLines, task.input.context);
          await cache.write(cacheKey, rawLines, context: task.input.context);
        }
        _updateChapter(chapterId, MapChapterStatus.done);
      }

      chapterRead = true;
      state = state!.copyWith(phase: MapGenerationPhase.streaming, failure: null);
      await _streamBuild(state!.request, cancel, epoch);
    } catch (e) {
      final failure = e is ResearchFailure ? e : const ResearchFailure(ResearchFailureKind.unavailable);
      if (!_disposed && epoch == _generation) {
        if (!chapterRead) _updateChapter(chapterId, MapChapterStatus.failed, failure: failure);
        state = state!.copyWith(
          phase: state!.lines.isEmpty ? MapGenerationPhase.failed : MapGenerationPhase.stopped,
          failure: failure,
        );
      }
    } finally {
      if (!_disposed && epoch == _generation) {
        _ownsBusy = false;
        ref.read(expansionBusyProvider.notifier).set(false);
      }
    }
  }

  Future<void> retry() async {
    if (state == null || state!.phase != MapGenerationPhase.failed) return;
    final req = state!.request;
    if (state!.needsTextDocumentId != null && _ownsBusy) {
      _ownsBusy = false;
      ref.read(expansionBusyProvider.notifier).set(false);
    }
    if (_collectedPoints.isNotEmpty && state!.chapterFailures.isEmpty) {
      state = state!.copyWith(phase: MapGenerationPhase.streaming, failure: null);
      final epoch = ++_generation;
      final cancel = _cancel = CancellationToken();
      _ownsBusy = true;
      ref.read(expansionBusyProvider.notifier).set(true);
      try {
        await _streamBuild(req, cancel, epoch);
      } catch (e) {
        if (!_disposed && epoch == _generation) {
          state = state!.copyWith(
            phase: state!.lines.isEmpty ? MapGenerationPhase.failed : MapGenerationPhase.stopped,
            failure: e is ResearchFailure ? e : const ResearchFailure(ResearchFailureKind.unavailable),
          );
        }
      } finally {
        if (!_disposed && epoch == _generation) {
          _ownsBusy = false;
          ref.read(expansionBusyProvider.notifier).set(false);
        }
      }
    } else {
      state = null;
      await start(req);
    }
  }

  void stop() {
    if (state == null || state!.isApplying) return;
    _ocrSubscription?.close();
    _ocrSubscription = null;
    _cancel?.cancel();
    _generator?.close();
    ++_generation;
    _ownsBusy = false;
    ref.read(expansionBusyProvider.notifier).set(false);
    state = state!.lines.isEmpty ? null : state!.copyWith(phase: MapGenerationPhase.stopped);
  }

  void discard() {
    if (state?.isApplying == true) return;
    if (state != null) stop();
    state = null;
  }

  /// An immediate first click may be followed by double-click editing. Keep
  /// an exact, selection-only undo: toggling a parent twice is not an inverse
  /// because excluding it also excludes its descendants.
  void Function()? toggleForClick(String id) {
    if (!_reviewable) return null;
    final current = state!;
    final request = current.request;
    final item = current.lines.where((d) => d.id == id).firstOrNull;
    if (item == null) return null;
    final before = {for (final d in current.lines) d.id: d.kept};
    toggle(id, !item.kept);
    final changed = {
      for (final d in state!.lines)
        if (before[d.id] != d.kept) d.id: d.kept,
    };
    return () {
      if (!_reviewable || !identical(state!.request, request)) return;
      state = state!.copyWith(
        lines: [
          for (final d in state!.lines)
            if (changed.containsKey(d.id) && d.kept == changed[d.id]) d.copyWith(kept: before[d.id]!) else d,
        ],
      );
    };
  }

  void toggle(String id, bool kept) {
    if (!_reviewable) return;
    state = state!.copyWith(lines: _select(state!.lines, id, kept));
  }

  void edit(String id, String title) {
    if (!_reviewable || normalizeExpansionTitle(title).isEmpty) return;
    final line = state!.lines.where((l) => l.id == id).firstOrNull;
    if (line == null || (line.kind != MapLineKind.add && line.kind != MapLineKind.rename)) return;
    final edited = Map<String, String>.from(state!.editedTitles);
    edited[id] = title.trim();
    state = state!.copyWith(
      lines: _select(state!.lines, id, true, title: title),
      editedTitles: Map.unmodifiable(edited),
    );
  }

  bool get _reviewable =>
      state != null &&
      !state!.isApplying &&
      {
        MapGenerationPhase.review,
        MapGenerationPhase.diff,
        MapGenerationPhase.stopped,
        MapGenerationPhase.failed,
      }.contains(state!.phase);

  Future<void> regenerate([MapGenerationRequest? settings]) async {
    if (!_reviewable || ref.read(assistantControllerProvider.notifier).busy) return;
    final old = state!;
    final r = settings ?? old.request;
    final nextRequest = r.copyWith(round: old.round + 1);

    state = MapGenerationPreview(
      request: nextRequest,
      baseRevision: old.baseRevision,
      proposalId: old.proposalId,
      generation: old.generation,
      phase: MapGenerationPhase.streaming,
      round: old.round + 1,
      editedTitles: old.editedTitles,
    );

    final epoch = ++_generation;
    final cancel = _cancel = CancellationToken();
    _ownsBusy = true;
    ref.read(expansionBusyProvider.notifier).set(true);

    try {
      await _streamBuild(nextRequest, cancel, epoch);
    } catch (e) {
      if (!_disposed && epoch == _generation) {
        state = state!.copyWith(
          phase: state!.lines.isEmpty ? MapGenerationPhase.failed : MapGenerationPhase.stopped,
          failure: e is ResearchFailure ? e : const ResearchFailure(ResearchFailureKind.unavailable),
        );
      }
    } finally {
      if (!_disposed && epoch == _generation) {
        _ownsBusy = false;
        ref.read(expansionBusyProvider.notifier).set(false);
      }
    }
  }

  Future<int> keep() async {
    if (!_reviewable || state!.selectedCount == 0) return 0;
    final old = state!;
    state = old.copyWith(isApplying: true);

    try {
      final isNewMap = old.request.destination == MapGenerationDestination.newMap;
      final proposal = old.request.destination == MapGenerationDestination.update
          ? diffToProposal(
              proposalId: old.proposalId,
              studySetId: old.request.studySetId,
              mapId: old.request.mapId,
              baseRevision: old.baseRevision,
              generation: old.generation,
              lines: old.lines,
              excerptAnnotations: _excerptAnnotations,
            )
          : generationToProposal(
              proposalId: old.proposalId,
              studySetId: old.request.studySetId,
              mapId: old.request.mapId,
              baseRevision: old.baseRevision,
              generation: old.generation,
              lines: old.lines,
              excerptAnnotations: _excerptAnnotations,
              createMap: isNewMap ? MindMap(id: old.request.mapId, title: old.request.title) : null,
            );

      final executor = ref.read(assistantMapEditExecutorProvider(arg));
      final receipt = await executor.apply(proposal, proposal.operations.map((o) => o.id).toSet());

      try {
        await _generator?.close();
      } catch (_) {
        /* The write already committed. */
      }
      _generator = null;
      if (!_disposed) {
        state = null;
        if (isNewMap) {
          await ref.read(workspaceProvider(arg).notifier).selectMap(old.request.mapId);
        }
      }
      return old.request.destination == MapGenerationDestination.update
          ? receipt.operationIds.length
          : receipt.nodeIds.length;
    } catch (e) {
      if (!_disposed) {
        state = old.copyWith(
          isApplying: false,
          failure: e is ResearchFailure ? e : const ResearchFailure(ResearchFailureKind.unavailable),
        );
      }
      return 0;
    }
  }

  List<MapLine> _select(List<MapLine> lines, String id, bool kept, {String? title}) {
    final byId = {for (final l in lines) l.id: l};
    if (!byId.containsKey(id)) return lines;
    final affected = <String>{id};

    if (kept || title != null) {
      var current = byId[id]!;
      while (current.parentId?.startsWith('new:') ?? false) {
        final parent = byId[current.parentId!.substring(4)];
        if (parent == null || !affected.add(parent.id)) break;
        current = parent;
      }
    } else {
      var changed = true;
      while (changed) {
        changed = false;
        for (final l in lines) {
          if ((l.parentId?.startsWith('new:') ?? false) &&
              affected.contains(l.parentId!.substring(4)) &&
              affected.add(l.id)) {
            changed = true;
          }
        }
      }
    }

    return List.unmodifiable([
      for (final l in lines)
        affected.contains(l.id)
            ? l.copyWith(
                kept: title != null || kept,
                title: l.id == id ? (title != null && title.trim().isNotEmpty ? title.trim() : l.title) : l.title,
              )
            : l,
    ]);
  }
}
