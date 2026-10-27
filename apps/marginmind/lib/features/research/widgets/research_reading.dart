import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_research/mm_research.dart';

import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import '../research_controller.dart';
import '../research_drafts.dart';
import '../research_providers.dart';
import '../research_settings.dart';
import 'research_widgets.dart';
import 'save_note_sheet.dart';

/// One kept paragraph as shown: Markdown markup dropped, its kind kept.
class ReadingBlock {
  const ReadingBlock(this.id, this.text, {this.heading = 0, this.code = false, this.table});

  final String id;
  final String text;

  /// 1–6 for a heading.
  final int heading;
  final bool code;

  /// Cells of a table, by row.
  final List<List<String>>? table;

  /// A snapshot paragraph as shown to the reader. Escapes and links become
  /// plain text; scripts and remote images never made it into snapshots.
  static ReadingBlock parse(String id, String markdown) {
    final value = markdown.trim();
    final heading = RegExp(r'^(#{1,6})\s+(.*)$', dotAll: true).firstMatch(value);
    if (heading != null) return ReadingBlock(id, _inline(heading[2]!), heading: heading[1]!.length);
    if (value.startsWith('```')) {
      return ReadingBlock(id, value.replaceAll(RegExp(r'^```[^\n]*\n?|\n?```$'), ''), code: true);
    }
    final lines = value.split('\n');
    if (lines.length >= 2 && lines.every((r) => r.trim().startsWith('|'))) {
      final rows = [
        for (final r in lines)
          if (!RegExp(r'^\s*\|?\s*:?-{2,}').hasMatch(r))
            [for (final cell in r.trim().replaceAll(RegExp(r'^\||\|$'), '').split('|')) _inline(cell.trim())],
      ];
      return ReadingBlock(id, rows.map((r) => r.join(' · ')).join('\n'), table: rows);
    }
    return ReadingBlock(
      id,
      lines.map((line) => _inline(line.replaceFirstMapped(RegExp(r'^\s*[-*+]\s+'), (_) => '• '))).join('\n'),
    );
  }

  static String _inline(String text) => text
      .replaceAllMapped(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'(\*\*|__)'), '')
      .replaceAllMapped(RegExp(r'\\([\\`*_\[\]<>#\-.!|])'), (m) => m[1]!);
}

/// Reading a source (design 4.5): its kept text with stable paragraphs, an AI
/// summary kept apart from it, passages taken as evidence; or why it could
/// not be read and what can be done instead.
class ResearchReading extends ConsumerStatefulWidget {
  const ResearchReading({
    super.key,
    required this.studySetId,
    required this.value,
    required this.sourceId,
    this.focusParagraphId,
    this.version,
  });

  final String studySetId;
  final ResearchSessionState value;
  final String sourceId;
  final String? focusParagraphId;
  final int? version;

  @override
  ConsumerState<ResearchReading> createState() => _ResearchReadingState();
}

class _ResearchReadingState extends ConsumerState<ResearchReading> {
  Future<List<ReadingBlock>>? _blocks;
  String? _file;
  final _keys = <String, GlobalKey>{};

  /// The selected passage: paragraph and text.
  (String, String)? _selection;

