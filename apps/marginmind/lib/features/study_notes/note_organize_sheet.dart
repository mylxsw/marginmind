import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../shared/l10n.dart';
import '../workspace/workspace_controller.dart';
import 'note_session.dart';

/// Compact sheets retain full action labels without overflowing the footer.
List<Widget> noteSheetActions(BuildContext context, List<Widget> actions) =>
    MediaQuery.sizeOf(context).width < MMSizeClass.compactMaxWidth
    ? [
        Flexible(
          child: Wrap(alignment: WrapAlignment.end, spacing: MMSpacing.s, runSpacing: MMSpacing.s, children: actions),
        ),
      ]
    : actions;

Future<void> resumeNoteOrganization(BuildContext context, NoteContinuation saved) => showMMSheet<void>(
  context: context,
  width: MMSizes.noteProgressSheetWidth,
  builder: (_) => NoteOrganizeSheet(
    setId: saved.setId,
    title: saved.title,
    scope: saved.scope,
    settings: saved.settings,
    template: saved.template,
    materials: saved.materials,
    existingId: saved.noteId,
    continuation: saved,
  ),
);

Future<void> showNoteOrganizeSheet(
  BuildContext context, {
  required String setId,
  required String title,
  required NoteScope scope,
  required NoteSettings settings,
  required NoteTemplate template,
  required NoteMaterials materials,
  bool previewOutline = false,
  String? existingId,
}) => showMMSheet<void>(
  context: context,
  width: MMSizes.noteProgressSheetWidth,
  builder: (_) => NoteOrganizeSheet(
    setId: setId,
    title: title,
    scope: scope,
    settings: settings,
    template: template,
    materials: materials,
    previewOutline: previewOutline,
    existingId: existingId,
  ),
);

class NoteOrganizeSheet extends ConsumerStatefulWidget {
  const NoteOrganizeSheet({
    super.key,
    required this.setId,
    required this.title,
    required this.scope,
    required this.settings,
    required this.template,
    required this.materials,
    this.previewOutline = false,
    this.existingId,
    this.continuation,
  });
  final String setId, title;
  final NoteScope scope;
  final NoteSettings settings;
  final NoteTemplate template;
  final NoteMaterials materials;
  final bool previewOutline;
  final String? existingId;
  final NoteContinuation? continuation;
  @override
  ConsumerState<NoteOrganizeSheet> createState() => _NoteOrganizeSheetState();
}

