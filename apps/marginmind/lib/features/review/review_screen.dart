import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../app/app.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../shared/l10n.dart';
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
    final provider = reviewSessionProvider(widget.studySetId);
    final session = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final content = ref.watch(contentProvider(widget.studySetId)).value ?? StudySetContent.empty;
    final setTitle = ref.watch(studySetProvider(widget.studySetId))?.title ?? '';
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
        message: session.reviewed == 0 ? l.reviewNothingDueMessage : l.reviewDoneMessage(session.reviewed),
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
            child: MMProgressBar(value: done, semanticLabel: l.reviewProgress),
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
                      child: _ReviewCard(
                        key: ValueKey('${session.index}-$id'),
                        card: card,
                        content: content,
                        rootTitle: setTitle,
                        revealed: session.revealed,
                        onRevealSource: () => _revealSource(card.id),
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
                    intervals: ReviewScheduler.preview(card.id, content.reviewOf(card.id), ref.read(clockProvider)()),
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
          subtitle: session.finished || !session.started
              ? setTitle
              : '$setTitle · ${l.reviewRemaining(session.remaining)}',
          leading: MMIconButton(icon: MMIcons.chevronLeft, tooltip: l.backToStudySet, onPressed: _back),
        ),
        body: ColoredBox(color: context.mmColors.windowBackground, child: body),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    super.key,
    required this.card,
    required this.content,
    required this.rootTitle,
    required this.revealed,
    required this.onRevealSource,
  });

  final Card card;
  final StudySetContent content;
  final String rootTitle;
  final bool revealed;
  final VoidCallback onRevealSource;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final path = [rootTitle, ...content.pathOf(card.id)].where((s) => s.trim().isNotEmpty).join('  ›  ');
    final annotation = card.annotationId == null ? null : content.annotation(card.annotationId!);
    final doc = annotation == null ? null : content.document(annotation.documentId);
    final color = MMAnnotationColor.fromIndex(annotation?.colorIndex ?? 0);
    final isExcerpt = card.kind == CardKind.excerpt;
    final hasQuestion = isExcerpt && card.title.trim().isNotEmpty;

    final prompt = hasQuestion
        ? Text(card.title, style: t.title2)
        : Text(isExcerpt ? l.reviewPromptExcerpt : l.reviewPromptNote, style: t.title3);

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), boxShadow: c.cardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(path, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.footnote),
          const SizedBox(height: 12),
          prompt,
          if (isExcerpt && doc != null && !hasQuestion) ...[
            const SizedBox(height: 6),
            Text(
              '${doc.title} · ${l.pageNumber(annotation!.page)}',
              style: t.callout.copyWith(color: c.secondaryLabel),
            ),
          ],
          if (!revealed && isExcerpt && !hasQuestion) ...[
            const SizedBox(height: 16),
            Text(l.reviewQuestionTip, style: t.footnote),
          ],
          if (revealed) ...[
            const SizedBox(height: 20),
            Container(height: 0.5, color: c.separator),
            const SizedBox(height: 20),
            if (isExcerpt && annotation != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: color.cardTint,
                  borderRadius: BorderRadius.circular(MMRadii.excerpt + 2),
                  border: Border(left: BorderSide(color: color.color, width: 3)),
                ),
                child: SelectableText(annotation.quote, style: t.readingExcerpt.copyWith(fontSize: 16, height: 1.6)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // The source is already under the prompt unless the
                  // card has its own question.
                  Expanded(
                    child: doc == null || !hasQuestion
                        ? const SizedBox.shrink()
                        : Text(
                            '${doc.title} · ${l.pageNumber(annotation.page)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.footnote,
                          ),
                  ),
                  MMButton(
                    label: l.revealSource,
                    icon: MMIcons.revealSource,
                    variant: MMButtonVariant.plain,
                    onPressed: onRevealSource,
                  ),
                ],
              ),
            ] else
              SelectableText(card.title, style: t.body.copyWith(fontSize: 16, height: 1.6)),
          ],
        ],
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, r) in Rating.values.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          _RatingButton(
            label: label(r),
            interval: l.reviewInterval(intervals[r]!),
            shortcut: '${i + 1}',
            primary: r == Rating.good,
            onPressed: () => onRate(r),
          ),
        ],
      ],
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.label,
    required this.interval,
    required this.shortcut,
    required this.primary,
    required this.onPressed,
  });

  final String label;
  final String interval;
  final String shortcut;
  final bool primary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    return MMInteractive(
      onTap: onPressed,
      tooltip: shortcut,
      semanticLabel: '$label, $interval',
      builder: (context, s) {
        final fg = primary ? c.onAccent : c.label;
        return AnimatedContainer(
          duration: MMMotion.quick,
          width: 104,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: primary ? c.accentFill : (s.hovered ? c.hover : c.fill),
            borderRadius: BorderRadius.circular(12),
            border: s.focused ? Border.all(color: c.accent, width: 2) : null,
          ),
          child: Column(
            children: [
              Text(label, style: t.headline.copyWith(color: fg)),
              const SizedBox(height: 2),
              Text(interval, style: t.footnote.copyWith(color: primary ? c.onAccent.withValues(alpha: 0.85) : null)),
            ],
          ),
        );
      },
    );
  }
}
