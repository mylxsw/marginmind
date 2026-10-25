import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../workspace_controller.dart';

/// Source pane: document tabs, the page area (Preview-style gray backdrop
/// with a white sheet) and the floating page pill. PDF rendering plugs in
/// here once mm_pdf exists.
class ReaderPane extends ConsumerWidget {
  const ReaderPane({super.key, required this.studySetId});

  final String studySetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final provider = workspaceProvider(studySetId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final doc = state.activeDocument;

    return ColoredBox(
      color: c.readerBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.openDocuments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  for (final d in state.openDocuments)
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
                ? MMEmptyState(icon: MMIcons.document, title: l.readerEmptyTitle, message: l.readerEmptyMessage)
                : Stack(
                    children: [
                      Positioned.fill(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(28, 20, 28, 96),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 620),
                              child: AspectRatio(
                                aspectRatio: 1 / 1.35,
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(60, 52, 60, 60),
                                  decoration: BoxDecoration(
                                    color: c.page,
                                    borderRadius: BorderRadius.circular(MMRadii.page),
                                    boxShadow: c.cardShadow,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              doc.title,
                                              style: t.readingExcerpt.copyWith(
                                                fontSize: 11,
                                                color: const Color(0xFF6E6E73),
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '${doc.currentPage}',
                                            style: t.readingExcerpt.copyWith(
                                              fontSize: 11,
                                              color: const Color(0xFF6E6E73),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 20, thickness: 0.5, color: Color(0xFFD2D2D7)),
                                      const SizedBox(height: 24),
                                      Text(l.readerPlaceholder, style: t.readingBody),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 16,
                        child: Center(
                          child: MMGlass(
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
                                  onPressed: () {},
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    l.pageOf(doc.currentPage, doc.pageCount),
                                    style: t.callout.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                                  ),
                                ),
                                MMIconButton(
                                  icon: MMIcons.chevronRight,
                                  tooltip: l.nextPage,
                                  size: 26,
                                  iconSize: 13,
                                  color: c.label,
                                  onPressed: () {},
                                ),
                              ],
                            ),
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
