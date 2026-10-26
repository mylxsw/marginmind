import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import '../../../shared/pdf_picker.dart';
import '../../../shared/image_picker.dart';
import '../workspace_controller.dart';

/// Shows a controller outcome as a HUD, in the current language.
void showNotice(BuildContext context, WorkspaceNotice? notice, {required String rootTitle}) {
  if (notice == null || !context.mounted) return;
  final l = context.l10n;
  final text = switch (notice) {
    ExcerptedNotice(:final targetTitle) => l.excerptedHud(targetTitle ?? rootTitle),
    HighlightedNotice() => l.highlightedHud,
    AreaFailedNotice() => l.somethingWentWrong,
    RemovedNotice() => l.removedHud,
    HighlightDeletedNotice() => l.highlightDeletedHud,
    UndoneNotice(:final redo) => redo ? l.redoneHud : l.undoneHud,
    DocumentRemovedNotice() => l.documentRemovedHud,
    ImportedNotice(:final count, :final failed) =>
      failed.isNotEmpty ? l.importFailed(failed.first) : l.importedHud(count),
  };
  MMHud.show(context, text, icon: notice is AreaFailedNotice ? MMIcons.close : MMIcons.success);
}

/// Opens the system file picker for PDFs and imports the chosen files.
Future<void> pickAndImportDocuments(BuildContext context, WidgetRef ref, String studySetId) async {
  final files = await ref.read(pdfPickerProvider)(context.l10n.pdfFiles);
  if (files.isEmpty || !context.mounted) return;
  final notice = await ref.read(workspaceProvider(studySetId).notifier).importDocuments(files);
  if (context.mounted) showNotice(context, notice, rootTitle: '');
}

Future<void> showNewMapSheet(BuildContext context, WidgetRef ref, String studySetId) async {
  final controller = ref.read(workspaceProvider(studySetId).notifier);
  final title = await showRenameSheet(context, title: context.l10n.newMap, initial: context.l10n.newMapName);
  if (title != null && context.mounted) await controller.addMap(title);
}

Future<void> showMapRenameSheet(BuildContext context, WidgetRef ref, String studySetId, String mapId) async {
  final controller = ref.read(workspaceProvider(studySetId).notifier);
  final map = controller.content.map(mapId);
  if (map == null) return;
  final title = await showRenameSheet(
    context,
    title: context.l10n.renameMap,
    initial: map.title.isEmpty ? context.l10n.mainMap : map.title,
  );
  if (title != null && context.mounted) await controller.renameMap(mapId, title);
}

/// Formats [ExportFormat] the active map can be saved as.
enum ExportFormat { markdown, opml }

/// Asks where to save, then writes the active map as Markdown or OPML.
Future<void> exportMap(BuildContext context, WidgetRef ref, String studySetId, ExportFormat format) async {
  final l = context.l10n;
  final controller = ref.read(workspaceProvider(studySetId).notifier);
  final mapTitle = controller.content.map(ref.read(workspaceProvider(studySetId)).activeMapId)?.title ?? '';
  final title = mapTitle.isEmpty ? (ref.read(studySetProvider(studySetId))?.title ?? l.appName) : mapTitle;
  final opml = format == ExportFormat.opml;
  final ext = opml ? 'opml' : 'md';
  final text = controller.export(
    opml: opml,
    rootTitle: title,
    source: (doc, page) => '${doc.title} · ${l.pageNumber(page)}',
    summary: (label) => label.isEmpty ? l.newSummaryLabel : l.exportSummary(label),
    relationsTitle: l.exportRelations,
  );
  final location = await getSaveLocation(
    suggestedName: '${title.replaceAll(RegExp(r'[/:\\]'), '-')}.$ext',
    acceptedTypeGroups: [
      XTypeGroup(label: opml ? 'OPML' : 'Markdown', extensions: [ext]),
    ],
  );
  if (location == null) return;
  try {
    await File(location.path).writeAsString(text, encoding: utf8);
    if (context.mounted) MMHud.show(context, l.exportedHud);
  } catch (_) {
    if (context.mounted) MMHud.show(context, l.somethingWentWrong, icon: MMIcons.close);
  }
}

