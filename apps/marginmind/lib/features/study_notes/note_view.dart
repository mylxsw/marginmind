import 'dart:ui' show ImageFilter;
import 'dart:async';
import 'dart:convert';

import 'package:mm_assistant/mm_assistant.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../shared/l10n.dart';
import '../../app/providers.dart';
import '../assistant/assistant_settings.dart';
import 'note_session.dart';
import 'note_organize_sheet.dart';
import '../../shared/card_image.dart';
import '../workspace/workspace_controller.dart';
import 'note_export_sheet.dart';
import 'note_setup_sheet.dart';
import 'note_text_source.dart';

/// Written note occupies the map pane, sharing the reader and global undo history.
class StudyNoteView extends ConsumerStatefulWidget {
  const StudyNoteView({super.key, required this.studySetId, required this.noteId});
  final String studySetId, noteId;
  @override
  ConsumerState<StudyNoteView> createState() => _StudyNoteViewState();
}

class _StudyNoteViewState extends ConsumerState<StudyNoteView> {
  final _keys = <String, GlobalKey>{};
  final _scroll = ScrollController();
  final _revealedAnswers = <String>{};
  NoteTextSource _text = const NoteTextSource();
  String? _focusedAnnotation;
  Timer? _focusTimer;
  int _loadGeneration = 0;
  bool _aiBusy = false;
  bool get _showAi => ref.read(noteAiMarkersProvider(widget.noteId));
  NoteSession? _editSession;

  @override
  void initState() {
    super.initState();
    _loadText();
  }

