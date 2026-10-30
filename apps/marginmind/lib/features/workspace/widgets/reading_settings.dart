import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../settings/app_settings.dart';
import '../../../shared/l10n.dart';
import '../../vocabulary/hint_controls.dart';
import '../reader_compare.dart';
import '../workspace_controller.dart';

void showReadingSettings(BuildContext context, WidgetRef ref, String setId, {Document? document}) {
  final id = ref.read(workspaceProvider(setId)).activeDocumentId;
  final doc = document ?? (id == null ? null : ref.read(workspaceProvider(setId)).content?.document(id));
  if (doc == null || (!doc.capabilities().readingSettings && !doc.capabilities().selectText)) return;
  showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: MMAppearance.duration(context, MMMotion.quick),
    transitionBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    pageBuilder: (_, _, _) => Align(
      alignment: MMSizeClass.of(context) == MMSizeClass.compact ? Alignment.bottomCenter : Alignment.topCenter,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(top: MMChromeInsets.of(context).top + MMSizes.touchTarget, bottom: MMSpacing.l),
          child: Material(
            type: MaterialType.transparency,
            child: ReadingSettingsPanel(format: doc.format, studySetId: setId, documentId: doc.id),
          ),
        ),
      ),
    ),
  );
}

class ReadingSettingsPanel extends ConsumerWidget {
  const ReadingSettingsPanel({super.key, required this.format, this.studySetId, this.documentId});
  final String? studySetId, documentId;
  final DocumentFormat format;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final settings = ref.watch(settingsProvider);
    final comparing = studySetId != null && documentId != null && ref.watch(readerCompareProvider(studySetId!)) != null;
    final comparison = comparing ? ref.read(readerCompareProvider(studySetId!).notifier) : null;
    final value = comparison?.reading(documentId!, format) ?? settings.reading(format);
    void change(ReadingSettings next) {
      if (comparison != null) {
        comparison.setReading(documentId!, next);
      } else {
        ref.read(settingsProvider.notifier).setReading(format, next);
      }
    }

    return MMGlass(
      padding: const EdgeInsets.all(MMSpacing.m),
      borderRadius: BorderRadius.circular(MMRadii.dropdown),
      child: SizedBox(
        width: MMReaderLayout.settingsWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (format != DocumentFormat.pdf) ...[
              Row(
                children: [
                  MMToolbarButton(
                    key: const ValueKey('reading-smaller'),
                    icon: MMIcons.zoomOut,
                    tooltip: l.readerFontSmaller,
                    onPressed: value.size == 0 ? null : () => change(value.copyWith(size: value.size - 1)),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < MMReaderTypography.fontSizes.length; i++)
                          Padding(
                            padding: const EdgeInsets.all(MMSpacing.xs),
                            child: Container(
                              width: MMSpacing.xs,
                              height: MMSpacing.xs,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == value.size ? context.mmColors.label : context.mmColors.separator,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  MMToolbarButton(
                    key: const ValueKey('reading-larger'),
                    icon: MMIcons.add,
                    tooltip: l.readerFontLarger,
                    onPressed: value.size == MMReaderTypography.fontSizes.length - 1
                        ? null
                        : () => change(value.copyWith(size: value.size + 1)),
                  ),
                ],
              ),
              const SizedBox(height: MMSpacing.s),
              MMSegmentedControl<int>(
                key: const ValueKey('reading-line-height'),
                expand: true,
                value: value.lineHeight,
                segments: [
                  MMSegment(
                    value: 0,
                    label: l.readerLineTight,
                    tooltip: l.readerLineTight,
                    child: const MMReaderLineSpacing(index: 0),
                  ),
                  MMSegment(
                    value: 1,
                    label: l.readerLineNormal,
                    tooltip: l.readerLineNormal,
                    child: const MMReaderLineSpacing(index: 1),
                  ),
                  MMSegment(
                    value: 2,
                    label: l.readerLineLoose,
                    tooltip: l.readerLineLoose,
                    child: const MMReaderLineSpacing(index: 2),
                  ),
                ],
                onChanged: (v) => change(value.copyWith(lineHeight: v)),
              ),
              const SizedBox(height: MMSpacing.s),
              MMSegmentedControl<ReaderFont>(
                expand: true,
                value: value.font,
                segments: [
                  if (!ReadingSettings.isArticle(format))
                    MMSegment(value: ReaderFont.original, label: l.readerFontOriginal),
                  MMSegment(
                    value: ReaderFont.serif,
                    label: l.readerFontSerif,
                    child: Text(
                      l.readerFontSerif,
                      style: context.mmText.callout.copyWith(fontFamily: MMReaderTypography.serif),
                    ),
                  ),
                  MMSegment(
                    value: ReaderFont.sans,
                    label: l.readerFontSans,
                    child: Text(
                      l.readerFontSans,
                      style: context.mmText.callout.copyWith(fontFamily: MMReaderTypography.sans),
                    ),
                  ),
                ],
                onChanged: (v) => change(value.copyWith(font: v)),
              ),
            ],
            const SizedBox(height: MMSpacing.m),
            VocabularyHintSettings(documentId: documentId),
            if (!comparing && format != DocumentFormat.pdf) ...[
              const SizedBox(height: MMSpacing.s),
              MMSegmentedControl<bool>(
                expand: true,
                value: value.paged,
                segments: [
                  MMSegment(value: true, label: l.readerModePaged),
                  MMSegment(value: false, label: l.readerModeScroll),
                ],
                onChanged: (v) => change(value.copyWith(paged: v)),
              ),
            ],
            if (MMSizeClass.of(context) != MMSizeClass.regular) ...[
              const SizedBox(height: MMSpacing.s),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final style in MMReaderStyle.values)
                    MMToolbarButton(
                      icon: MMIcons.appearance,
                      tint: style.inkColor,
                      selected: settings.readerStyle == style,
                      tooltip: switch (style) {
                        MMReaderStyle.white => l.readerStyleWhite,
                        MMReaderStyle.dark => l.readerStyleDark,
                        MMReaderStyle.paper => l.readerStylePaper,
                        MMReaderStyle.green => l.readerStyleGreen,
                      },
                      onPressed: () => ref.read(settingsProvider.notifier).setReaderStyle(style),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
