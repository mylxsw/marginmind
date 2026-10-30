import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../app/app_commands.dart';
import '../../shared/l10n.dart';
import 'vocabulary_hints.dart';

List<(VocabularyHintMode, String)> vocabularyHintModes(BuildContext context) => [
  (VocabularyHintMode.off, context.l10n.vocabularyHintsOff),
  (VocabularyHintMode.underline, context.l10n.vocabularyHintsUnderline),
  (VocabularyHintMode.gloss, context.l10n.vocabularyHintsGloss),
];

Future<void> changeVocabularyHint(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) MMHud.show(context, context.l10n.somethingWentWrong);
  }
}

Future<void> toggleVocabularyHints(BuildContext context, WidgetRef ref, String documentId) =>
    changeVocabularyHint(context, () async {
      final owner = ref.read(vocabularyHintProvider.notifier);
      final prefs = ref.read(vocabularyHintProvider);
      final hidden = prefs.hiddenDocuments.contains(documentId);
      if (hidden) await owner.setDocumentHidden(documentId, false);
      if (!hidden || prefs.mode == VocabularyHintMode.off) await owner.toggle();
    });

class VocabularyHintButton extends ConsumerWidget {
  const VocabularyHintButton({super.key, required this.documentId, this.compact = false});
  final String documentId;
  final bool compact;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(vocabularyHintProvider).modeFor(documentId) != VocabularyHintMode.off;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? context.mmColors.vocabularyTint : Colors.transparent,
        borderRadius: BorderRadius.circular(MMRadii.row),
      ),
      child: MMToolbarButton(
        key: const ValueKey('vocabulary-hint-toggle'),
        icon: MMIcons.vocabulary,
        compact: compact,
        tint: active ? context.mmColors.vocabulary : null,
        tooltip: AppShortcuts.tip(context.l10n.vocabularyHints, AppShortcuts.vocabularyHints),
        onPressed: () => toggleVocabularyHints(context, ref, documentId),
      ),
    );
  }
}