  @override
  void didUpdateWidget(StudyNoteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId) {
      _keys.clear();
      _focusedAnnotation = null;
      _revealedAnswers.clear();
      _loadText();
    }
  }

  Future<void> _loadText() async {
    final generation = ++_loadGeneration;
    final content = ref.read(workspaceProvider(widget.studySetId)).content;
    final note = content?.studyNote(widget.noteId);
    if (content == null || note == null) return;
    final text = await loadNoteTextSource(ref, widget.studySetId, content, note.scope);
    if (mounted && generation == _loadGeneration) setState(() => _text = text);
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    _editSession?.close();
    _scroll.dispose();
    super.dispose();
  }

  void _focusAnnotation(String id) {
    _focusTimer?.cancel();
    _owner.focusNoteAnnotation(id);
    setState(() => _focusedAnnotation = id);
    _focusTimer = Timer(MMMotion.flash, () {
      if (mounted) setState(() => _focusedAnnotation = null);
    });
  }

  WorkspaceController get _owner => ref.read(workspaceProvider(widget.studySetId).notifier);
  void _jump(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _keys[id]?.currentContext;
      if (mounted && target != null) Scrollable.ensureVisible(target, duration: MMMotion.quick, alignment: .15);
    });
  }

  void _undoHud(String text) => MMHud.show(
    context,
    text,
    action: (
      context.l10n.undo,
      () {
        _owner.undo();
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    ref.watch(assistantConfiguredProvider);
    ref.watch(noteAiMarkersProvider(widget.noteId));
    final provider = workspaceProvider(widget.studySetId);
    ref.listen(provider.select((s) => s.pending), (_, pending) {
      if (pending is! PendingHighlight) return;
      final note = _owner.content.studyNote(widget.noteId);
      final quote = note?.sections
          .expand((s) => s.blocks)
          .whereType<QuoteBlock>()
          .where((b) => b.annotationId == pending.annotationId)
          .firstOrNull;
      if (quote == null) {
        MMHud.show(context, context.l10n.noteNotIncluded);
        return;
      }
      _focusAnnotation(pending.annotationId);
      _jump(quote.id);
    });
    final content = ref.watch(workspaceContentProvider(widget.studySetId));
    final note = content?.studyNote(widget.noteId);
    if (note == null || content == null) return const SizedBox.shrink();
    final l = context.l10n, c = context.mmColors;
    final continuation = ref.watch(noteContinuationsProvider)[note.id];
    final used = note.sections.expand((s) => s.blocks).whereType<QuoteBlock>().map((b) => b.annotationId).toSet();
    final unused = note.unusedAnnotationIds.where((id) => content.annotation(id) != null).toList();
    Widget toc() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.readerOutline, style: context.mmText.subheadline),
        for (final (i, s) in note.sections.indexed)
          MMButton(label: '${i + 1}. ${s.title}', onPressed: () => _jump(s.id)),
      ],
    );
    return ColoredBox(
      color: c.windowBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final floating = constraints.maxWidth >= MMNoteLayout.tocMinWidth;
          final compact = constraints.maxWidth < MMSizes.noteSetupSheetWidth;
          return Column(
            children: [
              SizedBox(
                height: MMNoteLayout.barHeight,
                child: Row(
                  children: [
                    const SizedBox(width: MMSpacing.m),
                    if (compact)
                      MMIconButton(
                        key: const ValueKey('note-back'),
                        icon: MMIcons.chevronLeft,
                        tooltip: l.layoutReader,
                        onPressed: () => _owner.setLayout(MMSplitMode.primary),
                      ),
                    Icon(
                      MMIcons.studyNote,
                      key: const ValueKey('note-toolbar-icon'),
                      size: context.mmText.headline.fontSize,
                      color: c.accent,
                    ),
                    const SizedBox(width: MMSpacing.s),
                    Expanded(
                      child: Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.mmText.headline,
                      ),
                    ),
                    if (!compact &&
                        note.sections
                            .expand((s) => s.blocks)
                            .any((b) => b.origin == NoteOrigin.ai || b.origin == NoteOrigin.mixed))
                      MMIconButton(
                        key: const ValueKey('note-ai-markers'),
                        icon: MMIcons.ai,
                        tooltip: l.noteShowAi,
                        onPressed: () {
                          ref.read(noteAiMarkersProvider(widget.noteId).notifier).toggle();
                        },
                      ),
                    if (!compact)
                      MMIconButton(
                        key: const ValueKey('note-regenerate'),
                        icon: MMIcons.regenerate,
                        tooltip: l.noteRegenerate,
                        onPressed: () => showNoteReorganization(context, ref, widget.studySetId, note.id),
                      ),
                    if (compact)
                      MMDropdownMenuButton<String>(
                        key: const ValueKey('note-more'),
                        tooltip: l.moreTools,
                        icon: MMIcons.more,
                        itemBuilder: (_) => [
                          MMDropdownSubmenu<String>(
                            label: l.readerOutline,
                            entries: [
                              for (final section in note.sections)
                                (value: 'section:${section.id}', label: section.title, selected: false),
                            ],
                          ),
                          MMDropdownSubmenu<String>(
                            label: l.noteTemplate,
                            entries: [
                              for (final template in NoteTemplate.values)
                                (
                                  value: 'template:${template.name}',
                                  label: noteTemplateLabel(l, template),
                                  selected: template == note.template,
                                ),
                            ],
                          ),
                          if (note.sections
                              .expand((s) => s.blocks)
                              .any((b) => b.origin == NoteOrigin.ai || b.origin == NoteOrigin.mixed))
                            MMDropdownItem(value: 'markers', child: Text(l.noteShowAi)),
                          if (continuation != null) MMDropdownItem(value: 'continue', child: Text(l.noteContinue)),
                          MMDropdownItem(value: 'regenerate', child: Text(l.noteRegenerate)),
                          MMDropdownItem(value: 'export', child: Text(l.exportStudyNote)),
                        ],
                        onSelected: (value) {
                          if (value == 'markers') {
                            ref.read(noteAiMarkersProvider(widget.noteId).notifier).toggle();
                          } else if (value == 'continue' && continuation != null) {
                            resumeNoteOrganization(context, continuation);
                          } else if (value == 'regenerate') {
                            showNoteReorganization(context, ref, widget.studySetId, note.id);
                          } else if (value == 'export') {
                            showNoteExportSheet(context, ref, widget.studySetId, note.id, text: _text);
                          } else if (value.startsWith('section:')) {
                            _jump(value.substring('section:'.length));
                          } else if (value.startsWith('template:')) {
                            _owner.changeStudyNote(
                              note.id,
                              (n) =>
                                  n.copyWith(template: NoteTemplate.values.byName(value.substring('template:'.length))),
                            );
                          }
                        },
                      )
                    else ...[
                      if (!floating)
                        MMDropdownButton<String>(
                          key: const ValueKey('note-toc'),
                          tooltip: l.readerOutline,
                          itemBuilder: (_) => [
                            for (final section in note.sections)
                              MMDropdownItem(value: section.id, child: Text(section.title)),
                          ],
                          onSelected: _jump,
                          child: _toolbarLabel(l.readerOutline),
                        ),
                      MMDropdownButton<NoteTemplate>(
                        key: const ValueKey('note-template'),
                        tooltip: l.noteTemplate,
                        itemBuilder: (_) => [
                          for (final template in NoteTemplate.values)
                            MMDropdownItem(
                              value: template,
                              child: Row(
                                children: [
                                  SizedBox.square(
                                    dimension: MMSizes.dropdownIcon,
                                    child: template == note.template
                                        ? Icon(MMIcons.check, size: MMSizes.dropdownIcon)
                                        : null,
                                  ),
                                  const SizedBox(width: MMSpacing.s),
                                  Text(noteTemplateLabel(l, template)),
                                ],
                              ),
                            ),
                        ],
                        onSelected: (template) =>
                            _owner.changeStudyNote(note.id, (n) => n.copyWith(template: template)),
                        child: _toolbarLabel(noteTemplateLabel(l, note.template)),
                      ),
                      MMToolbarButton(
                        key: const ValueKey('note-export'),
                        icon: MMIcons.export,
                        label: l.noteExport,
                        tooltip: l.exportStudyNote,
                        onPressed: () => showNoteExportSheet(context, ref, widget.studySetId, note.id, text: _text),
                      ),
                    ],
                    const SizedBox(width: MMSpacing.s),
                  ],
                ),
              ),
              Divider(height: 1, color: c.separator),
              if (continuation != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: MMButton(
                    key: const ValueKey('note-continue'),
                    label: l.noteContinue,
                    onPressed: () => resumeNoteOrganization(context, continuation),
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      controller: _scroll,
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(
                            maxWidth: MMNoteLayout.measure + MMNoteLayout.gutter + MMNoteLayout.trailing,
                          ),
                          padding: EdgeInsets.fromLTRB(
                            compact ? MMNoteLayout.gutterCompact : MMNoteLayout.gutter,
                            MMNoteLayout.topInset,
                            compact ? MMNoteLayout.gutterCompact : MMNoteLayout.trailing,
                            MMNoteLayout.bottomInset,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              NoteEditableText(
                                key: ValueKey('note-title-${note.id}'),
                                text: note.title,
                                style: MMNoteTypography.title.copyWith(color: c.label),
                                onSave: (v) => v.trim().isEmpty
                                    ? Future.value()
                                    : _owner.changeStudyNote(note.id, (n) => n.copyWith(title: v.trim())),
                              ),
                              const SizedBox(height: MMSpacing.s),
                              Text(
                                '${MaterialLocalizations.of(context).formatShortDate(note.organizedAt.toLocal())} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(note.organizedAt.toLocal()))}',
                                style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: MMInteractive(
                                  key: const ValueKey('note-coverage'),
                                  onTap: () => _coverage(note, content, used, unused),
                                  builder: (_, _) => MMPill(
                                    unused.isEmpty ? l.noteCoverage(used.length) : l.noteUnusedCount(unused.length),
                                    color: unused.isEmpty ? c.positive : c.caution,
                                    icon: unused.isEmpty ? MMIcons.check : MMIcons.warning,
                                  ),
                                ),
                              ),
                              for (final (i, section) in note.sections.indexed) ...[
                                Padding(
                                  key: _keys.putIfAbsent(section.id, GlobalKey.new),
                                  padding: const EdgeInsets.only(
                                    top: MMNoteLayout.sectionTop,
                                    bottom: MMNoteLayout.sectionBottom,
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${i + 1}. ',
                                        style: MMNoteTypography.heading.copyWith(color: c.secondaryLabel),
                                      ),
                                      Expanded(
                                        child: NoteEditableText(
                                          text: section.title,
                                          style: MMNoteTypography.heading.copyWith(color: c.label),
                                          onSave: (v) => v.trim().isEmpty
                                              ? Future.value()
                                              : _owner.changeStudyNote(
                                                  note.id,
                                                  (n) => n.copyWith(
                                                    sections: [
                                                      for (final s in n.sections)
                                                        s.id == section.id ? s.copyWith(title: v.trim()) : s,
                                                    ],
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (note.template == NoteTemplate.cornell && !compact)
                                  IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        SizedBox(
                                          width: MMNoteLayout.cornellCueWidth,
                                          child: Padding(
                                            padding: const EdgeInsets.only(right: MMSpacing.m),
                                            child: _cornellField(note, section, 'cue'),
                                          ),
                                        ),
                                        VerticalDivider(color: c.separator),
                                        Expanded(child: _blocks(note, section, content)),
                                      ],
                                    ),
                                  )
                                else
                                  _blocks(note, section, content),
                                if (note.template == NoteTemplate.cornell) ...[
                                  const SizedBox(height: MMSpacing.m),
                                  Text(l.noteCornellSummary, style: context.mmText.subheadline),
                                  _cornellField(note, section, 'summary'),
                                ],
                              ],
                              if (note.sections.any((s) => s.question != null)) ...[
                                const SizedBox(height: MMSpacing.l),
                                MMButton(
                                  key: const ValueKey('note-all-review'),
                                  label: l.noteAddAllReview,
                                  onPressed: () async {
                                    await _owner.addNoteReviews(note.id);
                                    if (mounted) _undoHud(l.noteReviewAdded);
                                  },
                                ),
                                for (final s in note.sections)
                                  if (s.question != null) Text(s.question!, style: MMNoteTypography.body),
                              ],
                              if (used.isNotEmpty) ...[
                                const SizedBox(height: MMNoteLayout.sectionTop),
                                Text(l.noteSources, style: context.mmText.headline.copyWith(color: c.secondaryLabel)),
                                for (final (i, source) in _sourceEntries(content, used).indexed)
                                  Text(
                                    '${i + 1}. $source',
                                    key: ValueKey('note-source-entry-$i'),
                                    style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (floating)
                      Positioned(
                        top: MMSpacing.l,
                        right: MMSpacing.m,
                        child: SizedBox(width: MMNoteLayout.tocWidth, child: toc()),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // User-authored Cornell fields are ordinary TextBlocks, so they survive switching
  // templates and participate in exports, auto-save and the same global undo stack.
  Widget _cornellField(StudyNote note, NoteSection section, String kind) {
    final id = '${section.id}:cornell:$kind';
    final block = section.blocks.whereType<TextBlock>().where((b) => b.id == id).firstOrNull;
    return NoteEditableText(
      key: ValueKey(id),
      text: block?.text ?? '',
      style: MMNoteTypography.body.copyWith(color: context.mmColors.label),
      onSave: (text) => _owner.changeStudyNote(
        note.id,
        (n) => n.copyWith(
          sections: [
            for (final s in n.sections)
              s.id != section.id
                  ? s
                  : s.copyWith(
                      blocks: [
                        for (final b in s.blocks)
                          if (b.id != id) b,
                        TextBlock(
                          id: id,
                          text: text,
                          kind: kind == 'summary' ? TextKind.summary : TextKind.paragraph,
                          origin: NoteOrigin.user,
                          edited: true,
                        ),
                      ],
                    ),
          ],
        ),
      ),
    );
  }

  Widget _blocks(StudyNote note, NoteSection section, StudySetContent content) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final block in section.blocks)
        if (note.template != NoteTemplate.cornell || !block.id.startsWith('${section.id}:cornell:'))
          Padding(
            key: _keys.putIfAbsent(block.id, GlobalKey.new),
            padding: const EdgeInsets.only(bottom: MMNoteLayout.blockGap),
            child: _block(note, section, block, content),
          ),
    ],
  );

  Widget _toolbarLabel(String label) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: context.mmText.callout),
        const SizedBox(width: MMSpacing.xs),
        const Icon(MMIcons.chevronDown, size: MMSizes.dropdownIcon),
      ],
    ),
  );

  List<String> _sourceEntries(StudySetContent content, Set<String> used) {
    final grouped = <String, List<ResolvedNoteSource>>{};
    for (final id in used) {
      final source = resolveNoteSource(content, id);
      grouped.putIfAbsent(source.annotation?.documentId ?? id, () => []).add(source);
    }
    return [
      for (final sources in grouped.values)
        (() {
          final pages = {
            for (final source in sources)
              if (source.annotation case final annotation? when !annotation.isText)
                for (final page in annotation.pages) page.page,
          }.toList()..sort();
          return [
            sources.first.documentTitle ?? context.l10n.noteMissingHighlight,
            if (pages.isNotEmpty) pages.map(context.l10n.notePage).join(context.l10n.notePageSeparator),
          ].where((s) => s.isNotEmpty).join(' · ');
        })(),
    ];
  }

  String _citation(StudySetContent content, String id) {
    final source = resolveNoteSource(content, id), annotation = source.annotation;
    final title = source.documentTitle == null ? '' : context.l10n.noteSourceTitle(source.documentTitle!);
    final location = annotation == null
        ? ''
        : annotation.isText
        ? const NoteMaterialCollector().sectionTitle(content, annotation) ?? ''
        : context.l10n.notePage(annotation.page);
    final status = switch (source.status) {
      NoteSourceStatus.available => '',
      NoteSourceStatus.documentRemoved => context.l10n.noteMissingDocument,
      _ => context.l10n.noteMissingHighlight,
    };
    final citation = annotation != null && !annotation.isText
        ? context.l10n.noteSourcePage(source.documentTitle ?? '', annotation.page)
        : [title, location].where((s) => s.isNotEmpty).join(' · ');
    return [citation, status].where((s) => s.isNotEmpty).join(' · ');
  }

  String _ownSource(StudySetContent content, OwnBlock block) {
    final l = context.l10n;
    String label;
    String? location;
    switch (block.source) {
      case OwnSource.marginNote:
        label = l.noteMarginSource;
        final note = content.marginNotes.where((n) => n.id == block.sourceId).firstOrNull;
        if (note != null) {
          if (note.anchor?.textAnchors.isNotEmpty == true) {
            final anchor = note.anchor!.textAnchors.first;
            TextReadingPosition? latest;
            for (final section in OutlineTree.flatten(content.outlineOn(note.documentId)?.items ?? const [])) {
              final position = section.position;
              if (position is TextReadingPosition &&
                  position.chapterId == anchor.chapterId &&
                  position.offset <= anchor.start &&
                  (latest == null || position.offset >= latest.offset)) {
                latest = position;
                location = section.title;
              }
            }
          } else {
            location = l.notePage(note.page);
          }
        }
      case OwnSource.card:
        label = l.noteMapNotes;
        final card = content.card(block.sourceId);
        if (card != null) location = notePlainText(card.title, card.textFormat);
      case OwnSource.researchNote:
        label = l.noteSavedAi;
        location = content.researchNote(block.sourceId)?.title;
      case OwnSource.image:
        label = l.noteImages;
    }
    return [label, if (location?.trim().isNotEmpty == true) location!].join(' · ');
  }

  Widget _block(StudyNote note, NoteSection section, StudyNoteBlock block, StudySetContent content) {
    final l = context.l10n, c = context.mmColors;
    Widget child;
    if (block is QuoteBlock) {
      final resolved = resolveNoteSource(content, block.annotationId), a = resolved.annotation;
      final color = MMAnnotationColor.fromIndex(a?.colorIndex ?? 0);
      final ctx = a == null
          ? const NoteContext(noText: true)
          : const NoteMaterialCollector().contextFor(content, a, note.settings.contextSentences, text: _text);
      final question =
          section.question ??
          l.noteRecallQuestion(resolved.documentTitle ?? '', a == null || a.isText ? '' : l.pageNumber(a.page));
      final review = note.template == NoteTemplate.review;
      final visible = !review || _revealedAnswers.contains(block.id);
      child = DecoratedBox(
        decoration: BoxDecoration(
          color: _focusedAnnotation == block.annotationId
              ? c.accentTint
              : review
              ? c.card
              : null,
          borderRadius: BorderRadius.circular(MMRadii.row),
          border: Border(
            left: BorderSide(color: color.color, width: MMNoteLayout.quoteBar),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: MMNoteLayout.quoteIndent),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (review) Text(question, style: context.mmText.headline),
              if (block.contextOpen && ctx.before.isNotEmpty)
                Text(ctx.before, style: MMNoteTypography.context.copyWith(color: c.secondaryLabel)),
              MMInteractive(
                key: ValueKey('quote-${block.annotationId}'),
                onTap: () {
                  _focusAnnotation(block.annotationId);
                  if (review) setState(() => _revealedAnswers.add(block.id));
                },
                builder: (_, _) => ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: MMNoteLayout.answerBlur, sigmaY: MMNoteLayout.answerBlur),
                  enabled: !visible,
                  child: Text(
                    a?.quote ?? l.noteMissingHighlight,
                    style: MMNoteTypography.quote.copyWith(
                      color: c.excerptText,
                      backgroundColor: block.contextOpen ? color.highlight : null,
                    ),
                  ),
                ),
              ),
              if (block.contextOpen && ctx.after.isNotEmpty)
                Text(ctx.after, style: MMNoteTypography.context.copyWith(color: c.secondaryLabel)),
              if (block.contextOpen && (ctx.noText || ctx.unresolved))
                Text(l.noteNoText, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: MMSpacing.s,
                children: [
                  MMInteractive(
                    key: ValueKey('note-source-${block.id}'),
                    tooltip: a == null
                        ? null
                        : const NoteMaterialCollector().sectionTitle(content, a) ?? resolved.documentTitle,
                    onTap: resolved.status == NoteSourceStatus.available && a?.needsReview != true
                        ? () {
                            _focusAnnotation(block.annotationId);
                            _owner.revealNoteAnnotation(block.annotationId);
                          }
                        : null,
                    builder: (_, state) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xs, vertical: MMSpacing.xxs),
                      decoration: BoxDecoration(
                        color: state.hovered ? c.accentTint : null,
                        borderRadius: BorderRadius.circular(MMRadii.row),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            MMIcons.revealSource,
                            size: context.mmText.footnote.fontSize,
                            color: resolved.status == NoteSourceStatus.available ? c.accent : c.critical,
                          ),
                          const SizedBox(width: MMSpacing.xs),
                          Flexible(
                            child: Text(
                              _citation(content, block.annotationId),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.mmText.footnote.copyWith(
                                color: resolved.status == NoteSourceStatus.available ? c.accent : c.critical,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  MMIconButton(
                    icon: MMIcons.context,
                    tooltip: block.contextOpen ? l.noteCollapseContext : l.noteExpandContext,
                    onPressed: () => _toggleContext(note.id, block.id),
                  ),
                  if (review) MMButton(label: l.review, onPressed: a == null ? null : () => _review(a, question)),
                ],
              ),
            ],
          ),
        ),
      );
    } else if (block is OwnBlock && block.source == OwnSource.image) {
      final path = content.card(block.sourceId)?.imageFileName;
      child = path == null ? const SizedBox.shrink() : CardImage(path);
    } else {
      final text = switch (block) {
        OwnBlock() => ownNoteText(content, block),
        TextBlock() => block.text,
        PointsBlock() => block.items.join('\n'),
        XrefBlock() => block.text,
        _ => null,
      };
      if (text == null) return const SizedBox.shrink();
      child = Container(
        padding: const EdgeInsets.all(MMSpacing.m),
        decoration: BoxDecoration(
          color: block is OwnBlock || block.origin == NoteOrigin.user
              ? MMAnnotationColor.yellow.cardTint
              : _showAi && (block.origin == NoteOrigin.ai || block.origin == NoteOrigin.mixed)
              ? c.researchTint
              : c.quaternaryFill,
          borderRadius: BorderRadius.circular(MMRadii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NoteEditableText(
              key: ValueKey('note-edit-${block.id}'),
              onReadTap: block is XrefBlock ? () => _jump(block.toSectionId) : null,
              text: text,
              style: MMNoteTypography.body.copyWith(color: c.label),
              onSave: (value) => _owner.editStudyNoteBlock(
                note.id,
                block.id,
                text: block is PointsBlock ? null : value,
                items: block is PointsBlock ? value.split('\n') : null,
              ),
            ),
            if (block is OwnBlock)
              Text(
                _ownSource(content, block),
                key: ValueKey('note-own-source-${block.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
              ),
          ],
        ),
      );
    }
    final ai = block.origin == NoteOrigin.ai || block.origin == NoteOrigin.mixed;
    if (ai) {
      final body = child;
      child = Container(
        key: ValueKey('note-ai-block-${block.id}'),
        padding: const EdgeInsets.only(left: MMSpacing.s),
        decoration: BoxDecoration(
          border: _showAi
              ? Border(
                  left: BorderSide(color: c.researchTint, width: MMNoteLayout.aiRule),
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showAi)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  key: ValueKey('note-ai-tag-${block.id}'),
                  padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xs),
                  decoration: BoxDecoration(color: c.research, borderRadius: BorderRadius.circular(MMRadii.row)),
                  child: Text(
                    block.edited ? l.noteAiEdited : 'AI',
                    style: context.mmText.footnote.copyWith(color: c.onResearch),
                  ),
                ),
              ),
            if (block is XrefBlock)
              MMInteractive(
                key: ValueKey('note-xref-${block.id}'),
                onTap: () => _jump(block.toSectionId),
                builder: (_, _) => body,
              )
            else
              body,
          ],
        ),
      );
    }
    if (block.edited && block is! OwnBlock && block is! QuoteBlock) {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          Align(
            alignment: Alignment.centerRight,
            child: Tooltip(
              message: l.noteLocked,
              child: Icon(MMIcons.lock, size: MMSizes.dropdownIcon, color: c.secondaryLabel),
            ),
          ),
        ],
      );
    }
    return _NoteBlockFrame(onMenu: (position) => _menu(note, block, position), child: child);
  }

  Future<void> _review(Annotation annotation, String question) async {
    await _owner.makeNoteReview(annotation.id, question, annotation.quote);
    if (mounted) _undoHud(context.l10n.noteReviewAdded);
  }

  Future<void> _toggleContext(String noteId, String blockId) => _owner.changeStudyNote(
    noteId,
    (n) => n.copyWith(
      sections: [
        for (final s in n.sections)
          s.copyWith(
            blocks: [
              for (final b in s.blocks)
                b.id == blockId && b is QuoteBlock
                    ? QuoteBlock(id: b.id, annotationId: b.annotationId, contextOpen: !b.contextOpen)
                    : b,
            ],
          ),
      ],
    ),
  );

  Future<void> _menu(StudyNote note, StudyNoteBlock block, Offset position) => showMMMenu(
    context,
    position: position,
    entries: [
      if (block is QuoteBlock) ...[
        MMMenuItem(
          block.contextOpen ? context.l10n.noteCollapseContext : context.l10n.noteExpandContext,
          () => _toggleContext(note.id, block.id),
        ),
        MMMenuItem(
          context.l10n.revealSource,
          _owner.content.annotation(block.annotationId) == null
              ? null
              : () => _owner.revealNoteAnnotation(block.annotationId),
          shortcut: '⌘L',
        ),
        MMMenuItem(
          context.l10n.noteExplain,
          ref.read(assistantConfiguredProvider).value == true && !_aiBusy ? () => _explain(note, block) : null,
        ),
        const MMMenuDivider(),
        MMMenuItem(
          context.l10n.addToMapAction,
          _owner.content.annotation(block.annotationId) == null
              ? null
              : () async {
                  await _owner.addHighlightToMap(block.annotationId);
                  if (mounted) MMHud.show(context, context.l10n.noteAddedToMap);
                },
        ),
        MMMenuItem(
          context.l10n.noteCreateReview,
          _owner.content.annotation(block.annotationId) == null
              ? null
              : () {
                  final source = resolveNoteSource(_owner.content, block.annotationId);
                  _review(
                    source.annotation!,
                    context.l10n.noteRecallQuestion(
                      source.documentTitle ?? '',
                      source.annotation!.isText ? '' : context.l10n.pageNumber(source.annotation!.page),
                    ),
                  );
                },
        ),
      ],
      if (block is! OwnBlock && block is! QuoteBlock) ...[
        if (block.origin != NoteOrigin.user)
          for (final mode in NoteRewrite.values)
            MMMenuItem(
              switch (mode) {
                NoteRewrite.rephrase => context.l10n.noteRephrase,
                NoteRewrite.concise => context.l10n.noteConcise,
                NoteRewrite.expand => context.l10n.noteExpand,
              },
              ref.read(assistantConfiguredProvider).value == true && !_aiBusy
                  ? () => _rewrite(note, block, mode)
                  : null,
            ),
        if (block.origin != NoteOrigin.user)
          MMMenuItem(context.l10n.noteMakeMine, () async {
            await _owner.markStudyNoteBlockMine(note.id, block.id);
            if (mounted) _undoHud(context.l10n.noteMakeMine);
          }),
        MMMenuItem(context.l10n.addToMapAction, () async {
          await _owner.addNote(_blockText(block));
          if (mounted) _undoHud(context.l10n.noteAddedToMap);
        }),
        MMMenuItem(
          context.l10n.noteCreateReview,
          ref.read(assistantConfiguredProvider).value == true && !_aiBusy ? () => _createAiReview(note, block) : null,
        ),
      ],
      if (block is OwnBlock && block.source == OwnSource.marginNote)
        MMMenuItem(context.l10n.addToMapAction, () async {
          await _owner.attachMarginNote(block.sourceId);
          if (mounted) MMHud.show(context, context.l10n.noteAddedToMap);
        }),
      const MMMenuDivider(),
      MMMenuItem(context.l10n.noteRemoveBlock, () async {
        await _owner.removeStudyNoteBlock(note.id, block.id);
        if (mounted) _undoHud(context.l10n.noteRemoved);
      }, destructive: true),
    ],
  );

  String _blockText(StudyNoteBlock block) => switch (block) {
    TextBlock() => block.text,
    PointsBlock() => block.items.join('\n'),
    XrefBlock() => block.text,
    _ => '',
  };

  Future<void> _createAiReview(StudyNote note, StudyNoteBlock block) async {
    if (_aiBusy) return;
    final section = note.sections.where((s) => s.blocks.any((b) => b.id == block.id)).firstOrNull;
    final quote = section?.blocks.whereType<QuoteBlock>().firstOrNull;
    final annotation = quote == null ? null : _owner.content.annotation(quote.annotationId);
    if (section == null || annotation == null) return;
    if (section.question case final question?) {
      await _review(annotation, question);
      return;
    }
    setState(() => _aiBusy = true);
    NoteSession? session;
    try {
      session = await ref.read(noteSessionFactoryProvider)();
      if (!mounted) return;
      _editSession = session;
      final question = await session.reviewQuestion(
        NoteDraftSection(
          title: section.title,
          blocks: [
            NoteDraftBlock.fromJson({'type': 'paragraph', 'text': _blockText(block)}),
          ],
        ),
      );
      if (mounted) await _review(annotation, question);
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.noteFailed);
    } finally {
      session?.close();
      _editSession = null;
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _rewrite(StudyNote note, StudyNoteBlock block, NoteRewrite mode) async {
    if (_aiBusy) return;
    setState(() => _aiBusy = true);
    NoteSession? session;
    try {
      session = await ref.read(noteSessionFactoryProvider)();
      if (!mounted) return;
      _editSession = session;
      final text = await session.rewrite(_blockText(block), mode);
      if (!mounted) return;
      final current = _owner.content
          .studyNote(note.id)
          ?.sections
          .expand((s) => s.blocks)
          .where((b) => b.id == block.id)
          .firstOrNull;
      if (current == null || jsonEncode(current.toJson()) != jsonEncode(block.toJson())) return;
      await _owner.editStudyNoteBlock(
        note.id,
        block.id,
        text: block is PointsBlock ? null : text,
        items: block is PointsBlock ? text.split('\n') : null,
      );
      if (mounted) _undoHud(context.l10n.noteAiEdited);
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.noteFailed);
    } finally {
      session?.close();
      _editSession = null;
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _explain(StudyNote note, QuoteBlock quote) async {
    if (_aiBusy) return;
    final materials = const NoteMaterialCollector().collect(
      _owner.content,
      note.scope,
      note.settings,
      now: ref.read(clockProvider)(),
      text: _text,
    );
    final material = materials.highlights.where((m) => m.sourceId == quote.annotationId).firstOrNull;
    if (material == null) return;
    setState(() => _aiBusy = true);
    NoteSession? session;
    try {
      session = await ref.read(noteSessionFactoryProvider)();
      if (!mounted) return;
      _editSession = session;
      final text = await session.explain(material);
      if (!mounted) return;
      await _owner.changeStudyNote(
        note.id,
        (n) => n.copyWith(
          sections: [
            for (final s in n.sections)
              s.copyWith(
                blocks: [
                  for (final b in s.blocks) ...[
                    b,
                    if (b.id == quote.id)
                      TextBlock(
                        id: ref.read(editorProvider).newId(),
                        text: text,
                        kind: TextKind.gloss,
                        annotationId: quote.annotationId,
                      ),
                  ],
                ],
              ),
          ],
        ),
      );
      if (mounted) _undoHud(context.l10n.noteGenerated);
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.noteFailed);
    } finally {
      session?.close();
      _editSession = null;
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  void _coverage(StudyNote note, StudySetContent content, Set<String> used, List<String> unused) => showMMSheet<void>(
    context: context,
    width: MMSizes.noteCoverageWidth,
    builder: (context) => MMSheet(
      title: context.l10n.noteSources,
      actions: [MMButton(label: context.l10n.cancel, onPressed: () => Navigator.of(context).pop())],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: MMSizes.noteExportBodyHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final id in [...unused, ...used])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: MMSpacing.s),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          resolveNoteSource(content, id).annotation?.quote ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: MMTypography.readingExcerpt.copyWith(color: context.mmColors.label),
                        ),
                      ),
                      MMButton(
                        label: unused.contains(id) ? context.l10n.notePutBack : context.l10n.revealSource,
                        onPressed: () async {
                          Navigator.of(context).pop();
                          if (unused.contains(id)) {
                            await _owner.restoreStudyNoteQuote(note.id, id);
                            if (mounted) _undoHud(this.context.l10n.noteRestored);
                          } else {
                            _owner.revealNoteAnnotation(id);
                            final block = note.sections
                                .expand((s) => s.blocks)
                                .whereType<QuoteBlock>()
                                .where((b) => b.annotationId == id)
                                .first;
                            _focusAnnotation(id);
                            _jump(block.id);
                          }
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NoteBlockFrame extends StatefulWidget {
  const _NoteBlockFrame({required this.child, required this.onMenu});
  final Widget child;
  final Future<void> Function(Offset) onMenu;
  @override
  State<_NoteBlockFrame> createState() => _NoteBlockFrameState();
}

class _NoteBlockFrameState extends State<_NoteBlockFrame> {
  bool _hover = false, _focus = false, _menu = false;
  Future<void> _show(Offset position) async {
    setState(() => _menu = true);
    try {
      await widget.onMenu(position);
    } finally {
      if (mounted) setState(() => _menu = false);
    }
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: Focus(
      onFocusChange: (v) => setState(() => _focus = v),
      child: GestureDetector(
        onLongPressStart: (d) => _show(d.globalPosition),
        onSecondaryTapUp: (d) => _show(d.globalPosition),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: _hover || _focus || _menu || context.mmTouch ? 1 : 0,
              child: Builder(
                builder: (buttonContext) => MMIconButton(
                  icon: MMIcons.more,
                  size: MMNoteLayout.blockButton,
                  iconSize: MMSpacing.m,
                  tooltip: context.l10n.moreTools,
                  onPressed: () => _show((buttonContext.findRenderObject()! as RenderBox).localToGlobal(Offset.zero)),
                ),
              ),
            ),
            const SizedBox(width: MMSpacing.s),
            Expanded(child: widget.child),
          ],
        ),
      ),
    ),
  );
}

