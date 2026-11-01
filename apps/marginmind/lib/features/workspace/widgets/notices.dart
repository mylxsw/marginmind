import '../document_import.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../../../shared/pdf_picker.dart';
import '../../../shared/image_picker.dart';
import '../workspace_controller.dart';

/// Offers a way to a new excerpt's card while the map is out of view (a
/// compact window showing the source): the HUD after excerpting gets a
/// View action instead of switching panes on its own.
class ExcerptViewScope extends InheritedWidget {
  const ExcerptViewScope({super.key, required this.showInMap, required super.child});

  /// Null while the map is in view.
  final ValueChanged<String>? showInMap;

  static ValueChanged<String>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ExcerptViewScope>()?.showInMap;

  @override
  bool updateShouldNotify(ExcerptViewScope oldWidget) => (oldWidget.showInMap == null) != (showInMap == null);
}

/// Shows a controller outcome as a HUD, in the current language.
void showNotice(BuildContext context, WorkspaceNotice? notice, {required String rootTitle}) {
  if (notice == null || !context.mounted) return;
  final l = context.l10n;
  if (notice is ImportedNotice && notice.count == 0 && notice.failed.isEmpty) return;
  if (notice is ImportedNotice && notice.errors.isNotEmpty) {
    String reason(DocumentImportError error) => switch (error) {
      DocumentImportError.drm => l.importErrorDrm,
      DocumentImportError.damaged => l.importErrorDamaged,
      DocumentImportError.unsupported => l.importErrorUnsupported,
      DocumentImportError.kfx => l.importErrorKfx,
      DocumentImportError.empty => l.importErrorEmpty,
      DocumentImportError.limitExceeded => l.importErrorLimit,
      DocumentImportError.unavailable => l.somethingWentWrong,
    };
    showMMDialog<void>(
      context: context,
      builder: (dialogContext) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: MMSheet(
          key: const ValueKey('import-failed-sheet'),
          title: notice.failed.length == 1
              ? l.importFailedTitle(notice.failed.first)
              : l.importFailedMany(notice.failed.length),
          actions: [
            MMButton(
              label: l.okAction,
              variant: MMButtonVariant.primary,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                key: const ValueKey('import-failed-badge'),
                width: MMSizes.noticeBadge,
                height: MMSizes.noticeBadge,
                decoration: BoxDecoration(
                  color: dialogContext.mmColors.critical.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(MMRadii.row),
                ),
                child: Icon(
                  notice.failed.length == 1 && notice.errors[notice.failed.first] == DocumentImportError.drm
                      ? MMIcons.shield
                      : MMIcons.warning,
                  color: dialogContext.mmColors.critical,
                ),
              ),
              const SizedBox(width: MMSpacing.m),
              Expanded(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(dialogContext).height * MMSizes.bottomSheetMedium,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final name in notice.failed)
                          Text(
                            notice.failed.length == 1
                                ? reason(notice.errors[name]!)
                                : '$name — ${reason(notice.errors[name]!)}',
                            style: notice.failed.length == 1
                                ? dialogContext.mmText.body
                                : dialogContext.mmText.callout.copyWith(color: dialogContext.mmColors.secondaryLabel),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (notice.count > 0) MMHud.show(context, l.importedHud(notice.count), icon: MMIcons.success);
    return;
  }
  final text = switch (notice) {
    ExcerptedNotice(:final targetTitle) => l.excerptedHud(targetTitle ?? rootTitle),
    HighlightedNotice() => l.highlightedHud,
    UnderlinedNotice() => l.underlinedHud,
    AreaFailedNotice() => l.somethingWentWrong,
    RemovedNotice() => l.removedHud,
    HighlightDeletedNotice(:final underline) => underline ? l.underlineDeletedHud : l.highlightDeletedHud,
    UndoneNotice(:final redo) => redo ? l.redoneHud : l.undoneHud,
    DocumentRemovedNotice() => l.documentRemovedHud,
    ResearchNoteSavedNotice(:final cardId, :final inSource) =>
      cardId != null && inSource
          ? l.researchSavedBoth
          : cardId != null
          ? l.researchSavedMap
          : l.researchSavedSource,
    ImportedNotice(:final count, :final failed) =>
      failed.isNotEmpty ? l.importFailed(failed.first) : l.importedHud(count),
  };
  final cardId = notice is ExcerptedNotice ? notice.cardId : null;
  final showInMap = cardId == null ? null : ExcerptViewScope.of(context);
  MMHud.show(
    context,
    text,
    icon: notice is AreaFailedNotice ? MMIcons.close : MMIcons.success,
    action: showInMap == null ? null : (l.excerptView, () => showInMap(cardId!)),
  );
}

/// Opens the system file picker for documents and imports the chosen files.
Future<void> pickAndImportDocuments(BuildContext context, WidgetRef ref, String studySetId) async {
  final files = await ref.read(pdfPickerProvider)(context.l10n.documentFiles);
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
