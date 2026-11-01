import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../shared/l10n.dart';
import 'note_share_card.dart';
import 'note_filename.dart';

Future<void> showNoteShareSheet(BuildContext context, StudySetContent content, StudyNote note) => showMMSheet<void>(
  context: context,
  width: MMSizes.noteShareSheetWidth,
  builder: (_) => NoteShareSheet(content: content, note: note),
);

class NoteShareSheet extends StatefulWidget {
  const NoteShareSheet({super.key, required this.content, required this.note, this.capture, this.save, this.copy});
  final StudySetContent content;
  final StudyNote note;
  final Future<Uint8List> Function(RenderRepaintBoundary)? capture;
  final Future<bool> Function(String, Uint8List)? save;
  final Future<void> Function(Uint8List)? copy;
  @override
  State<NoteShareSheet> createState() => _NoteShareSheetState();
}

class _NoteShareSheetState extends State<NoteShareSheet> {
  final _boundary = GlobalKey();
  var _scope = NoteShareScope.section;
  var _theme = MMShareCardTheme.paper;
  var _section = 0, _quote = 0;
  var _own = true, _ai = true, _busy = false, _failed = false;
  Future<void> _output(bool copy) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      final bytes = await (widget.capture ?? captureNoteCard)(
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary,
      );
      final saved = copy
          ? await (widget.copy ?? MMMapClipboard.writeImage)(bytes).then((_) => true)
          : await (widget.save ?? (name, data) => MMNoteFiles.save(name, data))(
              noteFileName(widget.note.title, 'png'),
              bytes,
            );
      if (mounted && saved) MMHud.show(context, copy ? context.l10n.copiedHud : context.l10n.studyNoteSavedImage);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final selected = selectSharedNote(widget.note, _scope, _section, _quote);
    final document = NoteRichDocument.resolve(
      widget.content,
      selected,
      language: Localizations.localeOf(context).languageCode == 'zh' ? NoteExportLanguage.zh : NoteExportLanguage.en,
      options: NoteExportOptions(context: false, ownNotes: _own, aiContent: _ai, questions: false, sources: false),
    );
    final hasQuotes = document.paragraphs.any((p) => p.kind == NoteParagraphKind.quote);
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: MMSpacing.s,
          runSpacing: MMSpacing.s,
          children: [
            for (final scope in NoteShareScope.values)
              MMButton(
                key: ValueKey('share-${scope.name}'),
                label: switch (scope) {
                  NoteShareScope.quote => l.noteShareQuote,
                  NoteShareScope.section => l.noteShareSection,
                  NoteShareScope.summary => l.noteShareSummary,
                },
                variant: _scope == scope ? MMButtonVariant.primary : MMButtonVariant.secondary,
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _scope = scope;
                        _quote = 0;
                      }),
              ),
          ],
        ),
        if (_scope != NoteShareScope.summary) ...[
          const SizedBox(height: MMSpacing.m),
          MMDropdownButton<int>(
            key: const ValueKey('share-section-picker'),
            enabled: !_busy && widget.note.sections.isNotEmpty,
            width: MMSizes.noteShareOptionsWidth,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.note.sections.isEmpty
                        ? l.noteNoQuotes
                        : '${_section + 1}. ${widget.note.sections[_section].title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(MMIcons.chevronDown),
              ],
            ),
            itemBuilder: (_) => [
              for (final (i, section) in widget.note.sections.indexed)
                MMDropdownItem(value: i, icon: MMIcons.section, child: Text('${i + 1}. ${section.title}')),
            ],
            onSelected: (i) => setState(() {
              _section = i;
              _quote = 0;
            }),
          ),
          if (_scope == NoteShareScope.quote && widget.note.sections.isNotEmpty)
            MMDropdownButton<int>(
              key: const ValueKey('share-quote-picker'),
              enabled: !_busy && widget.note.sections[_section].blocks.whereType<QuoteBlock>().isNotEmpty,
              width: MMSizes.noteShareOptionsWidth,
              child: Text('${l.noteShareQuote} ${_quote + 1}'),
              itemBuilder: (_) => [
                for (final (i, block) in widget.note.sections[_section].blocks.whereType<QuoteBlock>().indexed)
                  MMDropdownItem(
                    value: i,
                    icon: MMIcons.context,
                    child: Text(
                      resolveNoteSource(widget.content, block.annotationId).annotation?.quote ?? l.noteNoQuotes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onSelected: (i) => setState(() => _quote = i),
            ),
        ],
        const SizedBox(height: MMSpacing.m),
        Wrap(
          spacing: MMSpacing.s,
          runSpacing: MMSpacing.s,
          children: [
            for (final theme in MMShareCardTheme.values)
              MMButton(
                key: ValueKey('share-${theme.name}'),
                label: switch (theme) {
                  MMShareCardTheme.paper => l.noteSharePaper,
                  MMShareCardTheme.plain => l.noteSharePlain,
                  MMShareCardTheme.night => l.noteShareNight,
                },
                variant: _theme == theme ? MMButtonVariant.primary : MMButtonVariant.secondary,
                onPressed: _busy ? null : () => setState(() => _theme = theme),
              ),
          ],
        ),
        const SizedBox(height: MMSpacing.m),
        Row(
          children: [
            Expanded(child: Text(l.noteOwn)),
            MMSwitch(
              key: const ValueKey('share-own'),
              semanticLabel: l.noteOwn,
              value: _own,
              onChanged: _busy ? null : (v) => setState(() => _own = v),
            ),
          ],
        ),
        if (widget.note.sections.any((s) => s.blocks.any((b) => b.origin != NoteOrigin.user)))
          Row(
            children: [
              Expanded(child: Text(l.noteShareAi)),
              MMSwitch(
                key: const ValueKey('share-ai'),
                semanticLabel: l.noteShareAi,
                value: _ai,
                onChanged: _busy ? null : (v) => setState(() => _ai = v),
              ),
            ],
          ),
        if (_failed) Text(l.exportFailed, style: context.mmText.body.copyWith(color: context.mmColors.critical)),
      ],
    );
    final preview = Container(
      decoration: BoxDecoration(
        color: context.mmColors.quaternaryFill,
        borderRadius: BorderRadius.circular(MMRadii.card),
      ),
      padding: const EdgeInsets.all(MMSpacing.l),
      child: SingleChildScrollView(
        child: Center(
          child: hasQuotes
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(MMShareCardStyle.radius),
                    boxShadow: const [MMShareCardStyle.previewShadow],
                  ),
                  child: RepaintBoundary(
                    key: _boundary,
                    child: NoteShareCard(document: document, theme: _theme, scope: _scope),
                  ),
                )
              : Text(l.noteNoQuotes, style: context.mmText.body),
        ),
      ),
    );
    return PopScope(
      canPop: !_busy,
      child: MMSheet(
        title: l.noteShareTitle,
        actions: [
          MMButton(label: l.done, onPressed: _busy ? null : () => Navigator.of(context).pop()),
          if (MMPlatformCapabilities.current.nativeMapClipboard)
            MMButton(label: l.noteCopyImage, onPressed: _busy || !hasQuotes ? null : () => _output(true)),
          MMButton(
            label: MMPlatformCapabilities.current.shareFile ? l.noteShareAction : l.noteSaveImage,
            variant: MMButtonVariant.primary,
            onPressed: _busy || !hasQuotes ? null : () => _output(false),
          ),
        ],
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .6,
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < MMSizes.noteSetupSheetWidth
                ? SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(height: MMSizes.noteExportOptionsWidth, child: preview),
                        controls,
                      ],
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: MMSizes.noteShareOptionsWidth,
                        child: SingleChildScrollView(child: controls),
                      ),
                      const SizedBox(width: MMSpacing.l),
                      Expanded(child: preview),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
