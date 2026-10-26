import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../app/app_commands.dart';
import '../../../app/navigation.dart';
import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import '../../../settings/app_settings.dart';
import '../workspace_controller.dart';
import 'notices.dart';
import 'reader_find_bar.dart';
import 'reader_sidebar.dart';
import 'reader_annotation_tools.dart';
import 'selection_toolbar.dart';

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
  bool _hoveringPdf = false;
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
            child: Wrap(
              spacing: MMSpacing.s,
              runSpacing: MMSpacing.s,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MMToolbarButton(
                  icon: MMIcons.readerNavigation,
                  tooltip: AppShortcuts.tip(
                    state.readerPanelVisible ? l.hideReaderSidebar : l.showReaderSidebar,
                    AppShortcuts.toggleReaderSidebar,
                  ),
                  selected: state.readerPanelVisible,
                  onPressed: controller.toggleReaderPanel,
                ),
                PopupMenuButton<ReaderZoomCommand>(
                  key: const ValueKey('reader-zoom'),
                  tooltip: l.readerZoom,
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    minimumSize: MMSizes.toolbarButton,
                    fixedSize: MMSizes.toolbarButton,
                    padding: EdgeInsets.zero,
                  ),
                  iconSize: MMSpacing.l,
                  icon: const Icon(MMIcons.readerZoom),
                  onSelected: _zoom,
                  itemBuilder: (_) => [
                    for (final entry in [
                      (ReaderZoomCommand.zoomIn, l.zoomIn),
                      (ReaderZoomCommand.zoomOut, l.zoomOut),
                      (ReaderZoomCommand.actualSize, l.pdfActualSize),
                      (ReaderZoomCommand.fitWidth, l.pdfFitWidth),
                      (ReaderZoomCommand.fitPage, l.pdfFitPage),
                    ])
                      PopupMenuItem(value: entry.$1, child: Text(entry.$2)),
                  ],
                ),
                PopupMenuButton<MMReaderStyle>(
                  key: const ValueKey('reader-appearance'),
                  tooltip: l.readerAppearance,
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    minimumSize: MMSizes.toolbarButton,
                    fixedSize: MMSizes.toolbarButton,
                    padding: EdgeInsets.zero,
                  ),
                  iconSize: MMSpacing.l,
                  onSelected: ref.read(settingsProvider.notifier).setReaderStyle,
                  itemBuilder: (context) => [
                    for (final value in MMReaderStyle.values)
                      PopupMenuItem(
                        value: value,
                        child: Row(
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
                            if (value == style) Icon(Icons.check, color: c.accent, size: MMSpacing.l),
                          ],
                        ),
                      ),
                  ],
                  icon: const Icon(MMIcons.appearance),
                ),
                ReaderAnnotationTools(state: state, controller: controller),
              ],
            ),
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
                          onEnter: (_) => setState(() => _hoveringPdf = true),
                          onExit: (_) => setState(() => _hoveringPdf = false),
                          child: Listener(
                            onPointerSignal: (_) => dismissSelection(),
                            onPointerPanZoomStart: (_) => dismissSelection(),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: !ref.watch(pdfRenderingEnabledProvider)
                                      ? ColoredBox(
                                          key: ValueKey('pdf-placeholder-${doc.id}'),
                                          color: c.readerBackground,
                                        )
                                      : MMPdfView(
                                          key: ValueKey(doc.id),
                                          filePath: controller.filePath(doc),
                                          controller: _pdf,
                                          initialPage:
                                              ref.read(readingPagesProvider(widget.studySetId))[doc.id] ?? doc.lastPage,
                                          backgroundColor: c.readerBackground,
                                          emphasisColor: c.accent,
                                          pageColorFilter: style.pageFilter,
                                          highlights: _highlights(content, doc.id, state),
                                          areaSelecting: state.tool == AnnotationTool.area,
                                          onAreaSelected: (area) async {
                                            dismissSelection();
                                            final notice = await controller.excerptArea(
                                              doc.id,
                                              area,
                                              () => _pdf.captureArea(area.page, area.rect),
                                            );
                                            if (context.mounted) showNotice(context, notice, rootTitle: rootTitle);
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
                                      },
                                      child: SelectionToolbar(
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
                                  bottom: 16,
                                  child: Center(
                                    child: Consumer(
                                      builder: (context, ref, _) {
                                        final page =
                                            ref.watch(
                                              readingPagesProvider(widget.studySetId).select((p) => p[doc.id]),
                                            ) ??
                                            doc.lastPage;
                                        return Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _PagePill(
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
                                            ),
                                            if ((_hoveringPdf || _scrubPage != null) && doc.pageCount > 1)
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xl),
                                                child: Slider(
                                                  key: const ValueKey('reader-page-progress'),
                                                  min: 1,
                                                  max: doc.pageCount.toDouble(),
                                                  value: (_scrubPage ?? page.toDouble()).clamp(
                                                    1,
                                                    doc.pageCount.toDouble(),
                                                  ),
                                                  label: '${_scrubPage?.round() ?? page} / ${doc.pageCount}',
                                                  semanticFormatterCallback: (v) => '${v.round()} / ${doc.pageCount}',
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
    ];
  }
}

/// Space the page pill takes at the bottom of the reader; floating toolbars
/// keep clear of it. An estimate that is wider than `_PagePill`; change both
/// together.
const _pagePillBottom = 16.0;
const _pagePillHeight = 32.0;
const _pagePillSize = Size(200, _pagePillHeight);

/// How far the page pill reaches up from the window's bottom edge; the HUD
/// stays above it.
const pagePillClearance = _pagePillBottom + _pagePillHeight;

Rect _pagePillArea(Size viewport) => Rect.fromLTWH(
  (viewport.width - _pagePillSize.width) / 2,
  viewport.height - _pagePillBottom - _pagePillSize.height,
  _pagePillSize.width,
  _pagePillSize.height,
);

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
  });

  final int page;
  final int editRequests;
  final int pageCount;
  final ValueChanged<int> onJump;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    return MMGlass(
      borderRadius: BorderRadius.circular(MMRadii.capsule),
      color: c.glassOpaque,
      blurSigma: 0,
      shadows: const [],
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MMIconButton(
            icon: MMIcons.chevronLeft,
            tooltip: l.previousPage,
            size: 26,
            iconSize: 13,
            color: c.label,
            onPressed: page > 1 ? onPrevious : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _PageField(page: page, pageCount: pageCount, onJump: onJump, editRequests: editRequests),
          ),
          MMIconButton(
            icon: MMIcons.chevronRight,
            tooltip: l.nextPage,
            size: 26,
            iconSize: 13,
            color: c.label,
            onPressed: page < pageCount ? onNext : null,
          ),
        ],
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