/// Two-button confirmation sheet; resolves to true when confirmed.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final l = context.l10n;
  final ok = await showMMSheet<bool>(
    context: context,
    builder: (context) => MMSheet(
      title: title,
      actions: [
        MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop(false)),
        MMButton(
          label: confirmLabel,
          variant: MMButtonVariant.primary,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      child: Text(message, style: context.mmText.body),
    ),
  );
  return ok ?? false;
}

/// Single-field sheet used to rename topics, excerpts and notes.
Future<String?> showRenameSheet(
  BuildContext context, {
  required String title,
  required String initial,
  String? fieldLabel,
}) => showMMSheet<String>(
  context: context,
  builder: (_) => _RenameSheet(title: title, initial: initial, fieldLabel: fieldLabel),
);

class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.title, required this.initial, this.fieldLabel});

  final String title;
  final String initial;
  final String? fieldLabel;

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
        label: widget.fieldLabel ?? l.sheetName,
        child: MMTextField(controller: _controller, autofocus: true, onSubmitted: (_) => _save()),
      ),
    );
  }
}

Future<void> showCardTagsSheet(BuildContext context, WidgetRef ref, String studySetId, String cardId) async {
  final controller = ref.read(workspaceProvider(studySetId).notifier);
  final card = controller.content.card(cardId);
  if (card == null) return;
  final tags = await showMMSheet<List<String>>(
    context: context,
    builder: (_) => _CardTagsSheet(tags: card.tags),
  );
  if (tags != null && context.mounted) await controller.setTags(cardId, tags);
}

class _CardTagsSheet extends StatefulWidget {
  const _CardTagsSheet({required this.tags});
  final List<String> tags;
  @override
  State<_CardTagsSheet> createState() => _CardTagsSheetState();
}

class _CardTagsSheetState extends State<_CardTagsSheet> {
  late final _tags = [...widget.tags];
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final tag = _input.text.trim();
    if (tag.isEmpty) return;
    setState(() {
      if (!_tags.any((t) => t.toLowerCase() == tag.toLowerCase())) _tags.add(tag);
      _input.clear();
    });
  }

  void _save() {
    _add();
    Navigator.of(context).pop(_tags);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return MMSheet(
      title: l.sectionTags,
      actions: [
        MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
        MMButton(label: l.save, variant: MMButtonVariant.primary, onPressed: _save),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height / 3),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final tag in _tags)
                    Row(
                      children: [
                        Expanded(child: Text(tag, style: context.mmText.body)),
                        MMIconButton(
                          icon: MMIcons.close,
                          tooltip: l.removeTag,
                          onPressed: () => setState(() => _tags.remove(tag)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: MMTextField(
                  controller: _input,
                  placeholder: l.addTag,
                  semanticLabel: l.addTag,
                  autofocus: true,
                  onSubmitted: (_) => _add(),
                ),
              ),
              MMIconButton(icon: MMIcons.add, tooltip: l.addTag, onPressed: _add),
            ],
          ),
        ],
      ),
    );
  }
}

/// All image entry points share validation, persistence and error feedback.
Future<void> insertImageFiles(BuildContext context, WidgetRef ref, String studySetId, List<String> paths) async {
  if (paths.isEmpty) return;
  try {
    final inserted = await ref.read(workspaceProvider(studySetId).notifier).insertImages(paths: paths);
    if (inserted && context.mounted) MMHud.show(context, context.l10n.imageInserted);
  } catch (_) {
    if (context.mounted) MMHud.show(context, context.l10n.imageImportFailed, icon: MMIcons.close);
  }
}

Future<void> pickAndInsertImages(BuildContext context, WidgetRef ref, String studySetId) async {
  try {
    final paths = await ref.read(imagePickerProvider)(context.l10n.imageFiles);
    if (context.mounted) await insertImageFiles(context, ref, studySetId, paths);
  } catch (_) {
    if (context.mounted) MMHud.show(context, context.l10n.imageImportFailed, icon: MMIcons.close);
  }
}
