import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../features/library/library_controller.dart';
import '../features/library/new_study_set.dart';
import '../features/workspace/widgets/notices.dart';
import '../features/workspace/workspace_controller.dart';
import '../settings/settings_sheet.dart';
import '../shared/l10n.dart';
import 'navigation.dart';
import 'providers.dart';

/// A user-invocable command: one definition feeds the macOS menu bar,
/// keyboard shortcuts on other platforms and tooltips.
class AppCommand {
  const AppCommand(this.label, this.onInvoke, {this.shortcut});

  final String label;
  final SingleActivator? shortcut;

  /// Null disables the command in the current context.
  final VoidCallback? onInvoke;
}

/// Global shortcuts. Defined in macOS terms; [primaryShortcut] swaps ⌘ for
/// Ctrl on Windows and Linux.
abstract final class AppShortcuts {
  static SingleActivator get settings => primaryShortcut(LogicalKeyboardKey.comma);
  static SingleActivator get newStudySet => primaryShortcut(LogicalKeyboardKey.keyN);
  static SingleActivator get showLibrary => primaryShortcut(LogicalKeyboardKey.keyL, shift: true);
  static SingleActivator get find => primaryShortcut(LogicalKeyboardKey.keyF);
  static SingleActivator get toggleSidebar => primaryShortcut(LogicalKeyboardKey.keyS, control: true);
  static SingleActivator get view1 => primaryShortcut(LogicalKeyboardKey.digit1);
  static SingleActivator get view2 => primaryShortcut(LogicalKeyboardKey.digit2);
  static SingleActivator get view3 => primaryShortcut(LogicalKeyboardKey.digit3);
  static SingleActivator get importDocument => primaryShortcut(LogicalKeyboardKey.keyO);
  static SingleActivator get addTopic => primaryShortcut(LogicalKeyboardKey.keyN, shift: true);
  static SingleActivator get addNote => primaryShortcut(LogicalKeyboardKey.keyN, alt: true);
  static SingleActivator get revealSource => primaryShortcut(LogicalKeyboardKey.keyL);
  static SingleActivator get gallery => primaryShortcut(LogicalKeyboardKey.keyG, alt: true);
  static SingleActivator get undo => primaryShortcut(LogicalKeyboardKey.keyZ);
  static SingleActivator get redo => primaryShortcut(LogicalKeyboardKey.keyZ, shift: true);
  static SingleActivator get review => primaryShortcut(LogicalKeyboardKey.keyR);

  static SingleActivator get findNext => primaryShortcut(LogicalKeyboardKey.keyG);
  static SingleActivator get findPrevious => primaryShortcut(LogicalKeyboardKey.keyG, shift: true);
  static SingleActivator get toggleBookmark => primaryShortcut(LogicalKeyboardKey.keyD);
  static SingleActivator get goBack => primaryShortcut(LogicalKeyboardKey.bracketLeft);
  static SingleActivator get firstPage => const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true);
  static SingleActivator get lastPage => const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true);
  static SingleActivator get toggleReaderSidebar => primaryShortcut(LogicalKeyboardKey.keyS, alt: true);
  static SingleActivator get readerThumbnails => primaryShortcut(LogicalKeyboardKey.digit1, alt: true);
  static SingleActivator get readerOutline => primaryShortcut(LogicalKeyboardKey.digit2, alt: true);
  static SingleActivator get readerBookmarks => primaryShortcut(LogicalKeyboardKey.digit3, alt: true);
  static SingleActivator get readerAnnotations => primaryShortcut(LogicalKeyboardKey.digit4, alt: true);

  static SingleActivator get toggleAnnotationTool => primaryShortcut(LogicalKeyboardKey.keyH, shift: true);
  static SingleActivator get toggleAreaTool => primaryShortcut(LogicalKeyboardKey.keyR, shift: true);

  /// "Tooltip (⌘1)".
  static String tip(String label, SingleActivator shortcut) => '$label（${describeShortcut(shortcut)}）';
}

