import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

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
  const VocabularyHintSettings({super.key, this.documentId});
  final String? documentId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hints = ref.watch(vocabularyHintProvider), l = context.l10n;
    final owner = ref.read(vocabularyHintProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.vocabularyHints, style: context.mmText.headline),
        const SizedBox(height: MMSpacing.s),
        MMSegmentedControl<VocabularyHintMode>(
          key: const ValueKey('vocabulary-hint-modes'),
          expand: true,
          value: hints.mode,
          segments: [for (final (value, label) in vocabularyHintModes(context)) MMSegment(value: value, label: label)],
          onChanged: (v) => changeVocabularyHint(context, () => owner.setMode(v)),
        ),
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
