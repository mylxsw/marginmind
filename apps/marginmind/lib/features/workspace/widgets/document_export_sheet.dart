import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/foundation.dart' show Uint8List, visibleForTesting;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import '../document_export.dart';
import '../workspace_controller.dart';

enum _PageRange { all, marked, custom }

Future<void> showDocumentExportSheet(BuildContext context, String studySetId, String documentId) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final content = container.read(workspaceProvider(studySetId).notifier).content;
  final document = content.documents.where((d) => d.id == documentId).firstOrNull;
  final repository = container.read(contentRepositoryProvider);
  if (document == null || repository is! DocumentRepository) return;
  final l = context.l10n;
  await showMMSheet<void>(
    context: context,
    width: MMSizes.documentExportSheetWidth,
    builder: (_) => DocumentExportSheet(
      content: content,
      document: document,
      exporter: DocumentExporter(
        repository: repository as DocumentRepository,
        studySetId: studySetId,
        content: content,
        document: document,
        labels: DocumentExportLabels(
          markedSuffix: l.documentExportMarkedSuffix,
          cleanSuffix: l.documentExportCleanSuffix,
          notesHeading: l.marginNotes,
        ),
      ),
    ),
  );
}

/// One decision for most people: tap what the copy should keep and it is saved.
/// "More options" swaps those choices for the individual switches.
class DocumentExportSheet extends StatefulWidget {
  const DocumentExportSheet({
    super.key,
    required this.content,
    required this.document,
    required this.exporter,
    this.save,
  });

  final StudySetContent content;
  final Document document;
  final DocumentExporter exporter;

  /// Test seam for the system save panel or share sheet.
  final Future<bool> Function(String name, Uint8List bytes)? save;

  /// The same seam for sheets opened through the app's real entry points.
  @visibleForTesting
  static Future<bool> Function(String name, Uint8List bytes)? debugSave;

  @override
  State<DocumentExportSheet> createState() => _DocumentExportSheetState();
}

class _DocumentExportSheetState extends State<DocumentExportSheet> {
  late final DocumentExportInventory _inventory = DocumentExportPlan.inventory(widget.content, widget.document);
  late var _canWriteMarks =
      widget.document.exportsMarks && (!widget.document.exportsAsPdf || MMPdfExport.canWriteMarks);
  var _options = const DocumentExportOptions();
  var _expanded = false;
  var _range = _PageRange.all;
  final _pagesController = TextEditingController();
  final _pagesErrorKey = GlobalKey();
  DocumentExportPreset? _running;
  var _runningOptions = false;
  var _failed = false;
  var _cancelled = false;

  bool get _busy => _running != null || _runningOptions;
  bool get _hasMarks => _canWriteMarks && !_inventory.isEmpty;
  bool get _isPdf => widget.document.exportsAsPdf;

  @override
  void initState() {
    super.initState();
    if (_isPdf && _canWriteMarks) _checkPermissions();
  }

  @override
  void dispose() {
    _pagesController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    final bool allowed;
    try {
      allowed = await widget.exporter.canWriteMarks();
    } catch (_) {
      // Unreadable here means unwritable there; a clean copy needs no parsing.
      if (mounted) setState(() => _canWriteMarks = false);
      return;
    }
    if (mounted && !allowed) setState(() => _canWriteMarks = false);
  }

  /// A page selection, or null when the typed range is not valid.
  Set<int>? get _pages => parseDocumentPageRanges(_pagesController.text, widget.document.pageCount);

  bool get _customRangeInvalid => _range == _PageRange.custom && _pages == null;

  DocumentExportOptions get _advancedOptions => _options.copyWith(
    pages: () => switch (_range) {
      _PageRange.all => null,
      _PageRange.marked => DocumentExportPlan.markedPages(widget.content, widget.document, _options),
      _PageRange.custom => _pages,
    },
  );

