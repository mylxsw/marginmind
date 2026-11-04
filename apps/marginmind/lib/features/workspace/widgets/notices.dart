import '../document_import.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_core/mm_core.dart';

import '../../../app/providers.dart';
import '../../../shared/content_input.dart';

import '../../../shared/l10n.dart';
import '../../../shared/phone_form.dart';
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
    UndoneNotice(conflict: true) => l.undoContentChanged,
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
  final title = await showRenameSheet(
    context,
    title: context.l10n.newMap,
    initial: context.l10n.newMapName,
    actionLabel: context.l10n.create,
  );
  if (title != null && context.mounted) await controller.addMap(title);
}

Future<void> showMapRenameSheet(BuildContext context, WidgetRef ref, String studySetId, String mapId) async {
  final controller = ref.read(workspaceProvider(studySetId).notifier);
  final map = controller.content.map(mapId);
  if (map == null) return;
  final defaultTitle = context.l10n.mainMap;
  await showContentRenameSheet(
    context,
    ref,
    studySetId,
    title: context.l10n.renameMap,
    paths: [
      ['maps', mapId],
    ],
    read: (c) {
      final map = c.map(mapId);
      return map == null
          ? null
          : map.title.isEmpty
          ? defaultTitle
          : map.title;
    },
    save: (value) => controller.renameMap(mapId, value),
  );
}

/// Content-backed forms hold their observed entity until save or dismissal.
/// Save happens inside the sheet so failures retain the text and protection.
Future<void> showContentRenameSheet(
  BuildContext context,
  WidgetRef ref,
  String studySetId, {
  required String title,
  required List<List<String>> paths,
  required String? Function(StudySetContent) read,
  required Future<void> Function(String) save,
}) async {
  ContentInputSession<String>? input;
  try {
    input = await ContentInput(
      repository: ref.read(contentRepositoryProvider),
      studySetId: studySetId,
      paths: paths,
      read: read,
    ).open();
    if (!context.mounted) return;
    final session = input;
    await showMMSheet<String>(
      context: context,
      builder: (_) =>
          _RenameSheet(title: title, initial: session.value, save: (value) => session.save(() => save(value))),
    );
  } catch (_) {
    if (context.mounted) MMHud.show(context, context.l10n.somethingWentWrong);
  } finally {
    await input?.close();
  }
}

