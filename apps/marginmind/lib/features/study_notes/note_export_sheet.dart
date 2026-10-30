import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/providers.dart';
import '../../shared/l10n.dart';
import '../workspace/workspace_controller.dart';
import 'note_text_source.dart';

Future<void> showNoteExportSheet(
  BuildContext context,
  WidgetRef ref,
  String setId,
  String noteId, {
  NoteTextSource? text,
}) async {
  final owner = ref.read(workspaceProvider(setId).notifier);
  final content = owner.content;
  final note = content.studyNote(noteId);
  if (note == null) return;
  final textSource = text ?? await loadNoteTextSource(ref, setId, content, note.scope);
  if (!context.mounted) return;
  final prefs = ref.read(sharedPreferencesProvider);
  await showMMSheet<void>(
    context: context,
    width: MMSizes.noteExportSheetWidth,
    builder: (_) => NoteExportSheet(
      content: content,
      note: note,
      text: textSource,
      initialFormat: prefs.getString('studyNotes.exportFormat') == 'obsidian'
          ? NoteExportFormat.obsidian
          : NoteExportFormat.markdown,
      rememberFormat: (format) async {
        await prefs.setString('studyNotes.exportFormat', format.name);
      },
      resolveImage: owner.imagePath,
    ),
  );
}

class NoteExportSheet extends StatefulWidget {
  const NoteExportSheet({
    super.key,
    required this.content,
    required this.note,
    this.text = const NoteTextSource(),
    this.initialFormat = NoteExportFormat.markdown,
    this.rememberFormat,
    this.resolveImage,
    this.save,
  });
  final StudySetContent content;
  final StudyNote note;
  final NoteTextSource text;
  final NoteExportFormat initialFormat;
  final Future<void> Function(NoteExportFormat)? rememberFormat;
  final String Function(String)? resolveImage;
  final Future<bool> Function(String, Uint8List, Map<String, Uint8List>)? save;
  @override
  State<NoteExportSheet> createState() => _NoteExportSheetState();
}

