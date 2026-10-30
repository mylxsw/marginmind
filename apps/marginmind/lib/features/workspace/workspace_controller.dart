import 'source_selection.dart';
export 'source_selection.dart';
import '../../app/app_commands.dart' show ReaderSelectionCommand;
import 'document_import.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show AxisDirection, Rect;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/providers.dart';
import '../../settings/app_settings.dart';
import '../../settings/highlight_palette.dart';

export '../../settings/app_settings.dart' show AnnotationTool;

enum MapViewMode { map, outline }

/// What the right panel shows. One panel, one content at a time.
enum RightPanel { assistant, details }

/// Where the right panel was opened from: in split layout the other pane
/// steps aside (the map for the source, the source for the map).
enum PanelOrigin { reader, map, toolbar }

/// What the right panel's closing restores.
typedef _PanelRestore = ({MMSplitMode layout, bool sidebarVisible});

/// What the reader's page sidebar lists.
enum ReaderPanelMode { thumbnails, outline, bookmarks, annotations }

/// Something the source pane is waiting on the user to decide.
sealed class PendingAction {
  const PendingAction();

  /// Keep the settings panel mounted when a selection becomes a saved mark.
  Object get toolbarIdentity => this;
}

/// Text selected with the Select tool: choose excerpt / highlight / copy.
class PendingSelection extends PendingAction {
  PendingSelection(this.documentId, MMPdfSelection selection) : selection = SourceSelection.pdf(selection);
  const PendingSelection.source(this.documentId, this.selection);

  final String documentId;
  final SourceSelection selection;
}

/// A clicked highlight: recolor, add to map / locate card, copy or delete.
class PendingHighlight extends PendingAction {
  const PendingHighlight(this.annotationId, [this.viewportRect = Rect.zero]) : _toolbarIdentity = null;
  const PendingHighlight.fromSelection(this.annotationId, this.viewportRect, this._toolbarIdentity);

  final String annotationId;
  final Rect viewportRect;
  final Object? _toolbarIdentity;

  @override
  Object get toolbarIdentity => _toolbarIdentity ?? this;
}

/// A research note's mark in the source was clicked: its card pops up.
class PendingResearchNote extends PendingAction {
  const PendingResearchNote(this.attachmentId, [this.viewportRect = Rect.zero]);

  final String attachmentId;
  final Rect viewportRect;
}

/// The id a research note's attachment is drawn under in the source, so
/// clicks on it can be told from clicks on highlights.
String noteMarkId(String attachmentId) => 'note:$attachmentId';

/// What a research note was saved to, for the HUD: [cardId] when the map
/// got a card, [inSource] when the source got a mark.
class ResearchNoteSavedNotice extends WorkspaceNotice {
  const ResearchNoteSavedNotice({required this.noteId, this.cardId, required this.inSource});

  final String noteId;
  final String? cardId;
  final bool inSource;
}

/// Ask the source pane to scroll to a highlight.
class RevealRequest {
  const RevealRequest(this.documentId, int page, this.rects, this.nonce) : _page = page, textAnchors = const [];
  const RevealRequest.text(this.documentId, this.textAnchors, this.nonce) : _page = null, rects = const [];
  final List<TextAnchor> textAnchors;

  final String documentId;
  final int? _page;
  int get page => _page ?? (throw StateError('Text reveal has no page'));
  final List<PageRect> rects;
  final int nonce;
}

/// Outcomes worth telling the user about (shown as HUD by the UI, which
/// owns the wording).
sealed class WorkspaceNotice {
  const WorkspaceNotice();
}

class ExcerptedNotice extends WorkspaceNotice {
  const ExcerptedNotice(this.targetTitle, {this.cardId});

  final String? targetTitle;

  /// The new card, for showing it in the map.
  final String? cardId;
}

class UnderlinedNotice extends WorkspaceNotice {
  const UnderlinedNotice();
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
  const HighlightDeletedNotice({this.underline = false});
  final bool underline;
}

class UndoneNotice extends WorkspaceNotice {
  const UndoneNotice({required this.redo});

  final bool redo;
}

class DocumentRemovedNotice extends WorkspaceNotice {
  const DocumentRemovedNotice();
}

class ImportedNotice extends WorkspaceNotice {
  const ImportedNotice(this.count, this.failed, {this.errors = const {}});
  final Map<String, DocumentImportError> errors;

  final int count;
  final List<String> failed;
}

/// Live reading positions do not invalidate workspace layout or native menus.
final readingPagesProvider = NotifierProvider.family<ReadingPages, Map<String, int>, String>(ReadingPages.new);

class ReadingPages extends Notifier<Map<String, int>> {
  ReadingPages(this.studySetId);
  final String studySetId;
  @override
  Map<String, int> build() => const {};
  void record(String id, int page) => state = {...state, id: page};
}

class WorkspaceState {
  const WorkspaceState({
    this.content,
    this.activeMapId = MindMap.defaultId,
    this.sidebarVisible = true,
    this.layout = MMSplitMode.split,
    this.splitFraction = 0.5,
    this.mapView = MapViewMode.map,
    this.tool = AnnotationTool.select,
    this.color = MMAnnotationColor.yellow,
    this.underlineStyle = AnnotationLineStyle.solid,
    this.syncToMap = true,
    this.inkTool = MMPdfInkTool.freehand,
    this.inkColor = MMInkColor.red,
    this.inkWidth = MMInkWidth.medium,
    this.openDocumentIds = const [],
    this.activeDocumentId,
    this.sidebarQuery = '',
    this.tagFilter,
    this.selectedCardId,
    this.rootSelected = false,
    this.selectedCardIds = const {},
    this.flashCardId,
    this.flashCardIds = const {},
    this.locateCardTick = 0,
    this.flashAnnotationId,
    this.editingCardId,
    this.selectedMarkId,
    this.editingMarkId,
    this.connectingFromId,
    this.pending,
    this.reveal,
    this.canUndo = false,
    this.canRedo = false,
    this.sidebarAutoCollapsed = false,
    this.readerPanelVisible = false,
    this.readerPanelMode = ReaderPanelMode.thumbnails,
    this.findVisible = false,
    this.findFocusTick = 0,
    this.panel,
    this.detailCardId,
    this.expandedCardIds = const {},
  });

  /// Latest repository snapshot, including completed writes before stream delivery.
  final StudySetContent? content;

  final String activeMapId;
  final bool sidebarVisible;
  final MMSplitMode layout;
  final double splitFraction;
  final MapViewMode mapView;
  final AnnotationTool tool;
  final MMAnnotationColor color;
  final AnnotationLineStyle underlineStyle;

  /// Whether a new highlight also creates a card in the mind map.
  final bool syncToMap;

  /// The pen's shape, color and width while [tool] is [AnnotationTool.ink].
  final MMPdfInkTool inkTool;
  final MMInkColor inkColor;
  final MMInkWidth inkWidth;

  /// What [MMPdfView.ink] gets: the pen, or null when not drawing.
  MMPdfInk? get ink =>
      tool == AnnotationTool.ink ? MMPdfInk(tool: inkTool, colorIndex: inkColor.index, width: inkWidth.points) : null;
  final List<String> openDocumentIds;
  final String? activeDocumentId;
  final String sidebarQuery;
  final String? tagFilter;

  /// Selected card, or null when no card is selected.
  final String? selectedCardId;

  /// The map root is selected explicitly, independently of the default insertion parent.
  final bool rootSelected;
  final Set<String> selectedCardIds;
  final String? flashCardId;
  final Set<String> flashCardIds;
  final int locateCardTick;
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

  final bool canUndo;
  final bool canRedo;

  /// The window is too narrow for the sidebar beside the map, so it is not on
  /// screen although [sidebarVisible] is set. Reported by the screen, not saved.
  final bool sidebarAutoCollapsed;

  /// The reader's page sidebar (thumbnails, contents, bookmarks, highlights).
  final bool readerPanelVisible;
  final ReaderPanelMode readerPanelMode;

  /// The find-in-document bar is open; [findFocusTick] changes whenever the
  /// user asks for it again so the field takes focus and selects its text.
  final bool findVisible;
  final int findFocusTick;

  /// The right panel, or null when it is closed.
  final RightPanel? panel;

  /// The card the details show when no card is selected: the last one they
  /// showed. While a card is selected the details follow the selection.
  final String? detailCardId;

  /// Cards shown with their full text on the map. A view choice: never saved.
  final Set<String> expandedCardIds;

  /// The card the details panel shows.
  String? get detailsCardId => selectedCardId ?? detailCardId;