/// Metadata uses an observed repository revision, not a content edit path.
Future<void> showStudySetRenameSheet(BuildContext context, WidgetRef ref, StudySet set) async {
  final repository = ref.read(studySetRepositoryProvider);
  try {
    final observed = repository is StudySetTitleRepository
        ? await (repository as StudySetTitleRepository).titleForEditing(set.id)
        : StudySetTitle(set.title, '');
    if (!context.mounted) return;
    await showMMSheet<String>(
      context: context,
      builder: (_) => _RenameSheet(
        title: context.l10n.renameStudySet,
        initial: observed.title,
        save: (value) async {
          if (value.isEmpty) throw ArgumentError('Empty title');
          if (repository is StudySetTitleRepository) {
            await (repository as StudySetTitleRepository).renameObserved(
              set.id,
              value,
              expectedRevision: observed.revision,
            );
          } else {
            await repository.rename(set.id, value);
          }
        },
      ),
    );
  } catch (_) {
    if (context.mounted) MMHud.show(context, context.l10n.somethingWentWrong);
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
  if (usesNativePhonePresentation(context)) {
    return await MMNativePresentation.confirm(
          dark: Theme.of(context).brightness == Brightness.dark,
          title: title,
          message: message,
          cancel: l.cancel,
          actions: [MMNativeAction('confirm', confirmLabel, destructive: true)],
        ) ==
        'confirm';
  }
  final ok = await showMMSheet<bool>(
    context: context,
    // A question fits its content; half a screen of blank sheet says nothing.
    expand: false,
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
  String? actionLabel,
}) async {
  if (usesNativePhonePresentation(context)) {
    final values = await showPhoneForm(
      context,
      title: title,
      submit: actionLabel ?? context.l10n.save,
      fields: [MMNativeField(id: 'title', label: fieldLabel ?? context.l10n.sheetName, value: initial)],
    );
    return values?['title']?.trim();
  }
  return showMMSheet<String>(
    context: context,
    builder: (_) => _RenameSheet(title: title, initial: initial, fieldLabel: fieldLabel, actionLabel: actionLabel),
  );
}

class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.title, required this.initial, this.fieldLabel, this.actionLabel, this.save});

  final String title;
  final String initial;
  final String? fieldLabel;
  final String? actionLabel;
  final Future<void> Function(String)? save;

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

  bool _saving = false;
  Object? _error;
  Future<void> _save() async {
    if (_saving) return;
    final value = _controller.text.trim();
    if (widget.save == null) {
      Navigator.of(context).pop(value);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save!(value);
      if (mounted) Navigator.of(context).pop(value);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return MMSheet(
      title: widget.title.replaceFirst(RegExp(r'(…|\.{3})$'), ''),
      actions: [
        MMButton(label: l.cancel, onPressed: _saving ? null : () => Navigator.of(context).pop()),
        MMButton(
          label: widget.actionLabel ?? l.save,
          variant: MMButtonVariant.primary,
          onPressed: _saving ? null : _save,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Text(
              _error is ContentSyncActionException &&
                      (_error as ContentSyncActionException).reason == ContentSyncActionFailure.stale
                  ? l.syncRenameStale
                  : l.somethingWentWrong,
            ),
          MMFormRow(
            label: widget.fieldLabel ?? l.sheetName,
            child: MMTextField(
              enabled: !_saving,
              controller: _controller,
              semanticLabel: widget.fieldLabel ?? l.sheetName,
              autofocus: true,
              onSubmitted: (_) => _save(),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showCardTagsSheet(BuildContext context, WidgetRef ref, String studySetId, String cardId) async {
  final controller = ref.read(workspaceProvider(studySetId).notifier);
  final card = controller.content.card(cardId);
  if (card == null) return;
  ContentInputSession<List<String>>? input;
  try {
    input = await ContentInput(
      repository: ref.read(contentRepositoryProvider),
      studySetId: studySetId,
      paths: [
        ['cards', cardId],
      ],
      read: (c) => c.card(cardId)?.tags,
    ).open();
    if (!context.mounted) return;
    final session = input;
    await showMMSheet<void>(
      context: context,
      builder: (_) =>
          _CardTagsSheet(tags: session.value, save: (tags) => session.save(() => controller.setTags(cardId, tags))),
    );
  } catch (_) {
    if (context.mounted) MMHud.show(context, context.l10n.somethingWentWrong);
  } finally {
    await input?.close();
  }
}

class _CardTagsSheet extends StatefulWidget {
  const _CardTagsSheet({required this.tags, required this.save});
  final Future<void> Function(List<String>) save;
  final List<String> tags;
  @override
  State<_CardTagsSheet> createState() => _CardTagsSheetState();
}

class _CardTagsSheetState extends State<_CardTagsSheet> {
  late final _tags = [...widget.tags];
  final _input = TextEditingController();
  bool _saving = false, _failed = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    if (_saving) return;
    final tag = _input.text.trim();
    if (tag.isEmpty) return;
    setState(() {
      if (!_tags.any((t) => t.toLowerCase() == tag.toLowerCase())) _tags.add(tag);
      _input.clear();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    _add();
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.save(List.of(_tags));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return MMSheet(
      title: l.sectionTags,
      actions: [
        MMButton(label: l.cancel, onPressed: _saving ? null : () => Navigator.of(context).pop()),
        MMButton(label: l.save, variant: MMButtonVariant.primary, onPressed: _saving ? null : _save),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_failed) Text(l.somethingWentWrong),
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
                          onPressed: _saving ? null : () => setState(() => _tags.remove(tag)),
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
                  enabled: !_saving,
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
