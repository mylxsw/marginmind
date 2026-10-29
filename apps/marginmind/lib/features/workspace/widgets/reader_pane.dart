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
import '../reader_crop.dart';
import '../reader_compare.dart';
import '../reader_translation.dart';
import 'reader_compare_controls.dart';
import 'reader_zoom_control.dart';
import '../reader_margin.dart';
import 'reader_margin_notes.dart';
import 'reader_crop_controls.dart';
import 'reader_sidebar.dart';
import 'reader_annotation_tools.dart';
import 'reader_ink_toolbar.dart';
import 'selection_toolbar.dart';
import '../reader_ocr.dart';
import 'reader_ocr_controls.dart';

/// Source pane: the PDF, reader tools, document switcher and floating page pill.
class ReaderPane extends ConsumerStatefulWidget {
  const ReaderPane({super.key, required this.studySetId});

  final String studySetId;

  @override
  ConsumerState<ReaderPane> createState() => _ReaderPaneState();
}

class _ReaderPaneState extends ConsumerState<ReaderPane> {
  final _focus = FocusNode(debugLabel: 'PDF reader', skipTraversal: true);

  /// Counts the menu's "Go to Page…" requests; the page field opens on each.
  int _pageFieldRequests = 0;
  bool _hoveringNavigation = false;
  bool _navigationFocused = false;

  bool get _navigationVisible =>
      MMInput.touchInputOf(context) || _hoveringNavigation || _navigationFocused || _scrubPage != null;
  double? _scrubPage;