  ResearchSource? get _source {
    final source = widget.value.sources.where((s) => s.id == widget.sourceId).firstOrNull;
    if (source == null || widget.version == null) return source;
    final versionMeta = ((widget.value.metadata[source.id] as Map?)?['versions'] as Map?)?['${widget.version}'] as Map?;
    return ResearchSource.fromJson({
      ...source.toJson(),
      'readState':
          versionMeta?['readState'] ??
          (source.versions.lastOrNull?.version == widget.version ? source.readState : 'unread'),
      'fetchedAt': versionMeta?['fetchedAt'] ?? source.fetchedAt.toIso8601String(),
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(ResearchReading old) {
    super.didUpdateWidget(old);
    _load();
    if (old.focusParagraphId != widget.focusParagraphId) _scrollToFocus();
  }

  SourceVersion? get _version => widget.version == null
      ? _source?.versions.lastOrNull
      : _source?.versions.where((v) => v.version == widget.version).firstOrNull;

  void _load() {
    final file = _version?.snapshotFile;
    if (file == null) {
      _file = null;
      _blocks = null;
      return;
    }
    if (file == _file) return;
    _selection = null;
    _keys.clear();
    _file = file;
    _blocks = ref
        .read(researchSnapshotRepositoryProvider)
        .readResearchSnapshot(widget.studySetId, file)
        .then((markdown) => [for (final p in snapshotParagraphs(markdown).entries) ReadingBlock.parse(p.key, p.value)]);
    _blocks!.then((_) => _scrollToFocus(), onError: (Object _) {});
  }

  void _scrollToFocus() {
    final id = widget.focusParagraphId;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _keys[id]?.currentContext;
      if (context != null && context.mounted) {
        Scrollable.ensureVisible(context, alignment: 0.2, duration: MMMotion.standard);
      }
    });
  }

  Evidence _evidence(String paragraphId, String quote) {
    final source = _source!;
    final version = _version!.version;
    final pasted = widget.value.pastedVersions(source.id).contains(version);
    return Evidence(
      id: sha256.convert(utf8.encode(jsonEncode(['clip', source.id, version, paragraphId, quote]))).toString(),
      sourceId: source.id,
      sourceVersion: version,
      quote: quote,
      locator: EvidenceLocator.paragraph(paragraphId),
      acquisition: pasted ? EvidenceAcquisition.userPaste : EvidenceAcquisition.auto,
      capturedAt: ref.read(clockProvider)(),
    );
  }

  Future<void> _clip({required bool note}) async {
    final selection = _selection;
    final source = _source;
    if (selection == null || source == null) return;
    final clip = ResearchClip(evidence: _evidence(selection.$1, selection.$2), sourceTitle: source.title);
    final l = context.l10n;
    setState(() => _selection = null);
    final controller = ref.read(researchPanelProvider(widget.studySetId).notifier);
    if (note) {
      await showSaveNoteSheet(
        context,
        studySetId: widget.studySetId,
        sessionId: widget.value.session.id,
        clips: [clip],
      );
      return;
    }
    await controller.addClip(widget.value.session.id, clip);
    if (mounted) MMHud.show(context, l.researchClipped(widget.value.drafts.clips.length + 1));
  }

  Future<void> _paste() async {
    final l = context.l10n;
    final text = await showMMSheet<String>(context: context, builder: (_) => const _PasteSheet());
    if (text == null || text.trim().isEmpty || !mounted) return;
    try {
      await ref
          .read(researchPanelProvider(widget.studySetId).notifier)
          .paste(widget.value.session.id, widget.sourceId, text);
    } catch (_) {
      if (mounted) MMHud.show(context, l.somethingWentWrong, icon: MMIcons.close);
    }
  }

  Future<void> _summarize() async {
    final l = context.l10n;
    final source = _source;
    if (source == null) return;
    try {
      final block = await ref
          .read(researchPanelProvider(widget.studySetId).notifier)
          .summarize(
            widget.value.session.id,
            source,
            language: Localizations.localeOf(context).languageCode == 'zh' ? 'Chinese' : 'English',
          );
      if (block != null && mounted) MMHud.show(context, l.researchNoAi, icon: MMIcons.info);
    } catch (_) {
      if (mounted) MMHud.show(context, l.somethingWentWrong, icon: MMIcons.close);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final source = _source;
    final controller = ref.read(researchPanelProvider(widget.studySetId).notifier);
    final links = ref.read(researchLinksProvider);
    final url = source == null ? null : Uri.tryParse(source.url);
    final top = Row(
      children: [
        MMButton(
          key: const ValueKey('reading-back'),
          label: l.researchTabSources,
          icon: MMIcons.chevronLeft,
          variant: MMButtonVariant.plain,
          onPressed: controller.closeReading,
        ),
        const Spacer(),
        if (url != null)
          MMButton(
            label: l.researchOpenPage,
            icon: MMIcons.openExternal,
            variant: MMButtonVariant.plain,
            onPressed: () => links.open(url),
          ),
      ],
    );
    if (source == null) return Column(children: [top]);

    final sessionId = widget.value.session.id;
    final reading = ref.watch(
      researchPanelProvider(widget.studySetId).select((s) => s.progress[sessionId]?.stage == ResearchStage.read),
    );
    final Widget body;
    if (_version == null) {
      final failed = source.readState == ResearchReadState.failed.name;
      body = MMEmptyState(
        icon: failed ? MMIcons.warning : MMIcons.interpret,
        title: failed ? l.researchCantRead : source.title,
        message: failed ? readError(l, widget.value.readError(source.id)) : null,
        actions: [
          if (reading)
            SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.research))
          else if (source.kind != 'video')
            MMButton(
              key: const ValueKey('reading-read'),
              label: failed ? l.researchReadAgain : l.researchRead,
              onPressed: () => controller.read(source.id, sessionId: sessionId),
            ),
          if (failed || source.kind == 'video') ...[
            if (source.kind != 'video')
              MMButton(key: const ValueKey('reading-paste'), label: l.researchPasteText, onPressed: _paste),
            MMButton(
              key: const ValueKey('reading-link-only'),
              label: l.researchSaveLinkOnly,
              onPressed: () =>
                  showSaveNoteSheet(context, studySetId: widget.studySetId, sessionId: sessionId, linkOnly: source),
            ),
          ],
        ],
      );
    } else {
      final summaryKey = '${source.id}@${_version!.version}';
      final summary = widget.value.drafts.summaries[summaryKey];
      final summarizing = ref.watch(
        researchPanelProvider(widget.studySetId).select((s) => s.summarizing.contains(summaryKey)),
      );
      final ai = ref.watch(researchSettingsProvider).aiConfigured;
      final (state, stateColor) = readState(context, source.readState);
      final locale = Localizations.localeOf(context).toLanguageTag();
      body = FutureBuilder<List<ReadingBlock>>(
        future: _blocks,
        builder: (context, snapshot) {
          final blocks = snapshot.data;
          if (snapshot.hasError) return MMEmptyState(icon: MMIcons.warning, title: l.somethingWentWrong);
          if (blocks == null) return const SizedBox.shrink();
          return ListView(
            padding: const EdgeInsets.fromLTRB(MMSpacing.l, MMSpacing.s, MMSpacing.l, MMSpacing.l),
            children: [
              Text(source.title, style: t.title2.copyWith(fontSize: 17, height: 24 / 17)),
              const SizedBox(height: MMSpacing.xs),
              Wrap(
                spacing: MMSpacing.xs,
                runSpacing: MMSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (url != null) Text(url.host, style: t.footnote.copyWith(color: c.secondaryLabel)),
                  if (widget.version == null || source.readState != 'unread') MMPill(state, color: stateColor),
                  if (widget.value.pastedVersions(source.id).contains(_version!.version)) MMPill(l.researchPasted),
                  Text(
                    widget.version == null
                        ? l.researchFetchedAt(DateFormat.yMd(locale).add_Hm().format(source.fetchedAt))
                        : 'v${widget.version}',
                    style: t.footnote.copyWith(color: c.secondaryLabel),
                  ),
                ],
              ),
              if (widget.version == null && source.kind != 'video')
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: MMButton(
                    label: l.researchReadAgain,
                    variant: MMButtonVariant.plain,
                    onPressed: reading ? null : () => controller.read(source.id, sessionId: sessionId),
                  ),
                ),
              if (source.readState == ResearchReadState.abstractOnly.name) ...[
                const SizedBox(height: MMSpacing.s),
                ResearchNotice(
                  text: l.researchAbstractOnly,
                  action: url == null ? null : l.researchOpenPublisher,
                  onAction: url == null ? null : () => links.open(url),
                ),
              ],
              if (ai && widget.version == null && source.kind != 'video') ...[
                const SizedBox(height: MMSpacing.m),
                _SummaryBox(summary: summary, busy: summarizing, onSummarize: _summarize),
              ],
              const SizedBox(height: MMSpacing.m),
              for (final (i, block) in blocks.indexed)
                _Paragraph(
                  key: _keys.putIfAbsent(block.id, GlobalKey.new),
                  block: block,
                  number: i + 1,
                  focused: block.id == widget.focusParagraphId,
                  selected: _selection?.$1 == block.id,
                  onSelected: (text) =>
                      setState(() => _selection = text.trim().isEmpty ? null : (block.id, text.trim())),
                  onClip: () => _clip(note: false),
                  onNote: () => _clip(note: true),
                ),
            ],
          );
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(MMSpacing.s, MMSpacing.xs, MMSpacing.s, 0), child: top),
        Expanded(child: body),
      ],
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({required this.summary, required this.busy, required this.onSummarize});

