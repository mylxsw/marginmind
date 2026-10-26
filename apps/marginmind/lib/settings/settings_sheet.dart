import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../app/navigation.dart';
import '../shared/l10n.dart';
import 'app_settings.dart';

Future<void> showSettingsSheet(BuildContext context) =>
    showMMSheet<void>(context: context, builder: (_) => const SettingsSheet(), width: 480);

/// Appearance and language. Changes apply immediately and persist.
class SettingsSheet extends ConsumerWidget {
  const SettingsSheet({super.key, this.showsGallery = kDebugMode});

  /// The component gallery is a development tool, like its menu item.
  final bool showsGallery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    return MMSheet(
      title: l.settingsTitle,
      actions: [
        if (showsGallery)
          MMButton(
            label: l.componentGallery,
            variant: MMButtonVariant.plain,
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(navigationProvider.notifier).showGallery();
            },
          ),
        const Spacer(),
        MMButton(
          label: l.done,
          variant: MMButtonVariant.primary,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: Column(
        children: [
          MMFormRow(
            label: l.appearance,
            child: MMSegmentedControl<AppearancePreference>(
              value: settings.appearance,
              onChanged: controller.setAppearance,
              segments: [
                MMSegment(value: AppearancePreference.system, label: l.appearanceSystem),
                MMSegment(value: AppearancePreference.light, label: l.appearanceLight),
                MMSegment(value: AppearancePreference.dark, label: l.appearanceDark),
              ],
            ),
          ),
          MMFormRow(
            label: l.language,
            child: MMSegmentedControl<LanguagePreference>(
              value: settings.language,
              onChanged: controller.setLanguage,
              segments: [
                MMSegment(value: LanguagePreference.system, label: l.languageSystem),
                const MMSegment(value: LanguagePreference.zh, label: '简体中文'),
                const MMSegment(value: LanguagePreference.en, label: 'English'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