  MMPdfViewController get _pdf => ref.read(readerPdfProvider(widget.studySetId));

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _zoom(ReaderZoomCommand command) {
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
    final c = context.mmColors;
    final provider = workspaceProvider(widget.studySetId);
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

    ref.listen(provider.select((s) => s.reveal), (_, reveal) {
      if (reveal == null) return;
      // After this frame the right document's viewer exists; if it is still
      // loading, the view queues the reveal until it is ready.
      WidgetsBinding.instance.addPostFrameCallback((_) => _pdf.reveal(reveal.page, reveal.rects));
    });

    void dismissSelection() {
      if (ref.read(provider).pending != null) {
        controller.dismissPending();
        _pdf.clearSelection();
      }
    }

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
            _zoom(intent.command);
            return null;
          },
        ),
        ReaderNavIntent: CallbackAction<ReaderNavIntent>(
          onInvoke: (intent) {
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
              if (!comparing && id != null) ref.read(readerMarginProvider(widget.studySetId).notifier).toggle(id);
            },
            AppShortcuts.toggleCrop: () => toggleReaderCrop(context, ref, widget.studySetId),
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
    final l = context.l10n;
    final compact = !context.mmTouch;
    final navigation = MMToolbarButton(
      compact: compact,
      icon: MMIcons.readerNavigation,
      tooltip: AppShortcuts.tip(
        state.readerPanelVisible ? l.hideReaderSidebar : l.showReaderSidebar,
        AppShortcuts.toggleReaderSidebar,
      ),
      selected: state.readerPanelVisible,
      onPressed: controller.toggleReaderPanel,
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
      ReaderZoomSlider(pdf: _pdf, enabled: !crop.editing),
      for (final entry in [
        (ReaderZoomCommand.actualSize, l.pdfActualSize, MMIcons.actualSize),
        (ReaderZoomCommand.fitWidth, l.pdfFitWidth, MMIcons.fitWidth),
        (ReaderZoomCommand.fitPage, l.pdfFitPage, MMIcons.fitPage),
      ])
        MMDropdownItem<Object>(value: entry.$1, enabled: !crop.editing, child: _menuRow(entry.$3, entry.$2)),
    ];
    final canAdjustCrop = !crop.editing && !crop.busy && _pdf.isReady;
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
    final noteCount = controller.content.marginNotes.where((n) => n.documentId == state.activeDocumentId).length;
    final marginButton = MMToolbarButton(
      key: const ValueKey('reader-margin'),
      compact: compact,
      icon: MMIcons.marginNote,
      count: noteCount,
      tooltip: AppShortcuts.tip(l.marginNotes, AppShortcuts.toggleMarginNotes),
      selected: marginState.openDocuments.contains(state.activeDocumentId),
      onPressed: crop.editing || comparing || document == null
          ? null
          : () => ref.read(readerMarginProvider(widget.studySetId).notifier).toggle(document.id),
    );
    final compareButton = ReaderCompareMenu(studySetId: widget.studySetId, enabled: !crop.editing);
    final annotation = IgnorePointer(
      ignoring: crop.editing,
      child: Opacity(
        opacity: crop.editing ? .4 : 1,
        child: ReaderAnnotationTools(state: state, controller: controller, compact: compact),
      ),
    );
    final progress = ocrSource == null ? null : ReaderOcrProgress(source: ocrSource);
    if (MMSizeClass.of(context) != MMSizeClass.regular) {
      return Row(
        children: [
          navigation,
          const SizedBox(width: MMSpacing.s),
          Flexible(child: annotation),
          if (MMSizeClass.of(context) == MMSizeClass.medium) ...[marginButton, compareButton],
          const SizedBox(width: MMSpacing.s),
          MMDropdownButton<Object>(
            key: const ValueKey('reader-more'),
            tooltip: l.moreTools,
            icon: const Icon(MMIcons.more),
            onSelected: (value) {
              pageCommand(value);
              if (value is MMReaderStyle) setStyle(value);
            },
            itemBuilder: (_) => [
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
          width: MMSizes.readerZoomMenuWidth,
          icon: const Icon(MMIcons.zoomControl),
          onSelected: pageCommand,
          itemBuilder: (_) => zoomItems,
        ),
        MMToolbarButton(
          key: const ValueKey('reader-crop'),
          compact: compact,
          tooltip: l.cropMargins,
          icon: MMIcons.crop,
          onPressed: canAdjustCrop ? cropSession.adjust : null,
        ),
        MMDropdownButton<Object>(
          key: const ValueKey('reader-appearance'),
          tooltip: l.readerAppearance,
          onSelected: (value) => setStyle(value as MMReaderStyle),
          itemBuilder: (_) => styleItems,
          icon: const Icon(MMIcons.appearance),
        ),
        annotation,
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
      Text(label, style: context.mmText.callout),
    ],
  );

  Widget _styleRow(BuildContext context, MMReaderStyle value, {required bool selected}) {
    final l = context.l10n;
    final c = context.mmColors;
    return Row(
      children: [
        Container(
          width: MMSpacing.l,
          height: MMSpacing.l,
          decoration: BoxDecoration(
            color: value.paperColor,
            border: Border.all(color: c.separator),
            borderRadius: BorderRadius.circular(MMRadii.page),
          ),
        ),
        const SizedBox(width: MMSpacing.s),
        Text(switch (value) {
          MMReaderStyle.white => l.readerStyleWhite,
          MMReaderStyle.dark => l.readerStyleDark,
          MMReaderStyle.paper => l.readerStylePaper,
          MMReaderStyle.green => l.readerStyleGreen,
        }, style: context.mmText.callout),
        const Spacer(),
        if (selected) Icon(MMIcons.check, color: c.accent, size: MMSizes.dropdownIcon),
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
    final ocr = source == null || !ref.watch(pdfOcrServiceProvider).supported
        ? null
        : ref.watch(readerOcrProvider(source));
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (content.documents.isNotEmpty)
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
                  _DocumentSwitcher(
                    documents: content.documents,
                    activeDocumentId: doc?.id,
                    onOpen: controller.openDocument,
                    onClose: doc == null ? null : () => controller.closeDocument(doc.id),
                  ),
              ],
            ),
          ),
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
                        label: l.importPdf,
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
                      if (state.readerPanelVisible)
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
          padding: EdgeInsets.only(top: chrome.top),
          child: column,
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
        onPointerDown: (_) {
          if (comparing) compareSession.userInput(side);
          if (translating) ref.read(translationSourceInputProvider(widget.studySetId).notifier).take();
        },
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
                  : MMPdfView(
                      key: ocr == null || ocr.revision == 0 ? ValueKey(doc.id) : ValueKey((doc.id, ocr.revision)),
                      filePath: ocr?.document?.path ?? controller.filePath(doc),
                      controller: pdf,
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
                      pageColorFilter: style.pageFilter,
                      highlights: _highlights(content, doc.id, state),
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
                      onViewportChanged: () {
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
                        if (!selected && ref.read(provider).pending is PendingSelection) {
                          dismissSelection();
                        }
                      },
                      onHighlightTap: (id, bounds) {
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
            Positioned(
              top: crop.editing ? 10 : 8,
              left: 8,
              right: 8,
              child: Align(
                alignment: Alignment.topCenter,
                child: CropControls(studySetId: widget.studySetId, document: doc, documentScoped: documentScoped),
              ),
            ),
            if (state.tool == AnnotationTool.ink && !crop.editing)
              Positioned(
                top: MMSpacing.s,
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
                top: 12,
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
                  avoid: (viewport) => _pagePillArea(viewport, chrome.bottom),
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
                          key: ObjectKey(pending),
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
                child: MouseRegion(
                  key: const ValueKey('reader-page-navigation'),
                  onEnter: (_) => setState(() => _hoveringNavigation = true),
                  onExit: (_) => setState(() => _hoveringNavigation = false),
                  child: Focus(
                    onFocusChange: (focused) => setState(() => _navigationFocused = focused),
                    child: Consumer(
                      builder: (context, ref, _) {
                        final page =
                            ref.watch(readingPagesProvider(widget.studySetId).select((p) => p[doc.id])) ?? doc.lastPage;
                        return _PagePill(
                          visible: _navigationVisible,
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
                                  height: MMSizes.field - MMSpacing.xxs,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: c.secondaryLabel.withValues(
                                        alpha: _navigationVisible ? .65 : .3,
                                      ),
                                      inactiveTrackColor: c.secondaryLabel.withValues(
                                        alpha: _navigationVisible ? .2 : .12,
                                      ),
                                      thumbColor: c.secondaryLabel,
                                      overlayColor: c.secondaryLabel.withValues(alpha: .1),
                                      trackHeight: MMSizes.readerProgressTrack,
                                      trackShape: const RectangularSliderTrackShape(),
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
    return [
      for (final a in content.annotationsOn(documentId))
        for (final page in a.pages)
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
              color: color.color.withValues(alpha: strong ? 0.5 : 0.32),
              underline: card != null ? color.underline : null,
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

/// How far the page pill reaches up from the window's bottom edge; the HUD
/// stays above it.
const pagePillClearance = _pagePillBottom + _pagePillHeight;

/// The navigation area of a [viewport] whose bottom [inset] lies under chrome.
Rect _pagePillArea(Size viewport, double inset) =>
    Rect.fromLTWH(0, viewport.height - inset - _pagePillBottom - _pagePillHeight, viewport.width, _pagePillHeight);

/// "n / N" that turns into a field on click: type a page, Enter jumps.
class _PageField extends StatefulWidget {
  const _PageField({required this.page, required this.pageCount, required this.onJump, required this.editRequests});

  final int page;

  /// Changes when the field should open, without a click.
  final int editRequests;
  final int pageCount;
  final ValueChanged<int> onJump;

  @override
  State<_PageField> createState() => _PageFieldState();
}

class _PageFieldState extends State<_PageField> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void didUpdateWidget(_PageField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editRequests != oldWidget.editRequests) _start();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    _text.text = '${widget.page}';
    _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _finish({required bool jump}) {
    if (!_editing) return;
    final page = int.tryParse(_text.text.trim());
    setState(() => _editing = false);
    if (jump && page != null) widget.onJump(page);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.mmText;
    final style = t.callout.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    if (!_editing) {
      return MMInteractive(
        onTap: _start,
        semanticLabel: l.pageNumberField,
        builder: (context, _) => Text(l.pageOf(widget.page, widget.pageCount), style: style),
      );
    }
    final digits = '${widget.pageCount}'.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 10.0 * digits + 6,
          child: MMInlineTextField(
            controller: _text,
            focusNode: _focus,
            style: style,
            semanticLabel: l.pageNumberField,
            maxLines: 1,
            onSubmitted: () => _finish(jump: true),
            onCancel: () => _finish(jump: false),
            onTapOutside: () => _finish(jump: true),
          ),
        ),
        Text(' / ${widget.pageCount}', style: style),
      ],
    );
  }
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
    required this.visible,
  });

  final int page;
  final int editRequests;
  final int pageCount;
  final ValueChanged<int> onJump;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Widget? progress;
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
                child: _PageField(page: page, pageCount: pageCount, onJump: onJump, editRequests: editRequests),
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

/// Lists every document, including ones not yet opened in this session.
class _DocumentSwitcher extends StatelessWidget {
  const _DocumentSwitcher({
    required this.documents,
    required this.activeDocumentId,
    required this.onOpen,
    required this.onClose,
  });

  final List<Document> documents;
  final String? activeDocumentId;
  final ValueChanged<String> onOpen;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final text = context.mmText.callout;
    Widget row(IconData icon, String label, {bool selected = false, bool enabled = true}) => Row(
      children: [
        Icon(icon, size: 14, color: c.secondaryLabel),
        const SizedBox(width: MMSpacing.s),
        Expanded(
          child: Tooltip(
            message: label,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: enabled ? text : text.copyWith(color: c.secondaryLabel),
            ),
          ),
        ),
        const SizedBox(width: MMSpacing.s),
        SizedBox(width: 14, child: selected ? Icon(MMIcons.check, size: 14, color: c.accent) : null),
      ],
    );
    return MMDropdownButton<String>(
      key: const ValueKey('reader-documents'),
      tooltip: l.switchDocument,
      width: MMSizes.dropdownWideWidth,
      icon: Icon(MMIcons.chevronUpDown, color: c.label, semanticLabel: l.switchDocument),
      onSelected: (id) => id.isEmpty ? onClose?.call() : onOpen(id),
      itemBuilder: (_) => [
        for (final document in documents)
          MMDropdownItem<String>(
            value: document.id,
            labelTextStyle: WidgetStatePropertyAll(text),
            child: Semantics(
              selected: document.id == activeDocumentId,
              child: row(MMIcons.document, document.title, selected: document.id == activeDocumentId),
            ),
          ),
        const PopupMenuDivider(height: MMSpacing.s),
        MMDropdownItem<String>(
          value: '',
          enabled: onClose != null,
          labelTextStyle: WidgetStatePropertyAll(text),
          child: row(MMIcons.close, l.closeCurrentDocument, enabled: onClose != null),
        ),
      ],
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
