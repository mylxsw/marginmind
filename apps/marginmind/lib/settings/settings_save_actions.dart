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
    this.message,
  });

  final Key buttonKey;
  final VoidCallback? onSave;
  final bool dirty, saving, saved, failed;
  final Widget? secondaryAction;

  /// Replaces the status with a problem the user must resolve (critical).
  final String? message;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final status =
        message ??
        (saving
            ? l.settingsSaving
            : failed
            ? l.settingsSaveFailed
            : dirty
            ? l.settingsUnsaved
            : saved
            ? l.voiceSaved
            : '');
    final text = Text(
      status,
      style: context.mmText.footnote.copyWith(
        color: failed || message != null ? context.mmColors.critical : context.mmColors.secondaryLabel,
      ),
    );
    final save = MMButton(
      key: buttonKey,
      label: l.save,
      variant: MMButtonVariant.primary,
      onPressed: saving ? null : onSave,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // A narrow sheet or large text: the status above, the buttons wrapping at the right.
        if (constraints.maxWidth < 360 || MediaQuery.textScalerOf(context).scale(13) > 18) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status.isNotEmpty) ...[text, const SizedBox(height: MMSpacing.xs)],
              Wrap(
                alignment: WrapAlignment.end,
                spacing: MMSpacing.s,
                runSpacing: MMSpacing.xs,
                children: [?secondaryAction, save],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: text),
            if (secondaryAction != null) ...[secondaryAction!, const SizedBox(width: MMSpacing.s)],
            save,
          ],
        );
      },
    );
  }
}
