import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../settings/settings_window.dart';
import '../../../shared/l10n.dart';
import '../../assistant/settings/ai_task_settings.dart';
import '../full_translation.dart';

class FullTranslationStrip extends ConsumerWidget {
  const FullTranslationStrip({
    super.key,
    required this.studySetId,
    required this.documentId,
    required this.targetLang,
    this.onOpenSettings,
  });

  final String studySetId;
  final String documentId;
  final String targetLang;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mmColors;
    final l = context.l10n;
    final provider = fullTranslationProvider((studySetId, documentId, targetLang));

    final state = ref.watch(provider);
    final job = state.job;
    if (job == null) return const SizedBox.shrink();

    final controller = ref.read(provider.notifier);

    void openSettings() {
      if (onOpenSettings != null) {
        onOpenSettings!();
      } else {
        showSettings(context, tab: SettingsTab.aiTasks, focus: const AiTaskFocusTask(TaskType.documentTranslate));
      }
    }

    late final IconData icon;
    late final Color iconColor;
    late final Widget message;
    late final List<Widget> actions;
    final bool isError = job.state == TranslationJobState.error;

    switch (job.state) {
      case TranslationJobState.error:
        final isNoModel = job.errorKind == 'model' || (job.errorKind == null && job.runContext == null);
        final isStorageError = job.errorKind == 'storage';
        iconColor = c.critical;
        if (isStorageError) {
          icon = MMIcons.warning;
          message = Text(l.fullTranslationStripStorage, style: TextStyle(fontSize: 12.5, height: 1.35, color: c.label));
          actions = [
            MMButton(
              key: const Key('full_translation_strip_retry'),
              label: l.fullTranslationStripRetry,
              variant: MMButtonVariant.plain,
              color: c.accent,
              onPressed: controller.resume,
            ),
          ];
        } else if (isNoModel) {
          icon = MMIcons.warning;
          message = Text(l.fullTranslationStripNoModel, style: TextStyle(fontSize: 12.5, height: 1.35, color: c.label));
          actions = [
            MMButton(
              key: const Key('full_translation_strip_open_settings'),
              label: l.fullTranslationStripOpenSettings,
              variant: MMButtonVariant.plain,
              color: c.accent,
              onPressed: openSettings,
            ),
          ];
        } else {
          icon = MMIcons.key;
          message = Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 12.5, height: 1.35, color: c.label),
              children: [
                TextSpan(text: l.fullTranslationStripBadKey),
                const WidgetSpan(child: SizedBox(width: 6)),
                TextSpan(
                  text: l.fullTranslationStripSavedNote,
                  style: TextStyle(fontSize: 11.5, color: c.secondaryLabel),
                ),
              ],
            ),
          );
          actions = [
            MMButton(
              key: const Key('full_translation_strip_open_settings'),
              label: l.fullTranslationStripOpenSettings,
              variant: MMButtonVariant.plain,
              color: c.secondaryLabel,
              onPressed: openSettings,
            ),
            MMButton(
              key: const Key('full_translation_strip_retry'),
              label: l.fullTranslationStripRetry,
              variant: MMButtonVariant.plain,
              color: c.accent,
              onPressed: controller.resume,
            ),
          ];
        }
      case TranslationJobState.offline:
        icon = MMIcons.wifiOff;
        iconColor = c.caution;
        message = Text(l.fullTranslationStripOffline, style: TextStyle(fontSize: 12.5, height: 1.35, color: c.label));
        actions = [
          MMButton(
            key: const Key('full_translation_strip_pause'),
            label: l.fullTranslationActionPause,
            variant: MMButtonVariant.plain,
            color: c.secondaryLabel,
            onPressed: controller.pause,
          ),
        ];
      case TranslationJobState.budget:
        icon = MMIcons.warning;
        iconColor = c.caution;
        message = Text.rich(
          TextSpan(
            style: TextStyle(fontSize: 12.5, height: 1.35, color: c.label),
            children: [
              TextSpan(text: l.fullTranslationStripBudget(formatTokens(job.usage.totalTokens))),
              const WidgetSpan(child: SizedBox(width: 6)),
              TextSpan(
                text: l.fullTranslationStatEstToken(formatTokens(job.estimateTokens)),
                style: TextStyle(fontSize: 11.5, color: c.secondaryLabel),
              ),
            ],
          ),
        );
        actions = [
          MMButton(
            key: const Key('full_translation_strip_stop'),
            label: l.fullTranslationActionStop,
            variant: MMButtonVariant.plain,
            color: c.secondaryLabel,
            onPressed: controller.stop,
          ),
          MMButton(
            key: const Key('full_translation_strip_continue'),
            label: l.fullTranslationActionResume,
            variant: MMButtonVariant.plain,
            color: c.accent,
            onPressed: controller.resume,
          ),
        ];
      default:
        return const SizedBox.shrink();
    }

    final bg = isError
        ? Color.alphaBlend(
            c.critical.withValues(alpha: c.brightness == Brightness.dark ? 0.14 : 0.08),
            c.windowBackground,
          )
        : Color.alphaBlend(
            c.caution.withValues(alpha: c.brightness == Brightness.dark ? 0.14 : 0.09),
            c.windowBackground,
          );

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const ValueKey('full-translation-strip'),
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: BoxDecoration(
          color: bg,
          border: Border(bottom: BorderSide(color: c.separator, width: 0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 8),
            Expanded(child: message),
            const SizedBox(width: 8),
            ...actions,
          ],
        ),
      ),
    );
  }
}
