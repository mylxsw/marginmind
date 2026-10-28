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
import 'reader_sidebar.dart';
import 'reader_annotation_tools.dart';
import 'reader_ink_toolbar.dart';
import 'selection_toolbar.dart';
import '../reader_ocr.dart';
import 'reader_ocr_controls.dart';

/// Source pane: document tabs, the PDF (Preview-style gray backdrop), the
/// text action toolbar and the floating page pill.
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

  bool get _navigationVisible => _hoveringNavigation || _navigationFocused || _scrubPage != null;
  double? _scrubPage;

  MMPdfViewController get _pdf => ref.read(readerPdfProvider(widget.studySetId));

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _zoom(ReaderZoomCommand command) {
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

    final openDocs = [for (final id in state.openDocumentIds) ?content.document(id)];

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
            if (state.tool == AnnotationTool.ink) const SingleActivator(LogicalKeyboardKey.escape): controller.exitInk,
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
                child: _body(context, state, controller, content, doc, openDocs, rootTitle, dismissSelection),
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
    final button = context.mmToolbarButton;
    final buttonStyle = IconButton.styleFrom(minimumSize: button, fixedSize: button, padding: EdgeInsets.zero);
    final navigation = MMToolbarButton(
      icon: MMIcons.readerNavigation,
      tooltip: AppShortcuts.tip(
        state.readerPanelVisible ? l.hideReaderSidebar : l.showReaderSidebar,
        AppShortcuts.toggleReaderSidebar,
      ),
      selected: state.readerPanelVisible,
      onPressed: controller.toggleReaderPanel,
    );
    final zoomItems = [
      for (final entry in [
        (ReaderZoomCommand.actualSize, l.pdfActualSize, MMIcons.actualSize),
        (ReaderZoomCommand.fitWidth, l.pdfFitWidth, MMIcons.fitWidth),
        (ReaderZoomCommand.fitPage, l.pdfFitPage, MMIcons.fitPage),
      ])
        PopupMenuItem<Object>(value: entry.$1, child: _menuRow(entry.$3, entry.$2)),
    ];
    final styleItems = [
      for (final value in MMReaderStyle.values)
        PopupMenuItem<Object>(
          value: value,
          child: _styleRow(context, value, selected: value == style),
        ),
    ];
    void setStyle(MMReaderStyle value) => ref.read(settingsProvider.notifier).setReaderStyle(value);
    final annotation = ReaderAnnotationTools(state: state, controller: controller);
    final progress = ocrSource == null ? null : ReaderOcrProgress(source: ocrSource);
    if (MMSizeClass.of(context) != MMSizeClass.regular) {
      return Row(
        children: [
          navigation,
          const SizedBox(width: MMSpacing.s),
          Flexible(child: annotation),
          const SizedBox(width: MMSpacing.s),
          PopupMenuButton<Object>(
            key: const ValueKey('reader-more'),
            tooltip: l.moreTools,
            padding: EdgeInsets.zero,
            style: buttonStyle,
            iconSize: MMSpacing.l,
            icon: const Icon(MMIcons.more),
            onSelected: (value) {
              if (value is ReaderZoomCommand) _zoom(value);
              if (value is MMReaderStyle) setStyle(value);
            },
            itemBuilder: (_) => [
              PopupMenuItem<Object>(value: ReaderZoomCommand.zoomOut, child: _menuRow(MMIcons.zoomOut, l.zoomOut)),
              PopupMenuItem<Object>(value: ReaderZoomCommand.zoomIn, child: _menuRow(MMIcons.zoomIn, l.zoomIn)),
              ...zoomItems,
              const PopupMenuDivider(),
              ...styleItems,
            ],
          ),
          if (progress != null) ...[const SizedBox(width: MMSpacing.s), Flexible(child: progress)],
        ],
      );
    }
    return Wrap(
      spacing: MMSpacing.s,
      runSpacing: MMSpacing.s,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        navigation,
        MMToolbarButton(icon: MMIcons.zoomOut, tooltip: l.zoomOut, onPressed: _pdf.zoomOut),
        MMToolbarButton(icon: MMIcons.zoomIn, tooltip: l.zoomIn, onPressed: _pdf.zoomIn),
        PopupMenuButton<Object>(
          key: const ValueKey('reader-zoom'),
          tooltip: l.readerZoom,
          padding: EdgeInsets.zero,
          style: buttonStyle,
          iconSize: MMSpacing.l,
          icon: const Icon(MMIcons.fitPage),
          onSelected: (value) => _zoom(value as ReaderZoomCommand),
          itemBuilder: (_) => zoomItems,
        ),
        PopupMenuButton<Object>(
          key: const ValueKey('reader-appearance'),
          tooltip: l.readerAppearance,
          padding: EdgeInsets.zero,
          style: buttonStyle,
          iconSize: MMSpacing.l,
          onSelected: (value) => setStyle(value as MMReaderStyle),
          itemBuilder: (_) => styleItems,
          icon: const Icon(MMIcons.appearance),
        ),
        annotation,
        ?progress,
      ],
    );
  }

  Widget _menuRow(IconData icon, String label) => Row(
    children: [
      Icon(icon, size: MMSpacing.l),
      const SizedBox(width: MMSpacing.s),
      Text(label),
    ],
  );

  Widget _styleRow(BuildContext context, MMReaderStyle value, {required bool selected}) {
    final l = context.l10n;
    final c = context.mmColors;
    return Row(
      children: [
        Container(
          width: MMSpacing.xl,
          height: MMSpacing.xl,
          decoration: BoxDecoration(
            color: value.paperColor,
            border: Border.all(color: c.separator),
            borderRadius: BorderRadius.circular(MMRadii.field),
          ),
          child: Center(
            child: Text('Aa', style: context.mmText.footnote.copyWith(color: value.inkColor)),
          ),
        ),
        const SizedBox(width: MMSpacing.s),
        Text(switch (value) {
          MMReaderStyle.white => l.readerStyleWhite,
          MMReaderStyle.dark => l.readerStyleDark,
          MMReaderStyle.paper => l.readerStylePaper,
          MMReaderStyle.green => l.readerStyleGreen,
        }),
        const Spacer(),
        if (selected) Icon(Icons.check, color: c.accent, size: MMSpacing.l),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WorkspaceState state,
    WorkspaceController controller,
    StudySetContent content,
    Document? doc,
    List<Document> openDocs,
    String rootTitle,
    VoidCallback dismissSelection,
  ) {
    final l = context.l10n;
    final c = context.mmColors;
    final provider = workspaceProvider(widget.studySetId);
    final style = ref.watch(settingsProvider.select((s) => s.readerStyle));
    final source = doc == null ? null : controller.filePath(doc);
    final ocr = source == null || !ref.watch(pdfOcrServiceProvider).supported
        ? null
        : ref.watch(readerOcrProvider(source));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (openDocs.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.s),
            child: Row(
              children: [
                if (openDocs.length > 1)
                  for (final d in openDocs)
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: _Tab(
                            title: d.title,
                            active: d.id == state.activeDocumentId,
                            onOpen: () => controller.openDocument(d.id),
                            onClose: () => controller.closeDocument(d.id),
                            closeLabel: l.closeTab,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        if (doc != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.s),
            child: _toolbar(context, state, controller, style, ocr?.running == true ? source : null),
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
              ? MMEmptyState(
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
                )
              : LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      if (state.readerPanelVisible)
                        _ResizableReaderSidebar(
                          studySetId: widget.studySetId,
                          document: doc,
                          pdf: _pdf,
                          available: constraints.maxWidth,
                        ),
                      Expanded(
                        child: MouseRegion(
                          child: Listener(
                            onPointerSignal: (_) => dismissSelection(),
                            onPointerPanZoomStart: (_) => dismissSelection(),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child:
                                      !ref.watch(pdfRenderingEnabledProvider) ||
                                          (ocr != null && ocr.document == null && !ocr.failed)
                                      ? ColoredBox(
                                          key: ValueKey('pdf-placeholder-${doc.id}'),
                                          color: c.readerBackground,
                                        )
                                      : MMPdfView(
                                          key: ocr == null || ocr.revision == 0
                                              ? ValueKey(doc.id)
                                              : ValueKey((doc.id, ocr.revision)),
                                          filePath: ocr?.document?.path ?? controller.filePath(doc),
                                          controller: _pdf,
                                          onReady: (_) {
                                            if (ocr?.document?.hasCopy != true) return;
                                            dismissSelection();
                                            _pdf.search(_pdf.searchQuery);
                                          },
                                          initialPage:
                                              ref.read(readingPagesProvider(widget.studySetId))[doc.id] ?? doc.lastPage,
                                          backgroundColor: c.readerBackground,
                                          emphasisColor: c.accent,
                                          pageColorFilter: style.pageFilter,
                                          highlights: _highlights(content, doc.id, state),
                                          areaSelecting: state.tool == AnnotationTool.area,
                                          inkStrokes: [
                                            for (final s in content.inkStrokes)
                                              if (s.documentId == doc.id) s,
                                          ],
                                          inkColors: _inkColors,
                                          ink: state.ink,
                                          onInkDrawn: (draft) => controller.addInkStroke(doc.id, draft),
                                          onInkErased: controller.eraseInkStrokes,
                                          onAreaSelected: (area) async {
                                            dismissSelection();
                                            final notice = await controller.excerptArea(
                                              doc.id,
                                              area,
                                              () => _pdf.captureArea(area.page, area.rect),
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
                                                            .read(readerOcrProvider(source!).notifier)
                                                            .recognize(page, page, PdfOcrLanguage.chineseEnglish);
                                                      }),
                                                      MMMenuItem(
                                                        l.ocrRecognize,
                                                        () => showReaderOcrOptions(context, ref, widget.studySetId),
                                                      ),
                                                    ],
                                                  );
                                                },
                                          onViewportChanged: dismissSelection,
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
                                            _pdf.clearSelection();
                                            controller.tapHighlight(id, bounds);
                                          },
                                          onSelectionCommitted: (selection) async {
                                            final notice = await controller.onSelectionCommitted(doc.id, selection);
                                            if (notice != null) {
                                              await _pdf.clearSelection();
                                              if (context.mounted) showNotice(context, notice, rootTitle: rootTitle);
                                            }
                                          },
                                        ),
                                ),
                                if (state.tool == AnnotationTool.ink)
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
                                if (state.findVisible)
                                  Positioned(
                                    top: 12,
                                    left: 12,
                                    right: 16,
                                    child: Align(
                                      alignment: Alignment.topRight,
                                      child: ReaderFindBar(
                                        pdf: _pdf,
                                        focusTick: state.findFocusTick,
                                        onClose: controller.closeFind,
                                      ),
                                    ),
                                  ),
                                if (state.pending case final PendingAction pending)
                                  Positioned.fill(
                                    child: MMFloatingToolbarLayout(
                                      avoid: _pagePillArea,
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
                                              pdf: _pdf,
                                              rootTitle: rootTitle,
                                            ),
                                    ),
                                  ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: _pagePillBottom,
                                  child: MouseRegion(
                                    key: const ValueKey('reader-page-navigation'),
                                    onEnter: (_) => setState(() => _hoveringNavigation = true),
                                    onExit: (_) => setState(() => _hoveringNavigation = false),
                                    child: Focus(
                                      onFocusChange: (focused) => setState(() => _navigationFocused = focused),
                                      child: Consumer(
                                        builder: (context, ref, _) {
                                          final page =
                                              ref.watch(
                                                readingPagesProvider(widget.studySetId).select((p) => p[doc.id]),
                                              ) ??
                                              doc.lastPage;
                                          return _PagePill(
                                            visible: _navigationVisible,
                                            page: _scrubPage?.round() ?? page,
                                            editRequests: _pageFieldRequests,
                                            pageCount: doc.pageCount,
                                            onJump: (page) {
                                              dismissSelection();
                                              _pdf.jumpToPage(page);
                                            },
                                            onPrevious: () {
                                              dismissSelection();
                                              _pdf.goToPage((page) - 1);
                                            },
                                            onNext: () {
                                              dismissSelection();
                                              _pdf.goToPage((page) + 1);
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
                                                        value: (_scrubPage ?? page.toDouble()).clamp(
                                                          1,
                                                          doc.pageCount.toDouble(),
                                                        ),
                                                        label: '${_scrubPage?.round() ?? page} / ${doc.pageCount}',
                                                        semanticFormatterCallback: (v) =>
                                                            '${v.round()} / ${doc.pageCount}',
                                                        onChangeStart: (v) {
                                                          dismissSelection();
                                                          setState(() => _scrubPage = v);
                                                        },
                                                        onChanged: (v) {
                                                          setState(() => _scrubPage = v);
                                                          _pdf.scrubToPage(v.round());
                                                        },
                                                        onChangeEnd: (v) {
                                                          _pdf.scrubToPage(v.round());
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
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
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

Rect _pagePillArea(Size viewport) =>
    Rect.fromLTWH(0, viewport.height - _pagePillBottom - _pagePillHeight, viewport.width, _pagePillHeight);

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

class _Tab extends StatelessWidget {
  const _Tab({
    required this.title,
    required this.active,
    required this.onOpen,
    required this.onClose,
    required this.closeLabel,
  });

  final String title;
  final bool active;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final String closeLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    return MMInteractive(
      onTap: onOpen,
      selected: active,
      builder: (context, s) => AnimatedContainer(
        duration: MMMotion.quick,
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: active ? c.card : Color.alphaBlend(s.hovered ? c.hover : Colors.transparent, c.quaternaryFill),
          borderRadius: BorderRadius.circular(14),
          boxShadow: active ? c.cardShadow : null,
        ),
        child: Row(
          children: [
            Opacity(
              opacity: s.hovered || active ? 1 : 0,
              child: MMIconButton(icon: MMIcons.close, tooltip: closeLabel, size: 18, iconSize: 10, onPressed: onClose),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.callout.copyWith(
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? c.label : c.secondaryLabel,
                ),
              ),
            ),
            const SizedBox(width: 18),
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
