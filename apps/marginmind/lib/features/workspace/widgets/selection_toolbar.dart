import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../app/app_commands.dart';
import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'notices.dart';

/// Selection actions live in one place so pointer, menu and keyboard agree.
class SelectionToolbar extends ConsumerStatefulWidget {
  const SelectionToolbar({
    super.key,
    required this.studySetId,
    required this.pending,
    required this.pdf,
    required this.rootTitle,
  });

  final String studySetId;
  final PendingSelection pending;
  final MMPdfViewController pdf;
  final String rootTitle;

  @override
  ConsumerState<SelectionToolbar> createState() => _SelectionToolbarState();
}

class _SelectionToolbarState extends ConsumerState<SelectionToolbar> {
  final _focus = FocusNode();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _dismiss() {
    ref.read(workspaceProvider(widget.studySetId).notifier).dismissPending();
    widget.pdf.clearSelection();
  }

  Future<void> _run(ReaderSelectionCommand command, [MMAnnotationColor? color]) async {
    if (_busy) return;
    _busy = true;
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final selectedColor = color ?? ref.read(workspaceProvider(widget.studySetId)).color;
    final pending = widget.pending;
    final pdf = widget.pdf;
    final rootTitle = widget.rootTitle;
    // Capture the target before opening a sheet or clearing the selection.
    try {
      String? note;
      if (command == ReaderSelectionCommand.note) {
        // The toolbar must stay mounted while its sheet is open, but cannot
        // dispatch shortcuts through the sheet's text field.
        note = await showRenameSheet(
          context,
          title: context.l10n.addNote,
          initial: '',
          fieldLabel: context.l10n.noteText,
        );
        if (!mounted || note == null || note.isEmpty) return;
      }
      if (command == ReaderSelectionCommand.copy) {
        await Clipboard.setData(ClipboardData(text: pending.selection.text));
        if (!mounted) return;
        MMHud.show(context, context.l10n.copiedHud);
        controller.dismissPending();
      } else {
        final notice = command == ReaderSelectionCommand.highlight
            ? await controller.highlight(pending.documentId, pending.selection, selectedColor)
            : await controller.excerpt(pending.documentId, pending.selection, selectedColor, note: note);
        if (mounted) showNotice(context, notice, rootTitle: rootTitle);
      }
      await pdf.clearSelection();
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong, icon: MMIcons.close);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return TapRegion(
      onTapOutside: (_) {
        if (!_busy) _dismiss();
      },
      child: Actions(
        actions: {
          ReaderSelectionIntent: CallbackAction<ReaderSelectionIntent>(
            onInvoke: (intent) {
              _run(intent.command);
              return null;
            },
          ),
        },
        child: Shortcuts(
          shortcuts: readerSelectionShortcuts,
          child: CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.escape): _dismiss},
            child: Focus(
              focusNode: _focus,
              child: MMFloatingToolbar(
                children: [
                  for (final color in MMAnnotationColor.values)
                    MMFloatingToolbarColor(
                      color: color,
                      tooltip: l.excerptInColor(l.colorName(color)),
                      onPressed: () => _run(ReaderSelectionCommand.excerpt, color),
                    ),
                  const MMToolbarDivider(),
                  MMToolbarButton(
                    icon: MMIcons.highlight,
                    tooltip: l.highlightAction,
                    onPressed: () => _run(ReaderSelectionCommand.highlight),
                  ),
                  MMToolbarButton(
                    icon: MMIcons.copy,
                    tooltip: l.copyAction,
                    onPressed: () => _run(ReaderSelectionCommand.copy),
                  ),
                  MMToolbarButton(
                    icon: MMIcons.addNote,
                    tooltip: l.addNote,
                    onPressed: () => _run(ReaderSelectionCommand.note),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
