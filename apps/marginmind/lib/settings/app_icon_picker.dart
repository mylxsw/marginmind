import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../shared/l10n.dart';
import 'app_icon.dart';
import 'app_settings.dart';

class AppIconPicker extends ConsumerStatefulWidget {
  const AppIconPicker({super.key});

  @override
  ConsumerState<AppIconPicker> createState() => _AppIconPickerState();
}

class _AppIconPickerState extends ConsumerState<AppIconPicker> {
  bool _saving = false, _failed = false;

  Future<void> _choose(AppIconPreference icon) async {
    if (_saving || icon == ref.read(settingsProvider).appIcon) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await ref.read(settingsProvider.notifier).setAppIcon(icon);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(appIconServiceProvider);
    if (!service.supported) return const SizedBox.shrink();
    final selected = ref.watch(settingsProvider.select((settings) => settings.appIcon));
    final c = context.mmColors;
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MMSettingsHeader(l.appIconTitle),
        MMSettingsGroup(
          children: [
            Padding(
              padding: const EdgeInsets.all(MMSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (index, icon) in AppIconPreference.values.indexed) ...[
                        if (index > 0) const SizedBox(width: MMSpacing.s),
                        Expanded(
                          child: MMInteractive(
                            key: ValueKey('settings-icon-${icon.name}'),
                            selected: selected == icon,
                            enabled: !_saving,
                            onTap: () => _choose(icon),
                            semanticLabel: switch (icon) {
                              AppIconPreference.paperArc => l.appIconPaperArc,
                              AppIconPreference.leafFolio => l.appIconLeafFolio,
                              AppIconPreference.foldedF => l.appIconFoldedF,
                            },
                            builder: (context, interaction) => Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                              decoration: BoxDecoration(
                                color: selected == icon
                                    ? c.accentTint
                                    : interaction.hovered
                                    ? c.hover
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(MMRadii.card),
                                border: Border.all(
                                  color: selected == icon || interaction.focused ? c.accent : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: Image.asset(icon.previewAsset, width: 64, height: 64),
                                  ),
                                  const SizedBox(height: MMSpacing.s),
                                  Text(
                                    switch (icon) {
                                      AppIconPreference.paperArc => l.appIconPaperArc,
                                      AppIconPreference.leafFolio => l.appIconLeafFolio,
                                      AppIconPreference.foldedF => l.appIconFoldedF,
                                    },
                                    textAlign: TextAlign.center,
                                    style: context.mmText.footnote.copyWith(color: c.label),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_saving || _failed) ...[
                    const SizedBox(height: MMSpacing.s),
                    Text(
                      _saving ? l.appIconChanging : l.appIconChangeFailed,
                      key: const ValueKey('settings-icon-status'),
                      style: context.mmText.footnote.copyWith(color: _failed ? c.critical : c.secondaryLabel),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