class _NoteOrganizeSheetState extends ConsumerState<NoteOrganizeSheet> {
  final _sections = <NoteOutlineSection>[];
  final _draft = <NoteDraftSection>[];
  NoteSession? _session;
  late NoteSettings _settings;
  String? _savedId;
  int _generation = 0;
  bool _busy = true, _editing = false, _failed = false, _saving = false, _fallback = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _savedId = widget.existingId;
    if (widget.continuation case final saved?) {
      _sections.addAll(saved.outline.sections);
      _draft.addAll(saved.draft.sections);
    }
    _start();
  }

  @override
  void dispose() {
    ++_generation;
    _session?.close();
    super.dispose();
  }

  Future<void> _start({bool local = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
      _editing = false;
    });
    NoteSession? session;
    try {
      session = local || _settings.depth == NoteDepth.none
          ? NoteSession(const LocalNoteOrganizer())
          : await ref.read(noteSessionFactoryProvider)();
      if (!mounted || generation != _generation) {
        session.close();
        return;
      }
      _session = session;
      if (local) {
        _settings = NoteSettings(
          organization: widget.settings.effectiveOrganization == NoteOrganization.map
              ? NoteOrganization.map
              : NoteOrganization.source,
          depth: NoteDepth.none,
          contextSentences: widget.settings.contextSentences,
          completeFragments: false,
          marginNotes: widget.settings.marginNotes,
          mapNotes: widget.settings.mapNotes,
          researchNotes: widget.settings.researchNotes,
          images: widget.settings.images,
          mapId: widget.settings.mapId,
        );
        _sections.clear();
        _draft.clear();
      }
      if (_sections.isEmpty) {
        final outline = await session.organizer.outline(widget.materials, _settings);
        if (!mounted || generation != _generation) return;
        final seen = <String>{};
        _sections.addAll(
          outline.sections.map(
            (s) => NoteOutlineSection(
              title: s.title,
              why: s.why,
              refs: s.refs.where((r) => widget.materials[r] != null && seen.add(r)).toList(),
            ),
          ),
        );
        if (widget.previewOutline && !local) {
          setState(() {
            _editing = true;
            _busy = false;
          });
          return;
        }
      }
      setState(() {});
      final outline = NoteOutline(_sections.where((s) => s.refs.isNotEmpty).toList());
      await for (final section in session.write(widget.materials, outline, _settings, _draft.length)) {
        if (!mounted || generation != _generation) return;
        // Validate injected ports too; only complete structured sections reach the note.
        final validated = NoteDraft.fromJson(NoteDraft([section]).toJson());
        setState(() => _draft.add(validated.sections.single));
      }
      if (!mounted || generation != _generation) return;
      _fallback = session.usedFallback;
      await _persist();
      if (!mounted || generation != _generation) return;
      if (_savedId == null) throw StateError('Source changed');
      ref.read(noteContinuationsProvider.notifier).remove(_savedId);
      final message = _fallback ? context.l10n.noteAiFallback : context.l10n.noteGenerated;
      Navigator.of(context).pop();
      MMHud.show(context, message);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _failed = true;
        });
        if (_draft.isNotEmpty) {
          try {
            await _persist();
          } catch (_) {
            /* Keep preview available for retry. */
          }
        }
      }
    } finally {
      session?.close();
      if (identical(_session, session)) _session = null;
    }
  }

  Future<void> _persist() async {
    if (_draft.isEmpty) return;
    setState(() => _saving = true);
    try {
      final note = await ref
          .read(workspaceProvider(widget.setId).notifier)
          .acceptNoteDraft(
            widget.title,
            widget.scope,
            _settings,
            widget.template,
            widget.materials,
            NoteDraft(_draft),
            existingId: _savedId,
            local: _settings.depth == NoteDepth.none,
          );
      if (note == null) throw StateError('Source changed');
      _savedId = note.id;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _stop() async {
    ++_generation;
    _session?.close();
    setState(() => _busy = false);
    try {
      await _persist();
      if (!mounted) return;
      final saved = NoteContinuation(
        setId: widget.setId,
        title: widget.title,
        scope: widget.scope,
        settings: _settings,
        template: widget.template,
        materials: widget.materials,
        outline: NoteOutline(_sections),
        draft: NoteDraft(_draft),
        noteId: _savedId,
      );
      ref.read(noteContinuationsProvider.notifier).put(saved);
      final host = Navigator.of(context).context;
      final l = context.l10n;
      Navigator.of(context).pop();
      if (!host.mounted) return;
      MMHud.show(
        host,
        l.noteStopped,
        action: (
          l.noteContinue,
          () {
            if (host.mounted) resumeNoteOrganization(host, saved);
          },
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _move(String refId, int? target) => setState(() {
    final sourceId = widget.materials[refId]!.sourceId;
    final moving = {
      refId,
      ...widget.materials.items.where((m) => !m.isHighlight && m.annotationId == sourceId).map((m) => m.ref),
    };
    for (var i = 0; i < _sections.length; i++) {
      final s = _sections[i];
      _sections[i] = NoteOutlineSection(
        title: s.title,
        why: s.why,
        refs: s.refs.where((r) => !moving.contains(r)).toList(),
      );
    }
    if (target != null) {
      final s = _sections[target];
      _sections[target] = NoteOutlineSection(title: s.title, why: s.why, refs: [...s.refs, ...moving]);
    }
  });

  Widget _target(int? index, Widget child) => DragTarget<String>(
    onWillAcceptWithDetails: (d) => widget.materials[d.data]?.isHighlight == true,
    onAcceptWithDetails: (d) => _move(d.data, index),
    builder: (context, candidates, rejected) => Container(
      key: ValueKey('outline-target-${index ?? 'unassigned'}'),
      padding: const EdgeInsets.all(MMSpacing.s),
      decoration: BoxDecoration(
        border: Border.all(color: candidates.isEmpty ? context.mmColors.separator : context.mmColors.accent),
        borderRadius: BorderRadius.circular(MMRadii.card),
      ),
      child: child,
    ),
  );

  Widget _quote(String id) {
    final text = widget.materials[id]!.text;
    return Draggable<String>(
      key: ValueKey('outline-ref-$id'),
      data: id,
      feedback: Material(
        color: context.mmColors.card,
        child: SizedBox(
          width: MMSizes.noteCoverageWidth,
          child: Text(text, style: MMNoteTypography.quote.copyWith(color: context.mmColors.label)),
        ),
      ),
      childWhenDragging: Opacity(opacity: .4, child: Text(text)),
      child: Padding(
        padding: const EdgeInsets.all(MMSpacing.s),
        child: Text(text, style: MMNoteTypography.quote),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final assigned = _sections.expand((s) => s.refs).toSet();
    return PopScope(
      canPop: !_busy && !_saving,
      child: MMSheet(
        title: _editing ? l.noteOutlineTitle : l.noteGenerating,
        actions: noteSheetActions(context, [
          MMButton(label: l.cancel, onPressed: _busy || _saving ? null : () => Navigator.of(context).pop()),
          if (_editing)
            MMButton(
              key: const ValueKey('outline-generate'),
              label: l.noteGenerate,
              variant: MMButtonVariant.primary,
              onPressed: assigned.isEmpty ? null : () => _start(),
            ),
          if (_busy) MMButton(key: const ValueKey('note-stop'), label: l.noteStop, onPressed: _saving ? null : _stop),
          if (!_editing && !_busy) ...[
            MMButton(
              key: const ValueKey('note-fallback'),
              label: l.noteLayoutOnly,
              onPressed: _saving ? null : () => _start(local: true),
            ),
            MMButton(
              key: const ValueKey('note-continue'),
              label: l.noteContinue,
              variant: MMButtonVariant.primary,
              onPressed: _saving ? null : () => _start(),
            ),
          ],
        ]),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .6),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_editing) ...[
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: _sections.length,
                    onReorderItem: (old, next) => setState(() {
                      _sections.insert(next, _sections.removeAt(old));
                    }),
                    itemBuilder: (context, i) {
                      final s = _sections[i];
                      return Padding(
                        key: ObjectKey(s),
                        padding: const EdgeInsets.only(bottom: MMSpacing.s),
                        child: _target(
                          i,
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: Icon(MMIcons.grip, color: context.mmColors.secondaryLabel),
                                  ),
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: s.title,
                                      decoration: const InputDecoration(border: InputBorder.none),
                                      onChanged: (v) => _sections[i] = NoteOutlineSection(
                                        title: v.trim().isEmpty ? s.title : v,
                                        refs: _sections[i].refs,
                                        why: s.why,
                                      ),
                                    ),
                                  ),
                                  MMIconButton(
                                    key: ValueKey('outline-delete-$i'),
                                    icon: MMIcons.trash,
                                    tooltip: l.delete,
                                    onPressed: () => setState(() => _sections.removeAt(i)),
                                  ),
                                ],
                              ),
                              if (s.why != null) Text(s.why!, style: context.mmText.footnote),
                              for (final r in s.refs)
                                if (widget.materials[r]?.isHighlight == true) _quote(r),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  MMButton(
                    key: const ValueKey('outline-add'),
                    label: l.noteAddSection,
                    onPressed: () =>
                        setState(() => _sections.add(NoteOutlineSection(title: l.noteNewSection, refs: []))),
                  ),
                  _target(
                    null,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(l.noteUnassigned, style: context.mmText.headline),
                        for (final m in widget.materials.highlights)
                          if (!assigned.contains(m.ref)) _quote(m.ref),
                      ],
                    ),
                  ),
                ] else ...[
                  Wrap(
                    spacing: MMSpacing.m,
                    runSpacing: MMSpacing.s,
                    children: [
                      for (final (index, label) in [
                        l.noteStepCollect,
                        l.noteStepContext,
                        l.noteStepOutline,
                        l.noteStepCompose,
                        l.noteStepVerify,
                      ].indexed)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              index <
                                      (_saving
                                          ? 4
                                          : _sections.isEmpty
                                          ? 2
                                          : 3)
                                  ? MMIcons.check
                                  : MMIcons.ai,
                              size: MMSizes.dropdownIcon,
                              color:
                                  index <=
                                      (_saving
                                          ? 4
                                          : _sections.isEmpty
                                          ? 2
                                          : 3)
                                  ? context.mmColors.research
                                  : context.mmColors.secondaryLabel,
                            ),
                            const SizedBox(width: MMSpacing.xs),
                            Text(label, style: context.mmText.footnote),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: MMSpacing.m),
                  if (_busy)
                    LinearProgressIndicator(
                      value: _sections.isEmpty
                          ? null
                          : _draft.length / _sections.where((s) => s.refs.isNotEmpty).length.clamp(1, 100000),
                    ),
                  const SizedBox(height: MMSpacing.m),
                  Text(
                    _sections.isEmpty
                        ? l.noteStepOutline
                        : l.noteStepWrite(_draft.length, _sections.where((s) => s.refs.isNotEmpty).length),
                    style: context.mmText.headline,
                  ),
                  if (_failed)
                    Text(l.noteFailed, style: context.mmText.body.copyWith(color: context.mmColors.critical)),
                  for (final s in _draft) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: MMSpacing.m),
                      child: Text(s.title, style: MMNoteTypography.heading),
                    ),
                    for (final b in s.blocks)
                      Text(switch (b.type) {
                        'quote' || 'own' => widget.materials[b.ref!]?.text ?? '',
                        'points' => b.items.join('\n'),
                        _ => b.text ?? '',
                      }, style: b.type == 'quote' ? MMNoteTypography.quote : MMNoteTypography.body),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
