import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'notices.dart';
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
  final _pdf = MMPdfViewController();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final provider = workspaceProvider(widget.studySetId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final content = ref.watch(contentProvider(widget.studySetId)).value ?? StudySetContent.empty;
    final doc = state.activeDocumentId == null ? null : content.document(state.activeDocumentId!);
    final rootTitle = ref.watch(studySetProvider(widget.studySetId))?.title ?? '';

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

    final openDocs = [for (final id in state.openDocumentIds) ?content.document(id)];

    return ColoredBox(
      color: c.readerBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (openDocs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
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
                : Listener(
                    onPointerSignal: (_) => dismissSelection(),
                    onPointerPanZoomStart: (_) => dismissSelection(),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: !ref.watch(pdfRenderingEnabledProvider)
                              ? ColoredBox(key: ValueKey('pdf-placeholder-${doc.id}'), color: c.readerBackground)
                              : MMPdfView(
                                  key: ValueKey(doc.id),
                                  filePath: controller.filePath(doc),
                                  controller: _pdf,
                                  initialPage: doc.lastPage,
                                  backgroundColor: c.readerBackground,
                                  emphasisColor: c.accent,
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
                                    if (!selected && ref.read(provider).pending is PendingSelection) dismissSelection();
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
                        if (state.pending case final PendingAction pending)
                          Positioned.fill(
                            child: MMFloatingToolbarLayout(
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
                            child: _PagePill(
                              page: state.currentPages[doc.id] ?? doc.lastPage,
                              pageCount: doc.pageCount,
                              onPrevious: () {
                                dismissSelection();
                                _pdf.goToPage((state.currentPages[doc.id] ?? doc.lastPage) - 1);
                              },
                              onNext: () {
                                dismissSelection();
                                _pdf.goToPage((state.currentPages[doc.id] ?? doc.lastPage) + 1);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
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
            final card = content.cardForAnnotation(a.id);
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

class _PagePill extends StatelessWidget {
  const _PagePill({required this.page, required this.pageCount, required this.onPrevious, required this.onNext});

  final int page;
  final int pageCount;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    return MMGlass(
      borderRadius: BorderRadius.circular(16),
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
            child: Text(
              l.pageOf(page, pageCount),
              style: t.callout.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
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
      semanticLabel: title,
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
