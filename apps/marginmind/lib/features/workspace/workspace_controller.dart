import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../app/providers.dart';

enum MapViewMode { map, outline }

enum AnnotationTool { select, highlight, area, pen, text }

/// Something the source pane is waiting on the user to decide.
sealed class PendingAction {
  const PendingAction();
}

/// Text selected with the Select tool: choose excerpt / highlight / copy.
class PendingSelection extends PendingAction {
  const PendingSelection(this.documentId, this.selection);

  final String documentId;
  final MMPdfSelection selection;
}

/// A plain highlight (no card) was clicked: add to map, recolor or delete.
class PendingHighlight extends PendingAction {
  const PendingHighlight(this.annotationId);

  final String annotationId;
}

/// Ask the source pane to scroll to a highlight.
class RevealRequest {
  const RevealRequest(this.documentId, this.page, this.rects, this.nonce);

  final String documentId;
  final int page;
  final List<PageRect> rects;
  final int nonce;
}

/// Outcomes worth telling the user about (shown as HUD by the UI, which
/// owns the wording).
sealed class WorkspaceNotice {
  const WorkspaceNotice();
}

class ExcerptedNotice extends WorkspaceNotice {
  const ExcerptedNotice(this.targetTitle);

  final String? targetTitle;
}

class HighlightedNotice extends WorkspaceNotice {
  const HighlightedNotice();
}

class RemovedNotice extends WorkspaceNotice {
  const RemovedNotice();
}

class HighlightDeletedNotice extends WorkspaceNotice {
  const HighlightDeletedNotice();
}

class ImportedNotice extends WorkspaceNotice {
  const ImportedNotice(this.count, this.failed);

  final int count;
  final List<String> failed;
}

class WorkspaceState {
  const WorkspaceState({
    this.sidebarVisible = true,
    this.layout = MMSplitMode.split,
    this.splitFraction = 0.5,
    this.mapView = MapViewMode.map,
    this.tool = AnnotationTool.highlight,
    this.color = MMAnnotationColor.yellow,
    this.syncToMap = true,
    this.openDocumentIds = const [],
    this.activeDocumentId,
    this.sidebarQuery = '',
    this.selectedCardId,
    this.flashCardId,
    this.flashAnnotationId,
    this.pending,
    this.reveal,
    this.currentPages = const {},
  });

  final bool sidebarVisible;
  final MMSplitMode layout;
  final double splitFraction;
  final MapViewMode mapView;
  final AnnotationTool tool;
  final MMAnnotationColor color;

  /// Whether a new highlight also creates a card in the mind map.
  final bool syncToMap;
  final List<String> openDocumentIds;
  final String? activeDocumentId;
  final String sidebarQuery;

  /// Selected map node; null means the root.
  final String? selectedCardId;
  final String? flashCardId;
  final String? flashAnnotationId;
  final PendingAction? pending;
  final RevealRequest? reveal;

  /// Page currently shown per document (persisted as `lastPage`, debounced).
  final Map<String, int> currentPages;

  WorkspaceState copyWith({
    bool? sidebarVisible,
    MMSplitMode? layout,
    double? splitFraction,
    MapViewMode? mapView,
    AnnotationTool? tool,
    MMAnnotationColor? color,
    bool? syncToMap,
    List<String>? openDocumentIds,
    String? activeDocumentId,
    bool clearActive = false,
    String? sidebarQuery,
    String? selectedCardId,
    bool selectRoot = false,
    String? flashCardId,
    String? flashAnnotationId,
    bool clearFlash = false,
    PendingAction? pending,
    bool clearPending = false,
    RevealRequest? reveal,
    Map<String, int>? currentPages,
  }) {
    return WorkspaceState(
      sidebarVisible: sidebarVisible ?? this.sidebarVisible,
      layout: layout ?? this.layout,
      splitFraction: splitFraction ?? this.splitFraction,
      mapView: mapView ?? this.mapView,
      tool: tool ?? this.tool,
      color: color ?? this.color,
      syncToMap: syncToMap ?? this.syncToMap,
      openDocumentIds: openDocumentIds ?? this.openDocumentIds,
      activeDocumentId: clearActive ? null : (activeDocumentId ?? this.activeDocumentId),
      sidebarQuery: sidebarQuery ?? this.sidebarQuery,
      selectedCardId: selectRoot ? null : (selectedCardId ?? this.selectedCardId),
      flashCardId: clearFlash ? null : (flashCardId ?? this.flashCardId),
      flashAnnotationId: clearFlash ? null : (flashAnnotationId ?? this.flashAnnotationId),
      pending: clearPending ? null : (pending ?? this.pending),
      reveal: reveal ?? this.reveal,
      currentPages: currentPages ?? this.currentPages,
    );
  }
}

/// One study set window: panel state plus every user action on its content.
/// Content edits go through [StudySetEditor] and are persisted by the
/// content repository; the UI re-renders from the repository stream.
class WorkspaceController extends Notifier<WorkspaceState> {
  WorkspaceController(this.studySetId);

  final String studySetId;
  Timer? _flashTimer;
  Timer? _pageTimer;
  int _revealNonce = 0;

