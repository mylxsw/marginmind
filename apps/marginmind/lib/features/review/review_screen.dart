import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../app/app.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../shared/card_image.dart';
import '../../shared/l10n.dart';
import '../../shared/note_text.dart';
import '../workspace/workspace_controller.dart';
import 'review_controller.dart';

/// Flashcard review of one study set: prompt, "Show Answer", then four
/// ratings that schedule the card. Space / ↩ shows the answer, 1–4 rate.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.studySetId});

  final String studySetId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _focus = FocusNode(debugLabel: 'Review');

  @override
  void initState() {
    super.initState();
    // Take keyboard focus from the window-level shortcut scope.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _back() => ref.read(navigationProvider.notifier).openStudySet(widget.studySetId);

  void _revealSource(String cardId) {
    ref.read(navigationProvider.notifier).openStudySet(widget.studySetId);
    ref.read(workspaceProvider(widget.studySetId).notifier).revealCard(cardId);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final session = ref.read(reviewSessionProvider(widget.studySetId));
    final controller = ref.read(reviewSessionProvider(widget.studySetId).notifier);
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _back();
      return KeyEventResult.handled;
    }
    if (!session.revealed && (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter)) {
      controller.reveal();
      return KeyEventResult.handled;
    }
    if (session.revealed) {
      final rating = switch (key) {
        LogicalKeyboardKey.digit1 => Rating.again,
        LogicalKeyboardKey.digit2 => Rating.hard,
        LogicalKeyboardKey.digit3 || LogicalKeyboardKey.space || LogicalKeyboardKey.enter => Rating.good,
        LogicalKeyboardKey.digit4 => Rating.easy,
        _ => null,
      };
      if (rating != null) {
        controller.rate(rating);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final phone = MMInput.of(context).phone && MMSizeClass.of(context) == MMSizeClass.compact;
    final provider = reviewSessionProvider(widget.studySetId);
    final session = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final content = ref.watch(contentProvider(widget.studySetId)).value ?? StudySetContent.empty;
    final setTitle = ref.watch(studySetProvider(widget.studySetId))?.title ?? '';
    // A tag or branch session is named by what it covers.
    final branchTitle = content.card(controller.branchId ?? '')?.title ?? '';
    final scopeTitle = controller.tag ?? (branchTitle.isNotEmpty ? branchTitle : setTitle);
    final id = session.currentId;
    final card = id == null ? null : content.card(id);
    if (id != null && card == null && content != StudySetContent.empty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.skipMissing());
    }

    final Widget body;
    if (!session.started) {
      body = const SizedBox.shrink();
    } else if (session.finished) {
      body = MMEmptyState(
        icon: MMIcons.success,
        title: session.reviewed == 0 ? l.reviewNothingDueTitle : l.reviewDoneTitle,
        message: session.reviewed == 0 ? null : l.reviewDoneMessage(session.reviewed),
        actions: [
          MMButton(label: l.backToStudySet, variant: MMButtonVariant.primary, autofocus: true, onPressed: _back),
        ],
      );
    } else if (card == null) {
      body = const SizedBox.shrink();
    } else {
      final done = session.index / session.queue.length;
      body = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 0),
            child: phone
                ? MMPhoneReviewProgress(total: session.queue.length, completed: session.index, label: l.reviewProgress)
                : MMProgressBar(value: done, semanticLabel: l.reviewProgress),
          ),
          Expanded(
            child: LayoutBuilder(
              // Centered vertically (slightly above the middle) while it
              // fits; scrolls when the answer is long.
              builder: (context, box) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: math.max(0, box.maxHeight - 64) * 0.85),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      // Under touch, tapping the card turns it over.
                      child: GestureDetector(
                        key: const ValueKey('review-card-tap'),
                        behavior: HitTestBehavior.opaque,
                        onTap: context.mmTouch && !session.revealed ? controller.reveal : null,
                        child: _ReviewCard(
                          key: ValueKey('${session.index}-$id'),
                          studySetId: widget.studySetId,
                          card: card,
                          content: content,
                          rootTitle: content.map(controller.mapId ?? '')?.title.isNotEmpty == true
                              ? content.map(controller.mapId!)!.title
                              : setTitle,
                          mapId: controller.mapId,
                          revealed: session.revealed,
                          onRevealSource: () => _revealSource(card.id),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: session.revealed
                ? _RatingBar(
                    intervals: ReviewScheduler.preview(
                      card.id,
                      content.reviewOf(card.id),
                      ref.read(clockProvider)(),
                      memory: content.memoryOf(card.id),
                      parameters: ref.read(editorProvider).fsrsParameters,
                    ),
                    onRate: controller.rate,
                  )
                : MMButton(label: l.showAnswer, variant: MMButtonVariant.primary, onPressed: controller.reveal),
          ),
        ],
      );
    }

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: MMWindowScaffold(
        sidebarVisible: false,
        onDragStart: WindowChrome.onDragStart,
        onTitleDoubleTap: WindowChrome.onTitleDoubleTap,
        showsWindowButtons: WindowChrome.showsWindowButtons,
        toolbar: MMToolbar(
          title: l.reviewTitle,
          subtitle: phone || session.finished || !session.started
              ? scopeTitle
              : '$scopeTitle · ${l.reviewRemaining(session.remaining)}',
          leading: MMIconButton(
            icon: MMIcons.chevronLeft,
            tooltip: l.backToStudySet,
            size: context.mmToolbarIcon,
            onPressed: _back,
          ),
        ),
        body: CardImageScope(
          resolve: (name) => ref.read(contentRepositoryProvider).resolveFile(widget.studySetId, name),
          child: ColoredBox(color: context.mmColors.windowBackground, child: body),
        ),
      ),
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({
    super.key,
    required this.studySetId,
    required this.card,
    required this.content,
    required this.rootTitle,
    this.mapId,
    required this.revealed,
    required this.onRevealSource,
  });

  final String studySetId;
  final Card card;
  final StudySetContent content;
  final String rootTitle;
  final String? mapId;
  final bool revealed;
  final VoidCallback onRevealSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsText = needsPageText(card, content);
    // The front waits for the page text so it never flashes the thumbnail.
    final text = needsText ? ref.watch(excerptPageTextProvider((studySetId: studySetId, cardId: card.id))) : null;
    if (text != null && text.isLoading) return const SizedBox.shrink();
    final face = buildReviewFace(
      card,
      content,
      mapId: mapId ?? MindMap.defaultId,
      rootTitle: rootTitle,
      pageText: text?.value?.text,
      pageHeight: text?.value?.height,
      lastPageText: text?.value?.lastText,
    );
    return ReviewCardView(
      face: face,
      revealed: revealed,
      pagePath: _pagePath(ref, face.front),
      onRevealSource: onRevealSource,
    );
  }

  String? _pagePath(WidgetRef ref, ReviewFront front) {
    if (front.prompt != ReviewPrompt.page) return null;
    final annotation = card.annotationId == null ? null : content.annotation(card.annotationId!);
    final doc = annotation == null ? null : content.document(annotation.documentId);
    if (doc == null || !ref.watch(pdfRenderingEnabledProvider)) return null;
    return ref.read(contentRepositoryProvider).resolveFile(studySetId, doc.fileName);
  }
}