class VocabularyHintSettings extends ConsumerWidget {
  const VocabularyHintSettings({super.key, this.documentId, this.showPreview = false});
  final String? documentId;
  final bool showPreview;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hints = ref.watch(vocabularyHintProvider), l = context.l10n;
    final owner = ref.read(vocabularyHintProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showPreview) ...[
          MMSettingsGroup(
            children: [
              MMSettingsRow(
                label: l.vocabularyHints,
                trailing: MMPopUpButton<VocabularyHintMode>(
                  key: const ValueKey('settings-vocabulary-hints'),
                  value: hints.mode,
                  items: vocabularyHintModes(context),
                  semanticLabel: l.vocabularyHints,
                  onChanged: (v) => changeVocabularyHint(context, () => owner.setMode(v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: MMSpacing.m),
          VocabularyHintPreview(mode: hints.mode),
        ] else ...[
          Text(l.vocabularyHints, style: context.mmText.headline),
          const SizedBox(height: MMSpacing.s),
          MMSegmentedControl<VocabularyHintMode>(
            key: const ValueKey('vocabulary-hint-modes'),
            expand: true,
            value: hints.mode,
            segments: [
              for (final (value, label) in vocabularyHintModes(context)) MMSegment(value: value, label: label),
            ],
            onChanged: (v) => changeVocabularyHint(context, () => owner.setMode(v)),
          ),
        ],
        if (documentId != null) ...[
          MMSettingsRow(
            leading: Text(l.vocabularyHintsHidden, style: context.mmText.body, maxLines: 2),
            trailing: Switch(
              key: const ValueKey('vocabulary-hint-hidden'),
              value: hints.hiddenDocuments.contains(documentId),
              onChanged: (v) => changeVocabularyHint(context, () => owner.setDocumentHidden(documentId!, v)),
            ),
          ),
          MMSettingsRow(
            leading: Text(l.vocabularyHintsKnown, style: context.mmText.body, maxLines: 2),
            trailing: Switch(
              key: const ValueKey('vocabulary-hint-known'),
              value: hints.showKnown,
              onChanged: (v) => changeVocabularyHint(context, () => owner.setShowKnown(v)),
            ),
          ),
        ],
      ],
    );
  }
}

/// A read-only example; uses the same dotted stroke as actual reader hints.
class VocabularyHintPreview extends StatelessWidget {
  const VocabularyHintPreview({super.key, required this.mode});

  final VocabularyHintMode mode;
  static const sentence = 'Stay curious, keep learning.';

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors, l = context.l10n;
    final scaler = MediaQuery.textScalerOf(context);
    final style = context.mmText.body.copyWith(fontFamily: MMReaderTypography.serif, fontSize: 16.5, height: 1.5);
    final glossStyle = context.mmText.footnote.copyWith(color: c.vocabulary);
    final painter = _VocabularyExamplePainter(
      mode: mode,
      style: style,
      glossStyle: glossStyle,
      scaler: scaler,
      color: c.vocabulary,
      gloss: l.vocabularyHintsPreviewMeaning,
    );
    final example = LayoutBuilder(
      builder: (context, constraints) {
        final text = painter.layout(constraints.maxWidth);
        final height = text.height + painter.topInset + 4;
        text.dispose();
        return Semantics(
          key: const ValueKey('vocabulary-hint-preview'),
          label: '${l.vocabularyHintsPreview}: $sentence',
          value: switch (mode) {
            VocabularyHintMode.off => l.vocabularyHintsOff,
            VocabularyHintMode.underline => l.vocabularyHintsUnderline,
            VocabularyHintMode.gloss => '${l.vocabularyHintsGloss}: ${l.vocabularyHintsPreviewMeaning}',
          },
          child: CustomPaint(size: Size(constraints.maxWidth, height), painter: painter),
        );
      },
    );
    final label = Text(l.vocabularyHintsPreview, style: context.mmText.callout.copyWith(color: c.secondaryLabel));
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360 || scaler.scale(1) > 1.3) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [label, example]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: painter.topInset + 4),
              child: label,
            ),
            const SizedBox(width: MMSpacing.xl),
            Expanded(child: example),
          ],
        );
      },
    );
  }
}

class _VocabularyExamplePainter extends CustomPainter {
  const _VocabularyExamplePainter({
    required this.mode,
    required this.style,
    required this.glossStyle,
    required this.scaler,
    required this.color,
    required this.gloss,
  });

  final VocabularyHintMode mode;
  final TextStyle style, glossStyle;
  final TextScaler scaler;
  final Color color;
  final String gloss;

  double get topInset => scaler.scale(glossStyle.fontSize!) * 1.5 + 4;

  TextPainter layout(double width) => TextPainter(
    text: TextSpan(text: VocabularyHintPreview.sentence, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout(maxWidth: width);

  @override
  void paint(Canvas canvas, Size size) {
    final text = layout(size.width);
    text.paint(canvas, Offset(0, topInset));
    if (mode != VocabularyHintMode.off) {
      final boxes = text.getBoxesForSelection(const TextSelection(baseOffset: 5, extentOffset: 12));
      for (final box in boxes) {
        final rect = box.toRect().shift(Offset(0, topInset));
        canvas.save();
        canvas.translate(rect.left, rect.bottom);
        MMPdfAnnotationLinePainter(color: color, style: AnnotationLineStyle.dotted).paint(canvas, Size(rect.width, 3));
        canvas.restore();
      }
      if (mode == VocabularyHintMode.gloss && boxes.isNotEmpty) {
        final meaning = TextPainter(
          text: TextSpan(text: gloss, style: glossStyle),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout(maxWidth: size.width);
        meaning.paint(canvas, Offset(boxes.first.left, 0));
        meaning.dispose();
      }
    }
    text.dispose();
  }

  @override
  bool shouldRepaint(_VocabularyExamplePainter old) =>
      old.mode != mode ||
      old.style != style ||
      old.glossStyle != glossStyle ||
      old.scaler != scaler ||
      old.color != color ||
      old.gloss != gloss;
}