  WorkspaceState copyWith({
    StudySetContent? content,
    String? activeMapId,
    bool? sidebarVisible,
    MMSplitMode? layout,
    double? splitFraction,
    MapViewMode? mapView,
    AnnotationTool? tool,
    MMAnnotationColor? color,
    AnnotationLineStyle? underlineStyle,
    bool? syncToMap,
    MMPdfInkTool? inkTool,
    MMInkColor? inkColor,
    MMInkWidth? inkWidth,
    List<String>? openDocumentIds,
    String? activeDocumentId,
    bool clearActive = false,
    String? sidebarQuery,
    String? tagFilter,
    bool clearTagFilter = false,
    String? selectedCardId,
    Set<String>? selectedCardIds,
    bool selectRoot = false,
    bool? rootSelected,
    String? flashCardId,
    Set<String>? flashCardIds,
    int? locateCardTick,
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
    bool clearReveal = false,
    bool? canUndo,
    bool? canRedo,
    bool? sidebarAutoCollapsed,
    bool? readerPanelVisible,
    ReaderPanelMode? readerPanelMode,
    bool? findVisible,
    int? findFocusTick,
    RightPanel? panel,
    bool closePanel = false,
    String? detailCardId,
    Set<String>? expandedCardIds,
  }) {
    return WorkspaceState(
      content: content ?? this.content,
      activeMapId: activeMapId ?? this.activeMapId,
      sidebarVisible: sidebarVisible ?? this.sidebarVisible,
      layout: layout ?? this.layout,
      splitFraction: splitFraction ?? this.splitFraction,
      mapView: mapView ?? this.mapView,
      tool: tool ?? this.tool,
      color: color ?? this.color,
      underlineStyle: underlineStyle ?? this.underlineStyle,
      syncToMap: syncToMap ?? this.syncToMap,
      inkTool: inkTool ?? this.inkTool,
      inkColor: inkColor ?? this.inkColor,
      inkWidth: inkWidth ?? this.inkWidth,
      openDocumentIds: openDocumentIds ?? this.openDocumentIds,
      activeDocumentId: clearActive ? null : (activeDocumentId ?? this.activeDocumentId),
      sidebarQuery: sidebarQuery ?? this.sidebarQuery,
      tagFilter: clearTagFilter ? null : (tagFilter ?? this.tagFilter),
      selectedCardIds: selectedCardIds != null
          ? Set.unmodifiable(selectedCardIds)
          : selectRoot
          ? const {}
          : selectedCardId != null
          ? Set.unmodifiable({selectedCardId})
          : this.selectedCardIds,
      selectedCardId: selectRoot ? null : (selectedCardId ?? this.selectedCardId),
      rootSelected:
          rootSelected ??
          (selectRoot || selectedCardId != null || selectedCardIds != null || selectedMarkId != null
              ? false
              : this.rootSelected),
      locateCardTick: locateCardTick ?? this.locateCardTick,
      flashCardId: clearFlash ? null : (flashCardId ?? this.flashCardId),
      flashCardIds: clearFlash ? const {} : (flashCardIds ?? this.flashCardIds),
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
      reveal: clearReveal ? null : reveal ?? this.reveal,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      sidebarAutoCollapsed: sidebarAutoCollapsed ?? this.sidebarAutoCollapsed,
      readerPanelVisible: readerPanelVisible ?? this.readerPanelVisible,
      readerPanelMode: readerPanelMode ?? this.readerPanelMode,
      findVisible: findVisible ?? this.findVisible,
      findFocusTick: findFocusTick ?? this.findFocusTick,
      panel: closePanel ? null : (panel ?? this.panel),
      // Open details follow the selection, and keep the last card shown.
      detailCardId:
          detailCardId ??
          (!closePanel && (panel ?? this.panel) == RightPanel.details && !selectRoot
              ? selectedCardId ?? this.selectedCardId ?? this.detailCardId
              : this.detailCardId),
      expandedCardIds: expandedCardIds != null ? Set.unmodifiable(expandedCardIds) : this.expandedCardIds,
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
  final _pageTimers = <String, Timer>{};
  ({MMSplitMode layout, bool sidebar, bool readerPanel})? _compareRestore;
  int? _deliveredPdfReveal;

  /// A source route may mount after its reveal was requested. Keep delivery
  /// across reader remounts so returning later preserves the user's new place.
  bool claimPdfReveal(int nonce) {
    if (_deliveredPdfReveal == nonce) return false;
    _deliveredPdfReveal = nonce;
    return true;
  }

  int _revealNonce = 0;

  @override
  WorkspaceState build() {
    ref.onDispose(() {
      _flashTimer?.cancel();
      for (final timer in _pageTimers.values) {
        timer.cancel();
      }
    });
    ref.listen(contentProvider(studySetId), (_, next) {
      final c = next.value;
      if (c == null) return;
      // Events can have been queued before a completed write. Read the
      // current repository snapshot instead of installing that old payload.
      unawaited(_refreshContent());
    });
    ref.listen(settingsProvider.select((s) => s.annotationTool), (_, tool) {
      if (state.tool != tool) state = state.copyWith(tool: tool, clearPending: true);
    });
    ref.listen(highlightPaletteProvider.select((s) => s.current), (_, color) {
      if (state.color != color) state = state.copyWith(color: color);
    });
    ref.listen(settingsProvider.select((s) => s.underlineStyle), (_, style) {
      state = state.copyWith(underlineStyle: style);
    });
    final initialState = WorkspaceState(
      tool: ref.read(settingsProvider).annotationTool,
      color: ref.read(highlightPaletteProvider).current,
      underlineStyle: ref.read(settingsProvider).underlineStyle,
    );
    final initial = ref.read(contentProvider(studySetId)).value;
    return initial == null ? initialState : _withTabs(initialState.copyWith(content: initial), initial);
  }

  int _contentRequest = 0;
  Future<void>? _contentRefresh;

  StudySetContent get content => state.content ?? StudySetContent.empty;

  void _publishContent(StudySetContent next) {
    if (!ref.mounted || identical(state.content, next)) return;
    state = _withTabs(state.copyWith(content: next), next);
  }

  Future<void> _refreshContent() => _contentRefresh = _readContent(++_contentRequest);

  Future<void> _readContent(int request) async {
    final next = await _repo.load(studySetId);
    if (!ref.mounted) return;
    if (request != _contentRequest) {
      // A write must not finish before the newer refresh it yielded to.
      await _contentRefresh;
      return;
    }
    _publishContent(next);
  }

  /// Repository loads are in-memory snapshots in both local adapters. Reading
  /// after persistence also retains external edits made while our write waited
  /// for disk, rather than publishing the older value returned by update().
  Future<StudySetContent> _write(StudySetContent Function(StudySetContent) change) async {
    final next = await _repo.update(studySetId, change);
    if (ref.mounted) await _refreshContent();
    return next;
  }

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
      await _write((c) => StudySetEditor.restore(before, c));
      if (ref.mounted) state = state.copyWith(clearPending: true);
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
        final next = await _write((c) {
          before = c;
          return change(c);
        });
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

  /// Assistant adapters use the workspace writer so each proposal/save is one
  /// undo step and repository observers immediately update sidebar counts.
  Future<StudySetContent> applyAssistantChange(StudySetContent Function(StudySetContent) change) async {
    if (_transactionDepth > 0 || _editing != null || _creating || _markEditing != null) {
      throw StateError('Finish the current edit first');
    }
    return _update((content) {
      if (_transactionDepth > 0 || _editing != null || _creating || _markEditing != null) {
        throw StateError('Finish the current edit first');
      }
      return change(content);
    });
  }

  Future<void> setCardBody(String id, String body, [TextFormat? format]) => _update(
    (c) => c.copyWith(
      cards: [for (final card in c.cards) card.id == id ? card.copyWith(body: body, textFormat: format) : card],
    ),
  );

  /// A single state event contains every committed new node; canvas flashes
  /// them together and uses the final node as its scroll destination.
  void flashAssistantNodes(List<String> ids) {
    if (!ref.mounted || ids.isEmpty) return;
    _flash(cardId: ids.last, cardIds: Set.unmodifiable(ids));
  }

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
        await _write((c) {
          current = c;
          // An undone assistant change loses its receipt, so its proposal can
          // be applied again; redo brings the receipt back.
          return StudySetEditor.restore(snapshot, c).copyWith(assistantReceipts: snapshot.assistantReceipts);
        });
        from.removeLast();
        to.add(current!);
        if (ref.mounted) state = state.copyWith(clearPending: true);
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
    final selectionGone = s.selectedCardId != null && !c.isPlaced(s.selectedCardId!, mapId: mapId);
    final selectedIds = s.selectedCardIds.where((id) => c.isPlaced(id, mapId: mapId)).toSet();
    final selectedId = selectionGone ? selectedIds.lastOrNull : s.selectedCardId;
    final mark = s.selectedMarkId != null && _markExists(c, mapId, s.selectedMarkId!) ? s.selectedMarkId : null;
    final connecting = s.connectingFromId != null && c.isPlaced(s.connectingFromId!, mapId: mapId);
    if (listEquals(open, s.openDocumentIds) &&
        active == s.activeDocumentId &&
        mapId == s.activeMapId &&
        selectedId == s.selectedCardId &&
        setEquals(selectedIds, s.selectedCardIds) &&
        mark == s.selectedMarkId &&
        (connecting || s.connectingFromId == null)) {
      return s;
    }
    return s.copyWith(
      selectedMarkId: mark,
      clearMark: mark == null,
      clearConnecting: !connecting,
      activeMapId: mapId,
      openDocumentIds: open,
      activeDocumentId: active,
      clearActive: active == null,
      selectRoot: selectedId == null,
      rootSelected: s.rootSelected && mapId == s.activeMapId,
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

  void toggleSidebar() {
    if (state.sidebarAutoCollapsed) return showSidebar();
    _setSidebarVisible(!state.sidebarVisible);
  }

  void _setSidebarVisible(bool visible) {
    if (_panelRestore != null) {
      _panelRestore = (layout: _panelRestore!.layout, sidebarVisible: visible);
    }
    state = state.copyWith(sidebarVisible: visible);
  }

  /// Brings the sidebar on screen. With no room beside the right panel the
  /// sidebar takes the panel's place; with no room beside the map, the map's
  /// place (the reader alone), like the toolbar button.
  void showSidebar() {
    if (state.sidebarAutoCollapsed && state.panel != null) {
      closePanel();
      state = state.copyWith(sidebarVisible: true, sidebarAutoCollapsed: false);
      return;
    }
    if (state.sidebarAutoCollapsed) {
      state = state.copyWith(layout: MMSplitMode.primary, sidebarAutoCollapsed: false);
    }
    _setSidebarVisible(true);
  }

  // ---- right panel ------------------------------------------------------------

  _PanelRestore? _panelRestore;

  /// Set by the screen while the panel floats over the panes (touch windows
  /// below the regular size class): opening it then leaves the panes alone.
  bool panelFloats = false;

  /// Set by the screen while a touch window shows one pane at a time (a
  /// split shows the source): bringing the map into view then shows it alone.
  bool onePane = false;

  /// Opens the right panel on [content]. The first opening remembers the
  /// layout and sidebar. Only details may put the other pane aside;
  /// asking the assistant leaves the user's pane choices alone.
  void openPanel(RightPanel content, {PanelOrigin origin = PanelOrigin.toolbar}) {
    if (state.panel == null) _panelRestore = (layout: state.layout, sidebarVisible: state.sidebarVisible);
    final layout = panelFloats || content == RightPanel.assistant || state.layout != MMSplitMode.split
        ? null
        : switch (origin) {
            PanelOrigin.reader => MMSplitMode.primary,
            PanelOrigin.map => MMSplitMode.secondary,
            PanelOrigin.toolbar => null,
          };
    state = state.copyWith(panel: content, layout: layout);
  }

  /// Closes the right panel and restores its layout, keeping manual choices.
  /// The panes stayed mounted, so their zoom and scroll positions are as
  /// they were; the map's view is left alone.
  void closePanel() {
    if (state.panel == null) return;
    final restore = _panelRestore;
    _panelRestore = null;
    state = state.copyWith(
      closePanel: true,
      layout: restore?.layout,
      sidebarVisible: restore?.sidebarVisible,
      // Keyboard focus goes back to the card the details showed.
      selectedCardId: state.panel == RightPanel.details && state.selectedCardId == null
          ? _existing(state.detailCardId)
          : null,
    );
  }

  String? _existing(String? cardId) =>
      cardId != null && content.node(cardId, mapId: state.activeMapId) != null ? cardId : null;

  /// ⌃⌘R: opens the assistant panel, switches the panel to the assistant,
  /// or closes it when the assistant is already showing.
  void toggleAssistantPanel() {
    if (state.panel == RightPanel.assistant) return closePanel();
    openPanel(RightPanel.assistant);
  }

  /// Shows [cardId] (default: the selected card) in the details panel, opened
  /// from the map.
  void showDetails([String? cardId]) {
    final id = cardId ?? state.selectedCardId;
    if (id == null || content.card(id) == null) return;
    openPanel(RightPanel.details, origin: PanelOrigin.map);
    state = state.copyWith(selectedCardId: id, detailCardId: id);
  }

  /// ⌘I: shows the selected card's details, or closes them. Open details
  /// follow the selection, so they always show the selected card.
  void toggleDetails() => state.panel == RightPanel.details ? closePanel() : showDetails();

  /// Shows a card's full text on the map, or cuts it back to its preview.
  void toggleExpanded(String cardId) {
    final next = {...state.expandedCardIds};
    if (!next.remove(cardId)) next.add(cardId);
    state = state.copyWith(expandedCardIds: next);
  }

  /// ⌥Space: expands the selected cards, or collapses them when all are
  /// expanded already.
  void toggleSelectedExpanded() {
    final ids = state.selectedCardIds.isNotEmpty
        ? state.selectedCardIds
        : {if (state.selectedCardId != null) state.selectedCardId!};
    if (ids.isEmpty) return;
    final collapse = ids.every(state.expandedCardIds.contains);
    state = state.copyWith(
      expandedCardIds: collapse ? state.expandedCardIds.difference(ids) : state.expandedCardIds.union(ids),
    );
  }

  void setSidebarAutoCollapsed(bool value) {
    if (state.sidebarAutoCollapsed != value) state = state.copyWith(sidebarAutoCollapsed: value);
  }

  void toggleReaderPanel() {
    final available = ReaderPanelMode.values.where(canShowReaderPanel).toList();
    if (available.isEmpty) return;
    state = state.copyWith(
      readerPanelVisible: !state.readerPanelVisible,
      readerPanelMode: canShowReaderPanel(state.readerPanelMode) ? state.readerPanelMode : available.first,
    );
  }

  /// Opens the reader sidebar on [mode] (the source pane comes back in
  /// map-only layout, since the user asked for it).
  void showReaderPanel(ReaderPanelMode mode) {
    if (!canShowReaderPanel(mode)) return;
    state = state.copyWith(
      readerPanelVisible: true,
      readerPanelMode: mode,
      layout: state.layout == MMSplitMode.secondary ? MMSplitMode.split : null,
    );
  }

  bool canShowReaderPanel(ReaderPanelMode mode) => switch (mode) {
    ReaderPanelMode.thumbnails => activeCapabilities.thumbnails,
    ReaderPanelMode.outline => activeCapabilities.outline,
    ReaderPanelMode.bookmarks => activeCapabilities.bookmarks,
    ReaderPanelMode.annotations => activeCapabilities.annotate,
  };
  void setReaderPanelMode(ReaderPanelMode mode) {
    if (canShowReaderPanel(mode)) state = state.copyWith(readerPanelMode: mode);
  }

  /// Opens the find bar of the active document (or focuses it again).
  void openFind() {
    if (state.activeDocumentId == null || !activeCapabilities.search) return;
    state = state.copyWith(
      findVisible: true,
      findFocusTick: state.findFocusTick + 1,
      layout: state.layout == MMSplitMode.secondary ? MMSplitMode.split : null,
    );
  }

  void closeFind() => state = state.copyWith(findVisible: false);

  void setLayout(MMSplitMode layout) {
    if (state.panel == RightPanel.assistant && _panelRestore != null) {
      _panelRestore = (layout: layout, sidebarVisible: _panelRestore!.sidebarVisible);
    }
    state = state.copyWith(layout: layout);
  }

  /// Temporary space for two readable PDF columns; restore on exit.
  bool beginCompareLayout(double readerWidth) {
    _compareRestore ??= (layout: state.layout, sidebar: state.sidebarVisible, readerPanel: state.readerPanelVisible);
    final hideMap = state.layout == MMSplitMode.split && readerWidth < 900;
    state = state.copyWith(
      sidebarVisible: false,
      readerPanelVisible: false,
      layout: hideMap || state.layout == MMSplitMode.secondary ? MMSplitMode.primary : null,
      clearPending: true,
    );
    return hideMap;
  }

  void endCompareLayout() {
    final before = _compareRestore;
    _compareRestore = null;
    if (before == null) return;
    state = state.copyWith(
      layout: before.layout,
      sidebarVisible: before.sidebar,
      readerPanelVisible: before.readerPanel,
      clearPending: true,
    );
  }

  Future<void> saveComparePair(ComparePair pair, {bool undoable = false}) =>
      _update((c) => _editor.upsertComparePair(c, pair), undoable: undoable);

  void setSplitFraction(double value) => state = state.copyWith(splitFraction: value.clamp(0.1, 0.9));

  void setMapView(MapViewMode view) => state = state.copyWith(mapView: view);

  DocumentCapabilities get activeCapabilities =>
      (content.document(state.activeDocumentId ?? '') ??
              Document(
                id: '',
                title: '',
                fileName: '',
                pageCount: 0,
                importedAt: DateTime(1970),
                format: DocumentFormat.unknown,
              ))
          .capabilities(runtime: DocumentRuntime(ocr: MMPlatformCapabilities.current.pdfOcr));
  bool canUseTool(AnnotationTool tool) => switch (tool) {
    AnnotationTool.select => activeCapabilities.selectText,
    AnnotationTool.highlight || AnnotationTool.underline => activeCapabilities.annotate,
    AnnotationTool.area => activeCapabilities.capture,
    AnnotationTool.ink => activeCapabilities.ink,
  };

  bool canRunSelection(ReaderSelectionCommand command) => switch (command) {
    ReaderSelectionCommand.translate => MMPlatformCapabilities.current.assistant && activeCapabilities.translate,
    ReaderSelectionCommand.copy => activeCapabilities.selectText,
    ReaderSelectionCommand.assistant => activeCapabilities.selectText || activeCapabilities.capture,
    ReaderSelectionCommand.highlight || ReaderSelectionCommand.deleteHighlight => activeCapabilities.annotate,
    ReaderSelectionCommand.marginNote => activeCapabilities.marginNotes,
    ReaderSelectionCommand.excerpt ||
    ReaderSelectionCommand.note ||
    ReaderSelectionCommand.locateCard => activeCapabilities.excerpt,
  };

  Future<void> setTool(AnnotationTool tool) {
    if (content.document(state.activeDocumentId ?? '') != null && !canUseTool(tool) && tool != AnnotationTool.select) {
      return Future.value();
    }
    if (state.tool != tool) state = state.copyWith(tool: tool, clearPending: true);
    // The pen belongs to this window and this session; it never comes back
    // armed after a restart.
    if (tool == AnnotationTool.ink) return Future.value();
    return ref.read(settingsProvider.notifier).setAnnotationTool(tool);
  }

  /// ⇧⌘M: picks up the pen, or puts it down.
  Future<void> toggleInkTool() =>
      setTool(state.tool == AnnotationTool.ink ? AnnotationTool.select : AnnotationTool.ink);

  /// Esc / Done: back to the Select tool.
  Future<void> exitInk() => state.tool == AnnotationTool.ink ? setTool(AnnotationTool.select) : Future.value();

  void setInkTool(MMPdfInkTool tool) => state = state.copyWith(inkTool: tool);

  void setInkColor(MMInkColor color) => state = state.copyWith(
    inkColor: color,
    inkTool: state.inkTool == MMPdfInkTool.eraser ? MMPdfInkTool.freehand : null,
  );

  void setInkWidth(MMInkWidth width) => state = state.copyWith(
    inkWidth: width,
    inkTool: state.inkTool == MMPdfInkTool.eraser ? MMPdfInkTool.freehand : null,
  );

  Future<void> toggleTool() =>
      setTool(state.tool == AnnotationTool.highlight ? AnnotationTool.select : AnnotationTool.highlight);

  Future<void> toggleAreaTool() =>
      setTool(state.tool == AnnotationTool.area ? AnnotationTool.select : AnnotationTool.area);

  /// Color is shared by text markers and never changes the active tool.
  Future<void> setColor(MMAnnotationColor color) async {
    state = state.copyWith(color: color);
    await ref.read(highlightPaletteProvider.notifier).choose(color);
  }

  /// Color settings can edit a selected mark without dismissing its toolbar.
  Future<void> setAnnotationColor(MMAnnotationColor color, {String? annotationId}) async {
    if (!activeCapabilities.annotate) return;
    if (annotationId != null) {
      await _update((c) {
        final annotation = c.annotation(annotationId);
        return annotation == null || annotation.colorIndex == color.index
            ? c
            : _editor.recolor(c, annotationId, color.index);
      });
    }
    await setColor(color);
  }

  /// Selection actions keep the same annotation (and any linked card) alive
  /// so its color and line type can be adjusted without creating duplicates.
  Future<void> applyPendingTextAnnotation(AnnotationTool tool) async {
    if (!activeCapabilities.annotate || (tool != AnnotationTool.highlight && tool != AnnotationTool.underline)) return;
    final pending = state.pending;
    if (pending is PendingSelection) {
      late String id;
      final selection = pending.selection;
      final color = state.color;
      final style = state.underlineStyle;
      await _update((c) {
        _validateTextSelection(c, pending.documentId, selection);
        final (next, annotation) = tool == AnnotationTool.underline
            ? _editor.underline(
                c,
                documentId: pending.documentId,
                pages: selection.textAnchors.isEmpty ? selection.pages : null,
                textAnchors: selection.textAnchors,
                quote: selection.text,
                colorIndex: color.index,
                lineStyle: style,
              )
            : _editor.highlight(
                c,
                documentId: pending.documentId,
                pages: selection.textAnchors.isEmpty ? selection.pages : null,
                textAnchors: selection.textAnchors,
                quote: selection.text,
                colorIndex: color.index,
              );
        id = annotation.id;
        return next;
      });
      if (identical(state.pending, pending)) {
        state = state.copyWith(
          pending: PendingHighlight.fromSelection(id, selection.viewportRect ?? Rect.zero, pending.toolbarIdentity),
        );
      }
      await ref.read(highlightPaletteProvider.notifier).record(color);
    } else if (pending is PendingHighlight) {
      final annotation = content.annotation(pending.annotationId);
      if (annotation == null || annotation.quote.isEmpty) return;
      final kind = tool == AnnotationTool.underline ? AnnotationKind.underline : AnnotationKind.highlight;
      final color = MMAnnotationColor.fromIndex(annotation.colorIndex);
      final style = state.underlineStyle;
      if (annotation.kind != kind) {
        await _update(
          (c) => c.copyWith(
            annotations: [
              for (final a in c.annotations)
                a.id == annotation.id ? a.copyWith(kind: kind, lineStyle: style) : a,
            ],
          ),
        );
      }
      await setColor(color);
    }
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
      clearReveal: true,
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
  Future<ImportedNotice> importDocuments(List<({String path, String name})> files, {bool open = true}) async {
    var count = 0;
    final failed = <String>[];
    final errors = <String, DocumentImportError>{};
    String? firstId;
    final imports = ref.read(documentImportsProvider(studySetId).notifier);
    for (final f in files) {
      final task = imports.add(f.name);
      try {
        final package = await ref
            .read(documentImporterProvider)
            .prepare(f, id: task.id, now: ref.read(clockProvider)(), cancellation: task.cancellation);
        final repository = _repo;
        if (repository is! DocumentRepository) throw StateError('Document storage unavailable');
        await _enqueue(() async {
          final next = await (repository as DocumentRepository).importDocumentPackage(
            studySetId,
            package,
            cancelled: () => task.cancelled || !ref.mounted,
          );
          if (ref.mounted) state = state.copyWith(content: next);
        });
        if (ref.mounted) ref.read(importedDocumentsProvider(studySetId).notifier).flash(package.document.id);
        firstId ??= package.document.id;
        count++;
      } catch (error) {
        if (!task.cancelled) {
          failed.add(f.name);
          errors[f.name] = documentImportError(error);
        }
      } finally {
        if (ref.mounted) imports.remove(task);
      }
    }
    if (ref.mounted && firstId != null && open) openDocument(firstId);
    return ImportedNotice(count, failed, errors: errors);
  }

  String filePath(Document doc) => _repo.resolveFile(studySetId, doc.fileName);

  Future<void> saveWebDocument(DocumentPackage package, {required bool Function() cancelled}) => _enqueue(() async {
    final repo = _repo;
    if (repo is! DocumentRepository) throw StateError('Document storage unavailable');
    await (repo as DocumentRepository).importDocumentPackage(studySetId, package, cancelled: cancelled);
    if (ref.mounted) {
      await _refreshContent();
      openDocument(package.document.id);
    }
  });

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
    final pages = readingPagesProvider(studySetId);
    if (ref.read(pages)[documentId] == page) return;
    ref.read(pages.notifier).record(documentId, page);
    _pageTimers.remove(documentId)?.cancel();
    _pageTimers[documentId] = Timer(const Duration(milliseconds: 800), () {
      _update((c) => _editor.setLastPage(c, documentId, page), undoable: false);
    });
  }

  // ---- bookmarks ---------------------------------------------------------------

  /// The page of the active document the reader is on.
  int? get activePage {
    final doc = state.activeDocumentId == null ? null : content.document(state.activeDocumentId!);
    return doc == null || !doc.capabilities().zoom
        ? null
        : (ref.read(readingPagesProvider(studySetId))[doc.id] ?? doc.lastPage);
  }

  /// ⌘D: bookmarks the page being read, or removes the bookmark it has.
  Future<void> toggleBookmark() async {
    final documentId = state.activeDocumentId;
    final page = activePage;
    final revision = documentId == null ? null : content.document(documentId)?.revision;
    // Source navigation publishes its position through the same write queue.
    await _pendingEdits;
    if (!ref.mounted || documentId == null || content.document(documentId)?.revision != revision) return;
    final position = content.document(documentId)?.readingPosition;
    if (position is TextReadingPosition) {
      await _update((c) => _editor.toggleTextBookmark(c, documentId, position));
      return;
    }
    if (page == null) return;
    await _update((c) => _editor.toggleBookmark(c, documentId, page));
  }

  Future<void> setReadingPosition(String documentId, ReadingPosition position) => _update((c) {
    final revision = c.document(documentId)?.revision;
    if (position is TextReadingPosition && revision != null && position.revision != revision) return c;
    return _editor.setReadingPosition(c, documentId, position);
  }, undoable: false);

  Future<void> addBookmark(String documentId, int page, String title) =>
      _update((c) => _editor.addBookmark(c, documentId, page, title: title));

  Future<void> editBookmark(String id, String title, int page) =>
      _update((c) => _editor.editBookmark(c, id, title, page));

  Future<void> orderBookmarks(String documentId, List<String> ids) =>
      _update((c) => _editor.orderBookmarks(c, documentId, ids));

  Future<void> editDocumentOutline(
    String documentId,
    List<PdfOutlineEntry> original,
    List<PdfOutlineEntry> Function(List<PdfOutlineEntry>) edit,
  ) => _update((c) => _editor.setDocumentOutline(c, documentId, edit(c.outlineOn(documentId)?.items ?? original)));

  Future<void> renameBookmark(String id, String title) => _update((c) => _editor.renameBookmark(c, id, title));

  Future<void> removeBookmark(String id) => _update((c) => _editor.removeBookmark(c, id));

  // ---- excerpts and highlights ------------------------------------------------

  /// Where a new excerpt goes, and that node's title (null = root).
  String? get excerptTargetId => StudySetEditor.excerptTarget(content, state.selectedCardId, mapId: state.activeMapId);

  /// The mouse was released over selected text.
  Future<WorkspaceNotice?> onSelectionCommitted(String documentId, MMPdfSelection selection) =>
      onSourceSelectionCommitted(documentId, SourceSelection.pdf(selection));

  void _validateTextSelection(StudySetContent content, String documentId, SourceSelection selection) {
    if (selection.textAnchors.isEmpty) return;
    final document = content.document(documentId);
    if (document?.contentManifest == null ||
        document?.capabilities().selectText != true ||
        selection.text.trim().isEmpty ||
        selection.textAnchors.any((a) => a.revision != document!.revision)) {
      throw ArgumentError('Stale text selection');
    }
  }

  Future<WorkspaceNotice?> onSourceSelectionCommitted(String documentId, SourceSelection selection) async {
    try {
      _validateTextSelection(content, documentId, selection);
    } on ArgumentError {
      return null;
    }
    if (state.tool == AnnotationTool.underline) {
      await underlineSource(documentId, selection, addToMap: state.syncToMap);
      return const UnderlinedNotice();
    }
    if (state.tool == AnnotationTool.highlight) {
      return state.syncToMap
          ? excerptSource(documentId, selection, state.color)
          : highlightSource(documentId, selection, state.color);
    }
    state = state.copyWith(pending: PendingSelection.source(documentId, selection));
    return null;
  }

  Future<ExcerptedNotice> excerpt(String documentId, MMPdfSelection s, MMAnnotationColor color) =>
      excerptSource(documentId, SourceSelection.pdf(s), color);

  Future<ExcerptedNotice> excerptSource(String documentId, SourceSelection s, MMAnnotationColor color) async {
    final parent = excerptTargetId;
    late Card card;
    await _update((c) {
      _validateTextSelection(c, documentId, s);
      final (next, created) = _editor.createExcerpt(
        c,
        documentId: documentId,
        pages: s.textAnchors.isEmpty ? s.pages : null,
        textAnchors: s.textAnchors,
        quote: s.text,
        colorIndex: color.index,
        parentId: parent,
      );
      card = created;
      return next;
    });
    state = state.copyWith(clearPending: true);
    _flash(cardId: card.id);
    await ref.read(highlightPaletteProvider.notifier).record(color);
    return ExcerptedNotice(parent == null ? null : content.card(parent)?.title, cardId: card.id);
  }

  Future<HighlightedNotice> highlight(String documentId, MMPdfSelection s, MMAnnotationColor color) =>
      highlightSource(documentId, SourceSelection.pdf(s), color);

  Future<HighlightedNotice> highlightSource(String documentId, SourceSelection s, MMAnnotationColor color) async {
    await _update((c) {
      _validateTextSelection(c, documentId, s);
      return _editor
          .highlight(
            c,
            documentId: documentId,
            pages: s.textAnchors.isEmpty ? s.pages : null,
            textAnchors: s.textAnchors,
            quote: s.text,
            colorIndex: color.index,
          )
          .$1;
    });
    state = state.copyWith(clearPending: true);
    await ref.read(highlightPaletteProvider.notifier).record(color);
    return const HighlightedNotice();
  }

  Future<String> underline(
    String documentId,
    MMPdfSelection selection, {
    bool keepPending = false,
    bool addToMap = false,
  }) => underlineSource(documentId, SourceSelection.pdf(selection), keepPending: keepPending, addToMap: addToMap);

  Future<String> underlineSource(
    String documentId,
    SourceSelection selection, {
    bool keepPending = false,
    bool addToMap = false,
  }) async {
    late String id;
    final color = state.color;
    final style = state.underlineStyle;
    final parent = excerptTargetId;
    await _update((c) {
      _validateTextSelection(c, documentId, selection);
      final (next, annotation) = _editor.underline(
        c,
        documentId: documentId,
        pages: selection.textAnchors.isEmpty ? selection.pages : null,
        textAnchors: selection.textAnchors,
        quote: selection.text,
        colorIndex: color.index,
        lineStyle: style,
      );
      id = annotation.id;
      return addToMap ? _editor.attachCard(next, id, parentId: parent).$1 : next;
    });
    if (!keepPending) state = state.copyWith(clearPending: true);
    await ref.read(highlightPaletteProvider.notifier).record(color);
    return id;
  }

  /// Changing settings does not count as a highlighter color use. If a mark
  /// is being edited, keep its floating toolbar alive across each change.
  Future<void> styleUnderline({String? annotationId, MMAnnotationColor? color, AnnotationLineStyle? style}) async {
    final selectedColor = color ?? state.color;
    final selectedStyle = style ?? state.underlineStyle;
    if (annotationId != null) {
      await _update((c) {
        final a = c.annotation(annotationId);
        if (a == null ||
            a.quote.isEmpty ||
            (a.kind == AnnotationKind.underline &&
                a.colorIndex == selectedColor.index &&
                a.lineStyle == selectedStyle)) {
          return c;
        }
        return _editor.restyleAnnotation(c, annotationId, colorIndex: selectedColor.index, lineStyle: selectedStyle);
      });
    }
    await ref.read(settingsProvider.notifier).setUnderlineStyle(selectedColor, selectedStyle);
    if (color != null) await setColor(color);
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
    return ExcerptedNotice(parent == null ? null : content.card(parent)?.title, cardId: card.id);
  }

  Future<WorkspaceNotice> excerptTextArea(
    String documentId,
    List<TextAnchor> anchors,
    Future<Uint8List?> Function() capturePng, {
    required TextCapture capture,
  }) async {
    final revision = content.document(documentId)?.revision;
    if (anchors.isEmpty || anchors.any((a) => a.revision != revision)) return const AreaFailedNotice();
    final String image;
    try {
      final png = await capturePng();
      if (png == null) return const AreaFailedNotice();
      image = await _repo.importImageBytes(studySetId, png);
    } catch (_) {
      return const AreaFailedNotice();
    }
    if (!ref.mounted || content.document(documentId)?.revision != revision) return const AreaFailedNotice();
    final parent = excerptTargetId;
    Card? card;
    await _update((c) {
      if (c.document(documentId)?.revision != revision) return c;
      final annotation = Annotation(
        id: _editor.newId(),
        documentId: documentId,
        textAnchors: anchors,
        quote: '',
        colorIndex: state.color.index,
        createdAt: _editor.now(),
        capture: capture,
      );
      final (next, created) = _editor.createImage(
        c.copyWith(annotations: [...c.annotations, annotation]),
        imageFileName: image,
        annotationId: annotation.id,
        parentId: parent,
      );
      card = created;
      return next;
    });
    if (card == null) return const AreaFailedNotice();
    dismissPending();
    _flash(cardId: card!.id);
    return ExcerptedNotice(parent == null ? null : content.card(parent)?.title, cardId: card!.id);
  }

  /// Cross-paragraph segments are one undo group and reject a stale revision.
  Future<void> addParagraphInk(List<InkStroke> strokes) async {
    if (strokes.isEmpty) return;
    await _update((c) {
      if (strokes.any(
        (s) => s.textAnchor == null || c.document(s.documentId)?.revision != s.textAnchor!.anchor.revision,
      )) {
        return c;
      }
      return strokes.fold(c, _editor.addInkStroke);
    });
  }

  // ---- ink ---------------------------------------------------------------------

  /// Written-note changes participate in the existing persistent undo stack.
  Future<void> saveStudyNote(StudyNote note) => _update((c) => _editor.saveStudyNote(c, note));
  Future<void> deleteStudyNote(String id) => _update((c) => _editor.deleteStudyNote(c, id));
  Future<void> editStudyNoteBlock(String noteId, String blockId, {String? text, List<String>? items}) =>
      _update((c) => _editor.editStudyNoteBlock(c, noteId, blockId, text: text, items: items));

  /// Drafts never enter persistence or the undo stack until committed.
  Future<void> saveMarginNote(MarginNote note) => _update((c) {
    final current = c.marginNotes.where((n) => n.id == note.id).firstOrNull;
    return _editor.upsertMarginNote(
      c,
      current == null ? note : note.copyWith(nodeId: current.nodeId, mapId: current.mapId),
    );
  });

  Future<void> deleteMarginNote(String id) => _update((c) => _editor.removeMarginNote(c, id));

  Future<String?> attachMarginNote(String id) async {
    final note = content.marginNotes.where((n) => n.id == id).firstOrNull;
    if (note == null) return null;
    final selected = state.selectedCardId;
    var parent = excerptTargetId;
    if (selected == null && (note.anchor?.textAnchors.isEmpty ?? true)) {
      // With no selection, retain the most recent topic used on this page.
      final recent =
          content.annotations
              .where((a) => a.documentId == note.documentId && !a.isText && a.pages.any((p) => p.page == note.page))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      for (final annotation in recent) {
        final card = content.cardForAnnotation(annotation.id);
        final node = card == null ? null : content.node(card.id, mapId: state.activeMapId);
        if (node == null) continue;
        parent = node.parentId;
        break;
      }
    }
    await _update((c) {
      final next = _editor.attachMarginNote(c, id, parentId: parent);
      final cardId = next.marginNotes.where((n) => n.id == id).firstOrNull?.nodeId;
      return cardId == null ? next : _expandAncestors(next, cardId);
    });
    final cardId = content.marginNotes.where((n) => n.id == id).firstOrNull?.nodeId;
    if (cardId != null) {
      state = state.copyWith(selectedCardId: cardId, clearPending: true);
      _flash(cardId: cardId);
    }
    return cardId;
  }

  Future<void> locateMarginNote(String id, {bool showMap = true}) async {
    final note = content.marginNotes.where((n) => n.id == id).firstOrNull;
    if (note?.nodeId == null) return;
    if (note!.mapId != null && note.mapId != state.activeMapId) await selectMap(note.mapId!);
    await _update((c) => _expandAncestors(c, note.nodeId!), undoable: false);
    state = state.copyWith(
      selectedCardId: note.nodeId,
      locateCardTick: state.locateCardTick + 1,
      layout: showMap ? _layoutShowingMap : state.layout,
    );
    _flash(cardId: note.nodeId);
  }

  Future<void> setDocumentCrop(String documentId, DocumentCrop? crop) async {
    await _update((c) {
      final next = _editor.setDocumentCrop(c, documentId, crop);
      return next.copyWith(
        documents: [for (final d in next.documents) d.id == documentId ? d.copyWith(cropSuggestionDismissed: true) : d],
      );
    });
  }

  Future<void> dismissCropSuggestion(String documentId) async {
    await _update(
      (c) => c.copyWith(
        documents: [for (final d in c.documents) d.id == documentId ? d.copyWith(cropSuggestionDismissed: true) : d],
      ),
      undoable: false,
    );
  }

  /// One finished pen stroke; one undo step.
  Future<void> addInkStroke(String documentId, MMPdfInkDraft draft) async {
    if (content.document(documentId) == null) return;
    final stroke = draft.toStroke(id: ref.read(editorProvider).newId(), documentId: documentId);
    try {
      await _update((c) => _editor.addInkStroke(c, stroke));
    } on ArgumentError {
      // A stroke the model rejects (e.g. a page the document no longer has)
      // is dropped; the view stops showing it on its own.
    }
  }

  /// Whole strokes touched by one eraser gesture; one undo step.
  Future<void> eraseInkStrokes(Set<String> ids) async {
    if (ids.isEmpty) return;
    await _update((c) => ids.fold(c, _editor.removeInkStroke));
  }

  /// Absolute path of an image stored in this study set.
  String imagePath(String imageFileName) => _repo.resolveFile(studySetId, imageFileName);

  void dismissPending() => state = state.copyWith(clearPending: true);

  /// A highlight (or a research note's mark) on the page was clicked.
  void tapHighlight(String annotationId, [Rect viewportRect = Rect.zero]) {
    if (annotationId.startsWith('note:')) {
      final attachmentId = annotationId.substring(5);
      if (!content.noteAttachments.any((a) => a.id == attachmentId)) return;
      state = state.copyWith(pending: PendingResearchNote(attachmentId, viewportRect));
      return;
    }
    if (content.annotation(annotationId) == null) return;
    state = state.copyWith(pending: PendingHighlight(annotationId, viewportRect));
    final matches = content.segmentsForAnnotation(annotationId, mapId: state.activeMapId);
    if (matches.isNotEmpty) {
      state = state.copyWith(
        expandedCardIds: {
          ...state.expandedCardIds,
          for (final match in matches)
            if (match.card.segments.length > 1) match.card.id,
        },
      );
      _flash(cardId: matches.first.card.id, cardIds: matches.map((m) => m.card.id).toSet(), annotationId: annotationId);
    }
  }

  // ---- research notes -----------------------------------------------------------

  /// Saves a research note with its attachments as one undo step. The note
  /// id comes from the caller, so a repeated save of the same note is
  /// ignored instead of creating a second note or card. [cardParentId] puts
  /// a card in the active map (null: under the root); [splitPoints] become
  /// note cards under it.
  Future<ResearchNoteSavedNotice?> saveResearchNote(
    ResearchNote note, {
    PdfTarget? source,
    bool toMap = false,
    String? cardParentId,
    List<String> splitPoints = const [],
    List<Evidence> evidence = const [],
    List<ResearchSource> sources = const [],
  }) async {
    if (content.researchNote(note.id) != null) return null;
    String? cardId;
    var saved = false;
    await _update((c) {
      if (c.researchNote(note.id) != null) return c;
      final editor = _editor;
      final parent = cardParentId != null && c.node(cardParentId, mapId: state.activeMapId) != null
          ? cardParentId
          : null;
      var next = editor.saveResearchNote(
        c,
        note,
        targets: [?source],
        evidence: evidence,
        sources: sources,
        createCard: toMap,
        parentId: parent,
      );
      if (toMap) {
        cardId = next.cards.lastWhere((card) => card.researchNoteId == note.id).id;
        for (final point in splitPoints) {
          next = editor.addNote(next, text: point, parentId: cardId).$1;
        }
        next = _expandAncestors(next, cardId!);
      }
      saved = true;
      return next;
    });
    if (!saved || !ref.mounted) return null;
    if (cardId != null) {
      state = state.copyWith(selectedCardId: cardId);
      _flash(cardId: cardId);
    }
    return ResearchNoteSavedNotice(noteId: note.id, cardId: cardId, inSource: source != null);
  }

  /// A note's title or text, edited from the details: the map card and the
  /// source's mark show the same note. One undo step.
  Future<void> setResearchReview(String noteId, {required bool enabled}) =>
      _update((c) => _editor.setResearchReview(c, noteId, enabled: enabled));

  Future<void> editResearchNote(String noteId, {String? title, String? body}) =>
      _update((c) => _editor.editResearchNote(c, noteId, title: title, body: body));

  /// Removes one place the note is shown; the note and its citations stay.
  Future<void> detachResearchNote(String attachmentId) async {
    await _update((c) => _editor.detachNote(c, attachmentId));
    if (ref.mounted && state.pending is PendingResearchNote) state = state.copyWith(clearPending: true);
  }

  /// Deletes a note with its marks and cards; one undo step brings all back.
  Future<void> deleteResearchNote(String noteId) async {
    await _update((c) => _editor.deleteNote(c, noteId));
    if (ref.mounted) state = state.copyWith(clearPending: true);
  }

  /// Shows the note's place in the source (the first one).
  void revealNoteInSource(String noteId) {
    final target = content.noteAttachments
        .where((a) => a.noteId == noteId)
        .map((a) => a.target)
        .where(
          (t) => switch (t) {
            PdfTarget(:final documentId) || TextTarget(:final documentId) => content.document(documentId) != null,
            _ => false,
          },
        )
        .firstOrNull;
    if (target is PdfTarget) _revealPdf(target);
    if (target is TextTarget) {
      openDocument(target.documentId);
      state = state.copyWith(reveal: RevealRequest.text(target.documentId, target.textAnchors, ++_revealNonce));
    }
  }

  /// Selects and centers the note's card in the active map (the map comes
  /// back if it was put aside).
  Future<void> locateNoteCard(String noteId) async {
    final card = content.cards
        .where((c) => c.researchNoteId == noteId && content.node(c.id, mapId: state.activeMapId) != null)
        .firstOrNull;
    if (card == null) return;
    await _update((c) => _expandAncestors(c, card.id), undoable: false);
    if (!ref.mounted) return;
    state = state.copyWith(
      selectedCardId: card.id,
      locateCardTick: state.locateCardTick + 1,
      clearPending: true,
      mapView: MapViewMode.map,
      layout: _layoutShowingMap,
    );
    _flash(cardId: card.id);
  }

  /// Back to where a research started: the page and sentence, or the node.
  /// False when that place no longer exists.
  Future<bool> revealAnchor(SourceAnchor anchor) async {
    switch (anchor.target) {
      case PdfTarget target when content.document(target.documentId) != null:
        _revealPdf(target);
        return true;
      case TextTarget target when content.document(target.documentId) != null:
        openDocument(target.documentId);
        state = state.copyWith(reveal: RevealRequest.text(target.documentId, target.textAnchors, ++_revealNonce));
        return true;
      case CardTarget(:final cardId):
        final mapId = anchor.mapId ?? state.activeMapId;
        if (content.node(cardId, mapId: mapId) == null) return false;
        if (mapId != state.activeMapId) await selectMap(mapId);
        if (!ref.mounted) return false;
        await _update((c) => _expandAncestors(c, cardId), undoable: false);
        if (!ref.mounted) return false;
        state = state.copyWith(
          selectedCardId: cardId,
          locateCardTick: state.locateCardTick + 1,
          mapView: MapViewMode.map,
          layout: _layoutShowingMap,
        );
        _flash(cardId: cardId);
        return true;
      default:
        return false;
    }
  }

  void _revealPdf(PdfTarget target) {
    final page = target.pages.first;
    openDocument(target.documentId);
    state = state.copyWith(reveal: RevealRequest(target.documentId, page.page, page.rects, ++_revealNonce));
  }

  Future<void> locateHighlightCard(String annotationId) async {
    final matches = content.segmentsForAnnotation(annotationId, mapId: state.activeMapId);
    final card = matches.firstOrNull?.card;
    if (card == null) return;
    await _update((c) => _expandAncestors(c, card.id), undoable: false);
    state = state.copyWith(
      selectedCardId: card.id,
      locateCardTick: state.locateCardTick + 1,
      clearPending: true,
      expandedCardIds: {...state.expandedCardIds, if (card.segments.length > 1) card.id},
      mapView: MapViewMode.map,
      layout: _layoutShowingMap,
    );
    _flash(cardId: card.id, annotationId: annotationId);
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
      layout: _layoutShowingMap,
    );
    _flash(cardId: card.id);
    return ExcerptedNotice(parent == null ? null : content.card(parent)?.title, cardId: card.id);
  }

  Future<void> recolor(String annotationId, MMAnnotationColor color) async {
    final annotation = content.annotation(annotationId);
    if (annotation?.kind == AnnotationKind.underline) {
      await styleUnderline(annotationId: annotationId, color: color, style: annotation!.lineStyle);
      state = state.copyWith(clearPending: true);
      return;
    }
    await _update((c) => _editor.recolor(c, annotationId, color.index));
    state = state.copyWith(clearPending: true);
    await ref.read(highlightPaletteProvider.notifier).record(color);
  }

  Future<HighlightDeletedNotice> deleteHighlight(String annotationId) async {
    final underline = content.annotation(annotationId)?.kind == AnnotationKind.underline;
    await _update((c) => _editor.deleteAnnotation(c, annotationId));
    state = state.copyWith(clearPending: true);
    return HighlightDeletedNotice(underline: underline);
  }

  // ---- map --------------------------------------------------------------------

  /// Modifier-click toggles membership; normal navigation selects just one.
  void toggleCardSelection(String cardId) {
    final ids = {...state.selectedCardIds};
    if (!ids.remove(cardId)) ids.add(cardId);
    selectCards(ids);
  }

  void selectCards(Iterable<String> cardIds) {
    final ids = cardIds.where((id) => content.isPlaced(id, mapId: state.activeMapId)).toSet();
    state = state.copyWith(selectedCardIds: ids, selectedCardId: ids.lastOrNull, selectRoot: ids.isEmpty);
  }

  bool _clipboardBusy = false;

  /// Cut removes exactly the copied selection, only after a successful write.
  Future<void> copySelection({bool cut = false}) async {
    if (_editing != null || _creating || _clipboardBusy) return;
    final ids = state.selectedCardIds.toList();
    _clipboardBusy = true;
    try {
      final files = <String, String>{};
      final preview = MapClipboard.copy(content, ids, mapId: state.activeMapId);
      if (preview.isEmpty) return;
      final repository = _repo;
      for (final entry in preview) {
        for (final source in entry.sources) {
          for (final version in source.versions) {
            if (files.containsKey(version.snapshotFile)) continue;
            if (repository is! ResearchSnapshotRepository) throw StateError('Research snapshots unavailable');
            files[version.snapshotFile] = await (repository as ResearchSnapshotRepository).readResearchSnapshot(
              studySetId,
              version.snapshotFile,
            );
          }
        }
      }
      if (!ref.mounted) return;
      final entries = MapClipboard.copy(
        content,
        ids,
        mapId: state.activeMapId,
        resolveImage: imagePath,
        snapshots: files,
      );
      await MMMapClipboard.write(text: MapClipboard.toText(entries), internal: MapClipboard.encode(entries));
      if (cut && ref.mounted && _editing == null && !_creating) await removeCards(ids);
    } finally {
      _clipboardBusy = false;
    }
  }

  /// Imports resources and creates their cards in one serialized undo step.
  /// Retains package resources on undo, so redo never needs the original file.
  Future<bool> insertImages({List<String> paths = const [], Uint8List? bytes, bool pasted = false}) async {
    if (_editing != null || _markEditing != null || _creating || _clipboardBusy) return false;
    _clipboardBusy = true;
    try {
      return await _insertImages(paths: paths, bytes: bytes, pasted: pasted);
    } finally {
      _clipboardBusy = false;
    }
  }

  Future<bool> _insertImages({List<String> paths = const [], Uint8List? bytes, bool pasted = false}) async {
    final parent = excerptTargetId;
    final editor = _editor;
    final repository = _repo;
    return _enqueue(() async {
      final names = <String>[];
      for (final path in paths) {
        if (!RegExp(r'\.(png|jpe?g)$', caseSensitive: false).hasMatch(path)) {
          throw const FormatException('Expected PNG or JPEG image');
        }
        names.add(await repository.importImage(studySetId, path));
      }
      if (bytes != null) names.add(await repository.importImageBytes(studySetId, bytes));
      if (!ref.mounted || names.isEmpty) return false;
      late StudySetContent before;
      Card? last;
      await _write((c) {
        if (c.map(editor.mapId) == null || (parent != null && c.node(parent, mapId: editor.mapId) == null)) {
          throw StateError('Image destination no longer exists');
        }
        before = c;
        for (var i = 0; i < names.length; i++) {
          final result = editor.createImage(
            c,
            imageFileName: names[i],
            parentId: parent,
            imageOrigin: pasted || i >= paths.length ? 'pasted' : 'file:${paths[i].split(RegExp(r'[/\\]')).last}',
          );
          c = result.$1;
          last = result.$2;
        }
        return c;
      });
      if (_transactionDepth > 0) {
        _transactionBefore ??= before;
      } else {
        _record(before);
      }
      _syncHistory();
      if (ref.mounted && last != null) {
        selectCard(last!.id);
        _flash(cardId: last!.id);
      }
      return true;
    });
  }

  Future<void> pasteSelection({bool imagesOnly = false}) async {
    if (_editing != null || _creating || _clipboardBusy) return;
    final parent = state.selectedCardId;
    _clipboardBusy = true;
    try {
      final data = await MMMapClipboard.read();
      if (!ref.mounted || _editing != null || _creating) return;
      final internalEntries = data.internal == null ? null : MapClipboard.decode(data.internal!);
      final entries = internalEntries ?? MapClipboard.fromText(data.text);
      if (internalEntries == null) {
        final image = await MMMapClipboard.readImage();
        if (!ref.mounted || _editing != null || _creating) return;
        if (image != null) {
          await _insertImages(paths: image.path == null ? const [] : [image.path!], bytes: image.bytes, pasted: true);
          return;
        }
      }
      if (entries.isEmpty || imagesOnly) return;
      final images = await _importClipboardImages(entries);
      final snapshots = <String, String>{};
      final repository = _repo;
      for (final entry in entries) {
        for (final snapshot in entry.snapshots.entries) {
          if (snapshots.containsKey(snapshot.key)) continue;
          if (repository is! ResearchSnapshotRepository) throw StateError('Research snapshots unavailable');
          snapshots[snapshot.key] = await (repository as ResearchSnapshotRepository).writeResearchSnapshot(
            studySetId,
            snapshot.value,
          );
        }
      }
      if (!ref.mounted || _editing != null || _creating) return;
      var roots = <String>[];
      await _update((c) {
        final (next, ids) = _editor.paste(c, entries, parentId: parent, images: images, snapshots: snapshots);
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

  /// Selects the map root without making it a content card.
  void selectMapRoot() => state = state.copyWith(selectRoot: true, rootSelected: true);

  void selectCard(String? cardId) {
    state = cardId == null ? state.copyWith(selectRoot: true) : state.copyWith(selectedCardId: cardId);
    final annotationId = cardId == null ? null : content.card(cardId)?.annotationId;
    if (annotationId != null) _flash(annotationId: annotationId);
  }

  /// Shows [cardId] on the map alone: a compact window's way from the
  /// source to a new excerpt.
  Future<void> showCardInMap(String cardId) async {
    final shown = await revealAnchor(SourceAnchor(target: CardTarget(cardId: cardId)));
    if (shown && ref.mounted) setLayout(MMSplitMode.secondary);
  }

  MapEditReason? get mergeReason => _editor.mergeReason(content, state.selectedCardIds);
  MapEditReason? get summaryReason => _editor.summaryReason(content, state.selectedCardIds);

  String? get mergeSurvivorId =>
      mergeReason == null ? _editor.mergeCards(content, state.selectedCardIds).value?.id : null;

  Future<MapEditResult<Card>?> mergeSelected() async {
    if (_editing != null || _markEditing != null || _creating || _clipboardBusy) return null;
    final ids = {...state.selectedCardIds};
    final editor = _editor;
    MapEditResult<Card>? result;
    await _update((c) {
      result = editor.mergeCards(c, ids);
      return result!.content;
    });
    if (result?.value case final card? when ref.mounted && state.activeMapId == editor.mapId) {
      selectCard(card.id);
      _flash(cardId: card.id);
    }
    return result;
  }

  Future<void> splitCard(String id) async {
    if (_editing != null || _markEditing != null || _creating || _clipboardBusy) return;
    final editor = _editor;
    MapEditResult<List<Card>>? result;
    await _update((c) {
      result = editor.splitCard(c, id);
      return result!.content;
    });
    if (result?.value case final cards? when ref.mounted && state.activeMapId == editor.mapId) {
      selectCards(cards.map((c) => c.id));
    }
  }

  void revealSegment(String cardId, int index) {
    final card = content.card(cardId);
    if (card == null) return;
    final segments = content.segmentsOf(card);
    if (index < 0 || index >= segments.length) return;
    final annotation = content.annotation(segments[index].annotationId ?? '');
    if (annotation == null) return;
    openDocument(annotation.documentId);
    if (annotation.needsReview) return;
    state = state.copyWith(
      selectedCardId: cardId,
      reveal: annotation.isText
          ? RevealRequest.text(annotation.documentId, annotation.textAnchors, ++_revealNonce)
          : RevealRequest(annotation.documentId, annotation.page, annotation.rects, ++_revealNonce),
    );
    _flash(annotationId: annotation.id, cardId: cardId);
  }

  /// Opens the source document of an excerpt and scrolls to it.
  void revealCard(String cardId) {
    final card = content.card(cardId);
    if (card == null) return;
    final firstSource = content.segmentsOf(card).indexWhere((s) => s.annotationId != null);
    revealSegment(cardId, firstSource);
  }

  /// Adds a topic under the selected topic, or at the root. With
  /// [asChild] it goes under the selected node of any kind (Tab).
  Future<Card> addTopic(String title, {bool asChild = false}) async {
    final summary = content.summaries
        .where((s) => s.mapId == state.activeMapId && s.id == state.selectedMarkId)
        .firstOrNull;
    final selectedId = state.selectedCardId ?? summary?.cardId;
    final selected = selectedId == null ? null : content.card(selectedId);
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

  /// Keeps [cardId] out of review (or lets it back in); one undo step.
  Future<void> setSuspended(String cardId, {required bool suspended}) =>
      _update((c) => _editor.setSuspended(c, cardId, suspended: suspended));

  /// Sets a card's title; with [format], a note's text format too (one undo
  /// step).
  Future<void> rename(String cardId, String title, [TextFormat? format]) => _update((c) {
    final renamed = _editor.rename(c, cardId, title);
    final card = renamed.card(cardId);
    return format == null || card == null || card.textFormat == format
        ? renamed
        : _editor.setCardTextFormat(renamed, cardId, format);
  });

  /// Whether [title] / [format] would change [card].
  static bool _changes(Card card, String title, TextFormat? format) =>
      title != card.title || (format != null && format != card.textFormat);

  /// A title typed in the details panel, with the in-place editor's rules:
  /// trimmed; only excerpts and images may be left untitled.
  Future<void> setTitle(String cardId, String text, [TextFormat? format]) async {
    final card = content.card(cardId);
    final title = text.trim();
    if (card == null || !_changes(card, title, format)) return;
    if (title.isEmpty && card.kind != CardKind.excerpt && card.kind != CardKind.image) return;
    await rename(cardId, title, format);
  }

  // ---- card width and map density (P2-C06) --------------------------------------

  /// Sets the width of [cardId] in the active map (kept within
  /// [MapNode.minWidth]..[MapNode.maxWidth]); null restores the default width.
  Future<void> setCardWidth(String cardId, double? width) async {
    final node = content.node(cardId, mapId: state.activeMapId);
    if (node == null || _editing != null || _creating) return;
    final next = width?.clamp(MapNode.minWidth, MapNode.maxWidth).roundToDouble();
    if (next == node.width) return;
    await _update((c) => _editor.setCardWidth(c, cardId, next));
  }

  /// How much each card of the active map shows. The text itself is never
  /// changed by it.
  Future<void> setMapDensity(MapDensity density) async {
    if (content.map(state.activeMapId)?.density == density) return;
    await _update((c) => _editor.setMapDensity(c, density));
  }

  /// The active map's structure and palette; each change is one undo step.
  Future<void> setMapStructure(MapStructure structure) async {
    if ((content.map(state.activeMapId)?.structure ?? MapStructure.mind) == structure) return;
    await _update((c) => _editor.setMapStructure(c, structure));
  }

  Future<void> setMapPalette(MapPalette palette) async {
    if ((content.map(state.activeMapId)?.palette ?? MapPalette.system) == palette) return;
    await _update((c) => _editor.setMapPalette(c, palette));
  }

  // ---- in-place editing -------------------------------------------------------

  _EditSession? _editing;

  /// A card is being created for editing; no other edit may start yet.
  bool _creating = false;

  /// Starts editing a card's title (a note's text) in place. Nothing is
  /// written until [finishEditing], so the whole edit is one undo step.
  void beginEditing(String cardId) {
    if (_editing != null || _markEditing != null || _creating || content.card(cardId) == null) return;
    // A research card shows its note: the note is edited in the details.
    if (content.card(cardId)!.kind == CardKind.research) return showDetails(cardId);
    _editing = _EditSession(cardId, created: false, previousSelection: state.selectedCardId);
    state = state.copyWith(selectedCardId: cardId, editingCardId: cardId, layout: _layoutShowingMap);
  }

  /// A field opens in the map pane: with the reader alone on screen the
  /// pane comes back, so the edit can take focus and be finished.
  MMSplitMode? get _layoutShowingMap => onePane
      ? (state.layout == MMSplitMode.secondary ? null : MMSplitMode.secondary)
      : (state.layout == MMSplitMode.primary ? MMSplitMode.split : null);

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

  /// Excerpts the selected text and opens an empty note under the new card for
  /// typing in place. The excerpt and the typed note are one undo step;
  /// cancelling or leaving the note empty leaves nothing behind.
  Future<Card?> excerptAndEditNote(String documentId, MMPdfSelection s, MMAnnotationColor color) =>
      excerptSourceAndEditNote(documentId, SourceSelection.pdf(s), color);

  Future<Card?> excerptSourceAndEditNote(String documentId, SourceSelection s, MMAnnotationColor color) {
    return _createAndEdit((_) async {
      final parent = excerptTargetId;
      late Card note;
      await _update((c) {
        _validateTextSelection(c, documentId, s);
        final (next, excerpt) = _editor.createExcerpt(
          c,
          documentId: documentId,
          pages: s.textAnchors.isEmpty ? s.pages : null,
          textAnchors: s.textAnchors,
          quote: s.text,
          colorIndex: color.index,
          parentId: parent,
        );
        final (withNote, created) = _editor.addNote(next, text: '', parentId: excerpt.id);
        note = created;
        return withNote;
      });
      state = state.copyWith(clearPending: true, selectedCardId: note.id);
      return note;
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
    final previousRootSelected = state.rootSelected;
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
    _editing = _EditSession(
      card.id,
      created: true,
      previousSelection: previous,
      previousRootSelected: previousRootSelected,
    );
    state = state.copyWith(editingCardId: card.id, layout: _layoutShowingMap);
    return card;
  }

  /// Enter or clicking elsewhere. An empty title keeps the old one (an
  /// excerpt's is cleared), or drops a node created for this edit.
  Future<void> finishEditing(String text, [TextFormat? format]) async {
    final session = _editing;
    if (session == null) return;
    _editing = null;
    final title = text.trim();
    try {
      if (session.created && title.isEmpty) {
        await _dropCreated(session);
      } else if (session.created) {
        try {
          if (content.card(session.cardId) case final card? when _changes(card, title, format)) {
            await rename(session.cardId, title, format);
          }
        } finally {
          await commitTransaction();
        }
      } else if (content.card(session.cardId) case final card?
          when (title.isNotEmpty || card.kind == CardKind.excerpt || card.kind == CardKind.image) &&
              _changes(card, title, format)) {
        // An excerpt's title is optional: clearing it shows the quote (or
        // the image's default label) again.
        await rename(session.cardId, title, format);
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
        : state.copyWith(selectRoot: true, rootSelected: session.previousRootSelected);
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
    if (found) {
      if (target == null) {
        selectMapRoot();
      } else {
        selectCard(target);
      }
    }
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
    var existing = false;
    await _update((c) {
      final (next, relation) = _editor.addRelation(c, fromId, toId);
      created = relation;
      existing = identical(c, next);
      return next;
    });
    if (created == null || !ref.mounted) return;
    state = state.copyWith(selectRoot: true, selectedMarkId: created!.id);
    if (!existing) beginMarkEditing(created!.id);
  }

  Future<void> adjustSummaryRange(String id, String from, String to) =>
      _update((c) => _editor.adjustSummaryRange(c, id, [from, to]).content);

  Future<void> updateRelation(MapRelation relation) => _update(
    (c) => _editor.updateRelation(
      c,
      relation.id,
      arrow: relation.arrow,
      solid: relation.solid,
      control1: relation.control1,
      control2: relation.control2,
    ),
  );

  Future<void> reverseRelation(String id) => _update((c) => _editor.reverseRelation(c, id));

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

  void _flash({String? cardId, String? annotationId, Set<String> cardIds = const {}}) {
    _flashTimer?.cancel();
    state = state.copyWith(flashCardId: cardId, flashCardIds: cardIds, flashAnnotationId: annotationId);
    _flashTimer = Timer(MMMotion.flash, () {
      if (ref.mounted) state = state.copyWith(clearFlash: true);
    });
  }
}

class _EditSession {
  const _EditSession(
    this.cardId, {
    required this.created,
    required this.previousSelection,
    this.previousRootSelected = false,
  });

  final String cardId;

  /// The card was added for this edit inside an open transaction.
  final bool created;
  final String? previousSelection;
  final bool previousRootSelected;
}

class _MarkEditSession {
  const _MarkEditSession(this.id, {required this.created});

  final String id;

  /// The summary was added for this edit inside an open transaction.
  final bool created;
}

final workspaceProvider = NotifierProvider.family<WorkspaceController, WorkspaceState, String>(WorkspaceController.new);

/// Workspace presentation ignores persisted reading metadata. The repository
/// remains authoritative; library Continue Learning still observes contentProvider.
final workspaceContentProvider = Provider.family<StudySetContent?, String>((ref, id) {
  StudySetContent? visible;
  bool sameDocument(Document a, Document b) =>
      a.id == b.id &&
      a.title == b.title &&
      a.fileName == b.fileName &&
      a.format == b.format &&
      a.features.text == b.features.text &&
      a.features.outline == b.features.outline &&
      a.layout == b.layout &&
      a.sourceFileName == b.sourceFileName &&
      a.contentManifest == b.contentManifest &&
      a.revision == b.revision &&
      jsonEncode(a.origin?.toJson()) == jsonEncode(b.origin?.toJson()) &&
      a.pageCount == b.pageCount &&
      a.importedAt == b.importedAt &&
      a.cropSuggestionDismissed == b.cropSuggestionDismissed &&
      (identical(a.crop, b.crop) || jsonEncode(a.crop?.toJson()) == jsonEncode(b.crop?.toJson()));
  bool samePresentation(StudySetContent a, StudySetContent b) =>
      identical(a.cards, b.cards) &&
      identical(a.nodes, b.nodes) &&
      identical(a.maps, b.maps) &&
      identical(a.annotations, b.annotations) &&
      identical(a.reviews, b.reviews) &&
      identical(a.relations, b.relations) &&
      identical(a.summaries, b.summaries) &&
      identical(a.bookmarks, b.bookmarks) &&
      identical(a.documentOutlines, b.documentOutlines) &&
      identical(a.inkStrokes, b.inkStrokes) &&
      identical(a.marginNotes, b.marginNotes) &&
      identical(a.comparePairs, b.comparePairs) &&
      identical(a.researchNotes, b.researchNotes) &&
      identical(a.noteAttachments, b.noteAttachments) &&
      identical(a.evidence, b.evidence) &&
      a.documents.length == b.documents.length &&
      Iterable.generate(a.documents.length).every((i) => sameDocument(a.documents[i], b.documents[i]));
  return ref.watch(
    workspaceProvider(id).select((value) {
      final next = value.content;
      if (next == null || visible == null || !samePresentation(visible!, next)) visible = next;
      return visible;
    }),
  );
});
