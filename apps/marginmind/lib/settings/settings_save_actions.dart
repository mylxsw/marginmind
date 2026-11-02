import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'settings_drafts.dart';

import 'package:mm_design/mm_design.dart';

import '../shared/l10n.dart';

/// The same explicit save action for model, search and voice settings.
class SettingsSaveActions extends StatefulWidget {
  const SettingsSaveActions({
    super.key,
    required this.buttonKey,
    required this.onSave,
    this.dirty = false,
    this.trackDraft = true,
    this.saving = false,
    this.saved = false,
    this.failed = false,
    this.secondaryAction,
    this.message,
  });

  final Key buttonKey;
  final FutureOr<void> Function()? onSave;
  final bool dirty, saving, saved, failed;
  final bool trackDraft;
  final Widget? secondaryAction;

  /// Replaces the status with a problem the user must resolve (critical).
  final String? message;

  @override
  State<SettingsSaveActions> createState() => _SettingsSaveActionsState();
}

class _SettingsSaveActionsState extends State<SettingsSaveActions> {
  SettingsDrafts? _drafts;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = widget.trackDraft && MMInput.of(context).phone ? SettingsDraftScope.of(context) : null;
    if (next == _drafts) return;
    _drafts?.remove(this);
    _drafts = next;
    next?.register(
      this,
      dirty: () => widget.dirty,
      save: () async {
        await widget.onSave?.call();
        await SchedulerBinding.instance.endOfFrame;
        return !widget.dirty && !widget.failed && widget.message == null;
      },
    );
  }

  @override
  void didUpdateWidget(SettingsSaveActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dirty != widget.dirty) _drafts?.changed();
  }

  @override
  void dispose() {
    _drafts?.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buttonKey = widget.buttonKey, onSave = widget.onSave;
    final dirty = widget.dirty, saving = widget.saving, saved = widget.saved, failed = widget.failed;
    final secondaryAction = widget.secondaryAction, message = widget.message;
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
            if (secondaryAction != null) ...[secondaryAction, const SizedBox(width: MMSpacing.s)],
            save,
          ],
        );
      },
    );
  }
}
