import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/card_image.dart';
import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'notices.dart';
import 'right_panel.dart';

/// The details of the card shown in the right panel (P2-C01): its whole
/// text, an editable title, the way back to the source, tags and review
/// state. Edits go through the controller, so the map follows and each one
/// is a single undo step.
class CardDetails extends ConsumerWidget {
  const CardDetails({super.key, required this.studySetId});

  final String studySetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final provider = workspaceProvider(studySetId);
    final cardId = ref.watch(provider.select((s) => s.detailsCardId));
    // The controller's copy includes its own writes before the stream delivers them.
    ref.watch(workspaceContentProvider(studySetId));
    final controller = ref.read(provider.notifier);
    final content = controller.content;
    final card = cardId == null ? null : content.card(cardId);
    final annotation = content.annotation(card?.annotationId ?? '');

    final (icon, kindLabel) = switch (card?.kind) {
      CardKind.excerpt => (MMIcons.document, l.detailsExcerpt),
      CardKind.image => (MMIcons.areaSelect, l.detailsImage),
      // Research notes get their own details with the research flow.
      CardKind.note || CardKind.research => (MMIcons.addNote, l.detailsNote),
      CardKind.topic || null => (MMIcons.mindMap, l.detailsTopic),
    };
    final header = RightPanelHeader(icon: icon, title: kindLabel, onClose: controller.closePanel);
    if (card == null) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header]);

    final color = MMAnnotationColor.fromIndex(annotation?.colorIndex ?? 0);
    final reviewable = card.suspended || card.kind != CardKind.topic;
    final sections = <Widget>[
      if (card.kind == CardKind.image && card.imageFileName != null)
        ClipRRect(
          key: const ValueKey('details-image'),
          borderRadius: BorderRadius.circular(MMRadii.card),
          child: ColoredBox(
            color: color.cardTint,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: MMSizes.rightPanelNarrowWidth),
              // Sized from the captured area before the file is decoded, so
              // the panel does not jump when the picture arrives.
              child: AspectRatio(
                aspectRatio: _aspect(annotation),
                child: GestureDetector(
                  onTap: () => showCardImagePreview(context, card.imageFileName!),
                  child: CardImage(
                    card.imageFileName!,
                    semanticLabel: card.title.isEmpty ? l.imageExcerpt : card.title,
                  ),
                ),
              ),
            ),
          ),
        ),
      _DetailsTitle(
        key: ValueKey('details-title-${card.id}'),
        title: card.title,
        note: card.kind == CardKind.note || card.kind == CardKind.research,
        image: card.kind == CardKind.image,
        optional: card.kind == CardKind.excerpt || card.kind == CardKind.image,
        onCommit: (text) => controller.setTitle(card.id, text),
      ),
      if (card.kind == CardKind.excerpt && annotation != null)
        Container(
          key: const ValueKey('details-quote'),
          padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.s + MMSpacing.xxs),
          decoration: BoxDecoration(color: color.cardTint, borderRadius: BorderRadius.circular(MMRadii.field)),
          child: SelectableText(annotation.quote, style: t.readingExcerpt),
        ),
      if (annotation != null || card.kind == CardKind.excerpt)
        Wrap(
          spacing: MMSpacing.s,
          runSpacing: MMSpacing.s,
          children: [
            if (annotation != null)
              MMButton(
                icon: MMIcons.revealSource,
                label: l.revealSourcePage(annotation.page),
                onPressed: () => controller.revealCard(card.id),
              ),
            if (card.kind == CardKind.excerpt && annotation != null && annotation.quote.isNotEmpty)
              MMButton(
                icon: MMIcons.copy,
                label: l.copyAction,
                onPressed: () async {
                  try {
                    await Clipboard.setData(ClipboardData(text: annotation.quote));
                    if (context.mounted) MMHud.show(context, l.copiedHud, icon: MMIcons.success);
                  } on PlatformException {
                    if (context.mounted) MMHud.show(context, l.somethingWentWrong, icon: MMIcons.close);
                  }
                },
              ),
          ],
        ),
      _Section(
        label: l.sectionTags,
        child: Wrap(
          spacing: MMSpacing.xs,
          runSpacing: MMSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final tag in card.tags) _TagChip(tag),
            MMIconButton(
              icon: MMIcons.add,
              tooltip: l.cardTags,
              size: 22,
              iconSize: 12,
              onPressed: () => showCardTagsSheet(context, ref, studySetId, card.id),
            ),
          ],
        ),
      ),
      if (reviewable)
        _Section(
          label: l.review,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _reviewStatus(l, card, content.reviewOf(card.id)),
                  key: const ValueKey('details-review-status'),
                  style: t.callout.copyWith(color: c.secondaryLabel),
                ),
              ),
              MMButton(
                label: card.suspended ? l.resumeCard : l.suspendCard,
                variant: MMButtonVariant.plain,
                onPressed: () => controller.setSuspended(card.id, suspended: !card.suspended),
              ),
            ],
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(MMSpacing.l, MMSpacing.m, MMSpacing.l, MMSpacing.l),
            itemCount: sections.length,
            separatorBuilder: (_, _) => const SizedBox(height: MMSpacing.l),
            itemBuilder: (_, i) => sections[i],
          ),
        ),
      ],
    );
  }

  /// Width / height of an area's picture; a square when it is unknown.
  static double _aspect(Annotation? a) {
    final r = a?.rects.firstOrNull;
    if (r == null) return 1;
    final w = (r.right - r.left).abs(), h = (r.top - r.bottom).abs();
    return w <= 0 || h <= 0 ? 1 : (w / h).clamp(0.25, 4.0);
  }

  static String _reviewStatus(AppLocalizations l, Card card, ReviewState? review) {
    if (card.suspended) return l.cardSuspended;
    if (review == null) return l.reviewStatusNew;
    return l.reviewStatusScheduled(review.due, review.reps);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.mmText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.subheadline.copyWith(color: context.mmColors.secondaryLabel)),
        const SizedBox(height: MMSpacing.s - MMSpacing.xxs),
        child,
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip(this.tag);

  final String tag;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s - 1, vertical: MMSpacing.xxs),
      decoration: BoxDecoration(color: c.fill, borderRadius: BorderRadius.circular(MMRadii.row)),
      child: Text(tag, style: context.mmText.footnote),
    );
  }
}