class _NoteExportSheetState extends State<NoteExportSheet> {
  late var _format = widget.initialFormat;
  var _citation = NoteCitationStyle.inline;
  var _context = true, _own = true, _ai = true, _questions = true, _sources = true, _marks = true;
  var _busy = false, _failed = false;
  bool get _hasAi =>
      widget.note.sections.any((s) => s.blocks.any((b) => b.origin == NoteOrigin.ai || b.origin == NoteOrigin.mixed));
  NoteExportResult _result() => NoteExporter(widget.content, textSource: widget.text).export(
    widget.note,
    format: _format,
    language: Localizations.localeOf(context).languageCode == 'zh' ? NoteExportLanguage.zh : NoteExportLanguage.en,
    options: NoteExportOptions(
      citations: _citation,
      context: _context,
      ownNotes: _own,
      aiContent: _ai,
      questions: _questions,
      sources: _sources,
      markAi: _marks,
    ),
  );

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final result = _result();
      final attachments = <String, Uint8List>{};
      for (final entry in result.attachments.entries) {
        final path = widget.resolveImage?.call(entry.value);
        if (path == null) throw StateError('Missing image');
        attachments[entry.key] = await MMNoteFiles.read(path);
      }
      final sanitized = widget.note.title.replaceAll(RegExp(r'[/:\\\x00-\x1f\x7f]'), '').trim();
      final name = '${sanitized.isEmpty ? 'note' : sanitized}.md';
      final bytes = Uint8List.fromList(utf8.encode(result.text));
      final saved = widget.save != null
          ? await widget.save!(name, bytes, attachments)
          : await MMNoteFiles.save(name, bytes, attachments: attachments);
      if (saved) await widget.rememberFormat?.call(_format);
      if (!mounted) return;
      if (saved) {
        Navigator.of(context).pop();
        MMHud.show(context, context.l10n.exportedHud);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, c = context.mmColors;
    final preview = _result().text;
    Widget toggle(String key, String label, bool value, ValueChanged<bool>? change) => Padding(
      padding: const EdgeInsets.symmetric(vertical: MMSpacing.s),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: context.mmText.body.copyWith(color: c.label)),
          ),
          MMSwitch(
            key: ValueKey(key),
            value: value,
            semanticLabel: label,
            onChanged: _busy || change == null ? null : (v) => setState(() => change(v)),
          ),
        ],
      ),
    );
    final options = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: MMSpacing.s,
            runSpacing: MMSpacing.s,
            children: [
              for (final format in NoteExportFormat.values)
                MMButton(
                  key: ValueKey('export-${format.name}'),
                  label: format == NoteExportFormat.markdown ? 'Markdown' : 'Obsidian',
                  variant: _format == format ? MMButtonVariant.primary : MMButtonVariant.secondary,
                  onPressed: _busy ? null : () => setState(() => _format = format),
                ),
            ],
          ),
          const SizedBox(height: MMSpacing.l),
          Text(l.noteSources, style: context.mmText.subheadline),
          const SizedBox(height: MMSpacing.s),
          Wrap(
            spacing: MMSpacing.s,
            runSpacing: MMSpacing.s,
            children: [
              for (final (value, label) in [
                (NoteCitationStyle.inline, l.noteCitationPage),
                (NoteCitationStyle.footnote, l.noteCitationFootnote),
                (NoteCitationStyle.none, l.noteCitationNone),
              ])
                MMButton(
                  key: ValueKey('citation-${value.name}'),
                  label: label,
                  variant: _citation == value ? MMButtonVariant.primary : MMButtonVariant.secondary,
                  onPressed: _busy ? null : () => setState(() => _citation = value),
                ),
            ],
          ),
          const SizedBox(height: MMSpacing.l),
          Text(l.noteInclude, style: context.mmText.subheadline),
          toggle('export-context', l.noteContext, _context, (v) => _context = v),
          toggle('export-own', l.noteOwn, _own, (v) => _own = v),
          toggle('export-ai', l.noteAiContent, _hasAi && _ai, _hasAi ? (v) => _ai = v : null),
          toggle(
            'export-questions',
            l.noteQuestions,
            _questions && widget.note.sections.any((s) => s.question != null),
            widget.note.sections.any((s) => s.question != null) ? (v) => _questions = v : null,
          ),
          toggle('export-sources', l.noteSourceList, _sources, (v) => _sources = v),
          if (_hasAi && _ai) toggle('export-marks', l.noteAiMarks, _marks, (v) => _marks = v),
          if (_failed) Text(l.exportFailed, style: context.mmText.body.copyWith(color: c.critical)),
        ],
      ),
    );
    final rendered = Container(
      decoration: BoxDecoration(
        color: c.readerBackground,
        border: Border.all(color: c.separator),
        borderRadius: BorderRadius.circular(MMRadii.card),
      ),
      padding: const EdgeInsets.all(MMSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${widget.note.title}.md', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.mmText.footnote),
          const SizedBox(height: MMSpacing.m),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                preview,
                key: const ValueKey('note-export-preview'),
                style: MMTypography.mono.copyWith(color: c.label),
              ),
            ),
          ),
        ],
      ),
    );
    return PopScope(
      canPop: !_busy,
      child: MMSheet(
        title: l.exportStudyNote.replaceAll('…', ''),
        actions: [
          MMButton(label: l.cancel, onPressed: _busy ? null : () => Navigator.of(context).pop()),
          MMButton(
            label: l.copyAction,
            onPressed: _busy
                ? null
                : () async {
                    try {
                      await Clipboard.setData(ClipboardData(text: preview));
                      if (context.mounted) MMHud.show(context, l.copiedHud);
                    } catch (_) {
                      if (mounted) setState(() => _failed = true);
                    }
                  },
          ),
          MMButton(
            key: const ValueKey('note-export-save'),
            label: _failed ? l.exportRetry : l.exportAction,
            variant: MMButtonVariant.primary,
            onPressed: _busy ? null : _export,
          ),
        ],
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: MediaQuery.sizeOf(context).height * .6 > MMSizes.noteExportBodyHeight
                ? MMSizes.noteExportBodyHeight
                : MediaQuery.sizeOf(context).height * .6,
            child: constraints.maxWidth < MMSizes.noteSetupSheetWidth
                ? SingleChildScrollView(
                    child: Column(
                      children: [
                        options,
                        const SizedBox(height: MMSpacing.l),
                        SizedBox(height: MMSizes.noteExportOptionsWidth, child: rendered),
                      ],
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: MMSizes.noteExportOptionsWidth, child: options),
                      const SizedBox(width: MMSpacing.l),
                      Expanded(child: rendered),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