  @override
  WorkspaceState build() {
    ref.onDispose(() {
      _flashTimer?.cancel();
      _pageTimer?.cancel();
    });
    ref.listen(contentProvider(studySetId), (_, next) {
      final c = next.value;
      if (c != null) state = _withTabs(state, c);
    });
    final initial = ref.read(contentProvider(studySetId)).value;
    return initial == null ? const WorkspaceState() : _withTabs(const WorkspaceState(), initial);
  }

  StudySetContent get content => ref.read(contentProvider(studySetId)).value ?? StudySetContent.empty;

  StudySetEditor get _editor => ref.read(editorProvider);

  StudySetContentRepository get _repo => ref.read(contentRepositoryProvider);

  Future<StudySetContent> _update(StudySetContent Function(StudySetContent) change) => _repo.update(studySetId, change);

  /// Opens the last-read document on first load, drops tabs (and the
  /// selection) whose target no longer exists.
  static WorkspaceState _withTabs(WorkspaceState s, StudySetContent c) {
    var open = [
      for (final id in s.openDocumentIds)
        if (c.document(id) != null) id,
    ];
    String? active = s.activeDocumentId != null && c.document(s.activeDocumentId!) != null ? s.activeDocumentId : null;
    if (open.isEmpty && c.documents.isNotEmpty) {
      final first = c.lastRead ?? c.documents.first;
      open = [first.id];
      active = first.id;
    }
    active ??= open.lastOrNull;
    final selectionGone = s.selectedCardId != null && c.card(s.selectedCardId!) == null;
    return s.copyWith(
      openDocumentIds: open,
      activeDocumentId: active,
      clearActive: active == null,
      selectRoot: selectionGone,
    );
  }

  // ---- panels ---------------------------------------------------------------

  void toggleSidebar() => state = state.copyWith(sidebarVisible: !state.sidebarVisible);

  void setLayout(MMSplitMode layout) => state = state.copyWith(layout: layout);

  void setSplitFraction(double value) => state = state.copyWith(splitFraction: value.clamp(0.1, 0.9));

  void setMapView(MapViewMode view) => state = state.copyWith(mapView: view);

  void setTool(AnnotationTool tool) => state = state.copyWith(tool: tool, clearPending: true);

  void setColor(MMAnnotationColor color) => state = state.copyWith(color: color, tool: AnnotationTool.highlight);

  void toggleSyncToMap() => state = state.copyWith(syncToMap: !state.syncToMap);

  void setSidebarQuery(String query) => state = state.copyWith(sidebarQuery: query);

  /// Opens (or focuses) a document tab. In map-only layout the source pane
  /// comes back, since the user asked to see a document.
  void openDocument(String id) {
    final open = state.openDocumentIds.contains(id) ? state.openDocumentIds : [...state.openDocumentIds, id];
    state = state.copyWith(
      openDocumentIds: open,
      activeDocumentId: id,
      clearPending: true,
      layout: state.layout == MMSplitMode.secondary ? MMSplitMode.split : null,
    );
  }

  void closeDocument(String id) {
    final open = [...state.openDocumentIds]..remove(id);
    final wasActive = state.activeDocumentId == id;
    state = state.copyWith(
      openDocumentIds: open,
      activeDocumentId: wasActive ? open.lastOrNull : null,
      clearActive: wasActive && open.isEmpty,
      clearPending: true,
    );
  }

  // ---- documents ------------------------------------------------------------

  /// Copies each file into the study set and adds it as a document.
  Future<ImportedNotice> importDocuments(List<({String path, String name})> files) async {
    var count = 0;
    final failed = <String>[];
    String? lastId;
    for (final f in files) {
      try {
        final info = await MMPdfEngine.inspect(f.path);
        final stored = await _repo.importFile(studySetId, f.path);
        final title = f.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        await _update((c) {
          final (next, doc) = _editor.addDocument(c, title: title, fileName: stored, pageCount: info.pageCount);
          lastId = doc.id;
          return next;
        });
        count++;
      } catch (_) {
        failed.add(f.name);
      }
    }
    if (lastId != null) openDocument(lastId!);
    return ImportedNotice(count, failed);
  }

  String filePath(Document doc) => _repo.resolveFile(studySetId, doc.fileName);

  void recordPage(String documentId, int page) {
    if (state.currentPages[documentId] == page) return;
    state = state.copyWith(currentPages: {...state.currentPages, documentId: page});
    _pageTimer?.cancel();
    _pageTimer = Timer(const Duration(milliseconds: 800), () {
      _update((c) => _editor.setLastPage(c, documentId, page));
    });
  }

  // ---- excerpts and highlights ------------------------------------------------

  /// Where a new excerpt goes, and that node's title (null = root).
  String? get excerptTargetId => StudySetEditor.excerptTarget(content, state.selectedCardId);

  /// The mouse was released over selected text.
  Future<WorkspaceNotice?> onSelectionCommitted(String documentId, MMPdfSelection selection) async {
    if (state.tool == AnnotationTool.highlight) {
      return state.syncToMap
          ? excerpt(documentId, selection, state.color)
          : highlight(documentId, selection, state.color);
    }
    state = state.copyWith(pending: PendingSelection(documentId, selection));
    return null;
  }