/// The card itself: [face]'s front, and its back once [revealed].
class ReviewCardView extends StatelessWidget {
  const ReviewCardView({
    super.key,
    required this.face,
    required this.revealed,
    this.pagePath,
    required this.onRevealSource,
  });

  final ReviewFace face;
  final bool revealed;

  /// The PDF file behind a [ReviewPrompt.page] front; without it the front
  /// shows a blank page instead.
  final String? pagePath;
  final VoidCallback onRevealSource;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final front = face.front;
    final back = face.back;
    final source = back.source;
    final phone = MMInput.of(context).phone && MMSizeClass.of(context) == MMSizeClass.compact;
    final sourceButton = MMButton(
      label: context.l10n.revealSource,
      icon: MMIcons.revealSource,
      variant: MMButtonVariant.plain,
      onPressed: onRevealSource,
    );
    final color = MMAnnotationColor.fromIndex(back.colorIndex);
    final answer = <Widget>[
      if (back.imageFileName != null)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(MMRadii.excerpt + 2),
            child: CardImage(back.imageFileName!),
          ),
        )
      else if (back.quote.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.cardTint,
            borderRadius: BorderRadius.circular(MMRadii.excerpt + 2),
            border: Border(left: BorderSide(color: color.color, width: 3)),
          ),
          child: SelectableText(back.quote, style: t.readingExcerpt.copyWith(fontSize: 16, height: 1.6)),
        ),
      for (final note in back.notes)
        NoteText(note.text, note.format, style: t.body.copyWith(fontSize: 16, height: 1.6), selectable: true),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), boxShadow: c.cardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (front.path.isNotEmpty) ...[
            Text(front.path.join('  ›  '), maxLines: 2, overflow: TextOverflow.ellipsis, style: t.footnote),
            const SizedBox(height: 12),
          ],
          if (front.prompt == ReviewPrompt.title) Text(front.title, style: t.title2),
          if (!revealed) ...[
            if (front.prompt == ReviewPrompt.cloze) _Cloze(front: front),
            if (front.prompt == ReviewPrompt.page) _PagePrompt(front: front, path: pagePath),
          ],
          if (revealed) ...[
            if (front.prompt == ReviewPrompt.title) ...[
              const SizedBox(height: 20),
              Container(height: 0.5, color: c.separator),
              const SizedBox(height: 20),
            ],
            for (final block in answer) ...[block, const SizedBox(height: 12)],
            if (source != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!phone)
                    Expanded(
                      child: Text(
                        source.textAnchor != null
                            ? source.documentTitle
                            : '${source.documentTitle} · ${context.l10n.pageNumber(source.page)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.footnote,
                      ),
                    ),
                  if (phone) Flexible(child: sourceButton) else sourceButton,
                ],
              ),
          ],
        ],
      ),
    );
  }
}

