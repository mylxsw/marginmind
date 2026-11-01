import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_design/mm_design.dart';

import '../../shared/l10n.dart';
import '../workspace/workspace_controller.dart';
import 'note_session.dart';
import 'note_organization_progress.dart';

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
    modelOverride: saved.modelOverride,
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
  ModelReference? modelOverride,
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
    modelOverride: modelOverride,
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
    this.modelOverride,
  });
  final String setId, title;
  final NoteScope scope;
  final NoteSettings settings;
  final NoteTemplate template;
  final NoteMaterials materials;
  final bool previewOutline;
  final ModelReference? modelOverride;
  final String? existingId;
  final NoteContinuation? continuation;
  @override
  ConsumerState<NoteOrganizeSheet> createState() => _NoteOrganizeSheetState();
}

class _NoteOrganizeSheetState extends ConsumerState<NoteOrganizeSheet> {
  final _sections = <NoteOutlineSection>[];
  final _draft = <NoteDraftSection>[];
  NoteSession? _session;
  late final String _sessionId = widget.continuation?.sessionId ?? newId();
  late NoteSettings _settings;
  String? _savedId;
  Object? _error;
  int _generation = 0;
  bool _busy = true, _editing = false, _failed = false, _saving = false, _fallback = false;
  NoteOrganizationPhase _phase = NoteOrganizationPhase.outline;

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
      _error = null;
      _editing = false;
      _phase = _sections.isEmpty ? NoteOrganizationPhase.outline : NoteOrganizationPhase.write;
    });
    NoteSession? session;
    try {
      session = local || _settings.depth == NoteDepth.none
          ? NoteSession(const LocalNoteOrganizer())
          : await ref.read(noteSessionFactoryProvider)(
              studySetId: widget.setId,
              sessionId: _sessionId,
              modelOverride: widget.modelOverride,
            );
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
      setState(() => _phase = NoteOrganizationPhase.write);
      final outline = NoteOutline(_sections.where((s) => s.refs.isNotEmpty).toList());
      await for (final section in session.write(widget.materials, outline, _settings, _draft.length)) {
        if (!mounted || generation != _generation) return;
        // Validate injected ports too; only complete structured sections reach the note.
        final validated = NoteDraft.fromJson(NoteDraft([section]).toJson());
        setState(() => _draft.add(validated.sections.single));
        await _persist();
        await _remember();
      }
      if (!mounted || generation != _generation) return;
      _fallback = session.usedFallback;
      setState(() => _phase = NoteOrganizationPhase.verify);
      await _persist();
      if (!mounted || generation != _generation) return;
      if (_savedId == null) throw StateError('Source changed');
      await ref.read(noteContinuationsProvider.notifier).remove(_savedId);
      if (!mounted || generation != _generation) return;
      final message = _fallback ? context.l10n.noteAiFallback : context.l10n.noteGenerated;
      Navigator.of(context).pop();
      MMHud.show(context, message);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _failed = true;
          _error = error;
        });
        if (_draft.isNotEmpty) {
          try {
            await _persist();
            await _remember();
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

  Future<void> _remember() async {
    await ref
        .read(noteContinuationsProvider.notifier)
        .put(
          NoteContinuation(
            setId: widget.setId,
            title: widget.title,
            scope: widget.scope,
            settings: _settings,
            template: widget.template,
            materials: widget.materials,
            outline: NoteOutline(_sections),
            draft: NoteDraft(_draft),
            noteId: _savedId,
            sessionId: _sessionId,
            modelOverride: widget.modelOverride,
          ),
        );
  }

  Future<void> _persist() async {
    if (_draft.isEmpty) return;
    // An incomplete reorganization must not remove the destination of a
    // handwritten cross-reference. Keep the existing note until all sections
    // are ready; the continuation and individual runtime stages are durable.
    if (widget.existingId != null && _draft.length < _sections.where((s) => s.refs.isNotEmpty).length) return;
    setState(() => _saving = true);
    try {
      final current = const NoteMaterialCollector().collect(
        ref.read(workspaceProvider(widget.setId).notifier).content,
        widget.scope,
        _settings,
        now: widget.materials.collectedAt,
      );
      for (final material in widget.materials.items) {
        final live = current.items
            .where((m) => m.sourceId == material.sourceId && m.source == material.source)
            .firstOrNull;
        if (live == null || live.text != material.text) throw StateError('Source changed');
      }
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
    if (!_busy || _saving) return;
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
        sessionId: _sessionId,
        modelOverride: widget.modelOverride,
      );
      await ref.read(noteContinuationsProvider.notifier).put(saved);
      if (!mounted) return;
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
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _error = error;
        });
      }
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

  String _failureMessage(BuildContext context) {
    final l = context.l10n;
    if (_error == null || _error is StateError || _error is FormatException) return l.noteFailed;
    return switch (assistantFailureKind(_error!)) {
      ResearchFailureKind.authentication => l.noteFailureAuthentication,
      ResearchFailureKind.timeout => l.noteFailureTimeout,
      ResearchFailureKind.budget => l.noteFailureBudget,
      ResearchFailureKind.network => l.noteFailureNetwork,
      ResearchFailureKind.rateLimited || ResearchFailureKind.unavailable => l.noteFailureService,
      ResearchFailureKind.protocol || ResearchFailureKind.invalidRequest => l.noteFailureProtocol,
      _ => l.noteFailed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final content = ref.read(workspaceProvider(widget.setId).notifier).content;
    final assigned = _sections.expand((s) => s.refs).toSet();
    return PopScope(
      canPop: !_busy && !_saving,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_busy) {
              _stop();
            } else if (!_saving) {
              Navigator.of(context).maybePop();
            }
          },
        },
        child: Focus(
          autofocus: true,
          child: MMSheet(
            titleStyle: _editing ? null : context.mmText.title2,
            titleLeading: _editing
                ? null
                : Icon(
                    _settings.depth == NoteDepth.none ? MMIcons.studyNote : MMIcons.ai,
                    color: context.mmColors.research,
                    size: 24,
                  ),
            title: _editing
                ? l.noteOutlineTitle
                : _settings.depth == NoteDepth.none
                ? l.noteProgressLayoutTitle
                : l.noteProgressTitle,
            actions: [
              if (!_busy) MMButton(label: l.cancel, onPressed: _saving ? null : () => Navigator.of(context).pop()),
              if (_editing)
                MMButton(
                  key: const ValueKey('outline-generate'),
                  label: l.noteGenerate,
                  variant: MMButtonVariant.primary,
                  onPressed: assigned.isEmpty ? null : () => _start(),
                ),
              if (_busy)
                MMButton(
                  key: const ValueKey('note-stop'),
                  label: l.noteStop,
                  icon: MMIcons.stop,
                  onPressed: _saving ? null : _stop,
                ),
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
            ],
            child: !_editing
                ? NoteOrganizationProgress(
                    phase: _phase,
                    status: _failed ? (_draft.isNotEmpty ? RunStatus.partial : RunStatus.failed) : null,
                    materials: widget.materials,
                    sections: _sections.where((s) => s.refs.isNotEmpty).toList(),
                    draft: List.of(_draft),
                    local: _settings.depth == NoteDepth.none,
                    busy: _busy,
                    error: _failed ? _failureMessage(context) : null,
                    sources: {
                      for (final material in widget.materials.items)
                        if (content.annotation(material.sourceId) case final annotation?)
                          material.ref: annotation.isText
                              ? material.groupTitle
                              : l.noteSourcePage(
                                  content.document(annotation.documentId)?.title ?? material.groupTitle,
                                  annotation.page,
                                ),
                    },
                    quoteColors: {
                      for (final material in widget.materials.highlights)
                        if (content.annotation(material.sourceId) case final annotation?)
                          material.ref: MMAnnotationColor.fromIndex(annotation.colorIndex).color,
                    },
                  )
                : ConstrainedBox(
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
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