  Future<ExcerptedNotice> excerpt(String documentId, MMPdfSelection s, MMAnnotationColor color) async {
    final parent = excerptTargetId;
    late Card card;
    await _update((c) {
      final (next, created) = _editor.createExcerpt(
        c,
        documentId: documentId,
        page: s.page,
        rects: s.rects,
        quote: s.text,
        colorIndex: color.index,
        parentId: parent,
      );
      card = created;
      return next;
    });
    state = state.copyWith(clearPending: true);
    _flash(cardId: card.id);
    return ExcerptedNotice(parent == null ? null : content.card(parent)?.title);
  }

  Future<HighlightedNotice> highlight(String documentId, MMPdfSelection s, MMAnnotationColor color) async {
    await _update(
      (c) => _editor
          .highlight(c, documentId: documentId, page: s.page, rects: s.rects, quote: s.text, colorIndex: color.index)
          .$1,
    );
    state = state.copyWith(clearPending: true);
    return const HighlightedNotice();
  }

  void dismissPending() => state = state.copyWith(clearPending: true);

  /// A highlight on the page was clicked.
  void tapHighlight(String annotationId) {
    final card = content.cardForAnnotation(annotationId);
    if (card != null) {
      state = state.copyWith(selectedCardId: card.id, clearPending: true, mapView: MapViewMode.map);
      _flash(cardId: card.id);
    } else {
      state = state.copyWith(pending: PendingHighlight(annotationId));
    }
  }

  Future<ExcerptedNotice> addHighlightToMap(String annotationId) async {
    final parent = excerptTargetId;
    late Card card;
    await _update((c) {
      final (next, created) = _editor.attachCard(c, annotationId, parentId: parent);
      card = created;
      return next;
    });
    state = state.copyWith(clearPending: true, selectedCardId: card.id);
    _flash(cardId: card.id);
    return ExcerptedNotice(parent == null ? null : content.card(parent)?.title);
  }

  Future<void> recolor(String annotationId, MMAnnotationColor color) async {
    await _update((c) => _editor.recolor(c, annotationId, color.index));
    state = state.copyWith(clearPending: true);
  }

  Future<HighlightDeletedNotice> deleteHighlight(String annotationId) async {
    await _update((c) => _editor.deleteAnnotation(c, annotationId));
    state = state.copyWith(clearPending: true);
    return const HighlightDeletedNotice();
  }

  // ---- map --------------------------------------------------------------------

  void selectCard(String? cardId) {
    state = cardId == null ? state.copyWith(selectRoot: true) : state.copyWith(selectedCardId: cardId);
    final annotationId = cardId == null ? null : content.card(cardId)?.annotationId;
    if (annotationId != null) _flash(annotationId: annotationId);
  }

  /// Opens the source document of an excerpt and scrolls to it.
  void revealCard(String cardId) {
    final c = content;
    final annotation = c.annotation(c.card(cardId)?.annotationId ?? '');
    if (annotation == null) return;
    openDocument(annotation.documentId);
    state = state.copyWith(
      selectedCardId: cardId,
      reveal: RevealRequest(annotation.documentId, annotation.page, annotation.rects, ++_revealNonce),
    );
    _flash(annotationId: annotation.id, cardId: cardId);
  }

  /// Adds a topic under the selected topic, or at the root.
  Future<Card> addTopic(String title) async {
    final selected = state.selectedCardId == null ? null : content.card(state.selectedCardId!);
    final parent = selected?.kind == CardKind.topic ? selected!.id : null;
    late Card card;
    await _update((c) {
      final (next, created) = _editor.addTopic(c, title: title, parentId: parent);
      card = created;
      return next;
    });
    state = state.copyWith(selectedCardId: card.id);
    return card;
  }

  /// Adds a note under the selected node (any kind), or at the root.
  Future<Card> addNote(String text) async {
    final parent = state.selectedCardId;
    late Card card;
    await _update((c) {
      final (next, created) = _editor.addNote(c, text: text, parentId: parent);
      card = created;
      return next;
    });
    state = state.copyWith(selectedCardId: card.id);
    return card;
  }

  Future<void> rename(String cardId, String title) => _update((c) => _editor.rename(c, cardId, title));

  Future<RemovedNotice?> removeSelected() async {
    final id = state.selectedCardId;
    if (id == null) return null;
    final parent = content.node(id)?.parentId;
    await _update((c) => _editor.removeFromMap(c, id));
    state = parent == null ? state.copyWith(selectRoot: true) : state.copyWith(selectedCardId: parent);
    return const RemovedNotice();
  }

  void _flash({String? cardId, String? annotationId}) {
    _flashTimer?.cancel();
    state = state.copyWith(flashCardId: cardId, flashAnnotationId: annotationId);
    _flashTimer = Timer(MMMotion.flash, () {
      if (ref.mounted) state = state.copyWith(clearFlash: true);
    });
  }
}

final workspaceProvider = NotifierProvider.family<WorkspaceController, WorkspaceState, String>(WorkspaceController.new);
