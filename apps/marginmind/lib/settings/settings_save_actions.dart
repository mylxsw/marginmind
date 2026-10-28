import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import '../shared/l10n.dart';

/// The same explicit save action for model, search and voice settings.
class SettingsSaveActions extends StatelessWidget {
  const SettingsSaveActions({
    super.key,
    required this.buttonKey,
    required this.onSave,
    this.dirty = false,
    this.saving = false,
    this.saved = false,
    this.failed = false,
    this.secondaryAction,
  });

  final Key buttonKey;
  final VoidCallback? onSave;
  final bool dirty, saving, saved, failed;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final status = saving
        ? l.settingsSaving
        : failed
        ? l.settingsSaveFailed
        : dirty
        ? l.settingsUnsaved
        : saved
        ? l.voiceSaved
        : '';
    return Row(
      children: [
        Expanded(
          child: Text(
            status,
            style: context.mmText.footnote.copyWith(
              color: failed ? context.mmColors.critical : context.mmColors.secondaryLabel,
            ),
          ),
        ),
        if (secondaryAction != null) ...[secondaryAction!, const SizedBox(width: MMSpacing.s)],
        MMButton(key: buttonKey, label: l.save, variant: MMButtonVariant.primary, onPressed: saving ? null : onSave),
      ],
    );
  }
}