/// Shared by the native menu and the focused canvas.
enum MindMapCommand {
  siblingAfter,
  siblingBefore,
  child,
  promote,
  parent,
  edit,
  delete,
  fold,
  up,
  down,
  fit,
  center,
  copy,
  cut,
  paste,
  relation,
  summary,
}

class MindMapIntent extends Intent {
  const MindMapIntent(this.command);
  final MindMapCommand command;
}

Map<SingleActivator, MindMapCommand> get mindMapShortcuts => {
  primaryShortcut(LogicalKeyboardKey.keyC): MindMapCommand.copy,
  primaryShortcut(LogicalKeyboardKey.keyX): MindMapCommand.cut,
  primaryShortcut(LogicalKeyboardKey.keyV): MindMapCommand.paste,
  const SingleActivator(LogicalKeyboardKey.enter): MindMapCommand.siblingAfter,
  const SingleActivator(LogicalKeyboardKey.enter, shift: true): MindMapCommand.siblingBefore,
  const SingleActivator(LogicalKeyboardKey.tab): MindMapCommand.child,
  const SingleActivator(LogicalKeyboardKey.tab, shift: true): MindMapCommand.promote,
  primaryShortcut(LogicalKeyboardKey.enter): MindMapCommand.parent,
  const SingleActivator(LogicalKeyboardKey.space): MindMapCommand.edit,
  const SingleActivator(LogicalKeyboardKey.f2): MindMapCommand.edit,
  const SingleActivator(LogicalKeyboardKey.backspace): MindMapCommand.delete,
  const SingleActivator(LogicalKeyboardKey.delete): MindMapCommand.delete,
  primaryShortcut(LogicalKeyboardKey.slash): MindMapCommand.fold,
  primaryShortcut(LogicalKeyboardKey.arrowUp): MindMapCommand.up,
  primaryShortcut(LogicalKeyboardKey.arrowDown): MindMapCommand.down,
  primaryShortcut(LogicalKeyboardKey.digit0): MindMapCommand.fit,
  primaryShortcut(LogicalKeyboardKey.keyR, alt: true): MindMapCommand.relation,
  primaryShortcut(LogicalKeyboardKey.bracketRight): MindMapCommand.summary,
};

/// Selection commands share their intents between menus and the floating toolbar.
enum ReaderSelectionCommand { excerpt, highlight, copy, note, locateCard, deleteHighlight }

class ReaderSelectionIntent extends Intent {
  const ReaderSelectionIntent(this.command);
  final ReaderSelectionCommand command;
}

Map<ShortcutActivator, ReaderSelectionIntent> get readerSelectionShortcuts => {
  const SingleActivator(LogicalKeyboardKey.keyE): const ReaderSelectionIntent(ReaderSelectionCommand.excerpt),
  const SingleActivator(LogicalKeyboardKey.keyH): const ReaderSelectionIntent(ReaderSelectionCommand.highlight),
  primaryShortcut(LogicalKeyboardKey.keyC): const ReaderSelectionIntent(ReaderSelectionCommand.copy),
};

/// Page navigation keys that only act while the reader has the keyboard
/// (Home and End belong to text fields everywhere else).
enum ReaderNavCommand { firstPage, lastPage }

class ReaderNavIntent extends Intent {
  const ReaderNavIntent(this.command);
  final ReaderNavCommand command;
}

Map<ShortcutActivator, ReaderNavIntent> get readerNavShortcuts => {
  const SingleActivator(LogicalKeyboardKey.home): const ReaderNavIntent(ReaderNavCommand.firstPage),
  const SingleActivator(LogicalKeyboardKey.end): const ReaderNavIntent(ReaderNavCommand.lastPage),
};

