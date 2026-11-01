import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';

class ResearchFieldLabel extends StatelessWidget {
  const ResearchFieldLabel(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: MMSpacing.xs + 2),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: context.mmText.subheadline.copyWith(color: context.mmColors.secondaryLabel)),
        ),
        ?trailing,
      ],
    ),
  );
}

class EvidenceQuote extends StatefulWidget {
  const EvidenceQuote({super.key, required this.quote, this.caption, this.onOpen});

  static const maxLines = 4;

  final String quote;
  final String? caption;
  final VoidCallback? onOpen;

  @override
  State<EvidenceQuote> createState() => _EvidenceQuoteState();
}

class _EvidenceQuoteState extends State<EvidenceQuote> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    return Container(
      padding: const EdgeInsets.only(left: MMSpacing.s + 2),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.research, width: 2)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: widget.quote, style: t.readingExcerpt),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: EvidenceQuote.maxLines,
          )..layout(maxWidth: constraints.maxWidth);
          final long = painter.didExceedMaxLines;
          painter.dispose();
          final text = Text(
            widget.quote,
            maxLines: _expanded ? null : EvidenceQuote.maxLines,
            overflow: _expanded ? null : TextOverflow.ellipsis,
            style: t.readingExcerpt,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.onOpen == null)
                text
              else
                MMInteractive(onTap: widget.onOpen, semanticLabel: widget.quote, builder: (context, s) => text),
              if (long || widget.caption != null)
                Padding(
                  padding: const EdgeInsets.only(top: MMSpacing.xxs),
                  child: Row(
                    children: [
                      if (widget.caption != null)
                        Flexible(
                          child: Text(
                            widget.caption!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.footnote.copyWith(color: c.secondaryLabel),
                          ),
                        ),
                      if (long) ...[
                        if (widget.caption != null) const SizedBox(width: MMSpacing.s),
                        MMInteractive(
                          onTap: () => setState(() => _expanded = !_expanded),
                          semanticLabel: _expanded ? l.collapseSection : l.expandSection,
                          builder: (context, s) => Text(
                            _expanded ? l.collapseSection : l.expandSection,
                            style: t.footnote.copyWith(color: s.hovered ? c.research : c.accent),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class CiteBadge extends StatelessWidget {
  const CiteBadge({super.key, required this.number, required this.title, this.onTap});

  final int number;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MMInteractive(
      onTap: onTap,
      tooltip: title,
      semanticLabel: '[$number] $title',
      builder: (context, s) => Container(
        margin: const EdgeInsets.only(left: 3),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: s.hovered ? c.research : c.researchTint,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '$number',
          style: context.mmText.footnote.copyWith(color: s.hovered ? c.onResearch : c.research, height: 15 / 11),
        ),
      ),
    );
  }
}
