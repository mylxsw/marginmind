import 'dart:async';
import 'dart:convert';

import 'package:flutter/painting.dart' show AxisDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../app/providers.dart';
import '../../settings/app_settings.dart';

export '../../settings/app_settings.dart' show AnnotationTool;

enum MapViewMode { map, outline }

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

class UndoneNotice extends WorkspaceNotice {
  const UndoneNotice({required this.redo});

  final bool redo;
}

class DocumentRemovedNotice extends WorkspaceNotice {
  const DocumentRemovedNotice();
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
    this.tool = AnnotationTool.select,
    this.color = MMAnnotationColor.yellow,
    this.syncToMap = true,
    this.openDocumentIds = const [],
    this.activeDocumentId,
    this.sidebarQuery = '',
    this.selectedCardId,
    this.flashCardId,
    this.flashAnnotationId,
    this.editingCardId,
    this.pending,
    this.reveal,
    this.currentPages = const {},
    this.canUndo = false,
    this.canRedo = false,
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

  /// Topic whose title is being edited in place on the map.
  final String? editingCardId;
  final PendingAction? pending;
  final RevealRequest? reveal;

  /// Page currently shown per document (persisted as `lastPage`, debounced).
  final Map<String, int> currentPages;

  final bool canUndo;
  final bool canRedo;

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
    String? editingCardId,
    bool clearEditing = false,
    PendingAction? pending,
    bool clearPending = false,
    RevealRequest? reveal,
    Map<String, int>? currentPages,
    bool? canUndo,
    bool? canRedo,
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
      editingCardId: clearEditing ? null : (editingCardId ?? this.editingCardId),
      pending: clearPending ? null : (pending ?? this.pending),
      reveal: reveal ?? this.reveal,
      currentPages: currentPages ?? this.currentPages,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
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
      if (c == null) return;
      _latest = c;
      state = _withTabs(state, c);
    });
    ref.listen(settingsProvider.select((s) => s.annotationTool), (_, tool) {
      if (state.tool != tool) state = state.copyWith(tool: tool, clearPending: true);
    });
    final initialState = WorkspaceState(tool: ref.read(settingsProvider).annotationTool);
    final initial = ref.read(contentProvider(studySetId)).value;
    return initial == null ? initialState : _withTabs(initialState, initial);
  }

  /// The newest content seen, from either the stream or our own writes
  /// (the stream delivers a write a moment after it completes).
  StudySetContent? _latest;

  StudySetContent get content => _latest ?? ref.read(contentProvider(studySetId)).value ?? StudySetContent.empty;

  StudySetEditor get _editor => ref.read(editorProvider);

  StudySetContentRepository get _repo => ref.read(contentRepositoryProvider);

  /// Content before each undoable edit, newest last; redo holds what undo
  /// replaced.
  final List<StudySetContent> _undo = [];
  final List<StudySetContent> _redo = [];
  static const _historyLimit = 100;

  Future<void> _pendingEdits = Future.value();
  StudySetContent? _transactionBefore;
  int _transactionDepth = 0;

  /// Serializes writes and transaction boundaries, including callers that
  /// enqueue commit immediately after an edit without awaiting that edit.
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _pendingEdits.then((_) => action());
    _pendingEdits = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Nested begins join the outer transaction; only the outer commit records
  /// history. Await this before editing. Repeated commit/abort are harmless.
  Future<void> beginTransaction() => _enqueue(() async {
    _transactionDepth++;
    _syncHistory();
  });

  Future<void> commitTransaction() => _enqueue(() async {
    if (_transactionDepth == 0) return;
    if (--_transactionDepth != 0) return;
    final before = _transactionBefore;
    _transactionBefore = null;
    if (before != null && !_sameEdits(before, content)) _record(before);
    _syncHistory();
  });

  /// Cancels the whole transaction, including nested scopes. Uses the same
  /// restore policy as undo so reading position and reviews are preserved.
  Future<void> abortTransaction() => _enqueue(() async {
    if (_transactionDepth == 0) return;
    final before = _transactionBefore;
    if (before != null) {
      final next = await _repo.update(studySetId, (c) => StudySetEditor.restore(before, c));
      _latest = next;
      if (ref.mounted) state = _withTabs(state, next).copyWith(clearPending: true);
    }
    _transactionBefore = null;
    _transactionDepth = 0;
    _syncHistory();
  });

  static bool _sameEdits(StudySetContent before, StudySetContent after) =>
      identical(before, after) ||
      jsonEncode(StudySetEditor.restore(before, after).toJson()) == jsonEncode(after.toJson());

  void _record(StudySetContent before) {
    _undo.add(before);
    if (_undo.length > _historyLimit) _undo.removeAt(0);
    _redo.clear();
  }

  /// Standalone edits are implicit single-step transactions.
  Future<StudySetContent> _update(StudySetContent Function(StudySetContent) change, {bool undoable = true}) =>
      _enqueue(() async {
        StudySetContent? before;
        final next = await _repo.update(studySetId, (c) {
          before = c;
          return change(c);
        });
        _latest = next;
        if (ref.mounted) state = _withTabs(state, next);
        if (undoable && before != null && !_sameEdits(before!, next)) {
          if (_transactionDepth > 0) {
            _transactionBefore ??= before;
          } else {
            _record(before!);
          }
          _syncHistory();
        }
        return next;
      });

  void _syncHistory() {
    if (!ref.mounted) return;
    state = state.copyWith(
      canUndo: _transactionDepth == 0 && _undo.isNotEmpty,
      canRedo: _transactionDepth == 0 && _redo.isNotEmpty,
    );
  }

  Future<UndoneNotice?> undo() => _travel(_undo, _redo, redo: false);

  Future<UndoneNotice?> redo() => _travel(_redo, _undo, redo: true);

  Future<UndoneNotice?> _travel(List<StudySetContent> from, List<StudySetContent> to, {required bool redo}) =>
      _enqueue(() async {
        if (_transactionDepth > 0 || from.isEmpty) return null;
        final snapshot = from.last;
        StudySetContent? current;
        _latest = await _repo.update(studySetId, (c) {
          current = c;
          return StudySetEditor.restore(snapshot, c);
        });
        from.removeLast();
        to.add(current!);
        if (ref.mounted) state = _withTabs(state, _latest!).copyWith(clearPending: true);
        _syncHistory();
        return UndoneNotice(redo: redo);
      });

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

  Future<void> setTool(AnnotationTool tool) {
    if (state.tool != tool) state = state.copyWith(tool: tool, clearPending: true);
    return ref.read(settingsProvider.notifier).setAnnotationTool(tool);
  }

  Future<void> toggleTool() =>
      setTool(state.tool == AnnotationTool.select ? AnnotationTool.highlight : AnnotationTool.select);

  Future<void> setColor(MMAnnotationColor color) {
    state = state.copyWith(color: color);
    return setTool(AnnotationTool.highlight);
  }

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
        }, undoable: false);
        count++;
      } catch (_) {
        failed.add(f.name);
      }
    }
    if (lastId != null) openDocument(lastId!);
    return ImportedNotice(count, failed);
  }

  String filePath(Document doc) => _repo.resolveFile(studySetId, doc.fileName);

  Future<void> renameDocument(String documentId, String title) {
    if (title.trim().isEmpty) return Future.value();
    return _update((c) => _editor.renameDocument(c, documentId, title));
  }

  /// Removes a document with its highlights and excerpt cards (undoable;
  /// the file stays in the package until the study set is deleted).
  Future<DocumentRemovedNotice> removeDocument(String documentId) async {
    await _update((c) => _editor.removeDocument(c, documentId));
    return const DocumentRemovedNotice();
  }

  /// The main map as Markdown or OPML. [source] labels excerpt sources.
  String export({required bool opml, required String rootTitle, required String Function(Document, int) source}) {
    final exporter = MapExporter(content, rootTitle: rootTitle, source: source);
    return opml ? exporter.opml() : exporter.markdown();
  }

  void recordPage(String documentId, int page) {
    if (state.currentPages[documentId] == page) return;
    state = state.copyWith(currentPages: {...state.currentPages, documentId: page});
    _pageTimer?.cancel();
    _pageTimer = Timer(const Duration(milliseconds: 800), () {
      _update((c) => _editor.setLastPage(c, documentId, page), undoable: false);
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

  /// Adds a topic under the selected topic, or at the root. With
  /// [asChild] it goes under the selected node of any kind (Tab).
  Future<Card> addTopic(String title, {bool asChild = false}) async {
    final selected = state.selectedCardId == null ? null : content.card(state.selectedCardId!);
    final parent = asChild || selected?.kind == CardKind.topic ? selected?.id : null;
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

  // ---- in-place editing -------------------------------------------------------

  _EditSession? _editing;

  /// A topic is being created for editing; no other edit may start yet.
  bool _creating = false;

  /// Starts editing a topic's title in place. Nothing is written until
  /// [finishEditing], so the whole edit is one undo step.
  void beginEditing(String cardId) {
    if (_editing != null || _creating || content.card(cardId)?.kind != CardKind.topic) return;
    _editing = _EditSession(cardId, created: false, previousSelection: state.selectedCardId);
    state = state.copyWith(selectedCardId: cardId, editingCardId: cardId);
  }

  /// Adds a topic (see [addTopic]) and starts editing it. Creation and the
  /// typed title commit as one undo step; cancelling leaves no node and no
  /// history.
  Future<Card?> addTopicAndEdit(String title, {bool asChild = false}) async {
    if (_editing != null || _creating) return null;
    _creating = true;
    final previous = state.selectedCardId;
    final Card card;
    try {
      await beginTransaction();
      try {
        card = await addTopic(title, asChild: asChild);
      } catch (_) {
        await abortTransaction();
        rethrow;
      }
    } finally {
      _creating = false;
    }
    _editing = _EditSession(card.id, created: true, previousSelection: previous);
    state = state.copyWith(editingCardId: card.id);
    return card;
  }

  /// Enter or clicking elsewhere. An empty title keeps the old one, or
  /// drops a node created for this edit.
  Future<void> finishEditing(String text) async {
    final session = _editing;
    if (session == null) return;
    _editing = null;
    final title = text.trim();
    try {
      if (session.created && title.isEmpty) {
        await _dropCreated(session);
      } else if (session.created) {
        try {
          if (title != content.card(session.cardId)?.title) await rename(session.cardId, title);
        } finally {
          await commitTransaction();
        }
      } else if (title.isNotEmpty && title != content.card(session.cardId)?.title) {
        await rename(session.cardId, title);
      }
    } finally {
      _closeEditor();
    }
  }

  /// Esc: keeps the old title, or drops a node created for this edit.
  Future<void> cancelEditing() async {
    final session = _editing;
    if (session == null) return;
    _editing = null;
    try {
      if (session.created) await _dropCreated(session);
    } finally {
      _closeEditor();
    }
  }

  /// The field stays open until the edit is saved, so the new title
  /// replaces it without showing the old one in between.
  void _closeEditor() {
    if (_editing == null && ref.mounted) state = state.copyWith(clearEditing: true);
  }

  Future<void> _dropCreated(_EditSession session) async {
    await abortTransaction();
    final previous = session.previousSelection;
    if (!ref.mounted) return;
    state = previous != null && content.card(previous) != null
        ? state.copyWith(selectedCardId: previous)
        : state.copyWith(selectRoot: true);
  }

  Future<void> removeCards(Iterable<String> cardIds) {
    final ids = cardIds.toList();
    return _update((c) => _editor.removeMany(c, ids));
  }

  Future<void> moveCards(Iterable<String> cardIds, String? parentId, {int? index}) {
    final ids = cardIds.toList();
    return _update((c) => _editor.moveMany(c, ids, parentId, index: index));
  }

  Future<void> recolorCards(Iterable<String> cardIds, MMAnnotationColor color) {
    final ids = cardIds.toList();
    return _update((c) => _editor.recolorMany(c, ids, color.index));
  }

  /// Drag and drop: [cardId] becomes a child of [parentId] (null = root) at
  /// [index], or the last child.
  Future<void> moveCard(String cardId, String? parentId, {int? index}) async {
    await _update((c) => _editor.move(c, cardId, parentId, index: index));
    state = state.copyWith(selectedCardId: cardId);
  }

  /// ⌘↑ / ⌘↓: move the selected node among its siblings.
  Future<void> shiftSelected(int delta) async {
    final id = state.selectedCardId;
    if (id != null) await _update((c) => _editor.shift(c, id, delta));
  }

  Future<void> toggleCollapsed(String cardId) {
    final node = content.node(cardId);
    if (node == null || content.childrenOf(cardId).isEmpty) return Future.value();
    return _update((c) => _editor.setCollapsed(c, cardId, collapsed: !node.collapsed));
  }

  /// Arrow keys: parent (left), first child (right, expanding if needed),
  /// previous / next sibling (up / down). The root is "null".
  void selectNeighbor(AxisDirection direction) {
    final c = content;
    final id = state.selectedCardId;
    final node = id == null ? null : c.node(id);
    if (id != null && node == null) return;
    String? target;
    var found = false;
    switch (direction) {
      case AxisDirection.left:
        if (id == null) return;
        target = node!.parentId;
        found = true;
      case AxisDirection.right:
        final children = c.childrenOf(id);
        if (children.isEmpty) return;
        if (node?.collapsed ?? false) toggleCollapsed(id!);
        target = children.first.cardId;
        found = true;
      case AxisDirection.up || AxisDirection.down:
        if (node == null) return;
        final siblings = c.childrenOf(node.parentId);
        final i = siblings.indexWhere((n) => n.cardId == id) + (direction == AxisDirection.up ? -1 : 1);
        if (i < 0 || i >= siblings.length) return;
        target = siblings[i].cardId;
        found = true;
    }
    if (found) selectCard(target);
  }

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

class _EditSession {
  const _EditSession(this.cardId, {required this.created, required this.previousSelection});

  final String cardId;

  /// The card was added for this edit inside an open transaction.
  final bool created;
  final String? previousSelection;
}

final workspaceProvider = NotifierProvider.family<WorkspaceController, WorkspaceState, String>(WorkspaceController.new);