/// The card's title (a note's text), edited where it is shown. Enter, or
/// leaving the field, keeps the text; Esc puts the stored title back.
class _DetailsTitle extends StatefulWidget {
  const _DetailsTitle({
    super.key,
    required this.title,
    required this.note,
    required this.optional,
    this.image = false,
    required this.onCommit,
  });

  final String title;

  /// Whether the title may be cleared (excerpts and images show their
  /// content instead); a cleared required title comes back.
  final bool optional;
  final bool image;

  /// A note's text: body style, ⇧Enter for a new line.
  final bool note;
  final Future<void> Function(String text) onCommit;

  @override
  State<_DetailsTitle> createState() => _DetailsTitleState();
}

class _DetailsTitleState extends State<_DetailsTitle> {
  late final _controller = TextEditingController(text: widget.title);
  final _focus = FocusNode(debugLabel: 'DetailsTitle');

  /// The field has had the keyboard since its text was last saved or reset.
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!mounted) return;
      if (_focus.hasFocus) {
        _editing = true;
      } else {
        _commit();
      }
      setState(() {});
    });
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(_DetailsTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Undo, the map's own editor or another window changed the title.
    if (!_focus.hasFocus && widget.title != _controller.text) _controller.text = widget.title;
  }

  /// Whether [text] would change the stored title.
  bool _changes(String text) => text.trim() != widget.title && (widget.optional || text.trim().isNotEmpty);

  void _commit() {
    _editing = false;
    final text = _controller.text;
    if (_changes(text)) {
      unawaited(widget.onCommit(text));
    } else if (text != widget.title) {
      _controller.text = widget.title;
    }
  }

  @override
  void dispose() {
    // Moving to another card or closing the panel keeps what was typed.
    final text = _controller.text;
    final commit = widget.onCommit;
    if (_editing && _changes(text)) Future.microtask(() => commit(text));
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mmText;
    final c = context.mmColors;
    final style = widget.note ? t.body.copyWith(height: 19 / 13) : t.title3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xs, vertical: MMSpacing.xxs),
      decoration: BoxDecoration(
        color: _focus.hasFocus ? c.quaternaryFill : null,
        borderRadius: BorderRadius.circular(MMRadii.excerpt),
      ),
      child: Stack(
        children: [
          if (_controller.text.isEmpty)
            IgnorePointer(
              child: Text(
                (widget.image ? context.l10n.imageQuestion : context.l10n.addTitle),
                style: style.copyWith(color: c.secondaryLabel),
              ),
            ),
          MMInlineTextField(
            controller: _controller,
            focusNode: _focus,
            style: style,
            multiline: widget.note,
            semanticLabel: (widget.image ? context.l10n.imageQuestion : context.l10n.addTitle),
            onSubmitted: _focus.unfocus,
            onCancel: () {
              _editing = false;
              _controller.text = widget.title;
              _focus.unfocus();
            },
          ),
        ],
      ),
    );
  }
}