String? ownNoteText(StudySetContent content, OwnBlock block) => switch (block.source) {
  OwnSource.marginNote => content.marginNotes.where((n) => n.id == block.sourceId).firstOrNull?.text,
  OwnSource.card =>
    content.card(block.sourceId) == null
        ? null
        : [
            notePlainText(content.card(block.sourceId)!.title, content.card(block.sourceId)!.textFormat),
            notePlainText(content.card(block.sourceId)!.body, content.card(block.sourceId)!.textFormat),
          ].where((s) => s.isNotEmpty).join('\n'),
  OwnSource.researchNote => content.researchNote(block.sourceId)?.body,
  OwnSource.image => null,
};

/// IME-aware in-place editing. A commit is one durable edit; Esc writes nothing.
class NoteEditableText extends StatefulWidget {
  const NoteEditableText({super.key, required this.text, required this.style, required this.onSave, this.onReadTap});
  final String text;
  final TextStyle style;
  final Future<void> Function(String) onSave;
  final VoidCallback? onReadTap;
  @override
  State<NoteEditableText> createState() => _NoteEditableTextState();
}

class _NoteEditableTextState extends State<NoteEditableText> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  var _editing = false, _saving = false;
  @override
  void initState() {
    super.initState();
    _focus.addListener(_blur);
  }

  void _blur() {
    if (!_focus.hasFocus && _editing) _commit();
  }

  @override
  void dispose() {
    _focus.removeListener(_blur);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    if (_saving || !_editing) return;
    _saving = true;
    try {
      if (_controller.text != widget.text) await widget.onSave(_controller.text);
      if (mounted) setState(() => _editing = false);
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.noteFailed);
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) => _editing
      ? MMInlineTextField(
          controller: _controller,
          focusNode: _focus,
          style: widget.style,
          multiline: true,
          onSubmitted: _commit,
          onCancel: () => setState(() => _editing = false),
          onTapOutside: _commit,
        )
      : GestureDetector(
          onDoubleTap: widget.onReadTap == null ? null : _edit,
          child: MMInteractive(
            onTap: widget.onReadTap ?? _edit,
            builder: (_, _) => ConstrainedBox(
              constraints: const BoxConstraints(minHeight: MMNoteLayout.blockButton),
              child: Text(widget.text.isEmpty ? ' ' : widget.text, style: widget.style),
            ),
          ),
        );

  void _edit() {
    _controller.text = widget.text;
    setState(() => _editing = true);
    _focus.requestFocus();
  }
}
