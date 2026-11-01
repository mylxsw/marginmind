import '../workspace/widgets/workspace_toolbar.dart';

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
import 'note_updates.dart';
import 'note_update_sources.dart';
import 'note_organize_sheet.dart';
import '../../shared/card_image.dart';
import '../workspace/workspace_controller.dart';
import 'note_export_sheet.dart';
import 'note_share_sheet.dart';
import 'note_setup_sheet.dart';
import 'note_text_source.dart';
import 'note_contents.dart';

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
  final _scrollViewport = GlobalKey();
  final _activeSection = ValueNotifier<String?>(null);
  List<String> _sectionIds = const [];
  final _revealedAnswers = <String>{};
  NoteTextSource _text = const NoteTextSource();
  String? _focusedAnnotation;
  Timer? _focusTimer;
  int _loadGeneration = 0;
  bool _aiBusy = false;
  bool _updateBusy = false;
  int _updateGeneration = 0;
  NoteSession? _updateSession;
  NoteUpdatePreview? _update;
  StudyNote? _previewNote;
  NoteChanges? _previewChanges;
  String? _sourceFingerprint;
  final _insertReasons = <String, String>{};

  void _cancelUpdate() {
    _updateGeneration++;
    _updateSession?.close();
    _updateSession = null;
    setState(() {
      _updateBusy = false;
      _update = null;
      _previewNote = null;
      _previewChanges = null;
      _insertReasons.clear();
    });
  }

  Future<void> _previewUpdate() async {
    if (_updateBusy || _update != null) return;
    final content = _owner.content;
    final note = content.studyNote(widget.noteId);
    if (note == null) return;
    final changes = collectNoteChanges(
      content,
      note,
      text: _text,
      ignored: ref.read(noteIgnoredUpdatesProvider((widget.studySetId, widget.noteId))),
    );
    if (changes.count == 0) return;
    final noteId = widget.noteId;
    final generation = ++_updateGeneration;
    final fingerprint = noteSourceFingerprint(content);
    setState(() => _updateBusy = true);
    NoteSession? session;
    try {
      final local = note.settings.depth == NoteDepth.none || !(ref.read(assistantConfiguredProvider).value ?? false);
      if (!local && changes.materials.items.isNotEmpty) {
        session = await ref.read(noteSessionFactoryProvider)();
        if (!mounted || widget.noteId != noteId || generation != _updateGeneration) return;
        _updateSession = session;
      }
      final organizer = session?.organizer ?? const LocalNoteOrganizer();
      final placements = await organizer.place(changes.materials, note);
      if (!mounted || widget.noteId != noteId || generation != _updateGeneration) return;
      final current = _owner.content.studyNote(noteId);
      if (current == null || !sameStudyNote(current, note) || noteSourceFingerprint(_owner.content) != fingerprint) {
        throw StateError('Stale preview');
      }
      final preview = NoteUpdatePreview(base: note, materials: changes.materials, placements: placements);
      var nextId = 0;
      // Preview IDs never enter storage. Apply allocates durable IDs in the controller.
      final existingIds = note.sections.expand((s) => [s.id, ...s.blocks.map((b) => b.id)]).toSet();
      String previewId() {
        String id;
        do {
          id = 'update-preview-${nextId++}';
        } while (existingIds.contains(id));
        return id;
      }

      final proposed = const NoteUpdater().apply(note, preview, newId: previewId);
      final reasons = {
        for (final placement in placements.items)
          if (changes.materials[placement.ref] case final material?)
            noteMaterialKey(material): local ? context.l10n.noteLocalPlacement : placement.why,
      };
      _insertReasons.clear();
      for (final section in proposed.sections) {
        for (final block in section.blocks) {
          if (existingIds.contains(block.id)) continue;
          final key = switch (block) {
            QuoteBlock() => 'highlight:${block.annotationId}',
            OwnBlock() => '${block.source.name}:${block.sourceId}',
            _ => '',
          };
          _insertReasons[block.id] = reasons[key] ?? '';
        }
      }
      // The preview always presents insertion positions in reading layout.
      setState(() {
        _update = preview;
        _previewNote = proposed.copyWith(template: NoteTemplate.reading);
        _previewChanges = changes;
        _sourceFingerprint = fingerprint;
      });
    } catch (_) {
      if (mounted && widget.noteId == noteId && generation == _updateGeneration) {
        final current = _owner.content.studyNote(noteId);
        final stale =
            current == null || !sameStudyNote(current, note) || noteSourceFingerprint(_owner.content) != fingerprint;
        MMHud.show(context, stale ? context.l10n.noteUpdateStale : context.l10n.noteFailed);
      }
    } finally {
      session?.close();
      if (identical(_updateSession, session)) _updateSession = null;
      if (mounted && widget.noteId == noteId && generation == _updateGeneration) setState(() => _updateBusy = false);
    }
  }

  Future<void> _applyUpdate() async {
    final preview = _update;
    final changes = _previewChanges;
    if (preview == null || changes == null || _updateBusy) return;
    setState(() => _updateBusy = true);
    try {
      await _owner.applyStudyNoteUpdate(preview, deleted: changes.deleted, sourceFingerprint: _sourceFingerprint!);
      if (mounted) {
        final previousIds = preview.base.sections.expand((s) => s.blocks).map((b) => b.id).toSet();
        final added = _owner.content
            .studyNote(preview.base.id)!
            .sections
            .expand((s) => s.blocks)
            .where((b) => !previousIds.contains(b.id))
            .length;
        _cancelUpdate();
        final inserted = changes.materials.highlights.firstOrNull;
        if (inserted != null) {
          _focusAnnotation(inserted.sourceId);
          final block = _owner.content
              .studyNote(preview.base.id)
              ?.sections
              .expand((s) => s.blocks)
              .whereType<QuoteBlock>()
              .where((b) => b.annotationId == inserted.sourceId)
              .firstOrNull;
          if (block != null) _jump(block.id);
        }
        _undoHud(context.l10n.noteUpdateApplied(added));
      }
    } catch (_) {
      if (mounted) {
        final current = _owner.content.studyNote(preview.base.id);
        final stale =
            current == null ||
            !sameStudyNote(current, preview.base) ||
            noteSourceFingerprint(_owner.content) != _sourceFingerprint;
        _cancelUpdate();
        MMHud.show(context, stale ? context.l10n.noteUpdateStale : context.l10n.noteFailed);
      }
    }
  }

  Widget _updateBar(NoteChanges changes) {
    final l = context.l10n, c = context.mmColors;
    final preview = _update != null;
    if (preview) {
      final title = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(MMIcons.regenerate, size: MMSizes.dropdownIcon, color: c.secondaryLabel),
          const SizedBox(width: MMSpacing.s),
          Text(l.noteUpdateReady(_insertReasons.length), style: context.mmText.headline),
        ],
      );
      final cancel = MMButton(
        key: const ValueKey('note-update-cancel'),
        label: l.cancel,
        variant: MMButtonVariant.plain,
        onPressed: _updateBusy ? null : _cancelUpdate,
      );
      final apply = MMButton(
        key: const ValueKey('note-update-apply'),
        label: l.noteApplyUpdate,
        variant: MMButtonVariant.primary,
        onPressed: _updateBusy ? null : _applyUpdate,
      );
      return MMGlassBar(
        key: const ValueKey('note-update-preview-bar'),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.s),
            child: LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth < MMSizeClass.compactMaxWidth
                  ? Wrap(
                      spacing: MMSpacing.s,
                      runSpacing: MMSpacing.s,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [title, cancel, apply],
                    )
                  : Row(
                      children: [
                        Expanded(child: title),
                        cancel,
                        const SizedBox(width: MMSpacing.s),
                        apply,
                      ],
                    ),
            ),
          ),
        ),
      );
    }
    return Container(
      key: const ValueKey('note-update-banner'),
      constraints: const BoxConstraints(maxWidth: MMNoteLayout.measure),
      margin: const EdgeInsets.all(MMSpacing.s),
      padding: const EdgeInsets.all(MMSpacing.s),
      decoration: BoxDecoration(
        color: c.positive.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(MMRadii.card),
      ),
      child: Wrap(
        spacing: MMSpacing.s,
        runSpacing: MMSpacing.s,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            changes.deleted.isNotEmpty
                ? l.noteUpdateChanges(changes.count)
                : l.noteNewMaterials(changes.highlights, changes.own),
            style: context.mmText.callout,
          ),
          MMButton(
            key: const ValueKey('note-update-preview'),
            label: l.notePreviewUpdate,
            variant: MMButtonVariant.primary,
            onPressed: _updateBusy ? null : _previewUpdate,
          ),
          MMButton(
            key: ValueKey(_updateBusy ? 'note-update-cancel' : 'note-update-ignore'),
            label: _updateBusy ? l.cancel : l.noteIgnoreUpdate,
            variant: MMButtonVariant.plain,
            onPressed: _updateBusy
                ? _cancelUpdate
                : () => ref
                      .read(noteIgnoredUpdatesProvider((widget.studySetId, widget.noteId)).notifier)
                      .ignore(changes.keys),
          ),
        ],
      ),
    );
  }

  bool get _showAi => ref.read(noteAiMarkersProvider(widget.noteId));
  NoteSession? _editSession;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncActiveSection);
    _loadText();
  }

  @override
  void didUpdateWidget(StudyNoteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId) {
      _cancelUpdate();
      _keys.clear();
      _activeSection.value = null;
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
    _updateSession?.close();
    _scroll.dispose();
    _activeSection.dispose();
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

  void _syncActiveSection() {
    if (!mounted || !_scroll.hasClients || _sectionIds.isEmpty) return;
    final viewport = _scrollViewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    var active = _sectionIds.first;
    final readingLine = viewport.size.height * .15 + 1;
    for (final id in _sectionIds) {
      final heading = _keys[id]?.currentContext?.findRenderObject();
      if (heading is! RenderBox || !heading.hasSize) continue;
      if (heading.localToGlobal(Offset.zero, ancestor: viewport).dy <= readingLine) active = id;
    }
    if (_scroll.position.maxScrollExtent > 0 && _scroll.position.extentAfter <= 1) active = _sectionIds.last;
    _activeSection.value = active;
  }

  void _jump(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _keys[id]?.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : MMMotion.quick,
          alignment: .15,
        );
      }
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
    if (ref.watch(noteUpdateRequestedProvider(widget.noteId))) {
      final requestedId = widget.noteId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.noteId != requestedId || !ref.read(noteUpdateRequestedProvider(requestedId))) return;
        ref.read(noteUpdateRequestedProvider(requestedId).notifier).consume();
        _previewUpdate();
      });
    }
    final changes = ref.watch(noteChangesProvider((widget.studySetId, widget.noteId)));
    final content = ref.watch(workspaceContentProvider(widget.studySetId));
    final note = _previewNote ?? content?.studyNote(widget.noteId);
    if (note == null || content == null) return const SizedBox.shrink();
    final l = context.l10n, c = context.mmColors;
    final continuation = ref.watch(noteContinuationsProvider)[note.id];
    final used = note.sections.expand((s) => s.blocks).whereType<QuoteBlock>().map((b) => b.annotationId).toSet();
    final unused = note.unusedAnnotationIds.where((id) => content.annotation(id) != null).toList();
    _sectionIds = note.sections.map((s) => s.id).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncActiveSection());
    return ColoredBox(
      color: c.windowBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final floating = constraints.maxWidth >= MMNoteLayout.tocMinWidth;
          final scope = WorkspaceToolbarScope.maybeOf(context);
          final globalMenu = scope?.ownsActions == true;
          final compact = constraints.maxWidth < (context.mmTouchPlatform ? 960 : MMSizes.noteSetupSheetWidth);
          Widget mergeHeader(Widget header) {
            if (scope == null) return header;
            return MMToolbar.content(
              semanticLabel: note.title,
              child: Padding(
                padding: EdgeInsets.only(
                  left: scope.ownsLeading ? MMWindowChrome.maybeOf(context)?.toolbarLeadingInset ?? 0 : 0,
                ),
                child: Row(
                  children: [
                    if (scope.ownsLeading && scope.leading != null) scope.leading!,
                    Expanded(child: header),
                    if (globalMenu) ...[
                      for (final action in scope.actions)
                        if (action.id == 'assistant') action.child,
                    ],
                    if (globalMenu) const SizedBox(width: MMSpacing.s),
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              mergeHeader(
                AbsorbPointer(
                  absorbing: _updateBusy || _update != null,
                  child: SizedBox(
                    height: MMNoteLayout.barHeight,
                    child: Row(
                      children: [
                        const SizedBox(width: MMSpacing.m),
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
                        if (!compact) ...[
                          if (!floating && constraints.maxWidth >= 800)
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
                            key: const ValueKey('note-share'),
                            icon: MMIcons.share,
                            label: floating ? l.noteShareAction.replaceAll('…', '') : null,
                            tooltip: l.noteShareTitle,
                            onPressed: () => showNoteShareSheet(context, _owner.content, note),
                          ),
                          MMToolbarButton(
                            key: const ValueKey('note-export'),
                            icon: MMIcons.export,
                            label: constraints.maxWidth >= MMNoteLayout.exportLabelMinWidth ? l.noteExport : null,
                            tooltip: l.exportStudyNote,
                            onPressed: () => showNoteExportSheet(context, ref, widget.studySetId, note.id, text: _text),
                          ),
                        ],
                        MMDropdownMenuButton<Object>(
                          key: const ValueKey('note-more'),
                          tooltip: l.moreTools,
                          icon: MMIcons.more,
                          itemBuilder: (_) => [
                            MMDropdownSubmenu<Object>(
                              label: l.readerOutline,
                              icon: MMIcons.outline,
                              entries: [
                                for (final section in note.sections)
                                  (value: 'section:${section.id}', label: section.title, selected: false),
                              ],
                            ),
                            MMDropdownSubmenu<Object>(
                              label: l.noteTemplate,
                              icon: MMIcons.template,
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
                              MMDropdownItem(value: 'markers', icon: MMIcons.ai, child: Text(l.noteShowAi)),
                            if (continuation != null)
                              MMDropdownItem(value: 'continue', icon: MMIcons.play, child: Text(l.noteContinue)),
                            MMDropdownItem(
                              value: 'regenerate',
                              icon: MMIcons.regenerate,
                              child: Text(l.noteRegenerate),
                            ),
                            MMDropdownItem(value: 'export', icon: MMIcons.export, child: Text(l.exportStudyNote)),
                            MMDropdownItem(value: 'share', icon: MMIcons.share, child: Text('${l.noteShareTitle}…')),
                            if (globalMenu) ...[
                              const PopupMenuDivider(),
                              for (final action in scope!.actions)
                                if (action.id != 'assistant' && action.menuEntry is PopupMenuItem<VoidCallback>)
                                  MMDropdownItem<Object>(
                                    value: (action.menuEntry as PopupMenuItem<VoidCallback>).value,
                                    child: action.menuEntry is MMDropdownItem<VoidCallback>
                                        ? (action.menuEntry as MMDropdownItem<VoidCallback>).menuChild
                                        : (action.menuEntry as PopupMenuItem<VoidCallback>).child,
                                  ),
                              for (final entry in scope.menuEntries)
                                if (entry is PopupMenuItem<VoidCallback>)
                                  MMDropdownItem<Object>(
                                    key: entry.key,
                                    value: entry.value,
                                    enabled: entry.enabled,
                                    child: entry is MMDropdownItem<VoidCallback> ? entry.menuChild : entry.child,
                                  ),
                            ],
                          ],
                          onSelected: (command) {
                            if (command is VoidCallback) {
                              command();
                              return;
                            }
                            final value = command as String;
                            if (value == 'markers') {
                              ref.read(noteAiMarkersProvider(widget.noteId).notifier).toggle();
                            } else if (value == 'continue' && continuation != null) {
                              resumeNoteOrganization(context, continuation);
                            } else if (value == 'regenerate') {
                              showNoteReorganization(context, ref, widget.studySetId, note.id);
                            } else if (value == 'export') {
                              showNoteExportSheet(context, ref, widget.studySetId, note.id, text: _text);
                            } else if (value == 'share') {
                              showNoteShareSheet(context, _owner.content, note);
                            } else if (value.startsWith('section:')) {
                              _jump(value.substring('section:'.length));
                            } else if (value.startsWith('template:')) {
                              _owner.changeStudyNote(
                                note.id,
                                (n) => n.copyWith(
                                  template: NoteTemplate.values.byName(value.substring('template:'.length)),
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(width: MMSpacing.s),
                      ],
                    ),
                  ),
                ),
              ),
              Divider(height: c.flat ? MMSizes.hairline : 1, color: c.separator),
              if ((_previewChanges ?? changes) case final pending? when pending.count > 0) _updateBar(pending),
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
                  key: _scrollViewport,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(right: floating ? MMNoteLayout.tocWidth + MMSpacing.l : 0),
                      child: SingleChildScrollView(
                        key: const ValueKey('note-scroll'),
                        controller: _scroll,
                        child: AbsorbPointer(
                          absorbing: _update != null,
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
                                    else ...[
                                      if (note.template == NoteTemplate.cornell) _cornellField(note, section, 'cue'),
                                      _blocks(note, section, content),
                                    ],
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
                                    Text(
                                      l.noteSources,
                                      style: context.mmText.headline.copyWith(color: c.secondaryLabel),
                                    ),
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
                      ),
                    ),
                    if (floating && note.sections.isNotEmpty)
                      Positioned(
                        top: MMNoteLayout.topInset,
                        bottom: MMSpacing.l,
                        right: MMSpacing.m,
                        width: MMNoteLayout.tocWidth,
                        child: ValueListenableBuilder<String?>(
                          valueListenable: _activeSection,
                          builder: (context, active, _) => NoteContents(
                            title: l.readerOutline,
                            sections: note.sections,
                            activeId: active ?? note.sections.first.id,
                            onSelected: _jump,
                          ),
                        ),
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
    final block =
        section.blocks.whereType<TextBlock>().where((b) => b.id == id).firstOrNull ??
        (kind == 'summary'
            ? section.blocks.whereType<TextBlock>().where((b) => b.kind == TextKind.summary).firstOrNull
            : null);
    if (kind == 'summary' && block != null) {
      return KeyedSubtree(key: ValueKey(id), child: _block(note, section, block, _owner.content));
    }
    return NoteEditableText(
      key: ValueKey(id),
      text: block?.text ?? (kind == 'cue' ? section.question ?? '' : ''),
      style: MMNoteTypography.body.copyWith(color: context.mmColors.label),
      onSave: (text) => block != null
          ? _owner.editStudyNoteBlock(note.id, block.id, text: text)
          : _owner.changeStudyNote(
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

  Widget _blocks(StudyNote note, NoteSection section, StudySetContent content) {
    final summaries = section.blocks.whereType<TextBlock>();
    final summary =
        summaries.where((b) => b.id == '${section.id}:cornell:summary').firstOrNull ??
        summaries.where((b) => b.kind == TextKind.summary).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final block in section.blocks)
          if (note.template != NoteTemplate.cornell ||
              (block.id != '${section.id}:cornell:cue' && block.id != summary?.id))
            Padding(
              key: _keys.putIfAbsent(block.id, GlobalKey.new),
              padding: const EdgeInsets.only(bottom: MMNoteLayout.blockGap),
              child: _previewBlock(note, section, block, content),
            ),
      ],
    );
  }

  Widget _previewBlock(StudyNote note, NoteSection section, StudyNoteBlock block, StudySetContent content) {
    final child = _block(note, section, block, content);
    final reason = _insertReasons[block.id];
    if (reason == null) return child;
    return Container(
      key: ValueKey('note-insert-${block.id}'),
      padding: const EdgeInsets.all(MMSpacing.s),
      decoration: BoxDecoration(
        color: context.mmColors.positive.withValues(alpha: .12),
        border: Border(
          left: BorderSide(color: context.mmColors.positive, width: MMNoteLayout.quoteBar),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(reason, style: context.mmText.footnote.copyWith(color: context.mmColors.secondaryLabel)),
          child,
        ],
      ),
    );
  }

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

  Widget _ownSourceLink(StudySetContent content, OwnBlock block) {
    final VoidCallback? open = switch (block.source) {
      OwnSource.card || OwnSource.image when content.nodes.any((n) => n.cardId == block.sourceId) =>
        () => _owner.revealNoteCard(block.sourceId),
      OwnSource.marginNote
          when content.marginNotes.any((n) => n.id == block.sourceId && content.document(n.documentId) != null) =>
        () => _owner.revealNoteMargin(block.sourceId),
      _ => null,
    };
    return MMInteractive(
      key: ValueKey('note-own-source-link-${block.id}'),
      onTap: open,
      builder: (_, _) => Text(
        _ownSource(content, block),
        key: ValueKey('note-own-source-${block.id}'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.mmText.footnote.copyWith(
          color: open == null ? context.mmColors.secondaryLabel : context.mmColors.accent,
        ),
      ),
    );
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
      final aiQuestion =
          note.settings.depth != NoteDepth.none &&
          section.question?.trim().isNotEmpty == true &&
          section.blocks.whereType<QuoteBlock>().firstOrNull?.id == block.id;
      final question = aiQuestion
          ? section.question!
          : l.noteRecallQuestion(resolved.documentTitle ?? '', a == null || a.isText ? '' : l.pageNumber(a.page));
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
              if (review) ...[
                if (aiQuestion)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      key: ValueKey('note-review-ai-${block.id}'),
                      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xs),
                      decoration: BoxDecoration(color: c.research, borderRadius: BorderRadius.circular(MMRadii.row)),
                      child: Text('AI', style: context.mmText.footnote.copyWith(color: c.onResearch)),
                    ),
                  ),
                Text(question, key: ValueKey('note-review-question-${block.id}'), style: context.mmText.headline),
              ],
              if (visible && block.contextOpen && ctx.before.isNotEmpty)
                Text(ctx.before, style: MMNoteTypography.context.copyWith(color: c.secondaryLabel)),
              MMInteractive(
                key: ValueKey('quote-${block.annotationId}'),
                semanticLabel: visible ? null : question,
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
                      decoration: _previewChanges?.deleted.contains(block.annotationId) == true
                          ? TextDecoration.lineThrough
                          : null,
                      backgroundColor: block.contextOpen ? color.highlight : null,
                    ),
                  ),
                ),
              ),
              if (visible && block.contextOpen && ctx.after.isNotEmpty)
                Text(ctx.after, style: MMNoteTypography.context.copyWith(color: c.secondaryLabel)),
              if (visible && block.contextOpen && (ctx.noText || ctx.unresolved))
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
                  if (review)
                    MMButton(
                      key: ValueKey('note-review-add-${block.id}'),
                      label: l.noteAddToReview,
                      variant: MMButtonVariant.plain,
                      icon: MMIcons.review,
                      onPressed: a == null ? null : () => _review(a, question),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    } else if (block is OwnBlock && block.source == OwnSource.image) {
      final path = content.card(block.sourceId)?.imageFileName;
      child = path == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [CardImage(path), _ownSourceLink(content, block)],
            );
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
            if (block is OwnBlock) _ownSourceLink(content, block),
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
    if (block.edited) {
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
          icon: MMIcons.context,
        ),
        MMMenuItem(
          context.l10n.revealSource,
          _owner.content.annotation(block.annotationId) == null
              ? null
              : () => _owner.revealNoteAnnotation(block.annotationId),
          shortcut: '⌘L',
          icon: MMIcons.revealSource,
        ),
        MMMenuItem(
          context.l10n.noteExplain,
          ref.read(assistantConfiguredProvider).value == true && !_aiBusy ? () => _explain(note, block) : null,
          icon: MMIcons.explain,
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
          icon: MMIcons.mindMap,
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
          icon: MMIcons.review,
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
              icon: MMIcons.editNote,
            ),
        if (block.origin != NoteOrigin.user)
          MMMenuItem(context.l10n.noteMakeMine, () async {
            await _owner.markStudyNoteBlockMine(note.id, block.id);
            if (mounted) _undoHud(context.l10n.noteMakeMine);
          }, icon: MMIcons.editNote),
        MMMenuItem(context.l10n.addToMapAction, () async {
          await _owner.addNote(_blockText(block));
          if (mounted) _undoHud(context.l10n.noteAddedToMap);
        }, icon: MMIcons.mindMap),
        MMMenuItem(
          context.l10n.noteCreateReview,
          ref.read(assistantConfiguredProvider).value == true && !_aiBusy ? () => _createAiReview(note, block) : null,
          icon: MMIcons.review,
        ),
      ],
      if (block is OwnBlock && block.source == OwnSource.marginNote)
        MMMenuItem(context.l10n.addToMapAction, () async {
          await _owner.attachMarginNote(block.sourceId);
          if (mounted) MMHud.show(context, context.l10n.noteAddedToMap);
        }, icon: MMIcons.mindMap),
      const MMMenuDivider(),
      MMMenuItem(
        context.l10n.noteRemoveBlock,
        () async {
          await _owner.removeStudyNoteBlock(note.id, block.id);
          if (mounted) _undoHud(context.l10n.noteRemoved);
        },
        destructive: true,
        icon: MMIcons.trash,
      ),
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
      : widget.onReadTap == null
      ? _readText()
      : Row(
          children: [
            Expanded(child: _readText()),
            MMIconButton(icon: MMIcons.editNote, tooltip: context.l10n.editNote, onPressed: _edit),
          ],
        );

  Widget _readText() => MMInteractive(
    onTap: widget.onReadTap ?? _edit,
    builder: (_, _) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: MMNoteLayout.blockButton),
      child: Text(widget.text.isEmpty ? ' ' : widget.text, style: widget.style),
    ),
  );

  void _edit() {
    _controller.text = widget.text;
    setState(() => _editing = true);
    _focus.requestFocus();
  }
}
