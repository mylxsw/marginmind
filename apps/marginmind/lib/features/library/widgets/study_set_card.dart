import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import 'study_set_cover.dart';

/// Icon-view item. Finder conventions: click selects (gray well behind the
/// cover, accent capsule behind the name), double-click opens.
class StudySetCard extends StatelessWidget {
  const StudySetCard({
    super.key,
    required this.set,
    required this.selected,
    required this.now,
    required this.onSelect,
    required this.onOpen,
    required this.onToggleStar,
  });

  final StudySet set;
  final bool selected;
  final DateTime now;
  final VoidCallback onSelect;
  final VoidCallback onOpen;
  final VoidCallback onToggleStar;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    return MMInteractive(
      onTapDown: onSelect,
      onTap: MMInput.of(context).touchPlatform ? onOpen : null,
      onDoubleTap: MMInput.of(context).touchPlatform ? null : onOpen,
      selected: selected,
      builder: (context, s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: selected ? c.selectedRow : Colors.transparent,
              borderRadius: BorderRadius.circular(MMRadii.cover + 5),
            ),
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                AnimatedSlide(
                  duration: MMAppearance.duration(context, MMMotion.standard),
                  offset: Offset(0, s.hovered ? -0.02 : 0),
                  child: StudySetCover(
                    color: MMAnnotationColor.fromIndex(set.colorIndex),
                    documentCount: set.documentCount,
                  ),
                ),
                if (set.dueCount > 0)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: MMGlass(
                      // Glass stays off content on touch platforms: a card's badge only tints.
                      blurSigma: MMInput.of(context).touchPlatform ? 0 : 24,
                      borderRadius: BorderRadius.circular(10),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: Text(l.dueBadge(set.dueCount), style: t.subheadline.copyWith(color: c.label)),
                    ),
                  ),
                if (s.hovered || set.starred)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _StarButton(starred: set.starred, onPressed: onToggleStar),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? c.accentFill : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                set.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.headline.copyWith(color: selected ? c.onAccent : c.label),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${l.libraryCardMeta(set.documentCount, set.cardCount)} · ${l.relativeTime(set.lastOpenedAt, now)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: t.footnote,
          ),
        ],
      ),
    );
  }
}

class _StarButton extends StatelessWidget {
  const _StarButton({required this.starred, required this.onPressed});

  final bool starred;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return MMInteractive(
      onTap: onPressed,
      tooltip: starred ? l.unstar : l.star,
      semanticLabel: starred ? l.unstar : l.star,
      builder: (context, s) => MMControlFrame(
        child: MMGlass(
          blurSigma: MMInput.of(context).touchPlatform ? 0 : 24,
          borderRadius: BorderRadius.circular(context.mmTouchPlatform ? 16 : 13),
          child: SizedBox(
            width: context.mmTouchPlatform ? MMSizes.tabletControlVisual : 26,
            height: context.mmTouchPlatform ? MMSizes.tabletControlVisual : 26,
            child: Icon(
              starred ? MMIcons.starFill : MMIcons.star,
              size: context.mmTouchPlatform ? MMSizes.tabletToolbarIcon : 13,
              color: starred ? const Color(0xFFC79A00) : context.mmColors.label,
            ),
          ),
        ),
      ),
    );
  }
}
