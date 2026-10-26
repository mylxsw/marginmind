import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart' show AxisDirection, Rect;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/providers.dart';
import '../../settings/app_settings.dart';

export '../../settings/app_settings.dart' show AnnotationTool;

enum MapViewMode { map, outline }

/// What the reader's page sidebar lists.
enum ReaderPanelMode { thumbnails, outline, bookmarks, annotations }

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

/// A clicked highlight: recolor, add to map / locate card, copy or delete.
class PendingHighlight extends PendingAction {
  const PendingHighlight(this.annotationId, [this.viewportRect = Rect.zero]);

  final String annotationId;
  final Rect viewportRect;
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

/// The dragged area could not be rendered or stored.
class AreaFailedNotice extends WorkspaceNotice {
  const AreaFailedNotice();
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
    this.activeMapId = MindMap.defaultId,
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
    this.tagFilter,
    this.selectedCardId,
    this.selectedCardIds = const {},
    this.flashCardId,
    this.flashAnnotationId,
    this.editingCardId,
    this.selectedMarkId,
    this.editingMarkId,
    this.connectingFromId,
    this.pending,
    this.reveal,
    this.currentPages = const {},
    this.canUndo = false,
    this.canRedo = false,
    this.readerPanelVisible = false,
    this.readerPanelMode = ReaderPanelMode.thumbnails,
    this.findVisible = false,
    this.findFocusTick = 0,
  });

  final String activeMapId;
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
  final String? tagFilter;

  /// Selected map node; null means the root.
  final String? selectedCardId;
  final Set<String> selectedCardIds;
  final String? flashCardId;
  final String? flashAnnotationId;

  /// Card whose title (a note's text) is being edited in place.
  final String? editingCardId;

  /// Selected relation or summary of the active map. Selecting a node
  /// clears it; selecting it clears the node selection.
  final String? selectedMarkId;

  /// Relation or summary whose label is being edited in place.
  final String? editingMarkId;

  /// A relation is being drawn from this card; the next node clicked ends it.
  final String? connectingFromId;
  final PendingAction? pending;
  final RevealRequest? reveal;

  /// Page currently shown per document (persisted as `lastPage`, debounced).
  final Map<String, int> currentPages;

  final bool canUndo;
  final bool canRedo;

  /// The reader's page sidebar (thumbnails, contents, bookmarks, highlights).
  final bool readerPanelVisible;
  final ReaderPanelMode readerPanelMode;

  /// The find-in-document bar is open; [findFocusTick] changes whenever the
  /// user asks for it again so the field takes focus and selects its text.
  final bool findVisible;
  final int findFocusTick;

  WorkspaceState copyWith({
    String? activeMapId,
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
    String? tagFilter,
    bool clearTagFilter = false,
    String? selectedCardId,
    Set<String>? selectedCardIds,
    bool selectRoot = false,
    String? flashCardId,
    String? flashAnnotationId,
    bool clearFlash = false,
    String? editingCardId,
    bool clearEditing = false,
    String? selectedMarkId,
    bool clearMark = false,
    String? editingMarkId,
    bool clearMarkEditing = false,
    String? connectingFromId,
    bool clearConnecting = false,
    PendingAction? pending,
    bool clearPending = false,
    RevealRequest? reveal,
    Map<String, int>? currentPages,
    bool? canUndo,
    bool? canRedo,
    bool? readerPanelVisible,
    ReaderPanelMode? readerPanelMode,
    bool? findVisible,
    int? findFocusTick,
  }) {
    return WorkspaceState(
      activeMapId: activeMapId ?? this.activeMapId,
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
      tagFilter: clearTagFilter ? null : (tagFilter ?? this.tagFilter),
      selectedCardIds: Set.unmodifiable(
        selectedCardIds ??
            (selectRoot
                ? <String>{}
                : selectedCardId != null
                ? {selectedCardId}
                : this.selectedCardIds),
      ),
      selectedCardId: selectRoot ? null : (selectedCardId ?? this.selectedCardId),
      flashCardId: clearFlash ? null : (flashCardId ?? this.flashCardId),
      flashAnnotationId: clearFlash ? null : (flashAnnotationId ?? this.flashAnnotationId),
      editingCardId: clearEditing ? null : (editingCardId ?? this.editingCardId),
      // Any change of the node selection deselects the mark.
      selectedMarkId: clearMark
          ? null
          : selectedMarkId ??
                (selectedCardId != null || selectedCardIds != null || selectRoot ? null : this.selectedMarkId),
      editingMarkId: clearMarkEditing ? null : (editingMarkId ?? this.editingMarkId),
      connectingFromId: clearConnecting ? null : (connectingFromId ?? this.connectingFromId),
      pending: clearPending ? null : (pending ?? this.pending),
      reveal: reveal ?? this.reveal,
      currentPages: currentPages ?? this.currentPages,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      readerPanelVisible: readerPanelVisible ?? this.readerPanelVisible,
      readerPanelMode: readerPanelMode ?? this.readerPanelMode,
      findVisible: findVisible ?? this.findVisible,
      findFocusTick: findFocusTick ?? this.findFocusTick,
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

  StudySetEditor get _editor {
    final editor = ref.read(editorProvider);
    return StudySetEditor(newId: editor.newId, now: editor.now, mapId: state.activeMapId);
  }

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
        if (_transactionDepth > 0 || _clipboardBusy || from.isEmpty) return null;
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
    final mapId = c.map(s.activeMapId) != null ? s.activeMapId : (c.maps.firstOrNull?.id ?? MindMap.defaultId);
    final selectionGone = s.selectedCardId != null && c.node(s.selectedCardId!, mapId: mapId) == null;
    final selectedIds = s.selectedCardIds.where((id) => c.node(id, mapId: mapId) != null).toSet();
    final selectedId = selectionGone ? selectedIds.lastOrNull : s.selectedCardId;
    final mark = s.selectedMarkId != null && _markExists(c, mapId, s.selectedMarkId!) ? s.selectedMarkId : null;
    final connecting = s.connectingFromId != null && c.node(s.connectingFromId!, mapId: mapId) != null;
    return s.copyWith(
      selectedMarkId: mark,
      clearMark: mark == null,
      clearConnecting: !connecting,
      activeMapId: mapId,
      openDocumentIds: open,
      activeDocumentId: active,
      clearActive: active == null,
      selectRoot: selectedId == null,
      selectedCardId: selectedId,
      selectedCardIds: selectedIds,
    );
  }

  static bool _markExists(StudySetContent c, String mapId, String id) =>
      c.relationsOf(mapId).any((r) => r.id == id) || c.summariesOf(mapId).any((s) => s.$1.id == id);

  /// Switch only after queued writes; inline editors must finish first.
  Future<void> selectMap(String id) async {
    if (_creating || _editing != null || _markEditing != null || _clipboardBusy) return;
    await _enqueue(() async {
      if (!ref.mounted || _clipboardBusy || content.map(id) == null) return;
      state = state.copyWith(
        activeMapId: id,
        selectRoot: true,
        clearConnecting: true,
        clearEditing: true,
        clearPending: true,
        clearFlash: true,
      );
    });
  }

  Future<void> addMap(String title) async {
    if (title.trim().isEmpty || _editing != null || _creating || _clipboardBusy) return;
    String? id;
    await _update((c) {
      final (next, map) = _editor.addMap(c, title: title);
      id = map.id;
      return next;
    });
    if (ref.mounted && id != null) await selectMap(id!);
  }

  Future<void> renameMap(String id, String title) async {
    if (title.trim().isEmpty || _editing != null || _creating || _clipboardBusy) return;
    await _update((c) => _editor.renameMap(c, id, title));
  }

  Future<void> removeMap(String id) async {
    if (_editing != null || _creating || _clipboardBusy) return;
    await _update((c) => _editor.removeMap(c, id));
  }

  Future<void> placeCardInMap(String cardId, String mapId) async {
    if (_editing != null || _creating || _clipboardBusy) return;
    final editor = _editor;
    await _update((c) => StudySetEditor(newId: editor.newId, now: editor.now, mapId: mapId).placeCard(c, cardId));
  }

  // ---- panels ---------------------------------------------------------------

  void toggleSidebar() => state = state.copyWith(sidebarVisible: !state.sidebarVisible);

  void toggleReaderPanel() => state = state.copyWith(readerPanelVisible: !state.readerPanelVisible);

  /// Opens the reader sidebar on [mode] (the source pane comes back in
  /// map-only layout, since the user asked for it).
  void showReaderPanel(ReaderPanelMode mode) => state = state.copyWith(
    readerPanelVisible: true,
    readerPanelMode: mode,
    layout: state.layout == MMSplitMode.secondary ? MMSplitMode.split : null,
  );

  void setReaderPanelMode(ReaderPanelMode mode) => state = state.copyWith(readerPanelMode: mode);

  /// Opens the find bar of the active document (or focuses it again).
  void openFind() {
    if (state.activeDocumentId == null) return;
    state = state.copyWith(
      findVisible: true,
      findFocusTick: state.findFocusTick + 1,
      layout: state.layout == MMSplitMode.secondary ? MMSplitMode.split : null,
    );
  }

  void closeFind() => state = state.copyWith(findVisible: false);

  void setLayout(MMSplitMode layout) => state = state.copyWith(layout: layout);

  void setSplitFraction(double value) => state = state.copyWith(splitFraction: value.clamp(0.1, 0.9));

  void setMapView(MapViewMode view) => state = state.copyWith(mapView: view);

  Future<void> setTool(AnnotationTool tool) {
    if (state.tool != tool) state = state.copyWith(tool: tool, clearPending: true);
    return ref.read(settingsProvider.notifier).setAnnotationTool(tool);
  }

  Future<void> toggleTool() =>
      setTool(state.tool == AnnotationTool.highlight ? AnnotationTool.select : AnnotationTool.highlight);

  Future<void> toggleAreaTool() =>
      setTool(state.tool == AnnotationTool.area ? AnnotationTool.select : AnnotationTool.area);

  /// Picking a color arms the highlighter; the area tool keeps going and
  /// frames new areas in that color.
  Future<void> setColor(MMAnnotationColor color) {
    state = state.copyWith(color: color);
    return state.tool == AnnotationTool.area ? Future.value() : setTool(AnnotationTool.highlight);
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
      findVisible: id == state.activeDocumentId ? null : false,
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
      findVisible: wasActive ? false : null,
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

  /// The active map as Markdown or OPML. [source] labels excerpt sources,
  /// [summary] summary lines and [relationsTitle] the list of relations.
  String export({
    required bool opml,
    required String rootTitle,
    required String Function(Document, int) source,
    String Function(String label)? summary,
    String relationsTitle = 'Relationships',
  }) {
    final exporter = MapExporter(
      content,
      mapId: state.activeMapId,
      rootTitle: content.map(state.activeMapId)?.title.isNotEmpty == true
          ? content.map(state.activeMapId)!.title
          : rootTitle,
      source: source,
      summary: summary,
      relationsTitle: relationsTitle,
    );
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

  // ---- bookmarks ---------------------------------------------------------------

  /// The page of the active document the reader is on.
  int? get activePage {
    final doc = state.activeDocumentId == null ? null : content.document(state.activeDocumentId!);
    return doc == null ? null : (state.currentPages[doc.id] ?? doc.lastPage);
  }

  /// ⌘D: bookmarks the page being read, or removes the bookmark it has.
  Future<void> toggleBookmark() async {
    final documentId = state.activeDocumentId;
    final page = activePage;
    if (documentId == null || page == null) return;
    await _update((c) => _editor.toggleBookmark(c, documentId, page));
  }

  Future<void> renameBookmark(String id, String title) => _update((c) => _editor.renameBookmark(c, id, title));

  Future<void> removeBookmark(String id) => _update((c) => _editor.removeBookmark(c, id));

  // ---- excerpts and highlights ------------------------------------------------

  /// Where a new excerpt goes, and that node's title (null = root).
  String? get excerptTargetId => StudySetEditor.excerptTarget(content, state.selectedCardId, mapId: state.activeMapId);

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

  Future<ExcerptedNotice> excerpt(String documentId, MMPdfSelection s, MMAnnotationColor color, {String? note}) async {
    final parent = excerptTargetId;
    late Card card;
    await _update((c) {
      final (next, created) = _editor.createExcerpt(
        c,
        documentId: documentId,
        pages: s.pages,
        quote: s.text,
        colorIndex: color.index,
        parentId: parent,
      );
      card = created;
      return note == null ? next : _editor.addNote(next, text: note, parentId: card.id).$1;
    });
    state = state.copyWith(clearPending: true);
    _flash(cardId: card.id);
    return ExcerptedNotice(parent == null ? null : content.card(parent)?.title);
  }

  Future<HighlightedNotice> highlight(String documentId, MMPdfSelection s, MMAnnotationColor color) async {
    await _update(
      (c) => _editor.highlight(c, documentId: documentId, pages: s.pages, quote: s.text, colorIndex: color.index).$1,
    );
    state = state.copyWith(clearPending: true);
    return const HighlightedNotice();
  }

  /// An area dragged with the area tool becomes an image excerpt at once.
  /// [capture] renders the area as PNG; the image is stored in the package
  /// before the (undoable) card is added.
  Future<WorkspaceNotice> excerptArea(String documentId, MMPdfArea area, Future<Uint8List?> Function() capture) async {
    final String imageFileName;
    try {
      final png = await capture();
      if (png == null) return const AreaFailedNotice();
      imageFileName = await _repo.importImageBytes(studySetId, png);
    } catch (_) {
      return const AreaFailedNotice();
    }
    if (!ref.mounted || content.document(documentId) == null) return const AreaFailedNotice();
    final parent = excerptTargetId;
    late Card card;
    await _update((c) {
      final (next, created) = _editor.createAreaExcerpt(
        c,
        documentId: documentId,
        page: area.page,
        rect: area.rect,
        imageFileName: imageFileName,
        colorIndex: state.color.index,
        parentId: parent,
      );
      card = created;
      return next;
    });
    state = state.copyWith(clearPending: true);
    _flash(cardId: card.id);
    return ExcerptedNotice(parent == null ? null : content.card(parent)?.title);
  }

  /// Absolute path of an image stored in this study set.
  String imagePath(String imageFileName) => _repo.resolveFile(studySetId, imageFileName);

  void dismissPending() => state = state.copyWith(clearPending: true);

  /// A highlight on the page was clicked.
  void tapHighlight(String annotationId, [Rect viewportRect = Rect.zero]) {
    if (content.annotation(annotationId) == null) return;
    state = state.copyWith(pending: PendingHighlight(annotationId, viewportRect));
  }

  Future<void> locateHighlightCard(String annotationId) async {
    final card = content.cardForAnnotation(annotationId);
    if (card == null || content.node(card.id, mapId: state.activeMapId) == null) return;
    await _update((c) => _expandAncestors(c, card.id), undoable: false);
    state = state.copyWith(
      selectedCardId: card.id,
      clearPending: true,
      mapView: MapViewMode.map,
      layout: state.layout == MMSplitMode.primary ? MMSplitMode.split : null,
    );
    _flash(cardId: card.id);
  }

  StudySetContent _expandAncestors(StudySetContent c, String cardId) {
    var parent = c.node(cardId, mapId: state.activeMapId)?.parentId;
    final seen = <String>{};
    while (parent != null && seen.add(parent)) {
      final node = c.node(parent, mapId: state.activeMapId);
      if (node == null) break;
      if (node.collapsed) c = _editor.setCollapsed(c, parent, collapsed: false);
      parent = node.parentId;
    }
    return c;
  }

  Future<ExcerptedNotice> addHighlightToMap(String annotationId) async {
    final parent = excerptTargetId;
    late Card card;
    await _update((c) {
      final (next, created) = _editor.attachCard(c, annotationId, parentId: parent);
      card = created;
      return _expandAncestors(next, card.id);
    });
    state = state.copyWith(
      mapView: MapViewMode.map,
      clearPending: true,
      selectedCardId: card.id,
      layout: state.layout == MMSplitMode.primary ? MMSplitMode.split : null,
    );
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

  /// Modifier-click toggles membership; normal navigation selects just one.
  void toggleCardSelection(String cardId) {
    final ids = {...state.selectedCardIds};
    if (!ids.remove(cardId)) ids.add(cardId);
    selectCards(ids);
  }

  void selectCards(Iterable<String> cardIds) {
    final ids = cardIds.where((id) => content.node(id, mapId: state.activeMapId) != null).toSet();
    state = state.copyWith(selectedCardIds: ids, selectedCardId: ids.lastOrNull, selectRoot: ids.isEmpty);
  }

  bool _clipboardBusy = false;

  /// Cut removes exactly the copied selection, only after a successful write.
  Future<void> copySelection({bool cut = false}) async {
    if (_editing != null || _creating || _clipboardBusy) return;
    final ids = state.selectedCardIds.toList();
    final entries = MapClipboard.copy(content, ids, mapId: state.activeMapId, resolveImage: imagePath);
    if (entries.isEmpty) return;
    _clipboardBusy = true;
    try {
      await MMMapClipboard.write(text: MapClipboard.toText(entries), internal: MapClipboard.encode(entries));
      if (cut && ref.mounted && _editing == null && !_creating) await removeCards(ids);
    } finally {
      _clipboardBusy = false;
    }
  }

  Future<void> pasteSelection() async {
    if (_editing != null || _creating || _clipboardBusy) return;
    final parent = state.selectedCardId;
    _clipboardBusy = true;
    try {
      final data = await MMMapClipboard.read();
      if (!ref.mounted || _editing != null || _creating) return;
      final entries =
          (data.internal == null ? null : MapClipboard.decode(data.internal!)) ?? MapClipboard.fromText(data.text);
      if (entries.isEmpty) return;
      final images = await _importClipboardImages(entries);
      if (!ref.mounted || _editing != null || _creating) return;
      var roots = <String>[];
      await _update((c) {
        final (next, ids) = _editor.paste(c, entries, parentId: parent, images: images);
        roots = ids;
        return next;
      });
      if (ref.mounted && roots.isNotEmpty) selectCards(roots);
    } finally {
      _clipboardBusy = false;
    }
  }

  /// Copies images of another study set into this package. Only paths that
  /// end in the entry's own content-addressed name are read; unreadable or
  /// invalid files leave the entry to become a note.
  Future<Map<String, String>> _importClipboardImages(List<OutlineEntry> entries) async {
    final images = <String, String>{};
    for (final e in entries) {
      final name = e.imageFileName;
      final path = e.imagePath;
      if (e.kind != CardKind.image || name == null || path == null || images.containsKey(name)) continue;
      if (!_imageName.hasMatch(name) || !path.replaceAll(r'\', '/').endsWith('/$name')) continue;
      if (!await File(path).exists()) continue;
      try {
        images[name] = await _repo.importImage(studySetId, path);
      } catch (_) {}
    }
    return images;
  }

  static final _imageName = RegExp(r'^images/[0-9a-f]{64}\.(png|jpg)$');

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

  void filterTag(String? tag) => state = state.copyWith(tagFilter: tag, clearTagFilter: tag == null);

  Future<void> setTags(String cardId, Iterable<String> tags) {
    final values = tags.toList();
    return _update((c) => _editor.setTags(c, cardId, values));
  }

  Future<void> rename(String cardId, String title) => _update((c) => _editor.rename(c, cardId, title));

  // ---- in-place editing -------------------------------------------------------

  _EditSession? _editing;

  /// A card is being created for editing; no other edit may start yet.
  bool _creating = false;

  /// Starts editing a card's title (a note's text) in place. Nothing is
  /// written until [finishEditing], so the whole edit is one undo step.
  void beginEditing(String cardId) {
    if (_editing != null || _markEditing != null || _creating || content.card(cardId) == null) return;
    _editing = _EditSession(cardId, created: false, previousSelection: state.selectedCardId);
    state = state.copyWith(selectedCardId: cardId, editingCardId: cardId, layout: _layoutShowingMap);
  }

  /// A field opens in the map pane: with the reader alone on screen the
  /// pane comes back, so the edit can take focus and be finished.
  MMSplitMode? get _layoutShowingMap => state.layout == MMSplitMode.primary ? MMSplitMode.split : null;

  /// Adds a topic (see [addTopic]) and starts editing it. Creation and the
  /// typed title commit as one undo step; cancelling leaves no node and no
  /// history.
  Future<Card?> addTopicAndEdit(String title, {bool asChild = false, bool? siblingBefore, bool asParent = false}) {
    if ((siblingBefore != null || asParent) && state.selectedCardId == null) return Future.value();
    return _createAndEdit((previous) async {
      if (siblingBefore != null || asParent) {
        Card? created;
        await _update((c) {
          final (next, added) = asParent
              ? _editor.insertParent(c, previous, title: title)
              : _editor.insertSibling(c, previous, title: title, before: siblingBefore!);
          created = added;
          return next;
        });
        if (created != null) state = state.copyWith(selectedCardId: created!.id);
        return created;
      }
      final card = await addTopic(title, asChild: asChild);
      // A child added beneath a folded node must be visible for editing.
      final parent = content.node(card.id, mapId: state.activeMapId)?.parentId;
      if (parent != null) {
        await _update((c) => _editor.setCollapsed(c, parent, collapsed: false));
      }
      return card;
    });
  }

  /// Adds a note under the selection (see [addNote]) and starts editing its
  /// text, as one undo step like [addTopicAndEdit].
  Future<Card?> addNoteAndEdit(String text) => _createAndEdit((_) => addNote(text));

  /// Runs [create] (given the selection before it) in a transaction and opens
  /// the created card for editing. A null card aborts the transaction.
  Future<Card?> _createAndEdit(Future<Card?> Function(String? previous) create) async {
    if (_editing != null || _markEditing != null || _creating) return null;
    _creating = true;
    final previous = state.selectedCardId;
    final Card? card;
    try {
      await beginTransaction();
      try {
        card = await create(previous);
      } catch (_) {
        await abortTransaction();
        rethrow;
      }
      if (card == null) {
        await abortTransaction();
        return null;
      }
    } finally {
      _creating = false;
    }
    _editing = _EditSession(card.id, created: true, previousSelection: previous);
    state = state.copyWith(editingCardId: card.id, layout: _layoutShowingMap);
    return card;
  }

  /// Enter or clicking elsewhere. An empty title keeps the old one (an
  /// excerpt's is cleared), or drops a node created for this edit.
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
      } else if (content.card(session.cardId) case final card?
          when (title.isNotEmpty || card.kind == CardKind.excerpt || card.kind == CardKind.image) &&
              title != card.title) {
        // An excerpt's title is optional: clearing it shows the quote (or
        // the image's default label) again.
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

  Future<void> promoteSelected() async {
    if (_editing != null || _creating) return;
    final id = state.selectedCardId;
    if (id != null) await _update((c) => _editor.promote(c, id));
  }

  Future<void> toggleCollapsed(String cardId) {
    final node = content.node(cardId, mapId: state.activeMapId);
    if (node == null || content.childrenOf(cardId, mapId: state.activeMapId).isEmpty) return Future.value();
    return _update((c) => _editor.setCollapsed(c, cardId, collapsed: !node.collapsed));
  }

  /// Arrow keys: parent (left), first child (right, expanding if needed),
  /// previous / next sibling (up / down). The root is "null".
  void selectNeighbor(AxisDirection direction) {
    final c = content;
    final id = state.selectedCardId;
    final node = id == null ? null : c.node(id, mapId: state.activeMapId);
    if (id != null && node == null) return;
    String? target;
    var found = false;
    switch (direction) {
      case AxisDirection.left:
        if (id == null) return;
        target = node!.parentId;
        found = true;
      case AxisDirection.right:
        final children = c.childrenOf(id, mapId: state.activeMapId);
        if (children.isEmpty) return;
        if (node?.collapsed ?? false) toggleCollapsed(id!);
        target = children.first.cardId;
        found = true;
      case AxisDirection.up || AxisDirection.down:
        if (node == null) return;
        final siblings = c.childrenOf(node.parentId, mapId: state.activeMapId);
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
    final parent = content.node(id, mapId: state.activeMapId)?.parentId;
    await removeCards(state.selectedCardIds.isEmpty ? [id] : state.selectedCardIds);
    selectCard(parent != null && content.node(parent, mapId: state.activeMapId) != null ? parent : null);
    return const RemovedNotice();
  }

  // ---- relations and summaries ------------------------------------------------

  _MarkEditSession? _markEditing;

  /// Selects a relation or summary (null deselects it, keeping no node).
  void selectMark(String? id) {
    if (id == null) {
      state = state.copyWith(clearMark: true, clearConnecting: true);
      return;
    }
    if (!_markExists(content, state.activeMapId, id)) return;
    state = state.copyWith(selectRoot: true, selectedMarkId: id, clearConnecting: true);
  }

  /// With two nodes selected, relates the first to the second. With one, a
  /// line starts there and ends at the next node clicked ([connectTo]).
  Future<void> addRelation() async {
    if (_editing != null || _markEditing != null || _creating || _clipboardBusy) return;
    final ids = state.selectedCardIds.isEmpty
        ? [?state.selectedCardId]
        : [...state.selectedCardIds.where((id) => id != state.selectedCardId), ?state.selectedCardId];
    if (ids.length == 2) return _relate(ids.first, ids.last);
    if (ids.length == 1) state = state.copyWith(connectingFromId: ids.single);
  }

  Future<void> connectTo(String cardId) async {
    final from = state.connectingFromId;
    if (from == null) return;
    state = state.copyWith(clearConnecting: true);
    if (from == cardId) return;
    await _relate(from, cardId);
  }

  void cancelConnecting() => state = state.copyWith(clearConnecting: true);

  /// Draws the line and opens its label for typing; the label is optional.
  Future<void> _relate(String fromId, String toId) async {
    MapRelation? created;
    await _update((c) {
      final (next, relation) = _editor.addRelation(c, fromId, toId);
      created = relation;
      return next;
    });
    if (created == null || !ref.mounted) return;
    state = state.copyWith(selectRoot: true, selectedMarkId: created!.id);
    beginMarkEditing(created!.id);
  }

  /// Sums up the selected siblings and opens the label for typing. Creation
  /// and label are one undo step; Esc or an empty label leaves nothing.
  Future<void> addSummaryAndEdit(String label) async {
    if (_editing != null || _markEditing != null || _creating || _clipboardBusy) return;
    final ids = state.selectedCardIds.isEmpty ? [?state.selectedCardId] : state.selectedCardIds.toList();
    if (ids.isEmpty) return;
    _creating = true;
    MapSummary? created;
    try {
      await beginTransaction();
      try {
        await _update((c) {
          final (next, summary) = _editor.addSummary(c, ids, label: label);
          created = summary;
          return next;
        });
      } catch (_) {
        await abortTransaction();
        rethrow;
      }
      if (created == null) {
        await abortTransaction();
        return;
      }
    } finally {
      _creating = false;
    }
    if (!ref.mounted) return;
    _markEditing = _MarkEditSession(created!.id, created: true);
    state = state.copyWith(selectRoot: true, selectedMarkId: created!.id, editingMarkId: created!.id);
  }

  void beginMarkEditing(String id) {
    if (_editing != null || _markEditing != null || _creating || !_markExists(content, state.activeMapId, id)) return;
    _markEditing = _MarkEditSession(id, created: false);
    state = state.copyWith(selectRoot: true, selectedMarkId: id, editingMarkId: id, layout: _layoutShowingMap);
  }

  /// Enter or clicking elsewhere. An empty label clears it, or drops a
  /// summary created for this edit.
  Future<void> finishMarkEditing(String text) async {
    final session = _markEditing;
    if (session == null) return;
    _markEditing = null;
    final label = text.trim();
    try {
      if (session.created && label.isEmpty) {
        await abortTransaction();
      } else {
        try {
          await _update((c) => _relabel(c, session.id, label));
        } finally {
          if (session.created) await commitTransaction();
        }
      }
    } finally {
      if (ref.mounted) state = state.copyWith(clearMarkEditing: true);
    }
  }

  /// Esc: keeps the old label, or drops a summary created for this edit.
  Future<void> cancelMarkEditing() async {
    final session = _markEditing;
    if (session == null) return;
    _markEditing = null;
    try {
      if (session.created) await abortTransaction();
    } finally {
      if (ref.mounted) state = state.copyWith(clearMarkEditing: true);
    }
  }

  StudySetContent _relabel(StudySetContent c, String id, String label) {
    final relation = c.relations.where((r) => r.id == id).firstOrNull;
    if (relation != null) return relation.label == label ? c : _editor.relabelRelation(c, id, label);
    final summary = c.summaries.where((s) => s.id == id).firstOrNull;
    return summary == null || summary.label == label ? c : _editor.relabelSummary(c, id, label);
  }

  /// Deletes the selected relation or summary (one undo step).
  Future<void> removeSelectedMark() async {
    final id = state.selectedMarkId;
    if (id == null || _markEditing != null) return;
    await _update((c) => _editor.removeSummary(_editor.removeRelation(c, id), id));
    if (ref.mounted) state = state.copyWith(clearMark: true);
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

class _MarkEditSession {
  const _MarkEditSession(this.id, {required this.created});

  final String id;

  /// The summary was added for this edit inside an open transaction.
  final bool created;
}

final workspaceProvider = NotifierProvider.family<WorkspaceController, WorkspaceState, String>(WorkspaceController.new);