  Future<void> _export(DocumentExportOptions options, {DocumentExportPreset? preset}) async {
    final l = context.l10n;
    setState(() {
      _running = preset;
      _runningOptions = preset == null;
      _failed = false;
      _cancelled = false;
    });
    try {
      final file = await widget.exporter.write(options, cancelled: () => _cancelled);
      if (!mounted || _cancelled) return;
      final save = widget.save ?? DocumentExportSheet.debugSave ?? MMNoteFiles.save;
      final saved = await save(file.name, file.bytes);
      if (!mounted || !saved) return;
      final navigator = Navigator.of(context);
      MMHud.show(context, l.exportedHud);
      navigator.pop();
    } on MMPdfExportCancelled {
      // The user already moved on; there is nothing to report.
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) {
        setState(() {
          _running = null;
          _runningOptions = false;
        });
      }
    }
  }

  String _counts(AppLocalizations l) => [
    if (_inventory.highlights > 0) l.documentExportHighlights(_inventory.highlights),
    if (_inventory.underlines > 0) l.documentExportUnderlines(_inventory.underlines),
    if (_inventory.notes > 0) l.documentExportNotes(_inventory.notes),
    if (_inventory.ink > 0) l.documentExportInk(_inventory.ink),
  ].join(l.documentExportListSeparator);

  /// Named only when the copy cannot keep the source's own file type.
  String _withFormat(AppLocalizations l, String text) {
    final extension = widget.document.markedExportExtension;
    final source = widget.document.cleanExportExtension;
    if (extension == source) return text;
    return l.documentExportAsFormat(text, extension.toUpperCase());
  }

  Widget _choices(AppLocalizations l) => MMSettingsGroup(
    children: [
      if (_hasMarks)
        _ChoiceRow(
          key: const ValueKey('document-export-everything'),
          icon: MMIcons.highlight,
          title: l.documentExportEverything,
          subtitle: _withFormat(l, _counts(l)),
          running: _running == DocumentExportPreset.everything,
          autofocus: true,
          onTap: _busy
              ? null
              : () => _export(
                  DocumentExportOptions.preset(DocumentExportPreset.everything),
                  preset: DocumentExportPreset.everything,
                ),
        ),
      if (_hasMarks && _inventory.marks > 0 && _inventory.notes + _inventory.ink > 0)
        _ChoiceRow(
          key: const ValueKey('document-export-marks'),
          icon: MMIcons.underline,
          title: l.documentExportMarksOnly,
          subtitle: _withFormat(
            l,
            _inventory.ink > 0 && _inventory.notes > 0
                ? l.documentExportWithoutNotesAndInk
                : _inventory.ink > 0
                ? l.documentExportWithoutInk
                : l.documentExportWithoutNotes,
          ),
          running: _running == DocumentExportPreset.marksOnly,
          onTap: _busy
              ? null
              : () => _export(
                  DocumentExportOptions.preset(DocumentExportPreset.marksOnly),
                  preset: DocumentExportPreset.marksOnly,
                ),
        ),
      _ChoiceRow(
        key: const ValueKey('document-export-clean'),
        icon: MMIcons.layoutReader,
        title: _hasMarks ? l.documentExportClean : l.documentExportCopy,
        subtitle: widget.document.originalExportFile != null
            ? l.documentExportCleanDetail
            : _withFormat(l, l.documentExportCleanCaptureDetail),
        running: _running == DocumentExportPreset.clean,
        autofocus: !_hasMarks,
        onTap: _busy
            ? null
            : () =>
                  _export(DocumentExportOptions.preset(DocumentExportPreset.clean), preset: DocumentExportPreset.clean),
      ),
    ],
  );

  Widget _switchRow(String label, int count, bool value, ValueChanged<bool> onChanged, {Key? key}) => MMSettingsRow(
    key: key,
    label: label,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$count', style: context.mmText.body.copyWith(color: context.mmColors.secondaryLabel)),
        const SizedBox(width: MMSpacing.s),
        MMSwitch(value: value, onChanged: _busy ? null : onChanged, semanticLabel: label),
      ],
    ),
  );

  Widget _optionsForm(AppLocalizations l) {
    final colors = _inventory.highlightColors.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_hasMarks)
          MMSettingsGroup(
            children: [
              if (_inventory.highlights > 0) ...[
                _switchRow(
                  l.documentExportHighlightsOption,
                  _inventory.highlights,
                  _options.highlights,
                  (v) => setState(() => _options = _options.copyWith(highlights: v)),
                  key: const ValueKey('document-export-option-highlights'),
                ),
                if (_options.highlights && colors.length > 1)
                  _ColorFilter(
                    colors: colors,
                    counts: _inventory.highlightColors,
                    hidden: _options.hiddenColors,
                    onChanged: _busy
                        ? null
                        : (hidden) => setState(() {
                            // Turning off the last color means no highlights, not a stuck filter.
                            _options = hidden.length == colors.length
                                ? _options.copyWith(highlights: false, hiddenColors: const {})
                                : _options.copyWith(hiddenColors: hidden);
                          }),
                  ),
              ],
              if (_inventory.underlines > 0)
                _switchRow(
                  l.documentExportUnderlinesOption,
                  _inventory.underlines,
                  _options.underlines,
                  (v) => setState(() => _options = _options.copyWith(underlines: v)),
                  key: const ValueKey('document-export-option-underlines'),
                ),
              if (_inventory.notes > 0)
                _switchRow(
                  l.documentExportNotesOption,
                  _inventory.notes,
                  _options.notes,
                  (v) => setState(() => _options = _options.copyWith(notes: v)),
                  key: const ValueKey('document-export-option-notes'),
                ),
              if (_inventory.ink > 0)
                _switchRow(
                  l.documentExportInkOption,
                  _inventory.ink,
                  _options.ink,
                  (v) => setState(() => _options = _options.copyWith(ink: v)),
                  key: const ValueKey('document-export-option-ink'),
                ),
            ],
          ),
        if (_isPdf && _canWriteMarks) ...[
          if (_hasMarks) const SizedBox(height: MMSpacing.m),
          Text(l.documentExportPages, style: context.mmText.footnote.copyWith(color: context.mmColors.secondaryLabel)),
          const SizedBox(height: MMSpacing.xs),
          MMSegmentedControl<_PageRange>(
            expand: true,
            segments: [
              MMSegment(value: _PageRange.all, label: l.documentExportPagesAll),
              if (_hasMarks) MMSegment(value: _PageRange.marked, label: l.documentExportPagesMarked),
              MMSegment(value: _PageRange.custom, label: l.documentExportPagesCustom),
            ],
            value: _range,
            onChanged: _busy ? null : (v) => setState(() => _range = v),
          ),
          if (_range == _PageRange.custom) ...[
            const SizedBox(height: MMSpacing.s),
            MMTextField(
              key: const ValueKey('document-export-pages'),
              controller: _pagesController,
              autofocus: true,
              placeholder: l.documentExportPagesHint(widget.document.pageCount),
              semanticLabel: l.documentExportPagesCustom,
              onChanged: (_) {
                setState(() {});
                // The keyboard leaves little room: keep the message on screen.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final error = _pagesErrorKey.currentContext;
                  if (error != null && error.mounted) Scrollable.ensureVisible(error);
                });
              },
            ),
            if (_pagesController.text.trim().isNotEmpty && _customRangeInvalid) ...[
              const SizedBox(height: MMSpacing.xs),
              Text(
                l.documentExportPagesInvalid(widget.document.pageCount),
                key: _pagesErrorKey,
                style: context.mmText.footnote.copyWith(color: context.mmColors.critical),
              ),
            ],
          ],
        ],
      ],
    );
  }

  Widget _notice(String text, {Color? color}) => Padding(
    padding: const EdgeInsets.only(top: MMSpacing.s),
    child: Text(text, style: context.mmText.footnote.copyWith(color: color ?? context.mmColors.secondaryLabel)),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final share = MMPlatformCapabilities.current.shareFile;
    final hasOptions = _hasMarks || (_isPdf && _canWriteMarks);
    return PopScope(
      canPop: !_busy,
      child: MMSheet(
        title: l.documentExportTitle,
        subtitle: widget.document.title,
        footer: hasOptions
            ? Align(
                alignment: AlignmentDirectional.centerStart,
                child: MMButton(
                  key: const ValueKey('document-export-more'),
                  label: _expanded ? l.documentExportFewerOptions : l.documentExportMoreOptions,
                  variant: MMButtonVariant.plain,
                  onPressed: _busy ? null : () => setState(() => _expanded = !_expanded),
                ),
              )
            : null,
        actions: [
          MMButton(
            key: const ValueKey('document-export-cancel'),
            label: l.cancel,
            onPressed: () {
              if (_busy) {
                setState(() => _cancelled = true);
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          if (_expanded)
            MMButton(
              key: const ValueKey('document-export-save'),
              label: share ? l.noteShareAction : l.exportAction,
              variant: MMButtonVariant.primary,
              onPressed: _busy || _customRangeInvalid ? null : () => _export(_advancedOptions),
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_expanded) _optionsForm(l) else _choices(l),
            if (!_canWriteMarks && !_inventory.isEmpty)
              _notice(MMPdfExport.canWriteMarks ? l.documentExportProtected : l.documentExportWebLimit),
            if (_hasMarks && _inventory.unplaced > 0) _notice(l.documentExportUnplaced(_inventory.unplaced)),
            if (_hasMarks && _inventory.unsupportedInk > 0) _notice(l.documentExportInkDropped),
            if (_failed) _notice(l.exportFailed, color: c.critical),
          ],
        ),
      ),
    );
  }
}

/// A row that acts immediately: there is no selection to confirm afterwards.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.running,
    required this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final String title, subtitle;
  final bool running, autofocus;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          autofocus: autofocus,
          onTap: onTap,
          hoverColor: c.hover,
          focusColor: c.hover,
          highlightColor: c.pressed,
          splashFactory: NoSplash.splashFactory,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: MMSizes.documentExportChoiceHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: MMSpacing.s),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: enabled ? c.accent : c.secondaryLabel),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: context.mmText.body.copyWith(
                            fontWeight: FontWeight.w500,
                            color: enabled ? c.label : c.secondaryLabel,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
                      ],
                    ),
                  ),
                  const SizedBox(width: MMSpacing.s),
                  if (running)
                    const CupertinoActivityIndicator(radius: 8)
                  else
                    Icon(MMIcons.chevronRight, size: 14, color: c.secondaryLabel),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The highlight colors in this document, each one tap from leaving the copy.