/// Installs the menu bar (macOS) or equivalent shortcuts (elsewhere) for
/// the current route.
class AppMenus extends ConsumerStatefulWidget {
  const AppMenus({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppMenus> createState() => _AppMenusState();
}

class _AppMenusState extends ConsumerState<AppMenus> {
  late bool _textFocused;
  bool _mapFocused = false;
  bool _readerFocused = false;

  bool get _isTextFocused =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

  @override
  void initState() {
    super.initState();
    _textFocused = _isTextFocused;
    FocusManager.instance.addListener(_focusChanged);
  }

  void _focusChanged() {
    final textFocused = _isTextFocused;
    final focus = FocusManager.instance.primaryFocus?.context;
    final mapFocused = focus != null && Actions.maybeFind<MindMapIntent>(focus) != null;
    final readerFocused = focus != null && Actions.maybeFind<ReaderNavIntent>(focus) != null;
    if (textFocused == _textFocused && mapFocused == _mapFocused && readerFocused == _readerFocused) return;
    setState(() {
      _textFocused = textFocused;
      _mapFocused = mapFocused;
      _readerFocused = readerFocused;
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final route = ref.watch(navigationProvider);
    final nav = ref.read(navigationProvider.notifier);
    final inLibrary = route is LibraryRoute;
    final workspaceId = route is WorkspaceRoute ? route.studySetId : null;
    final inWorkspace = workspaceId != null;

    final workspace = inWorkspace ? ref.read(workspaceProvider(workspaceId).notifier) : null;
    final workspaceState = inWorkspace ? ref.watch(workspaceProvider(workspaceId)) : null;
    final selected = workspaceState?.selectedCardId;
    // While a title is typed in place, commands that change the content
    // wait: they would land in the edit's undo step and be lost on Esc.
    final editable =
        workspace != null && workspaceState?.editingCardId == null && workspaceState?.editingMarkId == null;
    final hasDocument =
        workspace != null &&
        workspaceState!.activeDocumentId != null &&
        workspace.content.document(workspaceState.activeDocumentId!) != null;
    // Page commands wait while a title or note is typed, but not in the
    // reader's own fields (the find bar).
    final canRead = hasDocument && (!_textFocused || _readerFocused);
    final findsInDocument = hasDocument && _readerFocused;
    final pdf = inWorkspace ? ref.read(readerPdfProvider(workspaceId)) : null;
    final bookmarked =
        hasDocument &&
        workspace.content.bookmarkAt(workspaceState.activeDocumentId!, workspace.activePage ?? 0) != null;
    final settings = AppCommand(l.settings, () => showSettingsSheet(context), shortcut: AppShortcuts.settings);
    final file = [
      AppCommand(l.showLibrary, inLibrary ? null : nav.showLibrary, shortcut: AppShortcuts.showLibrary),
      AppCommand(
        l.newStudySet,
        inLibrary ? () => newStudySetFromPdfs(context, ref) : null,
        shortcut: AppShortcuts.newStudySet,
      ),
      AppCommand(
        l.importDocument,
        editable ? () => pickAndImportDocuments(context, ref, workspaceId!) : null,
        shortcut: AppShortcuts.importDocument,
      ),
    ];
    file.addAll([
      AppCommand(
        l.exportMarkdown,
        inWorkspace ? () => exportMap(context, ref, workspaceId, ExportFormat.markdown) : null,
      ),
      AppCommand(l.exportOpml, inWorkspace ? () => exportMap(context, ref, workspaceId, ExportFormat.opml) : null),
    ]);
    Future<void> undoOrRedo({required bool redo}) async {
      // A focused text field keeps ⌘Z for its own text.
      final focus = FocusManager.instance.primaryFocus?.context;
      if (focus != null && focus.findAncestorWidgetOfExactType<EditableText>() != null) {
        final intent = redo
            ? const RedoTextIntent(SelectionChangedCause.keyboard)
            : const UndoTextIntent(SelectionChangedCause.keyboard);
        Actions.maybeInvoke(focus, intent);
        return;
      }
      final notice = redo ? await workspace?.redo() : await workspace?.undo();
      if (context.mounted) showNotice(context, notice, rootTitle: '');
    }

    final edit = [
      AppCommand(
        l.undo,
        workspaceState?.canUndo ?? false ? () => undoOrRedo(redo: false) : null,
        shortcut: AppShortcuts.undo,
      ),
      AppCommand(
        l.redo,
        workspaceState?.canRedo ?? false ? () => undoOrRedo(redo: true) : null,
        shortcut: AppShortcuts.redo,
      ),
    ];
    void invokeSelection(ReaderSelectionCommand command) {
      final focus = FocusManager.instance.primaryFocus?.context;
      if (focus != null) Actions.maybeInvoke(focus, ReaderSelectionIntent(command));
    }

    final selectionOpen = workspaceState?.pending is PendingSelection && !_textFocused;
    final highlightOpen = workspaceState?.pending is PendingHighlight && !_textFocused;
    // An area has no text to copy.
    final highlightText = switch (workspaceState?.pending) {
      PendingHighlight(:final annotationId) => workspace?.content.annotation(annotationId)?.quote.isNotEmpty ?? false,
      _ => false,
    };
    // One native key equivalent per operation. Dispatch to the focused field,
    // map, or PDF selection so menu shortcuts cannot shadow each other.
    for (final command in [MindMapCommand.copy, MindMapCommand.cut, MindMapCommand.paste]) {
      final mapClipboard = editable && _mapFocused && !_textFocused;
      final hasNodes = workspaceState?.selectedCardIds.isNotEmpty ?? false;
      final readerCopy = command == MindMapCommand.copy && (selectionOpen || (highlightOpen && highlightText));
      final enabled = _textFocused || (mapClipboard && (command == MindMapCommand.paste || hasNodes)) || readerCopy;
      edit.add(
        AppCommand(
          switch (command) {
            MindMapCommand.copy => l.copyAction,
            MindMapCommand.cut => l.cutNodes,
            _ => l.pasteNodes,
          },
          enabled
              ? () {
                  final focus = FocusManager.instance.primaryFocus?.context;
                  if (focus == null) return;
                  if (_textFocused) {
                    final Intent intent = switch (command) {
                      MindMapCommand.copy => CopySelectionTextIntent.copy,
                      MindMapCommand.cut => const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
                      _ => const PasteTextIntent(SelectionChangedCause.keyboard),
                    };
                    Actions.maybeInvoke(focus, intent);
                  } else if (mapClipboard) {
                    Actions.maybeInvoke(focus, MindMapIntent(command));
                  } else {
                    invokeSelection(ReaderSelectionCommand.copy);
                  }
                }
              : null,
          shortcut: mindMapShortcuts.entries.firstWhere((e) => e.value == command).key,
        ),
      );
    }
    final sharedHighlightCard = switch (workspaceState?.pending) {
      PendingHighlight(:final annotationId) => workspace?.content.cardForAnnotation(annotationId),
      _ => null,
    };
    final highlightCard =
        sharedHighlightCard != null &&
            workspace!.content.node(sharedHighlightCard.id, mapId: workspaceState!.activeMapId) != null
        ? sharedHighlightCard
        : null;
    edit.addAll([
      for (final entry in {
        ReaderSelectionCommand.excerpt: highlightOpen ? l.addToMapAction : l.excerptAction,
        ReaderSelectionCommand.highlight: l.highlightAction,
        ReaderSelectionCommand.note: l.excerptWithNote,
        ReaderSelectionCommand.locateCard: l.locateCard,
        ReaderSelectionCommand.deleteHighlight: l.deleteHighlight,
      }.entries)
        AppCommand(
          entry.value,
          (selectionOpen &&
                      entry.key != ReaderSelectionCommand.locateCard &&
                      entry.key != ReaderSelectionCommand.deleteHighlight) ||
                  (highlightOpen &&
                      (entry.key == ReaderSelectionCommand.copy ||
                          entry.key == ReaderSelectionCommand.deleteHighlight ||
                          (entry.key == ReaderSelectionCommand.excerpt && highlightCard == null) ||
                          (entry.key == ReaderSelectionCommand.locateCard && highlightCard != null)))
              ? () => invokeSelection(entry.key)
              : null,
          shortcut: readerSelectionShortcuts.entries
              .where((e) => e.value.command == entry.key)
              .map((e) => e.key as SingleActivator)
              .firstOrNull,
        ),
    ]);
    final study = [
      AppCommand(
        l.startReview,
        inWorkspace ? () => nav.startReview(workspaceId, mapId: workspaceState!.activeMapId) : null,
        shortcut: AppShortcuts.review,
      ),
    ];
    final map = <AppCommand>[
      AppCommand(
        l.cardTags,
        editable && selected != null ? () => showCardTagsSheet(context, ref, workspaceId!, selected) : null,
      ),
      if (workspace != null)
        for (final map in workspace.content.maps) ...[
          AppCommand(map.title.isEmpty ? l.mainMap : map.title, editable ? () => workspace.selectMap(map.id) : null),
          if (selected != null && workspace.content.node(selected, mapId: map.id) == null)
            AppCommand(
              l.addToNamedMap(map.title.isEmpty ? l.mainMap : map.title),
              editable ? () => workspace.placeCardInMap(selected, map.id) : null,
            ),
        ],
      AppCommand(l.newMap, editable ? () => showNewMapSheet(context, ref, workspaceId!) : null),
      AppCommand(
        l.renameMap,
        editable ? () => showMapRenameSheet(context, ref, workspaceId!, workspaceState!.activeMapId) : null,
      ),
      AppCommand(
        l.deleteMap,
        editable && workspace.content.maps.length > 1 ? () => workspace.removeMap(workspaceState!.activeMapId) : null,
      ),
      AppCommand(
        l.addTopic,
        editable ? () => workspace.addTopicAndEdit(l.newTopicName) : null,
        shortcut: AppShortcuts.addTopic,
      ),
      AppCommand(
        l.addNote,
        editable ? () => workspace.addNoteAndEdit(l.newNoteText) : null,
        shortcut: AppShortcuts.addNote,
      ),
      AppCommand(
        l.revealSource,
        workspace != null &&
                selected != null &&
                workspace.content.annotation(workspace.content.card(selected)?.annotationId ?? '') != null
            ? () => workspace.revealCard(selected)
            : null,
        shortcut: AppShortcuts.revealSource,
      ),
    ];
    final mapLabels = {
      MindMapCommand.siblingAfter: l.addSiblingAfter,
      MindMapCommand.siblingBefore: l.addSiblingBefore,
      MindMapCommand.child: l.addChildTopic,
      MindMapCommand.promote: l.promoteNode,
      MindMapCommand.parent: l.insertParentNode,
      MindMapCommand.edit: l.renameTitle,
      MindMapCommand.delete: l.removeFromMap,
      MindMapCommand.fold: l.toggleNodeFold,
      MindMapCommand.up: l.moveUp,
      MindMapCommand.down: l.moveDown,
      MindMapCommand.fit: l.fitMap,
      MindMapCommand.center: l.centerCurrentNode,
      MindMapCommand.relation: l.addRelation,
      MindMapCommand.summary: l.addSummary,
    };
    // Dispatch through the focused canvas so menu and keyboard run the same action.
    // The outline always shows the whole tree: folding, fitting and
    // centering only apply to the map.
    // Relations and summaries are drawn on the map only.
    const mapOnly = {
      MindMapCommand.fold,
      MindMapCommand.fit,
      MindMapCommand.center,
      MindMapCommand.relation,
      MindMapCommand.summary,
    };
    final inOutline = workspaceState?.mapView == MapViewMode.outline;
    for (final entry in mapLabels.entries) {
      map.add(
        AppCommand(
          entry.value,
          editable && _mapFocused && !_textFocused && !(inOutline && mapOnly.contains(entry.key))
              ? () {
                  final focus = FocusManager.instance.primaryFocus?.context;
                  if (focus != null) Actions.maybeInvoke(focus, MindMapIntent(entry.key));
                }
              : null,
          shortcut: mindMapShortcuts.entries.where((e) => e.value == entry.key).firstOrNull?.key,
        ),
      );
    }
    map.addAll([
      for (final color in MMAnnotationColor.values)
        AppCommand(
          l.colorName(color),
          editable &&
                  _mapFocused &&
                  !_textFocused &&
                  (workspaceState?.selectedCardIds.any((id) => workspace.content.card(id)?.annotationId != null) ??
                      false)
              ? () => workspace.recolorCards(workspaceState!.selectedCardIds, color)
              : null,
        ),
    ]);
    final view = <AppCommand>[
      if (inLibrary) ...[
        AppCommand(
          l.viewAsIcons,
          () => ref.read(libraryViewProvider.notifier).setViewMode(LibraryViewMode.grid),
          shortcut: AppShortcuts.view1,
        ),
        AppCommand(
          l.viewAsList,
          () => ref.read(libraryViewProvider.notifier).setViewMode(LibraryViewMode.list),
          shortcut: AppShortcuts.view2,
        ),
        AppCommand(
          l.hideSidebar,
          ref.read(libraryViewProvider.notifier).toggleSidebar,
          shortcut: AppShortcuts.toggleSidebar,
        ),
      ],
      if (inWorkspace) ...[
        AppCommand(l.toggleAnnotationTool, workspace!.toggleTool, shortcut: AppShortcuts.toggleAnnotationTool),
        AppCommand(l.toggleAreaTool, workspace.toggleAreaTool, shortcut: AppShortcuts.toggleAreaTool),
        AppCommand(
          l.layoutReader,
          () => ref.read(workspaceProvider(workspaceId).notifier).setLayout(MMSplitMode.primary),
          shortcut: AppShortcuts.view1,
        ),
        AppCommand(
          l.layoutSplit,
          () => ref.read(workspaceProvider(workspaceId).notifier).setLayout(MMSplitMode.split),
          shortcut: AppShortcuts.view2,
        ),
        AppCommand(
          l.layoutMap,
          () => ref.read(workspaceProvider(workspaceId).notifier).setLayout(MMSplitMode.secondary),
          shortcut: AppShortcuts.view3,
        ),
        AppCommand(
          l.hideSidebar,
          ref.read(workspaceProvider(workspaceId).notifier).toggleSidebar,
          shortcut: AppShortcuts.toggleSidebar,
        ),
      ],
      if (inWorkspace) ...[
        AppCommand(
          workspaceState!.readerPanelVisible ? l.hideReaderSidebar : l.showReaderSidebar,
          hasDocument ? workspace.toggleReaderPanel : null,
          shortcut: AppShortcuts.toggleReaderSidebar,
        ),
        for (final (mode, label, shortcut) in [
          (ReaderPanelMode.thumbnails, l.readerThumbnails, AppShortcuts.readerThumbnails),
          (ReaderPanelMode.outline, l.readerOutline, AppShortcuts.readerOutline),
          (ReaderPanelMode.bookmarks, l.readerBookmarks, AppShortcuts.readerBookmarks),
          (ReaderPanelMode.annotations, l.readerAnnotations, AppShortcuts.readerAnnotations),
        ])
          AppCommand(label, hasDocument ? () => workspace.showReaderPanel(mode) : null, shortcut: shortcut),
      ],
      // ⌘F finds in the PDF when the keyboard is in the reader, else in the sidebar.
      AppCommand(
        findsInDocument ? l.findInDocument : l.search,
        findsInDocument
            ? workspace.openFind
            : (inLibrary || inWorkspace)
            ? () => ref.read(focusRequestsProvider.notifier).request(FocusTarget.search)
            : null,
        shortcut: AppShortcuts.find,
      ),
    ];
    final go = [
      AppCommand(
        l.findNext,
        canRead && workspaceState.findVisible ? () => pdf!.nextMatch() : null,
        shortcut: AppShortcuts.findNext,
      ),
      AppCommand(
        l.findPrevious,
        canRead && workspaceState.findVisible ? () => pdf!.previousMatch() : null,
        shortcut: AppShortcuts.findPrevious,
      ),
      AppCommand(
        bookmarked ? l.removeBookmark : l.addBookmark,
        canRead && !_textFocused ? workspace.toggleBookmark : null,
        shortcut: AppShortcuts.toggleBookmark,
      ),
      AppCommand(l.goBack, canRead && !_textFocused ? () => pdf!.goBack() : null, shortcut: AppShortcuts.goBack),
      AppCommand(
        l.firstPage,
        canRead && !_textFocused ? () => pdf!.firstPage() : null,
        shortcut: AppShortcuts.firstPage,
      ),
      AppCommand(l.lastPage, canRead && !_textFocused ? () => pdf!.lastPage() : null, shortcut: AppShortcuts.lastPage),
    ];
    // The component gallery is a developer tool.
    final help = [if (kDebugMode) AppCommand(l.componentGallery, nav.showGallery, shortcut: AppShortcuts.gallery)];

    if (DesktopWindow.isMacOS) {
      return PlatformMenuBar(
        menus: [
          PlatformMenu(
            label: l.appName,
            menus: [
              _provided(PlatformProvidedMenuItemType.about),
              PlatformMenuItemGroup(members: [_item(settings)]),
              _provided(PlatformProvidedMenuItemType.servicesSubmenu),
              PlatformMenuItemGroup(
                members: [
                  ?_maybeProvided(PlatformProvidedMenuItemType.hide),
                  ?_maybeProvided(PlatformProvidedMenuItemType.hideOtherApplications),
                  ?_maybeProvided(PlatformProvidedMenuItemType.showAllApplications),
                ],
              ),
              _provided(PlatformProvidedMenuItemType.quit),
            ],
          ),
          PlatformMenu(
            label: l.menuFile,
            menus: [
              PlatformMenuItemGroup(members: [for (final c in file.take(3)) _item(c)]),
              PlatformMenuItemGroup(members: [for (final c in file.skip(3)) _item(c)]),
            ],
          ),
          PlatformMenu(label: l.menuEdit, menus: [for (final c in edit) _item(c)]),
          PlatformMenu(
            label: l.menuView,
            menus: [
              PlatformMenuItemGroup(members: [for (final c in view) _item(c)]),
              _provided(PlatformProvidedMenuItemType.toggleFullScreen),
            ],
          ),
          PlatformMenu(label: l.menuGo, menus: [for (final c in go) _item(c)]),
          PlatformMenu(
            label: l.menuMap,
            menus: [
              PlatformMenuItemGroup(members: [for (final c in map) _item(c)]),
              PlatformMenuItemGroup(members: [for (final c in study) _item(c)]),
            ],
          ),
          PlatformMenu(
            label: l.menuWindow,
            menus: [
              _provided(PlatformProvidedMenuItemType.minimizeWindow),
              _provided(PlatformProvidedMenuItemType.zoomWindow),
              _provided(PlatformProvidedMenuItemType.arrangeWindowsInFront),
            ],
          ),
          PlatformMenu(label: l.menuHelp, menus: [for (final c in help) _item(c)]),
        ],
        child: widget.child,
      );
    }

    return CallbackShortcuts(
      bindings: {
        for (final c in [settings, ...file, ...edit, ...view, ...go, ...map, ...study, ...help])
          if (c.shortcut != null && c.onInvoke != null) c.shortcut!: c.onInvoke!,
      },
      child: Focus(autofocus: true, child: widget.child),
    );
  }

  static PlatformMenuItem _item(AppCommand c) =>
      PlatformMenuItem(label: c.label, shortcut: c.shortcut, onSelected: c.onInvoke);

  static PlatformMenuItem _provided(PlatformProvidedMenuItemType type) =>
      PlatformMenuItemGroup(members: [?_maybeProvided(type)]);

  static PlatformMenuItem? _maybeProvided(PlatformProvidedMenuItemType type) =>
      PlatformProvidedMenuItem.hasMenu(type) ? PlatformProvidedMenuItem(type: type) : null;
}
