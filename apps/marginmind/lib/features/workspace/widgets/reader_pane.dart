import 'dart:async';

import 'reading_settings.dart';
import '../../vocabulary/pdf_hints.dart';
import '../../vocabulary/hint_controls.dart';
import '../../vocabulary/vocabulary_source_flash.dart';
import 'reader_page_field.dart';
import '../reflow_session.dart';
import '../../../shared/document_icon.dart';
import '../document_reader.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../app/app_commands.dart';
import '../../../app/navigation.dart';
import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import '../../../settings/app_settings.dart';
import '../../research/widgets/research_note_popover.dart';
import '../workspace_controller.dart';
import 'notices.dart';
import 'reader_find_bar.dart';
import '../workspace_browser.dart';
import 'browser_pane.dart';
import '../reader_crop.dart';
import '../reader_compare.dart';
import '../reader_translation.dart';
import 'reader_compare_controls.dart';
import 'reader_zoom_control.dart';
import '../translation_task_summary.dart';
import 'full_translation_sheet.dart';
import 'full_translation_panel.dart';
import '../reader_margin.dart';
import 'reader_margin_notes.dart';
import 'reader_crop_controls.dart';
import 'reader_sidebar.dart';
import 'reader_annotation_tools.dart';
import 'reader_toolbar.dart';
import '../workspace_chrome_controller.dart';
import 'document_switcher.dart';
import 'workspace_toolbar.dart';
import '../workspace_pane_chrome_controller.dart';
import 'highlight_color_button.dart';
import 'underline_tool_button.dart';
import 'annotation_palette.dart' show annotationTapGroup;
import 'reader_ink_toolbar.dart';
import 'selection_toolbar.dart';
import '../reader_ocr.dart';
import 'reader_ocr_controls.dart';
import 'web_source.dart';

/// Source pane: document renderer, tools, document switcher and navigation.
class ReaderPane extends ConsumerStatefulWidget {
  const ReaderPane({super.key, required this.studySetId});

  final String studySetId;

  @override
  ConsumerState<ReaderPane> createState() => _ReaderPaneState();
}