  final String? summary;
  final bool busy;
  final VoidCallback onSummarize;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    if (summary == null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: MMButton(
          key: const ValueKey('reading-summarize'),
          label: l.researchSummarize,
          icon: MMIcons.ai,
          onPressed: busy ? null : onSummarize,
        ),
      );
    }
    return Container(
      key: const ValueKey('reading-summary'),
      padding: const EdgeInsets.all(MMSpacing.m),
      decoration: BoxDecoration(color: c.researchTint, borderRadius: BorderRadius.circular(MMRadii.field + 2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(MMIcons.ai, size: 11, color: c.research),
              const SizedBox(width: MMSpacing.xs),
              Text(l.researchAiSummary, style: t.subheadline.copyWith(color: c.research)),
            ],
          ),
          const SizedBox(height: MMSpacing.xs),
          Text(summary!, style: t.body.copyWith(height: 20 / 13)),
        ],
      ),
    );
  }
}

/// A kept paragraph; selecting text in it offers to take it as evidence.
class _Paragraph extends StatelessWidget {
  const _Paragraph({
    super.key,
    required this.block,
    required this.number,
    required this.focused,
    required this.selected,
    required this.onSelected,
    required this.onClip,
    required this.onNote,
  });

  final ReadingBlock block;
  final int number;
  final bool focused;
  final bool selected;
  final ValueChanged<String> onSelected;
  final VoidCallback onClip;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final style = block.heading > 0
        ? t.title3.copyWith(height: 22 / 15)
        : block.code
        ? MMTypography.mono.copyWith(color: c.label)
        : t.body.copyWith(fontSize: 14, height: 24 / 14);
    final Widget text = block.table != null
        ? Table(
            border: TableBorder.all(color: c.separator),
            defaultColumnWidth: const IntrinsicColumnWidth(flex: 1),
            children: [
              for (final (i, row) in block.table!.indexed)
                TableRow(
                  children: [
                    for (final cell in row)
                      Padding(
                        padding: const EdgeInsets.all(MMSpacing.xs + 2),
                        child: Text(cell, style: i == 0 ? t.headline : t.callout.copyWith(fontWeight: FontWeight.w400)),
                      ),
                  ],
                ),
            ],
          )
        : SelectableText(
            block.text,
            style: style,
            onSelectionChanged: (selection, _) =>
                onSelected(selection.isCollapsed ? '' : selection.textInside(block.text)),
          );
    return Container(
      margin: EdgeInsets.only(bottom: MMSpacing.m, top: block.heading > 0 ? MMSpacing.s : 0),
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xs, vertical: MMSpacing.xxs),
      decoration: BoxDecoration(
        color: focused ? c.researchTint : null,
        borderRadius: BorderRadius.circular(MMRadii.excerpt),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(label: '¶$number', child: text),
          if (selected)
            Padding(
              padding: const EdgeInsets.only(top: MMSpacing.xs),
              child: Wrap(
                spacing: MMSpacing.xs,
                children: [
                  MMButton(
                    key: const ValueKey('reading-clip'),
                    label: l.researchClipEvidence,
                    icon: MMIcons.evidence,
                    variant: MMButtonVariant.primary,
                    color: c.research,
                    onPressed: onClip,
                  ),
                  MMButton(key: const ValueKey('reading-note'), label: l.researchWriteNote, onPressed: onNote),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PasteSheet extends StatefulWidget {
  const _PasteSheet();

  @override
  State<_PasteSheet> createState() => _PasteSheetState();
}

class _PasteSheetState extends State<_PasteSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return MMSheet(
      title: l.researchPasteTitle,
      actions: [
        MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
        MMButton(
          key: const ValueKey('paste-save'),
          label: l.save,
          variant: MMButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(_controller.text),
        ),
      ],
      child: MMTextField(
        key: const ValueKey('paste-text'),
        controller: _controller,
        maxLines: 12,
        minLines: 6,
        autofocus: true,
        semanticLabel: l.researchPasteTitle,
      ),
    );
  }
}