class _ColorFilter extends StatelessWidget {
  const _ColorFilter({required this.colors, required this.counts, required this.hidden, required this.onChanged});

  final List<int> colors;
  final Map<int, int> counts;
  final Set<int> hidden;
  final ValueChanged<Set<int>>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, MMSpacing.s),
      child: Wrap(
        spacing: MMSpacing.s,
        runSpacing: MMSpacing.xs,
        children: [
          for (final index in colors)
            () {
              final color = MMAnnotationColor.fromIndex(index).color;
              final on = !hidden.contains(index);
              return Semantics(
                button: true,
                toggled: on,
                label: context.l10n.documentExportColor(counts[index] ?? 0),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: ValueKey('document-export-color-$index'),
                    borderRadius: BorderRadius.circular(MMRadii.row),
                    hoverColor: c.hover,
                    splashFactory: NoSplash.splashFactory,
                    onTap: onChanged == null
                        ? null
                        : () => onChanged!(on ? {...hidden, index} : ({...hidden}..remove(index))),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: MMSizes.documentExportColorDot,
                            height: MMSizes.documentExportColorDot,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: on ? color : null,
                              border: on ? null : Border.all(color: color, width: 1.5),
                            ),
                            child: on ? const Icon(MMIcons.check, size: 12, color: Colors.white) : null,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${counts[index] ?? 0}',
                            style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }(),
        ],
      ),
    );
  }
}
