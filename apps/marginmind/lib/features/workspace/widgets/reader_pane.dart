import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'notices.dart';

/// Source pane: document tabs, the PDF (Preview-style gray backdrop), the
/// selection action bar and the floating page pill.
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
                : Stack(
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
                                onPageChanged: (page, _) => controller.recordPage(doc.id, page),
                                onHighlightTap: controller.tapHighlight,
                                onSelectionCommitted: (selection) async {
                                  final notice = await controller.onSelectionCommitted(doc.id, selection);
                                  if (notice != null) {
                                    await _pdf.clearSelection();
                                    if (context.mounted) showNotice(context, notice, rootTitle: rootTitle);
                                  }
                                },
                              ),
                      ),
                      if (state.pending != null)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 60,
                          child: Center(
                            child: _ActionBar(
                              studySetId: widget.studySetId,
                              pending: state.pending!,
                              content: content,
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
                            onPrevious: () => _pdf.goToPage((state.currentPages[doc.id] ?? doc.lastPage) - 1),
                            onNext: () => _pdf.goToPage((state.currentPages[doc.id] ?? doc.lastPage) + 1),
                          ),
                        ),
                      ),
                    ],
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
        () {
          final color = MMAnnotationColor.fromIndex(a.colorIndex);
          final hasCard = content.cardForAnnotation(a.id) != null;
          final strong = a.id == selectedAnnotation;
          return MMPdfHighlight(
            id: a.id,
            page: a.page,
            rects: a.rects,
            color: color.color.withValues(alpha: strong ? 0.5 : 0.32),
            underline: hasCard ? color.underline : null,
            emphasized: a.id == state.flashAnnotationId || a.id == pendingAnnotation,
          );
        }(),
    ];
  }
}

/// Glass bar for a pending selection or a clicked plain highlight.
class _ActionBar extends ConsumerWidget {
  const _ActionBar({
    required this.studySetId,
    required this.pending,
    required this.content,
    required this.pdf,
    required this.rootTitle,
  });

  final String studySetId;
  final PendingAction pending;
  final StudySetContent content;
  final MMPdfViewController pdf;
  final String rootTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final controller = ref.read(workspaceProvider(studySetId).notifier);
    final state = ref.watch(workspaceProvider(studySetId));

    Future<void> run(Future<WorkspaceNotice?> action) async {
      final notice = await action;
      await pdf.clearSelection();
      if (context.mounted) showNotice(context, notice, rootTitle: rootTitle);
    }

    final (String quote, MMAnnotationColor current, List<Widget> actions) = switch (pending) {
      PendingSelection(:final documentId, :final selection) => (
        selection.text,
        state.color,
        [
          MMButton(
            label: l.excerptAction,
            variant: MMButtonVariant.primary,
            onPressed: () => run(controller.excerpt(documentId, selection, state.color)),
          ),
          MMButton(
            label: l.highlightAction,
            variant: MMButtonVariant.plain,
            onPressed: () => run(controller.highlight(documentId, selection, state.color)),
          ),
          MMButton(
            label: l.copyAction,
            variant: MMButtonVariant.plain,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: selection.text));
              controller.dismissPending();
              await pdf.clearSelection();
              if (context.mounted) MMHud.show(context, l.copiedHud);
            },
          ),
        ],
      ),
      PendingHighlight(:final annotationId) => (
        content.annotation(annotationId)?.quote ?? '',
        MMAnnotationColor.fromIndex(content.annotation(annotationId)?.colorIndex ?? 0),
        [
          MMButton(
            label: l.addToMapAction,
            variant: MMButtonVariant.primary,
            onPressed: () => run(controller.addHighlightToMap(annotationId)),
          ),
          MMButton(
            label: l.deleteHighlight,
            variant: MMButtonVariant.plain,
            onPressed: () => run(controller.deleteHighlight(annotationId)),
          ),
        ],
      ),
    };

    void pickColor(MMAnnotationColor color) {
      switch (pending) {
        case PendingSelection(:final documentId, :final selection):
          run(controller.highlight(documentId, selection, color));
        case PendingHighlight(:final annotationId):
          controller.recolor(annotationId, color);
      }
    }

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): controller.dismissPending},
      child: MMGlass(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                '“${quote.trim()}”',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.readingExcerpt.copyWith(color: c.secondaryLabel),
              ),
            ),
            const MMToolbarDivider(),
            MMColorPicker(selected: current, onChanged: pickColor, labelOf: l.colorName, dotSize: 14),
            const MMToolbarDivider(),
            for (final a in actions) Padding(padding: const EdgeInsets.only(left: 2), child: a),
            MMIconButton(
              icon: MMIcons.close,
              tooltip: l.cancel,
              onPressed: () async {
                controller.dismissPending();
                await pdf.clearSelection();
              },
            ),
          ],
        ),
      ),
    );
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