class _ReaderPaneState extends ConsumerState<ReaderPane> {
  WorkspacePaneChromeController? _paneChrome;
  WorkspaceChromeController? _chrome;
  final _selectionHolds = <Object>{};
  final _pdfPointers = <int>{};
  Offset? _pointerStart;
  bool _pointerMoved = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chrome = WorkspaceChromeScope.maybeOf(context);
    final next = WorkspacePaneChromeScope.maybeOf(context);
    if (!identical(next, _paneChrome)) {
      _paneChrome?.unbindReader(this);
      _paneChrome = next;
    }
  }

  final _focus = FocusNode(debugLabel: 'PDF reader', skipTraversal: true);

  /// Counts the menu's "Go to Page…" requests; the page field opens on each.
  int _pageFieldRequests = 0;
  bool _hoveringNavigation = false;
  bool _navigationFocused = false;

  bool get _navigationVisible =>
      MMInput.touchInputOf(context) || _hoveringNavigation || _navigationFocused || _scrubPage != null;
  double? _scrubPage;

  MMPdfViewController get _pdf => ref.read(readerPdfProvider(widget.studySetId));

  int? _vocabularyRevealNonce;

  @override
  void dispose() {
    _paneChrome?.unbindReader(this);
    for (final reason in _selectionHolds) {
      _chrome?.release(reason);
    }
    _focus.dispose();
    super.dispose();
  }

  void _zoom(ReaderZoomCommand command) {
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    final doc = workspace.content.document(ref.read(workspaceProvider(widget.studySetId)).activeDocumentId ?? '');
    if (doc?.contentManifest != null && doc!.capabilities().zoom) {
      final session = ref.read(reflowSessionProvider((widget.studySetId, doc.id)));
      switch (command) {
        case ReaderZoomCommand.zoomIn:
          session.zoomTo(session.zoom * MMReaderLayout.zoomStep);
        case ReaderZoomCommand.zoomOut:
          session.zoomTo(session.zoom / MMReaderLayout.zoomStep);
        case ReaderZoomCommand.actualSize:
          session.actualSize();
        case ReaderZoomCommand.fitWidth:
          session.fitWidth();
        case ReaderZoomCommand.fitPage:
          session.fitPage();
      }
      return;
    }
    if (doc?.capabilities().readingSettings == true) {
      final compare = ref.read(readerCompareProvider(widget.studySetId).notifier);
      final comparing = ref.read(readerCompareProvider(widget.studySetId)) != null;
      final settings = comparing
          ? compare.reading(doc!.id, doc.format)
          : ref.read(settingsProvider).reading(doc!.format);
      final size = switch (command) {
        ReaderZoomCommand.zoomIn => settings.size + 1,
        ReaderZoomCommand.zoomOut => settings.size - 1,
        _ => MMReaderTypography.defaultSize,
      };
      if (comparing) {
        compare.setReading(doc.id, settings.copyWith(size: size));
      } else {
        ref.read(settingsProvider.notifier).setReading(doc.format, settings.copyWith(size: size));
      }
      return;
    }
    if (ref.read(readerCropProvider(widget.studySetId)).editing) return;
    switch (command) {
      case ReaderZoomCommand.zoomIn:
        _pdf.zoomIn();
      case ReaderZoomCommand.zoomOut:
        _pdf.zoomOut();
      case ReaderZoomCommand.actualSize:
        _pdf.actualSize();
      case ReaderZoomCommand.fitWidth:
        _pdf.fitWidth();
      case ReaderZoomCommand.fitPage:
        _pdf.fitPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final browser = ref.watch(workspaceBrowserProvider(widget.studySetId));
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    final content = ref.watch(workspaceContentProvider(widget.studySetId)) ?? StudySetContent.empty;
    Widget browserChrome(Widget child) => WorkspaceToolbarScope.maybeOf(context) == null
        ? child
        : Column(
            children: [
              WorkspaceToolbar(items: const [], menuEntries: const [], label: context.l10n.moreTools),
              Expanded(child: child),
            ],
          );
    return Stack(
      children: [
        Offstage(
          offstage: browser.visible,
          child: ExcludeFocus(excluding: browser.visible, child: _buildReader(context)),
        ),
        if (browser.session case final session?)
          Offstage(
            offstage: !browser.visible,
            child: browserChrome(
              BrowserPane(
                key: ValueKey(session.id),
                studySetId: widget.studySetId,
                session: session,
                visible: browser.visible,
                documentSwitcher: DocumentSwitcher(
                  studySetId: widget.studySetId,
                  documents: content.documents,
                  activeDocumentId: null,
                  onOpen: (id) {
                    ref.read(workspaceBrowserProvider(widget.studySetId).notifier).hide();
                    workspace.openDocument(id);
                  },
                  onClose: null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReader(BuildContext context) {
    final c = context.mmColors;
    final provider = workspaceProvider(widget.studySetId);
    ref.listen(provider.select((s) => s.activeDocumentId), (_, _) {
      for (final reason in _selectionHolds) {
        _chrome?.release(reason);
      }
      _selectionHolds.clear();
    });
    ref.listen(focusRequestsProvider, (_, next) {
      if (next?.$1 == FocusTarget.pageField) setState(() => _pageFieldRequests++);
    });
    ref.watch(
      provider.select(
        (s) => (
          s.activeDocumentId,
          s.openDocumentIds,
          s.tool,
          s.pending,
          s.selectedCardId,
          s.activeMapId,
          s.flashAnnotationId,
          s.reveal,
          s.readerPanelVisible,
          s.findVisible,
          s.findFocusTick,
          s.inkTool,
          s.inkColor,
          s.inkWidth,
          s.canUndo,
        ),
      ),
    );
    final comparing = ref.watch(readerCompareProvider(widget.studySetId)) != null;
    final marginState = ref.watch(readerMarginProvider(widget.studySetId));
    ref.listen(readerMarginProvider(widget.studySetId).select((s) => s.deleted), (before, next) {
      if (before != next) {
        MMHud.show(
          context,
          context.l10n.marginNoteDeleted,
          action: (context.l10n.undo, () => ref.read(provider.notifier).undo()),
        );
      }
    });
    ref.listen(readerMarginProvider(widget.studySetId).select((s) => s.errors), (before, next) {
      if (before != next) MMHud.show(context, context.l10n.somethingWentWrong);
    });
    final cropState = ref.watch(readerCropProvider(widget.studySetId));
    final cropSession = ref.read(readerCropProvider(widget.studySetId).notifier);
    ref.listen(readerCropProvider(widget.studySetId).select((s) => s.editing), (_, editing) {
      if (editing) _focus.requestFocus();
    });
    final state = ref.read(provider);
    final controller = ref.read(provider.notifier);
    final content = ref.watch(workspaceContentProvider(widget.studySetId)) ?? StudySetContent.empty;
    final doc = state.activeDocumentId == null ? null : content.document(state.activeDocumentId!);
    final rootTitle = ref.watch(studySetProvider(widget.studySetId).select((s) => s?.title)) ?? '';

    final reveal = state.reveal;
    if (reveal != null && reveal.textAnchors.isEmpty && reveal.nonce != _vocabularyRevealNonce) {
      _vocabularyRevealNonce = reveal.nonce;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final latest = ref.read(provider);
        if (latest.reveal?.nonce == reveal.nonce &&
            latest.activeDocumentId == reveal.documentId &&
            controller.claimPdfReveal(reveal.nonce)) {
          _pdf.reveal(reveal.page, reveal.rects);
        }
      });
    }

    void dismissSelection() {
      if (ref.read(provider).pending != null) {
        controller.dismissPending();
        _pdf.clearSelection();
      }
    }

    ref.listen(provider.select((s) => s.tool), (_, tool) {
      if (tool == AnnotationTool.underline) _pdf.clearSelection();
    });

    ref.listen(provider.select((s) => s.findVisible), (was, visible) {
      if (visible) return;
      _pdf.clearSearch();
      // Closing the find bar hands the keyboard back to the reader.
      if (was == true && mounted) _focus.requestFocus();
    });

    return Actions(
      actions: {
        ReaderZoomIntent: CallbackAction<ReaderZoomIntent>(
          onInvoke: (intent) {
            if (controller.activeCapabilities.zoom || controller.activeCapabilities.readingSettings) {
              _zoom(intent.command);
            }
            return null;
          },
        ),
        ReaderNavIntent: CallbackAction<ReaderNavIntent>(
          onInvoke: (intent) {
            if (doc?.contentManifest != null) {
              controller.dismissPending();
              final session = ref.read(reflowSessionProvider((widget.studySetId, doc!.id)));
              if (session.book != null) {
                session.jump(intent.command == ReaderNavCommand.firstPage ? session.book!.start : session.book!.end);
              }
              return null;
            }
            if (!controller.activeCapabilities.zoom) return null;
            dismissSelection();
            return switch (intent.command) {
              ReaderNavCommand.firstPage => _pdf.firstPage(),
              ReaderNavCommand.lastPage => _pdf.lastPage(),
            };
          },
        ),
      },
      child: Shortcuts(
        shortcuts: {...readerNavShortcuts, ...readerZoomShortcuts},
        child: CallbackShortcuts(
          bindings: {
            AppShortcuts.toggleMarginNotes: () {
              final id = ref.read(provider).activeDocumentId;
              if (controller.activeCapabilities.marginNotes && !comparing && id != null) {
                ref.read(readerMarginProvider(widget.studySetId).notifier).toggle(id);
              }
            },
            AppShortcuts.toggleCrop: () {
              if (controller.activeCapabilities.crop) toggleReaderCrop(context, ref, widget.studySetId);
            },
            if (marginState.popup.isNotEmpty)
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  ref.read(readerMarginProvider(widget.studySetId).notifier).close(),
            if (cropState.editing && marginState.popup.isEmpty) ...{
              const SingleActivator(LogicalKeyboardKey.escape): cropSession.cancel,
              const SingleActivator(LogicalKeyboardKey.enter): () =>
                  completeReaderCrop(context, ref, widget.studySetId),
              const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
                  completeReaderCrop(context, ref, widget.studySetId),
            } else if (comparing &&
                state.tool == AnnotationTool.select &&
                state.pending == null &&
                marginState.draft == null &&
                marginState.popup.isEmpty)
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  ref.read(readerCompareProvider(widget.studySetId).notifier).exit(),
            if (state.tool == AnnotationTool.underline && marginState.popup.isEmpty && !cropState.editing)
              const SingleActivator(LogicalKeyboardKey.escape): () => controller.setTool(AnnotationTool.select),
            if (state.tool == AnnotationTool.ink && marginState.popup.isEmpty)
              const SingleActivator(LogicalKeyboardKey.escape): controller.exitInk,
          },
          child: Focus(
            focusNode: _focus,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              // Clicking anywhere in the pane makes it the keyboard's home
              // (⌘F finds in the document), unless a field inside has it.
              onPointerDown: (_) {
                if (!_focus.hasFocus) _focus.requestFocus();
              },
              child: ColoredBox(
                color: c.readerBackground,
                child: _body(context, state, controller, content, doc, rootTitle, dismissSelection),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The reader's tool row. A regular window shows every tool and wraps if it
  /// must; a narrower one keeps one line and moves zoom and appearance into
  /// "More".
  Widget _toolbar(
    BuildContext context,
    WorkspaceState state,
    WorkspaceController controller,
    MMReaderStyle style,
    String? ocrSource,
  ) {
    if (WorkspaceToolbarScope.maybeOf(context) == null) {
      return _legacyToolbar(context, state, controller, style, ocrSource);
    }
    final l = context.l10n;
    final capabilities = controller.activeCapabilities;
    final settingsHandler = ref.watch(readingSettingsHandlerProvider);
    final comparing = ref.watch(readerCompareProvider(widget.studySetId)) != null;
    final crop = ref.watch(readerCropProvider(widget.studySetId));
    final cropSession = ref.read(readerCropProvider(widget.studySetId).notifier);
    final document = controller.content.documents.where((d) => d.id == state.activeDocumentId).firstOrNull;
    void pageCommand(Object value) {
      if (value is ReaderZoomCommand) _zoom(value);
      if (value == 'crop-adjust') cropSession.adjust();
    }

    final canAdjustCrop = capabilities.crop && !crop.editing && !crop.busy && _pdf.isReady;
    void setStyle(MMReaderStyle value) => ref.read(settingsProvider.notifier).setReaderStyle(value);
    final marginState = ref.watch(readerMarginProvider(widget.studySetId));
    final canFullTranslate =
        MMPlatformCapabilities.current.assistant &&
        MMSizeClass.of(context) != MMSizeClass.compact &&
        document?.format == DocumentFormat.pdf;
    final fullState = canFullTranslate
        ? ref.watch(translationTaskSummaryProvider((widget.studySetId, document!.id))).value
        : null;
    final hasActiveFullJob = fullState?.isActive == true;

    final commands = <String, WorkspacePaneCommand>{};
    VoidCallback? command(String id, VoidCallback? invoke, {bool selected = false}) {
      commands[id] = WorkspacePaneCommand(invoke, selected: selected);
      if (invoke == null) return null;
      return () {
        final adapter = _paneChrome?.reader;
        if (adapter == null) {
          invoke();
        } else {
          adapter.execute(id);
        }
      };
    }

    PopupMenuEntry<VoidCallback> entry(
      String label,
      VoidCallback? action, {
      bool selected = false,
      IconData? icon,
      String? id,
    }) => MMDropdownItem<VoidCallback>(
      key: id == null ? null : ValueKey(id),
      value: command(id ?? label, action, selected: selected),
      enabled: action != null,
      child: Semantics(
        selected: selected,
        child: Row(
          children: [
            if (icon != null) ...[Icon(icon, size: MMSizes.dropdownIcon), const SizedBox(width: MMSpacing.s)],
            Expanded(child: Text(label)),
            if (selected) const Icon(MMIcons.check, size: 14),
          ],
        ),
      ),
    );
    final tools = [
      (AnnotationTool.select, MMIcons.select, l.toolSelect, 60),
      (AnnotationTool.highlight, MMIcons.highlight, l.toolHighlight, 50),
      (AnnotationTool.underline, MMIcons.underline, l.toolUnderline, 40),
      (AnnotationTool.ink, MMIcons.pen, l.toolPen, 30),
      (AnnotationTool.area, MMIcons.areaSelect, l.toolArea, 10),
    ];
    final documents = DocumentSwitcher(
      studySetId: widget.studySetId,
      documents: controller.content.documents,
      activeDocumentId: state.activeDocumentId,
      primaryCompare: comparing,
      onOpen: controller.openDocument,
      onClose: document == null ? null : () => controller.closeDocument(document.id),
    );
    final items = <MMToolbarItem>[
      MMToolbarItem(
        id: 'navigation',
        priority: 90,
        child: MMToolbarButton(
          key: const ValueKey('reader-navigation'),
          icon: MMIcons.readerNavigation,
          tooltip: AppShortcuts.tip(
            state.readerPanelVisible ? l.hideReaderSidebar : l.showReaderSidebar,
            AppShortcuts.toggleReaderSidebar,
          ),
          selected: state.readerPanelVisible,
          onPressed: command(
            'reader-navigation',
            capabilities.thumbnails || capabilities.outline || capabilities.bookmarks || capabilities.annotate
                ? controller.toggleReaderPanel
                : null,
            selected: state.readerPanelVisible,
          ),
        ),
        menuEntry: entry(
          state.readerPanelVisible ? l.hideReaderSidebar : l.showReaderSidebar,
          capabilities.thumbnails || capabilities.outline || capabilities.bookmarks || capabilities.annotate
              ? controller.toggleReaderPanel
              : null,
          selected: state.readerPanelVisible,
          icon: MMIcons.readerNavigation,
          id: 'reader-navigation',
        ),
      ),
      for (final (tool, icon, label, priority) in tools)
        MMToolbarItem(
          id: tool.name,
          priority: priority,
          child: IgnorePointer(
            ignoring: crop.editing,
            child: Opacity(
              opacity: crop.editing ? .3 : 1,
              child: tool == AnnotationTool.highlight
                  ? HighlightColorButton(
                      color: state.color,
                      selected: state.tool == tool,
                      enabled: capabilities.annotate && !crop.editing,
                      onOpen: () => controller.setTool(tool),
                      onChanged: controller.setColor,
                    )
                  : tool == AnnotationTool.underline
                  ? UnderlineToolButton(studySetId: widget.studySetId, enabled: capabilities.annotate && !crop.editing)
                  : MMToolbarButton(
                      icon: icon,
                      tooltip: switch (tool) {
                        AnnotationTool.area => AppShortcuts.tip(label, AppShortcuts.toggleAreaTool),
                        AnnotationTool.ink => AppShortcuts.tip(label, AppShortcuts.toggleInkTool),
                        _ => label,
                      },
                      selected: state.tool == tool,
                      onPressed: command(
                        'tool-${tool.name}',
                        !crop.editing && controller.canUseTool(tool) ? () => controller.setTool(tool) : null,
                        selected: state.tool == tool,
                      ),
                    ),
            ),
          ),
          menuEntry: entry(
            label,
            !crop.editing && controller.canUseTool(tool) ? () => controller.setTool(tool) : null,
            selected: state.tool == tool,
            icon: switch (tool) {
              AnnotationTool.select => MMReaderIcons.select,
              AnnotationTool.ink => MMReaderIcons.pen,
              AnnotationTool.area => MMReaderIcons.area,
              _ => icon,
            },
            id: 'tool-${tool.name}',
          ),
        ),
      MMToolbarItem(
        id: 'sync',
        priority: 20,
        child: MMToolbarButton(
          icon: MMIcons.syncToMap,
          tooltip: state.syncToMap ? l.syncToMapOn : l.syncToMapOff,
          selected: state.syncToMap,
          onPressed: command(
            'sync',
            capabilities.excerpt && !crop.editing ? controller.toggleSyncToMap : null,
            selected: state.syncToMap,
          ),
        ),
        menuEntry: entry(
          state.syncToMap ? l.syncToMapOn : l.syncToMapOff,
          capabilities.excerpt && !crop.editing ? controller.toggleSyncToMap : null,
          selected: state.syncToMap,
          icon: MMReaderIcons.syncToMap,
        ),
      ),
      if (!MMInput.of(context).phone && MMSizeClass.of(context) != MMSizeClass.compact)
        MMToolbarItem(
          id: 'compare',
          priority: 80,
          child: ReaderCompareMenu(studySetId: widget.studySetId, enabled: capabilities.parallel && !crop.editing),
          menuEntry: PopupMenuItem<VoidCallback>(
            enabled: false,
            height: MMSizes.dropdownRowHeight,
            padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s, vertical: MMSpacing.xs),
            child: ReaderCompareMenu(
              studySetId: widget.studySetId,
              enabled: capabilities.parallel && !crop.editing,
              menuLabel: l.compareReading,
              onInvoked: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      MMToolbarItem(
        id: 'documents',
        priority: 70,
        child: documents,
        menuEntry: entry(
          l.switchDocument,
          () => showMMMenu(context, position: Offset.zero, entries: documents.menuEntries(context, ref)),
          icon: MMIcons.collections,
        ),
      ),
    ];
    // Rich zoom controls remain available alongside grouped reader commands.
    final menuEntries = <PopupMenuEntry<VoidCallback>>[
      MMDropdownHeader<VoidCallback>(l.readerMenuReading),
      entry(
        l.marginNotes,
        capabilities.marginNotes && document != null && !crop.editing && !comparing
            ? () => ref.read(readerMarginProvider(widget.studySetId).notifier).toggle(document.id)
            : null,
        selected: marginState.openDocuments.contains(state.activeDocumentId),
        icon: MMReaderIcons.marginNote,
        id: 'reader-margin',
      ),
      if (document != null)
        entry(
          l.vocabularyHints,
          () => toggleVocabularyHints(context, ref, document.id),
          icon: MMIcons.vocabulary,
          id: 'vocabulary-hint-toggle',
        ),
      entry(
        l.readingSettings,
        () {
          if (capabilities.readingSettings) {
            settingsHandler?.call(context, ref, widget.studySetId);
          } else {
            showReadingSettings(context, ref, widget.studySetId);
          }
        },
        icon: MMIcons.readingSettings,
        id: 'reader-settings',
      ),
      if (canFullTranslate)
        entry(
          hasActiveFullJob ? l.fullTranslationTaskMenu(fullState!.percent) : l.fullTranslationMenu,
          () => unawaited(
            hasActiveFullJob
                ? showFullTranslationPanel(
                    context,
                    studySetId: widget.studySetId,
                    documentId: document!.id,
                    targetLang: fullState!.targetLang,
                  )
                : showFullTranslationSheet(context, studySetId: widget.studySetId, documentId: document!.id),
          ),
          icon: MMIcons.layers,
          id: 'full-translation',
        ),
      const PopupMenuDivider(),
      MMDropdownHeader<VoidCallback>(l.readerMenuPage),
      PopupMenuItem<VoidCallback>(
        enabled: false,
        child: document?.contentManifest != null
            ? ReaderZoomSlider.source(
                ratio: () {
                  final session = ref.read(reflowSessionProvider((widget.studySetId, document!.id)));
                  return session.zoom / session.widthZoom;
                },
                ready: () => ref.read(reflowSessionProvider((widget.studySetId, document!.id))).ready,
                onZoom: (ratio) {
                  final session = ref.read(reflowSessionProvider((widget.studySetId, document!.id)));
                  session.zoomTo(ratio * session.widthZoom);
                },
                enabled: capabilities.zoom && !crop.editing,
              )
            : ReaderZoomSlider(pdf: _pdf, enabled: capabilities.zoom && !crop.editing),
      ),
      for (final command in [
        (ReaderZoomCommand.actualSize, l.pdfActualSize, MMReaderIcons.actualSize),
        (ReaderZoomCommand.fitWidth, l.pdfFitWidth, MMReaderIcons.fitWidth),
        (ReaderZoomCommand.fitPage, l.pdfFitPage, MMReaderIcons.fitPage),
      ])
        entry(command.$2, capabilities.zoom && !crop.editing ? () => pageCommand(command.$1) : null, icon: command.$3),
      entry(l.cropMargins, canAdjustCrop ? cropSession.adjust : null, icon: MMReaderIcons.crop, id: 'reader-crop'),
      const PopupMenuDivider(),
      MMDropdownHeader<VoidCallback>(l.readerAppearance),
      for (final value in MMReaderStyle.values)
        MMDropdownItem<VoidCallback>(
          value: () => setStyle(value),
          child: _styleRow(context, value, selected: value == style),
        ),
    ];
    _paneChrome?.bindReader(this, WorkspacePaneCommands(state.activeDocumentId, commands));
    return ReaderAnnotationTools(
      state: state,
      controller: controller,
      child: ReaderToolbar(
        items: items,
        menuEntries: menuEntries,
        label: l.moreTools,
        overflowLabel: l.readerMenuTools,
      ),
    );
  }

  Widget _legacyToolbar(
    BuildContext context,
    WorkspaceState state,
    WorkspaceController controller,
    MMReaderStyle style,
    String? ocrSource,
  ) {
    final l = context.l10n;
    final capabilities = controller.activeCapabilities;
    final settingsHandler = ref.watch(readingSettingsHandlerProvider);
    final compact = !context.mmTouch;
    final navigation = MMToolbarButton(
      compact: compact,
      icon: MMIcons.readerNavigation,
      tooltip: AppShortcuts.tip(
        state.readerPanelVisible ? l.hideReaderSidebar : l.showReaderSidebar,
        AppShortcuts.toggleReaderSidebar,
      ),
      selected: state.readerPanelVisible,
      onPressed: (capabilities.thumbnails || capabilities.outline || capabilities.bookmarks || capabilities.annotate)
          ? controller.toggleReaderPanel
          : null,
    );
    final comparing = ref.watch(readerCompareProvider(widget.studySetId)) != null;
    final crop = ref.watch(readerCropProvider(widget.studySetId));
    final cropSession = ref.read(readerCropProvider(widget.studySetId).notifier);
    final document = controller.content.documents.where((d) => d.id == state.activeDocumentId).firstOrNull;
    void pageCommand(Object value) {
      if (value is ReaderZoomCommand) _zoom(value);
      if (value == 'crop-adjust') cropSession.adjust();
    }

    final zoomItems = <PopupMenuEntry<Object>>[
      if (document?.contentManifest != null)
        ReaderZoomSlider.source(
          ratio: () =>
              ref.read(reflowSessionProvider((widget.studySetId, document!.id))).zoom /
              ref.read(reflowSessionProvider((widget.studySetId, document.id))).widthZoom,
          ready: () => ref.read(reflowSessionProvider((widget.studySetId, document!.id))).ready,
          onZoom: (ratio) {
            final session = ref.read(reflowSessionProvider((widget.studySetId, document!.id)));
            session.zoomTo(ratio * session.widthZoom);
          },
          enabled: capabilities.zoom && !crop.editing,
        )
      else
        ReaderZoomSlider(pdf: _pdf, enabled: capabilities.zoom && !crop.editing),
      for (final entry in [
        (ReaderZoomCommand.actualSize, l.pdfActualSize, MMIcons.actualSize),
        (ReaderZoomCommand.fitWidth, l.pdfFitWidth, MMIcons.fitWidth),
        (ReaderZoomCommand.fitPage, l.pdfFitPage, MMIcons.fitPage),
      ])
        MMDropdownItem<Object>(
          value: entry.$1,
          enabled: capabilities.zoom && !crop.editing,
          child: _menuRow(entry.$3, entry.$2),
        ),
    ];
    final canAdjustCrop = capabilities.crop && !crop.editing && !crop.busy && _pdf.isReady;
    final cropItems = <PopupMenuEntry<Object>>[
      MMDropdownItem<Object>(
        value: 'crop-adjust',
        enabled: canAdjustCrop,
        child: _menuRow(MMIcons.crop, l.cropMargins),
      ),
    ];
    final styleItems = [
      for (final value in MMReaderStyle.values)
        MMDropdownItem<Object>(
          value: value,
          child: _styleRow(context, value, selected: value == style),
        ),
    ];
    void setStyle(MMReaderStyle value) => ref.read(settingsProvider.notifier).setReaderStyle(value);
    final marginState = ref.watch(readerMarginProvider(widget.studySetId));
    final fullState = document == null
        ? null
        : ref.watch(translationTaskSummaryProvider((widget.studySetId, document.id))).value;
    final targetLang = fullState?.targetLang ?? 'zh';
    final hasActiveFullJob = fullState?.isActive == true;
    final canFullTranslate =
        MMPlatformCapabilities.current.assistant &&
        MMSizeClass.of(context) != MMSizeClass.compact &&
        document?.format == DocumentFormat.pdf;
    final marginButton = MMToolbarButton(
      key: const ValueKey('reader-margin'),
      compact: compact,
      icon: MMIcons.captionsBubble,
      tooltip: AppShortcuts.tip(l.marginNotes, AppShortcuts.toggleMarginNotes),
      selected: marginState.openDocuments.contains(state.activeDocumentId),
      onPressed: !capabilities.marginNotes || crop.editing || comparing || document == null
          ? null
          : () => ref.read(readerMarginProvider(widget.studySetId).notifier).toggle(document.id),
    );
    final hintButton = document == null
        ? const SizedBox.shrink()
        : VocabularyHintButton(documentId: document.id, compact: compact);
    final compareButton = ReaderCompareMenu(
      studySetId: widget.studySetId,
      enabled: capabilities.parallel && !crop.editing,
    );
    final annotation = IgnorePointer(
      ignoring: crop.editing,
      child: Opacity(
        opacity: crop.editing ? .4 : 1,
        child: ReaderAnnotationTools(state: state, controller: controller, compact: compact),
      ),
    );
    final progress = ocrSource == null ? null : ReaderOcrProgress(source: ocrSource);
    if (context.mmTablet) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final extended = constraints.maxWidth >= 460 && progress == null;
          return Row(
            key: const ValueKey('tablet-reader-toolbar'),
            children: [
              navigation,
              const SizedBox(width: MMSpacing.xs),
              Flexible(
                child: ReaderAnnotationTools(state: state, controller: controller, textOnly: !extended),
              ),
              if (MMSizeClass.of(context) != MMSizeClass.compact) compareButton,
              MMDropdownButton<Object>(
                key: const ValueKey('reader-more'),
                tooltip: l.moreTools,
                icon: const Icon(MMIcons.more),
                width: MMSizes.readerZoomMenuWidth,
                onSelected: (value) {
                  pageCommand(value);
                  if (value is MMReaderStyle) setStyle(value);
                  if (value is AnnotationTool) controller.setTool(value);
                  if (value == 'sync') controller.toggleSyncToMap();
                  if (value == 'margin') {
                    ref.read(readerMarginProvider(widget.studySetId).notifier).toggle(document!.id);
                  }
                  if (value == 'reading') {
                    if (capabilities.readingSettings) {
                      settingsHandler?.call(context, ref, widget.studySetId);
                    } else {
                      showReadingSettings(context, ref, widget.studySetId);
                    }
                  }
                  if (value == 'vocabulary' && document != null) toggleVocabularyHints(context, ref, document.id);
                  if (value == 'full-translation' && document != null) {
                    unawaited(
                      showFullTranslationSheet(context, studySetId: widget.studySetId, documentId: document.id),
                    );
                  }
                  if (value == 'full-translation-task' && document != null) {
                    unawaited(
                      showFullTranslationPanel(
                        context,
                        studySetId: widget.studySetId,
                        documentId: document.id,
                        targetLang: targetLang,
                      ),
                    );
                  }
                },
                itemBuilder: (_) => [
                  if (!extended) ...[
                    MMDropdownItem<Object>(
                      value: AnnotationTool.area,
                      enabled: controller.canUseTool(AnnotationTool.area),
                      child: _menuRow(MMIcons.areaSelect, l.toolArea),
                    ),
                    MMDropdownItem<Object>(
                      value: AnnotationTool.ink,
                      enabled: controller.canUseTool(AnnotationTool.ink),
                      child: _menuRow(MMIcons.pen, l.toolPen),
                    ),
                    MMDropdownItem<Object>(
                      value: 'sync',
                      enabled: capabilities.excerpt,
                      child: _menuRow(MMIcons.syncToMap, state.syncToMap ? l.syncToMapOn : l.syncToMapOff),
                    ),
                  ],
                  MMDropdownItem<Object>(
                    value: 'margin',
                    enabled: capabilities.marginNotes && document != null && !comparing,
                    child: _menuRow(MMIcons.captionsBubble, l.marginNotes),
                  ),
                  MMDropdownItem<Object>(value: 'reading', child: _menuRow(MMIcons.readingSettings, l.readingSettings)),
                  if (document != null)
                    MMDropdownItem<Object>(value: 'vocabulary', child: _menuRow(MMIcons.vocabulary, l.vocabularyHints)),
                  if (canFullTranslate)
                    MMDropdownItem<Object>(
                      value: hasActiveFullJob ? 'full-translation-task' : 'full-translation',
                      child: _menuRow(
                        MMIcons.layers,
                        hasActiveFullJob ? l.fullTranslationTaskMenu(fullState!.percent) : l.fullTranslationMenu,
                      ),
                    ),
                  const PopupMenuDivider(),
                  ...zoomItems,
                  ...cropItems,
                  const PopupMenuDivider(),
                  ...styleItems,
                ],
              ),
              if (progress != null) Flexible(child: progress),
            ],
          );
        },
      );
    }
    if (MMSizeClass.of(context) != MMSizeClass.regular) {
      return Row(
        children: [
          navigation,
          const SizedBox(width: MMSpacing.s),
          Flexible(child: annotation),
          hintButton,
          if (!capabilities.readingSettings && document != null)
            MMToolbarButton(
              icon: MMIcons.readingSettings,
              tooltip: l.readingSettings,
              onPressed: () => showReadingSettings(context, ref, widget.studySetId),
            ),
          if (MMSizeClass.of(context) == MMSizeClass.medium) ...[marginButton, compareButton],
          const SizedBox(width: MMSpacing.s),
          if (capabilities.readingSettings)
            MMToolbarButton(
              key: const ValueKey('reader-settings'),
              icon: MMIcons.readingSettings,
              tooltip: l.readingSettings,
              onPressed: settingsHandler == null ? null : () => settingsHandler(context, ref, widget.studySetId),
            )
          else
            MMDropdownButton<Object>(
              key: const ValueKey('reader-more'),
              tooltip: l.moreTools,
              icon: const Icon(MMIcons.more),
              onSelected: (value) {
                pageCommand(value);
                if (value is MMReaderStyle) setStyle(value);
                if (value == 'full-translation' && document != null) {
                  unawaited(showFullTranslationSheet(context, studySetId: widget.studySetId, documentId: document.id));
                }
                if (value == 'full-translation-task' && document != null) {
                  unawaited(
                    showFullTranslationPanel(
                      context,
                      studySetId: widget.studySetId,
                      documentId: document.id,
                      targetLang: targetLang,
                    ),
                  );
                }
              },
              itemBuilder: (_) => [
                if (canFullTranslate) ...[
                  MMDropdownItem<Object>(
                    value: hasActiveFullJob ? 'full-translation-task' : 'full-translation',
                    child: _menuRow(
                      MMIcons.layers,
                      hasActiveFullJob ? l.fullTranslationTaskMenu(fullState!.percent) : l.fullTranslationMenu,
                    ),
                  ),
                  const PopupMenuDivider(),
                ],
                ...zoomItems,
                const PopupMenuDivider(),
                ...cropItems,
                const PopupMenuDivider(),
                ...styleItems,
              ],
            ),
          if (progress != null) ...[const SizedBox(width: MMSpacing.s), Flexible(child: progress)],
        ],
      );
    }
    return Wrap(
      spacing: compact ? MMSpacing.xs : MMSpacing.s,
      runSpacing: MMSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        navigation,
        MMDropdownButton<Object>(
          key: const ValueKey('reader-page'),
          tooltip: l.readerZoom,
          enabled: capabilities.zoom,
          width: MMSizes.readerZoomMenuWidth,
          icon: const Icon(MMIcons.zoomControl),
          onSelected: pageCommand,
          itemBuilder: (_) => zoomItems,
        ),
        MMToolbarButton(
          key: const ValueKey('reader-crop'),
          compact: compact,
          tooltip: capabilities.readingSettings ? l.readingSettings : l.cropMargins,
          icon: capabilities.readingSettings ? MMIcons.readingSettings : MMIcons.crop,
          onPressed: capabilities.readingSettings
              ? (settingsHandler == null ? null : () => settingsHandler(context, ref, widget.studySetId))
              : canAdjustCrop
              ? cropSession.adjust
              : null,
        ),
        MMDropdownButton<Object>(
          key: const ValueKey('reader-appearance'),
          tooltip: l.readerAppearance,
          onSelected: (value) => setStyle(value as MMReaderStyle),
          itemBuilder: (_) => styleItems,
          icon: const Icon(MMIcons.appearance),
        ),
        annotation,
        hintButton,
        if (!capabilities.readingSettings && document != null)
          MMToolbarButton(
            icon: MMIcons.readingSettings,
            tooltip: l.readingSettings,
            onPressed: () => showReadingSettings(context, ref, widget.studySetId),
          ),
        marginButton,
        compareButton,
        ?progress,
      ],
    );
  }

  Widget _menuRow(IconData icon, String label) => Row(
    children: [
      Icon(icon, size: MMSizes.dropdownIcon),
      const SizedBox(width: MMSpacing.s),
      if (context.mmTouchPlatform)
        Flexible(child: Text(label, style: context.mmText.callout))
      else
        Text(label, style: context.mmText.callout),
    ],
  );

  Widget _styleRow(BuildContext context, MMReaderStyle value, {required bool selected}) {
    final l = context.l10n;
    final c = context.mmColors;
    return Row(
      children: [
        Icon(switch (value) {
          MMReaderStyle.white => MMReaderIcons.white,
          MMReaderStyle.dark => MMReaderIcons.dark,
          MMReaderStyle.paper => MMReaderIcons.paper,
          MMReaderStyle.green => MMReaderIcons.green,
        }, size: MMSizes.dropdownIcon),
        const SizedBox(width: MMSpacing.s),
        Text(switch (value) {
          MMReaderStyle.white => l.readerStyleWhite,
          MMReaderStyle.dark => l.readerStyleDark,
          MMReaderStyle.paper => l.readerStylePaper,
          MMReaderStyle.green => l.readerStyleGreen,
        }, style: context.mmText.callout),
        const Spacer(),
        Container(
          width: MMSizes.dropdownIcon,
          height: MMSizes.dropdownIcon,
          decoration: BoxDecoration(
            color: value.paperColor,
            border: Border.all(color: c.separator),
            borderRadius: BorderRadius.circular(MMRadii.page),
          ),
        ),
        const SizedBox(width: MMSpacing.s),
        SizedBox.square(
          dimension: MMSizes.dropdownIcon,
          child: selected ? Icon(MMIcons.check, color: c.accent, size: MMSizes.dropdownIcon) : null,
        ),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WorkspaceState state,
    WorkspaceController controller,
    StudySetContent content,
    Document? doc,
    String rootTitle,
    VoidCallback dismissSelection,
  ) {
    final l = context.l10n;
    // Keep navigation outside the PDF viewport on short handheld windows.
    // Tall phones, tablets and pointer windows retain their floating controls.
    // A touch window's glass toolbar lies above the reader's controls; the
    // pages run on beneath the bottom bar and scroll clear of it.
    final chrome = MMChromeInsets.of(context);
    final style = ref.watch(settingsProvider.select((s) => s.readerStyle));
    final source = doc == null ? null : controller.filePath(doc);
    final ocr =
        source == null ||
            !doc!.capabilities(runtime: DocumentRuntime(ocr: ref.watch(pdfOcrServiceProvider).supported)).ocr
        ? null
        : ref.watch(readerOcrProvider(source));
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (WorkspaceToolbarScope.maybeOf(context) == null && content.documents.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.xxs),
            child: Row(
              children: [
                Expanded(
                  child: doc == null
                      ? const SizedBox.shrink()
                      : _toolbar(context, state, controller, style, ocr?.running == true ? source : null),
                ),
                const SizedBox(width: MMSpacing.s),
                if (ref.watch(readerCompareProvider(widget.studySetId)) == null)
                  DocumentSwitcher(
                    studySetId: widget.studySetId,
                    documents: content.documents,
                    activeDocumentId: doc?.id,
                    onOpen: controller.openDocument,
                    onClose: doc == null ? null : () => controller.closeDocument(doc.id),
                  ),
              ],
            ),
          ),
        if (ocr?.running == true) ReaderOcrProgress(source: source!),
        if (ocr != null)
          ReaderOcrControls(
            key: ValueKey(source),
            source: source!,
            studySetId: widget.studySetId,
            documentId: doc!.id,
            initialPage: doc.lastPage,
            onRecognize: () => showReaderOcrOptions(context, ref, widget.studySetId),
          ),
        Expanded(
          child: doc == null
              ? Padding(
                  padding: EdgeInsets.only(bottom: chrome.bottom),
                  child: MMEmptyState(
                    icon: MMIcons.document,
                    title: l.readerEmptyTitle,
                    message: l.readerEmptyMessage,
                    actions: [
                      MMButton(
                        label: l.importDocument,
                        icon: MMIcons.import,
                        variant: MMButtonVariant.primary,
                        onPressed: () => pickAndImportDocuments(context, ref, widget.studySetId),
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      if (state.readerPanelVisible && doc.contentManifest == null)
                        Padding(
                          padding: EdgeInsets.only(bottom: chrome.bottom),
                          child: _ResizableReaderSidebar(
                            studySetId: widget.studySetId,
                            document: doc,
                            pdf: _pdf,
                            available: constraints.maxWidth,
                          ),
                        ),
                      Expanded(
                        child: ref.watch(readerCompareProvider(widget.studySetId)) != null
                            ? ReaderCompareView(
                                studySetId: widget.studySetId,
                                viewport: (document, side) => _viewport(
                                  context,
                                  state,
                                  controller,
                                  content,
                                  document,
                                  rootTitle,
                                  dismissSelection,
                                  side: side,
                                ),
                              )
                            : _viewport(context, state, controller, content, doc, rootTitle, dismissSelection),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => ReaderCompareWidth(
        width: constraints.maxWidth,
        child: Padding(
          padding: EdgeInsets.zero,
          child: Stack(
            children: [
              Positioned.fill(
                top: !MMInput.of(context).touchPlatform && WorkspaceToolbarScope.maybeOf(context) != null
                    ? MMSizes.paneHeaderHeight
                    : 0,
                child: MMChromeInsets(
                  insets: EdgeInsets.only(
                    top: MMInput.of(context).touchPlatform
                        ? MMInput.of(context).phone
                              ? MMSizes.phoneWorkspaceToolbarHeight
                              : WorkspaceToolbarScope.maybeOf(context) != null
                              ? MMSizes.paneHeaderHeight
                              : chrome.top
                        : chrome.top,
                    bottom: chrome.bottom,
                  ),
                  child: column,
                ),
              ),
              if (WorkspaceToolbarScope.maybeOf(context) != null)
                Positioned(
                  top: MMInput.of(context).phone ? null : 0,
                  bottom: MMInput.of(context).phone ? 30 : null,
                  left: MMInput.of(context).phone ? 12 : 0,
                  right: MMInput.of(context).phone ? 12 : 0,
                  child: _toolbar(context, state, controller, style, ocr?.running == true ? source : null),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String? _pendingDocument(StudySetContent content, PendingAction? pending) => switch (pending) {
    PendingSelection(:final documentId) => documentId,
    PendingHighlight(:final annotationId) =>
      content.annotations.where((a) => a.id == annotationId).firstOrNull?.documentId,
    PendingResearchNote(:final attachmentId) => switch (content.noteAttachments
        .where((a) => a.id == attachmentId)
        .firstOrNull
        ?.target) {
      PdfTarget(:final documentId) => documentId,
      _ => null,
    },
    _ => null,
  };

  Widget _viewport(
    BuildContext context,
    WorkspaceState state,
    WorkspaceController controller,
    StudySetContent content,
    Document doc,
    String rootTitle,
    VoidCallback onDismiss, {
    int side = 0,
  }) {
    if (doc.contentManifest != null) {
      return ref.watch(documentReaderBuilderProvider)?.call(context, ref, widget.studySetId, doc) ??
          MMEmptyState(icon: documentIcon(doc), title: doc.title, message: '');
    }
    final c = context.mmColors, l = context.l10n;
    final chrome = MMChromeInsets.of(context);
    final dockNavigation = MMInput.of(context).phone && MediaQuery.sizeOf(context).height < 500;
    final provider = workspaceProvider(widget.studySetId);
    final pdf = ref.watch(documentPdfProvider((widget.studySetId, doc.id)));
    final style = ref.watch(settingsProvider.select((s) => s.readerStyle));
    final source = controller.filePath(doc);
    final ocr = !ref.watch(pdfOcrServiceProvider).supported ? null : ref.watch(readerOcrProvider(source));
    // Every column needs inspection, including the PDF without the outer OCR bar.
    if (ocr != null && ocr.document == null && !ocr.failed) {
      ref.read(readerOcrProvider(source).notifier).inspect();
    }
    final documentScoped = doc.id != state.activeDocumentId;
    final cropProvider = !documentScoped
        ? readerCropProvider(widget.studySetId)
        : readerDocumentCropProvider((widget.studySetId, doc.id));
    final crop = ref.watch(cropProvider);
    final cropSession = ref.read(cropProvider.notifier);
    final comparePair = ref.watch(readerCompareProvider(widget.studySetId));
    final comparing = comparePair != null;
    final translating = comparePair?.right is AiCompareTarget;
    final translation = translating ? ref.watch(readerTranslationProvider(widget.studySetId)) : null;
    final compareSession = ref.read(readerCompareProvider(widget.studySetId).notifier);
    void dismissSelection() {
      if (ref.read(provider).pending != null) {
        controller.dismissPending();
        pdf.clearSelection();
      }
    }

    return MouseRegion(
      child: Listener(
        onPointerDown: (event) {
          _pdfPointers.add(event.pointer);
          _pointerStart = event.position;
          _pointerMoved = _pdfPointers.length > 1;
          if (comparing) compareSession.userInput(side);
          if (translating) ref.read(translationSourceInputProvider(widget.studySetId).notifier).take();
        },
        onPointerMove: (event) {
          if (_pointerStart != null && (event.position - _pointerStart!).distance > 8) _pointerMoved = true;
        },
        onPointerUp: (event) {
          _pdfPointers.remove(event.pointer);
          if (!_pointerMoved && state.pending == null && state.tool == AnnotationTool.select) {
            WorkspaceChromeScope.maybeOf(context)?.reveal();
          }
        },
        onPointerCancel: (event) => _pdfPointers.remove(event.pointer),
        onPointerSignal: (_) {
          dismissSelection();
          if (comparing) compareSession.userInput(side);
          if (translating) ref.read(translationSourceInputProvider(widget.studySetId).notifier).take();
        },
        onPointerPanZoomStart: (_) {
          dismissSelection();
          if (comparing) compareSession.userInput(side);
          if (translating) ref.read(translationSourceInputProvider(widget.studySetId).notifier).take();
        },
        child: Stack(
          children: [
            Positioned.fill(
              bottom: dockNavigation ? pagePillClearance + chrome.bottom : 0,
              child: !ref.watch(pdfRenderingEnabledProvider) || (ocr != null && ocr.document == null && !ocr.failed)
                  ? ColoredBox(key: ValueKey('pdf-placeholder-${doc.id}'), color: c.readerBackground)
                  : PdfVocabularyHints(
                      key: ValueKey((doc.id, ocr?.revision)),
                      studySetId: widget.studySetId,
                      documentId: doc.id,
                      pdf: pdf,
                      builder: (vocabularyHints, onVocabularyTap, vocabularyViewportChanged) => MMPdfView(
                        key: ocr == null || ocr.revision == 0 ? ValueKey(doc.id) : ValueKey((doc.id, ocr.revision)),
                        pageBorderColor: MMInput.of(context).phone ? Colors.transparent : context.mmColors.border,
                        pageSpacing: MMInput.of(context).phone ? 0 : 16,
                        filePath: ocr?.document?.path ?? controller.filePath(doc),
                        controller: pdf,
                        useTouchSelectionHandles: context.mmTouchPlatform,
                        selectionHandleTapGroup: context.mmTouchPlatform ? annotationTapGroup(widget.studySetId) : null,
                        paragraphs: translation?.paragraphs ?? const [],
                        hoveredParagraph: translation?.hovered,
                        onParagraphHover: !translating
                            ? null
                            : ref.read(readerTranslationProvider(widget.studySetId).notifier).hover,
                        crop: crop.draft ?? doc.crop,
                        margin: readerMargin(
                          context,
                          ref,
                          widget.studySetId,
                          doc,
                          style,
                          forceCollapsed: crop.editing || comparing,
                        ),
                        cropEditorBuilder: !crop.editing
                            ? null
                            : (context, page, size) {
                                var minWidth = size.width, minHeight = size.height;
                                for (var n = 1; n <= pdf.pageCount; n++) {
                                  if (crop.draft!.scope == CropScope.page && n != page) continue;
                                  if (crop.draft!.scope == CropScope.oddEven && n.isOdd != page.isOdd) {
                                    continue;
                                  }
                                  final other = pdf.pageSize(n);
                                  if (other == null) continue;
                                  if (other.width < minWidth) minWidth = other.width;
                                  if (other.height < minHeight) minHeight = other.height;
                                }
                                return [
                                  Positioned.fill(
                                    child: CropPageEditor(
                                      page: page,
                                      size: size,
                                      crop: crop.draft!,
                                      groupMinimum: Size(minWidth, minHeight),
                                      onChanged: (insets) => cropSession.change(page, insets),
                                    ),
                                  ),
                                ];
                              },
                        onReady: (_) {
                          cropSession.prepare();
                          compareSession.ready(doc.id);
                          if (ocr?.document?.hasCopy != true) return;
                          dismissSelection();
                          pdf.search(pdf.searchQuery);
                        },
                        initialPage: ref.read(readingPagesProvider(widget.studySetId))[doc.id] ?? doc.lastPage,
                        backgroundColor: c.readerBackground,
                        emphasisColor: c.accent,
                        bottomInset: dockNavigation ? 0 : chrome.bottom,
                        topInset: chrome.top,
                        pageColorFilter: style.pageFilter,
                        highlights: [..._highlights(content, doc.id, state), ...vocabularyHints],
                        areaSelecting: !crop.editing && state.tool == AnnotationTool.area,
                        inkStrokes: [
                          for (final s in content.inkStrokes)
                            if (s.documentId == doc.id) s,
                        ],
                        inkColors: _inkColors,
                        ink: crop.editing ? null : state.ink,
                        onInkDrawn: (draft) => controller.addInkStroke(doc.id, draft),
                        onInkErased: controller.eraseInkStrokes,
                        onAreaSelected: (area) async {
                          dismissSelection();
                          final notice = await controller.excerptArea(
                            doc.id,
                            area,
                            () => pdf.captureArea(area.page, area.rect),
                          );
                          if (context.mounted) showNotice(context, notice, rootTitle: rootTitle);
                        },
                        onTextUnavailable: ocr == null || ocr.running
                            ? null
                            : (page, position) {
                                showMMMenu(
                                  context,
                                  position: position,
                                  entries: [
                                    MMMenuItem(l.ocrNoText, null),
                                    MMMenuItem(l.ocrThisPage, () {
                                      ref
                                          .read(readerOcrProvider(source).notifier)
                                          .recognize(page, page, PdfOcrLanguage.chineseEnglish);
                                    }),
                                    MMMenuItem(
                                      l.ocrRecognize,
                                      () => showReaderOcrOptions(context, ref, widget.studySetId, documentId: doc.id),
                                    ),
                                  ],
                                );
                              },
                        onUserScroll: (delta, atStart) => WorkspaceChromeScope.maybeOf(context)
                            ?.onUserScroll(delta, atStart: atStart, geometryKey: (doc.id, MediaQuery.sizeOf(context))),
                        onViewportChanged: () {
                          vocabularyViewportChanged();
                          dismissSelection();
                          if (comparing) compareSession.changed(side);
                          if (translating) {
                            ref
                                .read(readerTranslationProvider(widget.studySetId).notifier)
                                .sourceChanged(pdf.readingPosition);
                          }
                        },
                        onPageChanged: (page, _) {
                          dismissSelection();
                          controller.recordPage(doc.id, page);
                        },
                        onSelectionChanged: (selected) {
                          final chrome = WorkspaceChromeScope.maybeOf(context);
                          final reason = (pdf, 'selection');
                          if (selected) {
                            _selectionHolds.add(reason);
                            chrome?.hold(reason);
                          } else {
                            _selectionHolds.remove(reason);
                            chrome?.release(reason);
                          }
                          if (!selected && ref.read(provider).pending is PendingSelection) {
                            dismissSelection();
                          }
                        },
                        onHighlightTap: (id, bounds) {
                          if (id.startsWith('vocabulary:')) {
                            onVocabularyTap(id, bounds);
                            return;
                          }
                          pdf.clearSelection();
                          controller.tapHighlight(id, bounds);
                        },
                        onSelectionCommitted: (selection) async {
                          final notice = await controller.onSelectionCommitted(doc.id, selection);
                          if (notice != null) {
                            await pdf.clearSelection();
                            if (context.mounted) showNotice(context, notice, rootTitle: rootTitle);
                          }
                        },
                      ),
                    ),
            ),
            Positioned(
              top: chrome.top + (crop.editing ? 10 : 8),
              left: 8,
              right: 8,
              child: Align(
                alignment: Alignment.topCenter,
                child: CropControls(studySetId: widget.studySetId, document: doc, documentScoped: documentScoped),
              ),
            ),
            if (state.tool == AnnotationTool.ink && !crop.editing)
              Positioned(
                top: chrome.top + MMSpacing.s,
                left: 0,
                right: 0,
                child: Center(
                  child: ReaderInkToolbar(
                    state: state,
                    controller: controller,
                    onUndo: () async {
                      final notice = await controller.undo();
                      if (context.mounted) showNotice(context, notice, rootTitle: rootTitle);
                    },
                  ),
                ),
              ),
            if (state.findVisible && side == 0)
              Positioned(
                top: chrome.top + 12,
                left: 12,
                right: 16,
                child: Align(
                  alignment: Alignment.topRight,
                  child: ReaderFindBar(pdf: pdf, focusTick: state.findFocusTick, onClose: controller.closeFind),
                ),
              ),
            if (state.pending case final PendingAction pending when _pendingDocument(content, pending) == doc.id)
              Positioned.fill(
                child: MMFloatingToolbarLayout(
                  padding: EdgeInsets.only(top: chrome.top, bottom: chrome.bottom),
                  avoid: (viewport) => _pagePillArea(
                    viewport,
                    chrome.bottom,
                    tablet: context.mmTouchPlatform,
                    source: doc.origin != null,
                  ),
                  anchor: switch (pending) {
                    PendingSelection(:final selection) => selection.viewportRect ?? Rect.zero,
                    PendingHighlight(:final viewportRect) => viewportRect,
                    PendingResearchNote(:final viewportRect) => viewportRect,
                  },
                  child: pending is PendingResearchNote
                      ? ResearchNotePopover(
                          key: ObjectKey(pending),
                          studySetId: widget.studySetId,
                          attachmentId: pending.attachmentId,
                        )
                      : SelectionToolbar(
                          key: ObjectKey(pending.toolbarIdentity),
                          studySetId: widget.studySetId,
                          pending: pending,
                          pdf: pdf,
                          rootTitle: rootTitle,
                        ),
                ),
              ),
            if (!comparing)
              Positioned(
                left: 0,
                right: 0,
                bottom: _pagePillBottom + chrome.bottom,
                child: WorkspaceChromeBar(
                  bottom: true,
                  child: MouseRegion(
                    key: const ValueKey('reader-page-navigation'),
                    // The floating tablet control must leave the document on
                    // either side of the capsule available for input.
                    hitTestBehavior: context.mmTouchPlatform ? HitTestBehavior.deferToChild : HitTestBehavior.opaque,
                    onEnter: (_) => setState(() => _hoveringNavigation = true),
                    onExit: (_) => setState(() => _hoveringNavigation = false),
                    child: Focus(
                      onFocusChange: (focused) => setState(() => _navigationFocused = focused),
                      child: Consumer(
                        builder: (context, ref, _) {
                          final page =
                              ref.watch(readingPagesProvider(widget.studySetId).select((p) => p[doc.id])) ??
                              doc.lastPage;
                          return _PagePill(
                            visible: _navigationVisible,
                            source: doc.origin == null ? null : WebSourceAttribution(document: doc),
                            page: _scrubPage?.round() ?? page,
                            editRequests: _pageFieldRequests,
                            pageCount: doc.pageCount,
                            onJump: (page) {
                              dismissSelection();
                              pdf.jumpToPage(page);
                            },
                            onPrevious: () {
                              dismissSelection();
                              pdf.goToPage((page) - 1);
                            },
                            onNext: () {
                              dismissSelection();
                              pdf.goToPage((page) + 1);
                            },
                            progress: doc.pageCount > 1
                                ? SizedBox(
                                    height: context.mmTouchPlatform
                                        ? MMSizes.touchTarget
                                        : MMSizes.field - MMSpacing.xxs,
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        activeTrackColor: context.mmTouchPlatform
                                            ? c.accent
                                            : c.secondaryLabel.withValues(alpha: _navigationVisible ? .65 : .3),
                                        inactiveTrackColor: c.secondaryLabel.withValues(
                                          alpha: _navigationVisible ? .2 : .12,
                                        ),
                                        thumbColor: context.mmTouchPlatform ? c.label : c.secondaryLabel,
                                        overlayColor: c.secondaryLabel.withValues(alpha: .1),
                                        trackHeight: MMSizes.readerProgressTrack,
                                        trackShape: context.mmTouchPlatform
                                            ? const RoundedRectSliderTrackShape()
                                            : const RectangularSliderTrackShape(),
                                        thumbShape: RoundSliderThumbShape(
                                          enabledThumbRadius: _navigationVisible ? MMSpacing.xs : 0,
                                          elevation: 0,
                                          pressedElevation: 0,
                                        ),
                                        showValueIndicator: ShowValueIndicator.never,
                                      ),
                                      child: Slider(
                                        key: const ValueKey('reader-page-progress'),
                                        padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s),
                                        min: 1,
                                        max: doc.pageCount.toDouble(),
                                        value: (_scrubPage ?? page.toDouble()).clamp(1, doc.pageCount.toDouble()),
                                        label: '${_scrubPage?.round() ?? page} / ${doc.pageCount}',
                                        semanticFormatterCallback: (v) => '${v.round()} / ${doc.pageCount}',
                                        onChangeStart: (v) {
                                          dismissSelection();
                                          setState(() => _scrubPage = v);
                                        },
                                        onChanged: (v) {
                                          setState(() => _scrubPage = v);
                                          pdf.scrubToPage(v.round());
                                        },
                                        onChangeEnd: (v) {
                                          pdf.scrubToPage(v.round());
                                          setState(() => _scrubPage = null);
                                        },
                                      ),
                                    ),
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<MMPdfHighlight> _highlights(StudySetContent content, String documentId, WorkspaceState state) {
    final selectedAnnotation = state.selectedCardId == null ? null : content.card(state.selectedCardId!)?.annotationId;
    final pendingAnnotation = switch (state.pending) {
      PendingHighlight(:final annotationId) => annotationId,
      _ => null,
    };
    final source = ref.watch(vocabularySourceFlashProvider);
    return [
      if (source != null &&
          source.studySetId == widget.studySetId &&
          source.documentId == documentId &&
          source.page != null)
        MMPdfHighlight(
          id: 'vocabulary-source-flash',
          page: source.page!,
          rects: source.rects,
          color: context.mmColors.vocabularyTint,
          emphasized: true,
        ),
      for (final a in content.annotationsOn(documentId))
        for (final page in a.isText || a.needsReview ? <AnnotationPage>[] : a.pages)
          () {
            final color = MMAnnotationColor.fromIndex(a.colorIndex);
            final sharedCard = content.cardForAnnotation(a.id);
            final card = sharedCard != null && content.node(sharedCard.id, mapId: state.activeMapId) != null
                ? sharedCard
                : null;
            final strong = a.id == selectedAnnotation;
            return MMPdfHighlight(
              id: a.id,
              page: page.page,
              rects: page.rects,
              color: a.kind == AnnotationKind.underline
                  ? Colors.transparent
                  : color.color.withValues(alpha: strong ? 0.5 : 0.32),
              underline: a.kind == AnnotationKind.underline || card != null ? color.underline : null,
              lineStyle: a.kind == AnnotationKind.underline ? a.lineStyle : null,
              emphasized: a.id == state.flashAnnotationId || a.id == pendingAnnotation,
              framed: card?.kind == CardKind.image,
            );
          }(),
      // Research notes attached here: a dashed underline and a mark in the
      // margin, both opening the note.
      for (final a in content.noteAttachments)
        if (a.target case PdfTarget(documentId: final doc, :final pages) when doc == documentId)
          for (final (i, page) in pages.indexed)
            MMPdfHighlight(
              id: noteMarkId(a.id),
              page: page.page,
              rects: page.rects,
              color: Colors.transparent,
              underline: context.mmColors.research,
              dashed: true,
              marker: i == 0 ? context.mmColors.research : null,
              emphasized: switch (state.pending) {
                PendingResearchNote(:final attachmentId) => attachmentId == a.id,
                _ => false,
              },
            ),
    ];
  }
}

final _inkColors = [for (final c in MMInkColor.values) c.stroke];

/// Full-width navigation area reserved for floating toolbars and HUDs.
const _pagePillBottom = 16.0;
const _pagePillHeight = MMSizes.readerNavigationHeight;
const _tabletPagePillWidth = 300.0;

/// How far the page pill reaches up from the window's bottom edge; the HUD
/// stays above it.
const pagePillClearance = _pagePillBottom + _pagePillHeight;

/// The navigation area of a [viewport] whose bottom [inset] lies under chrome.
Rect _pagePillArea(Size viewport, double inset, {bool tablet = false, bool source = false}) {
  final height = tablet ? MMSizes.touchTarget + (source ? 24 : 0) : _pagePillHeight;
  final width = tablet ? (viewport.width - 32).clamp(0.0, _tabletPagePillWidth) : viewport.width;
  return Rect.fromLTWH((viewport.width - width) / 2, viewport.height - inset - _pagePillBottom - height, width, height);
}

class _PagePill extends StatelessWidget {
  const _PagePill({
    required this.page,
    required this.editRequests,
    required this.pageCount,
    required this.onJump,
    required this.onPrevious,
    required this.onNext,
    this.progress,
    this.source,
    required this.visible,
  });

  final int page;
  final int editRequests;
  final int pageCount;
  final ValueChanged<int> onJump;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Widget? progress, source;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    Widget reveal(Widget child) => AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: MMAppearance.duration(context, MMMotion.quick),
      child: child,
    );
    if (context.mmTouchPlatform) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _tabletPagePillWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (source != null) ...[SizedBox(height: 20, child: source), const SizedBox(height: 4)],
                Container(
                  key: const ValueKey('tablet-reader-navigation'),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: MMAppearance.reduceTransparencyOf(context)
                        ? c.glassOpaque
                        : c.glassOpaque.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(MMRadii.capsule),
                  ),
                  child: SizedBox(
                    height: MMSizes.touchTarget,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 240;
                        final pageField = Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: ReaderPageField(
                            key: const ValueKey('reader-page-badge'),
                            page: page,
                            pageCount: pageCount,
                            onJump: onJump,
                            editRequests: editRequests,
                          ),
                        );
                        return Row(
                          children: [
                            MMIconButton(
                              icon: MMIcons.chevronLeft,
                              tooltip: l.previousPage,
                              onPressed: page > 1 ? onPrevious : null,
                            ),
                            if (narrow)
                              Expanded(child: pageField)
                            else
                              ConstrainedBox(constraints: const BoxConstraints(minWidth: 72), child: pageField),
                            if (!narrow) Expanded(child: progress ?? const SizedBox.shrink()),
                            MMIconButton(
                              icon: MMIcons.chevronRight,
                              tooltip: l.nextPage,
                              onPressed: page < pageCount ? onNext : null,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.l),
      child: SizedBox(
        height: MMSizes.readerNavigationHeight,
        child: Column(
          children: [
            reveal(
              Container(
                key: const ValueKey('reader-page-badge'),
                height: MMSizes.field,
                padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.xs),
                decoration: BoxDecoration(
                  color: MMAppearance.reduceTransparencyOf(context) ? c.glassOpaque : c.glass.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(MMRadii.capsule),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (source != null) ...[Flexible(child: source!), const SizedBox(width: MMSpacing.m)],
                    ReaderPageField(page: page, pageCount: pageCount, onJump: onJump, editRequests: editRequests),
                  ],
                ),
              ),
            ),
            const SizedBox(height: MMSpacing.s),
            Row(
              children: [
                reveal(
                  MMIconButton(
                    icon: MMIcons.chevronLeft,
                    tooltip: l.previousPage,
                    size: MMSizes.field,
                    iconSize: MMSpacing.l,
                    color: c.secondaryLabel,
                    onPressed: page > 1 ? onPrevious : null,
                  ),
                ),
                Expanded(child: progress ?? const SizedBox.shrink()),
                reveal(
                  MMIconButton(
                    icon: MMIcons.chevronRight,
                    tooltip: l.nextPage,
                    size: MMSizes.field,
                    iconSize: MMSpacing.l,
                    color: c.secondaryLabel,
                    onPressed: page < pageCount ? onNext : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResizableReaderSidebar extends ConsumerWidget {
  const _ResizableReaderSidebar({
    required this.studySetId,
    required this.document,
    required this.pdf,
    required this.available,
  });
  final double available;
  final String studySetId;
  final Document document;
  final MMPdfViewController pdf;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferred = ref.watch(settingsProvider.select((s) => s.readerSidebarWidth));
    final width = preferred.clamp(
      MMSizes.readerSidebarMinWidth,
      (available - MMSizes.readerContentMinWidth).clamp(MMSizes.readerSidebarMinWidth, MMSizes.readerSidebarMaxWidth),
    );
    return Row(
      children: [
        ReaderSidebar(studySetId: studySetId, document: document, pdf: pdf, width: width),
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            key: const ValueKey('reader-sidebar-resize'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (event) =>
                ref.read(settingsProvider.notifier).setReaderSidebarWidth(width + event.delta.dx, persist: false),
            onHorizontalDragEnd: (_) => ref
                .read(settingsProvider.notifier)
                .setReaderSidebarWidth(ref.read(settingsProvider).readerSidebarWidth),
            child: const SizedBox(width: MMSizes.dividerHitWidth, height: double.infinity),
          ),
        ),
      ],
    );
  }
}
