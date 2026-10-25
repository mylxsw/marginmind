import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';

/// Finder-style outline of the map: indentation per level, accent-filled
/// selection. Double-click reveals an excerpt in the source or renames
/// a topic / note.
class OutlineView extends StatelessWidget {
  const OutlineView({
    super.key,
    required this.content,
    required this.rootTitle,
    required this.selectedCardId,
    required this.onSelect,
    required this.onReveal,
    required this.onRename,
  });

  final StudySetContent content;
  final String rootTitle;
  final String? selectedCardId;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String> onReveal;
  final ValueChanged<String> onRename;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final rows = <Widget>[
      _OutlineRow(
        depth: 0,
        label: rootTitle,
        bold: true,
        selected: selectedCardId == null,
        onTap: () => onSelect(null),
      ),
    ];

    void walk(String? parentId, int depth) {
      for (final node in content.childrenOf(parentId)) {
        final card = content.card(node.cardId);
        if (card == null) continue;
        final annotation = card.annotationId == null ? null : content.annotation(card.annotationId!);
        final isExcerpt = card.kind == CardKind.excerpt;
        rows.add(
          _OutlineRow(
            depth: depth,
            label: isExcerpt ? (card.title.isEmpty ? (annotation?.quote ?? '') : card.title) : card.title,
            sub: isExcerpt && card.title.isNotEmpty ? annotation?.quote : null,
            meta: annotation == null ? null : l.pageNumber(annotation.page),
            dot: isExcerpt ? MMAnnotationColor.fromIndex(annotation?.colorIndex ?? 0).color : null,
            bold: card.kind == CardKind.topic,
            selected: card.id == selectedCardId,
            onTap: () => onSelect(card.id),
            onDoubleTap: () => isExcerpt ? onReveal(card.id) : onRename(card.id),
          ),
        );
        walk(card.id, depth + 1);
      }
    }

    walk(null, 1);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 76, 16, 72),
      children: [
        ...rows,
        if (rows.length == 1)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l.outlineEmpty, textAlign: TextAlign.center, style: context.mmText.footnote),
          ),
      ],
    );
  }
}

class _OutlineRow extends StatelessWidget {
  const _OutlineRow({
    required this.depth,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onDoubleTap,
    this.sub,
    this.meta,
    this.dot,
    this.bold = false,
  });

  final int depth;
  final String label;
  final String? sub;
  final String? meta;
  final Color? dot;
  final bool bold;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final fg = selected ? c.onAccent : c.label;
    final fg2 = selected ? c.onAccent.withValues(alpha: 0.85) : c.secondaryLabel;
    return MMInteractive(
      onTapDown: onTap,
      onDoubleTap: onDoubleTap,
      selected: selected,
      semanticLabel: label,
      builder: (context, s) => Container(
        padding: EdgeInsets.fromLTRB(8 + depth * 20.0, 5, 8, 5),
        decoration: BoxDecoration(
          color: selected ? c.accentFill : (s.hovered ? c.hover : Colors.transparent),
          borderRadius: BorderRadius.circular(MMRadii.row),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6, right: 8),
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                border: dot == null ? Border.all(color: fg2) : null,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.body.copyWith(
                      color: fg,
                      fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                      height: 20 / 13,
                    ),
                  ),
                  if (sub != null)
                    Text(
                      sub!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.readingExcerpt.copyWith(color: fg2),
                    ),
                ],
              ),
            ),
            if (meta != null)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 3),
                child: Text(meta!, style: t.footnote.copyWith(color: fg2)),
              ),
          ],
        ),
      ),
    );
  }
}
