import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../workspace_controller.dart';

/// Shows a controller outcome as a HUD, in the current language.
void showNotice(BuildContext context, WorkspaceNotice? notice, {required String rootTitle}) {
  if (notice == null || !context.mounted) return;
  final l = context.l10n;
  final text = switch (notice) {
    ExcerptedNotice(:final targetTitle) => l.excerptedHud(targetTitle ?? rootTitle),
    HighlightedNotice() => l.highlightedHud,
    RemovedNotice() => l.removedHud,
    HighlightDeletedNotice() => l.highlightDeletedHud,
    ImportedNotice(:final count, :final failed) =>
      failed.isNotEmpty ? l.importFailed(failed.first) : l.importedHud(count),
  };
  MMHud.show(context, text);
}

/// Opens the system file picker for PDFs and imports the chosen files.
Future<void> pickAndImportDocuments(BuildContext context, WidgetRef ref, String studySetId) async {
  final l = context.l10n;
  final files = await openFiles(
    acceptedTypeGroups: [
      XTypeGroup(label: l.pdfFiles, extensions: const ['pdf'], uniformTypeIdentifiers: const ['com.adobe.pdf']),
    ],
  );
  if (files.isEmpty || !context.mounted) return;
  final notice = await ref.read(workspaceProvider(studySetId).notifier).importDocuments([
    for (final f in files) (path: f.path, name: f.name),
  ]);
  if (context.mounted) showNotice(context, notice, rootTitle: '');
}

/// Single-field sheet used to rename topics, excerpts and notes.
Future<String?> showRenameSheet(BuildContext context, {required String title, required String initial}) =>
    showMMSheet<String>(
      context: context,
      builder: (_) => _RenameSheet(title: title, initial: initial),
    );

class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  // Owned by the sheet so it outlives the closing animation.
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return MMSheet(
      title: widget.title,
      actions: [
        MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
        MMButton(label: l.save, variant: MMButtonVariant.primary, onPressed: _save),
      ],
      child: MMFormRow(
        label: l.sheetName,
        child: MMTextField(controller: _controller, autofocus: true, onSubmitted: (_) => _save()),
      ),
    );
  }
}