/// Sentence context with a block where the excerpt was, about as wide as
/// the excerpt is long.
class _Cloze extends StatelessWidget {
  const _Cloze({required this.front});

  final ReviewFront front;

  static const _charWidth = 9.0;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final style = context.mmText.readingExcerpt.copyWith(fontSize: 18, height: 1.7);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: front.before),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              key: const ValueKey('cloze-mask'),
              width: math.min(math.max(front.maskLength * _charWidth, 36), 360),
              height: 20,
              decoration: BoxDecoration(color: c.secondaryLabel, borderRadius: BorderRadius.circular(MMRadii.excerpt)),
            ),
          ),
          TextSpan(text: front.after),
        ],
      ),
    );
  }
}

/// Thumbnail of the source page with the excerpt's area covered.
class _PagePrompt extends StatelessWidget {
  const _PagePrompt({required this.front, required this.path});

  final ReviewFront front;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320, maxWidth: 400),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(MMRadii.excerpt),
          child: path == null
              ? AspectRatio(
                  key: const ValueKey('page-prompt'),
                  aspectRatio: 0.75,
                  child: ColoredBox(color: c.quaternaryFill),
                )
              : MMPdfPagePreview(
                  key: const ValueKey('page-prompt'),
                  filePath: path!,
                  page: front.page!,
                  covers: front.areas,
                  coverColor: c.secondaryLabel,
                ),
        ),
      ),
    );
  }
}

class _RatingBar extends StatelessWidget {
  const _RatingBar({required this.intervals, required this.onRate});

  final Map<Rating, Duration> intervals;
  final ValueChanged<Rating> onRate;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    String label(Rating r) => switch (r) {
      Rating.again => l.rateAgain,
      Rating.hard => l.rateHard,
      Rating.good => l.rateGood,
      Rating.easy => l.rateEasy,
    };
    // Under touch the buttons share the width and grow to thumb size.
    final touch = context.mmTouch || (MMInput.of(context).phone && MMSizeClass.of(context) == MMSizeClass.compact);
    final buttons = [
      for (final (i, r) in Rating.values.indexed) ...[
        if (i > 0) SizedBox(width: touch ? MMSpacing.s : 10),
        _RatingButton(
          key: ValueKey('rate-${r.name}'),
          label: label(r),
          interval: l.reviewInterval(intervals[r]!),
          shortcut: touch ? null : '${i + 1}',
          primary: r == Rating.good,
          touch: touch,
          onPressed: () => onRate(r),
        ),
      ],
    ];
    if (!touch) return Row(mainAxisSize: MainAxisSize.min, children: buttons);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.l),
      child: Row(children: [for (final b in buttons) b is _RatingButton ? Expanded(child: b) : b]),
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    super.key,
    required this.label,
    required this.interval,
    required this.shortcut,
    required this.primary,
    required this.onPressed,
    this.touch = false,
  });

  final String label;
  final String interval;
  final String? shortcut;
  final bool primary;
  final VoidCallback onPressed;

  /// Shares the row under touch; phones also keep this layout with a pointer.
  final bool touch;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final phone = MMInput.of(context).phone && MMSizeClass.of(context) == MMSizeClass.compact;
    return MMInteractive(
      onTap: onPressed,
      tooltip: shortcut,
      semanticLabel: '$label, $interval',
      builder: (context, s) {
        final fg = primary ? c.onAccent : c.label;
        return AnimatedContainer(
          duration: MMMotion.quick,
          width: touch ? null : 104,
          height: touch && !phone ? MMSizes.reviewRatingTouch : null,
          constraints: phone ? const BoxConstraints(minHeight: MMPhoneNavigation.ratingHeight) : null,
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: touch ? 4 : 0),
          decoration: BoxDecoration(
            color: primary ? c.accentFill : (s.hovered ? c.hover : c.fill),
            borderRadius: BorderRadius.circular(12),
            border: s.focused ? Border.all(color: c.accent, width: 2) : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (touch ? t.title3 : t.headline).copyWith(color: fg),
              ),
              const SizedBox(height: 2),
              Text(
                interval,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.footnote.copyWith(color: primary ? c.onAccent.withValues(alpha: 0.85) : null),
              ),
            ],
          ),
        );
      },
    );
  }
}
