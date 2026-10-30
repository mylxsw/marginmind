import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../app/providers.dart';
import '../../shared/l10n.dart';
import '../workspace/workspace_controller.dart';
import 'note_text_source.dart';
import 'note_organize_sheet.dart';
import 'note_session.dart';
import '../assistant/assistant_settings.dart';
import '../../settings/settings_window.dart';

String noteTemplateLabel(AppLocalizations l, NoteTemplate template) => switch (template) {
  NoteTemplate.reading => l.noteReading,
  NoteTemplate.cornell => l.noteCornell,
  NoteTemplate.review => l.noteReview,
};

class _NoteGenerationRequest {
  const _NoteGenerationRequest(this.title, this.scope, this.settings, this.template, this.materials, this.preview);
  final String title;
  final NoteScope scope;
  final NoteSettings settings;
  final NoteTemplate template;
  final NoteMaterials materials;
  final bool preview;
}

Future<void> showNoteSetupSheet(
  BuildContext context,
  WidgetRef ref,
  String setId, {
  BranchScope? branch,
  String? existingId,
}) async {
  final request = await showMMSheet<_NoteGenerationRequest>(
    context: context,
    width: MMSizes.noteSetupSheetWidth,
    builder: (_) => NoteSetupSheet(studySetId: setId, branch: branch, existingId: existingId),
  );
  if (request == null || !context.mounted) return;
  await showNoteOrganizeSheet(
    context,
    setId: setId,
    title: request.title,
    scope: request.scope,
    settings: request.settings,
    template: request.template,
    materials: request.materials,
    previewOutline: request.preview,
    existingId: existingId,
  );
}

/// Reuse the current outline and protect edits when reorganizing an existing note.
Future<void> showNoteReorganization(BuildContext context, WidgetRef ref, String setId, String noteId) async {
  final owner = ref.read(workspaceProvider(setId).notifier);
  final note = owner.content.studyNote(noteId);
  if (note == null) return;
  final text = await loadNoteTextSource(ref, setId, owner.content, note.scope);
  if (!context.mounted) return;
  final materials = const NoteMaterialCollector().collect(
    owner.content,
    note.scope,
    note.settings,
    now: ref.read(clockProvider)(),
    text: text,
  );
  final assigned = <String>{};
  final outline = <NoteOutlineSection>[];
  for (final section in note.sections) {
    final refs = <String>[];
    for (final block in section.blocks) {
      final material = materials.items
          .where(
            (m) => switch (block) {
              QuoteBlock() => m.isHighlight && m.sourceId == block.annotationId,
              OwnBlock() => m.source == block.source && m.sourceId == block.sourceId,
              _ => false,
            },
          )
          .firstOrNull;
      if (material != null && assigned.add(material.ref)) refs.add(material.ref);
    }
    if (refs.isNotEmpty) outline.add(NoteOutlineSection(title: section.title, why: section.why, refs: refs));
  }
  final remaining = NoteMaterials(
    materials.items.where((m) => !assigned.contains(m.ref)).toList(),
    collectedAt: materials.collectedAt,
    catalog: materials.catalog,
  );
  outline.addAll((await const LocalNoteOrganizer().outline(remaining, note.settings)).sections);
  if (!context.mounted) return;
  await resumeNoteOrganization(
    context,
    NoteContinuation(
      setId: setId,
      title: note.title,
      scope: note.scope,
      settings: note.settings,
      template: note.template,
      materials: materials,
      outline: NoteOutline(outline),
      draft: NoteDraft([]),
      noteId: noteId,
    ),
  );
}

class NoteSetupSheet extends ConsumerStatefulWidget {
  const NoteSetupSheet({super.key, required this.studySetId, this.branch, this.existingId});
  final String studySetId;
  final BranchScope? branch;
  final String? existingId;
  @override
  ConsumerState<NoteSetupSheet> createState() => _NoteSetupSheetState();
}

class _NoteSetupSheetState extends ConsumerState<NoteSetupSheet> {
  late NoteScope _scope;
  late NoteSettings _settings;
  var _template = NoteTemplate.reading;
  var _busy = false, _failed = false;
  late final DateTime _now;
  bool _ai = false;
  NoteSettings? _remembered;
  NoteDepth _lastAiDepth = NoteDepth.deep;
  NoteTextSource _text = const NoteTextSource();
  Future<void> _configure() async {
    final ready = await ref.read(assistantConfiguredProvider.future);
    if (!mounted) return;
    final owner = ref.read(workspaceProvider(widget.studySetId).notifier);
    final text = await loadNoteTextSource(ref, widget.studySetId, owner.content, const WholeSet());
    if (!mounted) return;
    setState(() {
      _ai = ready;
      _text = text;
      if (ready) {
        final depth = _remembered?.depth ?? NoteDepth.deep;
        _lastAiDepth = depth == NoteDepth.none ? NoteDepth.deep : depth;
        _set(
          depth: depth,
          organization: widget.branch != null
              ? NoteOrganization.map
              : depth == NoteDepth.none
              ? NoteOrganization.source
              : NoteOrganization.theme,
          completeFragments: _remembered?.completeFragments ?? true,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _now = ref.read(clockProvider)();
    final state = ref.read(workspaceProvider(widget.studySetId));
    _scope =
        widget.branch ??
        (state.selectedAnnotationIds.isEmpty
            ? const WholeSet()
            : SelectedAnnotations(state.selectedAnnotationIds.toList()));
    NoteSettings? remembered;
    try {
      final stored = ref.read(sharedPreferencesProvider).getString('studyNotes.settings');
      if (stored != null) remembered = NoteSettings.fromJson((jsonDecode(stored) as Map).cast());
    } catch (_) {
      // Preferences from an incompatible version must not prevent local notes.
    }
    _remembered = remembered;
    _settings = NoteSettings(
      organization: widget.branch != null
          ? NoteOrganization.map
          : remembered?.effectiveOrganization == NoteOrganization.map
          ? NoteOrganization.map
          : NoteOrganization.source,
      depth: NoteDepth.none,
      contextSentences: remembered?.contextSentences ?? 1,
      completeFragments: false,
      marginNotes: remembered?.marginNotes ?? true,
      mapNotes: remembered?.mapNotes ?? true,
      researchNotes: remembered?.researchNotes ?? false,
      images: remembered?.images ?? false,
      mapId: state.activeMapId,
    );
    final existing = state.content?.studyNote(widget.existingId ?? '');
    if (existing != null) {
      _scope = existing.scope;
      _template = existing.template;
      _remembered = existing.settings;
    }
    _configure();
  }

  void _set({
    NoteOrganization? organization,
    NoteDepth? depth,
    bool? completeFragments,
    int? contextSentences,
    bool? marginNotes,
    bool? mapNotes,
    bool? researchNotes,
    bool? images,
  }) => setState(() {
    var nextDepth = depth ?? _settings.depth;
    var nextOrganization = organization ?? _settings.organization;
    if (organization == NoteOrganization.theme && nextDepth == NoteDepth.none) nextDepth = _lastAiDepth;
    if (nextDepth == NoteDepth.none && nextOrganization == NoteOrganization.theme) {
      nextOrganization = NoteOrganization.source;
    }
    if (nextDepth != NoteDepth.none) _lastAiDepth = nextDepth;
    _settings = NoteSettings(
      organization: nextOrganization,
      depth: nextDepth,
      contextSentences: contextSentences ?? _settings.contextSentences,
      completeFragments: completeFragments ?? _settings.completeFragments,
      marginNotes: marginNotes ?? _settings.marginNotes,
      mapNotes: mapNotes ?? _settings.mapNotes,
      researchNotes: researchNotes ?? _settings.researchNotes,
      images: images ?? _settings.images,
      mapId: _settings.mapId,
    );
  });

  Future<void> _generate({bool preview = false}) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final l = context.l10n;
    try {
      final owner = ref.read(workspaceProvider(widget.studySetId).notifier);
      final text = await loadNoteTextSource(ref, widget.studySetId, owner.content, _scope);
      if (!mounted) return;
      final title = ref.read(studySetProvider(widget.studySetId))?.title ?? l.noteReading;
      await ref.read(sharedPreferencesProvider).setString('studyNotes.settings', jsonEncode(_settings.toJson()));
      if (_settings.depth != NoteDepth.none) {
        final materials = const NoteMaterialCollector().collect(
          owner.content,
          _scope,
          _settings,
          now: _now,
          text: text,
        );
        if (!mounted) return;
        Navigator.of(context).pop(_NoteGenerationRequest(title, _scope, _settings, _template, materials, preview));
        return;
      }
      StudyNote? note;
      if (widget.existingId != null) {
        final materials = const NoteMaterialCollector().collect(
          owner.content,
          _scope,
          _settings,
          now: _now,
          text: text,
        );
        const local = LocalNoteOrganizer();
        final outline = await local.outline(materials, _settings);
        final draft = await local.write(materials, outline, _settings);
        note = await owner.acceptNoteDraft(
          title,
          _scope,
          _settings,
          _template,
          materials,
          draft,
          existingId: widget.existingId,
          local: true,
        );
      } else {
        note = await owner.organizeStudyNote(title, _scope, _settings, _template, text: text);
      }
      if (note == null) throw StateError('Empty scope');
      await ref.read(sharedPreferencesProvider).setString('studyNotes.settings', jsonEncode(_settings.toJson()));
      if (!mounted) return;
      Navigator.of(context).pop();
      MMHud.show(context, l.noteGenerated);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final content = ref.watch(workspaceContentProvider(widget.studySetId));
    if (content == null) return const SizedBox.shrink();
    final state = ref.read(workspaceProvider(widget.studySetId));
    final all = const NoteMaterialCollector().collect(
      content,
      _scope,
      NoteSettings(
        depth: NoteDepth.none,
        marginNotes: true,
        mapNotes: true,
        researchNotes: true,
        images: true,
        mapId: _settings.mapId,
      ),
      now: _now,
      text: _text,
    );
    final sending = const NoteMaterialCollector().collect(content, _scope, _settings, now: _now, text: _text);
    int count(NoteScope scope) =>
        const NoteMaterialCollector().collect(content, scope, _settings, now: _now).highlights.length;
    Widget choice(
      String key,
      String label,
      bool selected,
      VoidCallback? action, {
      bool ai = false,
      NoteTemplate? thumbnail,
    }) {
      final button = MMButton(
        key: ValueKey(key),
        label: label,
        variant: selected ? MMButtonVariant.primary : MMButtonVariant.secondary,
        onPressed: _busy ? null : action,
      );
      return Tooltip(
        message: ai && !_ai ? l.noteAiUnavailable : label,
        child: thumbnail == null
            ? button
            : SizedBox(
                width: MMSizes.noteTemplateCardWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MMInteractive(
                      onTap: _busy ? null : action,
                      semanticLabel: label,
                      builder: (_, _) => Container(
                        height: MMSizes.noteFormThumbHeight,
                        padding: const EdgeInsets.all(MMSpacing.s),
                        decoration: BoxDecoration(
                          color: selected ? c.accentTint : c.card,
                          borderRadius: BorderRadius.circular(MMRadii.row),
                          border: Border.all(color: selected ? c.accent : c.separator),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (thumbnail == NoteTemplate.cornell) ...[
                              Expanded(
                                child: Column(
                                  children: [
                                    for (var i = 0; i < 3; i++)
                                      Padding(
                                        padding: const EdgeInsets.all(MMSpacing.xxs),
                                        child: Container(height: MMSpacing.xxs, color: c.secondaryLabel),
                                      ),
                                  ],
                                ),
                              ),
                              VerticalDivider(color: c.separator),
                            ],
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(height: MMSpacing.xs, color: c.label),
                                  const SizedBox(height: MMSpacing.s),
                                  for (var i = 0; i < 3; i++)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: MMSpacing.xs),
                                      child: Container(
                                        height: MMSpacing.xxs,
                                        color: thumbnail == NoteTemplate.review
                                            ? c.separator
                                            : MMAnnotationColor.yellow.color,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: MMSpacing.xs),
                    button,
                  ],
                ),
              ),
      );
    }

    Widget row(String label, List<Widget> children) {
      final choices = Wrap(spacing: MMSpacing.s, runSpacing: MMSpacing.s, children: children);
      return MediaQuery.sizeOf(context).width < MMSizeClass.compactMaxWidth
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: MMSpacing.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(label, style: context.mmText.subheadline),
                  const SizedBox(height: MMSpacing.s),
                  choices,
                ],
              ),
            )
          : MMFormRow(label: label, child: choices);
    }

    Widget scope(String key, String label, NoteScope value) => choice(
      key,
      '$label ${count(value)}',
      jsonEncode(_scope.toJson()) == jsonEncode(value.toJson()),
      () => setState(() => _scope = value),
    );
    Widget material(String key, String label, OwnSource source, bool value, ValueChanged<bool> change) {
      final n = all.items.where((m) => m.source == source).length;
      return choice(key, '$label $n', value && n > 0, n == 0 ? null : () => change(!value));
    }

    return PopScope(
      canPop: !_busy,
      child: MMSheet(
        title: l.noteSetupTitle,
        actions: noteSheetActions(context, [
          MMButton(label: l.cancel, onPressed: _busy ? null : () => Navigator.of(context).pop()),
          if (_ai && _settings.depth != NoteDepth.none && _settings.organization == NoteOrganization.theme)
            MMButton(
              key: const ValueKey('note-preview-outline'),
              label: l.notePreviewOutline,
              onPressed: _busy || all.highlights.isEmpty ? null : () => _generate(preview: true),
            ),
          MMButton(
            key: const ValueKey('note-generate'),
            label: l.noteGenerate,
            variant: MMButtonVariant.primary,
            onPressed: _busy || all.highlights.isEmpty ? null : () => _generate(),
          ),
        ]),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .65),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                row(l.noteScope, [
                  scope('scope-selected', l.noteSelected, SelectedAnnotations(state.selectedAnnotationIds.toList())),
                  scope('scope-whole', l.noteWhole, const WholeSet()),
                  if (state.activeDocumentId case final id?)
                    scope('scope-document', content.document(id)?.title ?? '', DocumentScope(id)),
                  scope('scope-recent', l.noteRecent, SinceScope(_now.subtract(const Duration(days: 7)))),
                  if (widget.branch case final branch?)
                    scope('scope-branch', content.card(branch.nodeId)?.title ?? '', branch),
                ]),
                row(l.noteMaterials, [
                  choice('material-highlights', '${l.noteHighlights} ${all.highlights.length}', true, null),
                  material(
                    'material-margin',
                    l.noteOwn,
                    OwnSource.marginNote,
                    _settings.marginNotes,
                    (v) => _set(marginNotes: v),
                  ),
                  material(
                    'material-map',
                    l.noteMapNotes,
                    OwnSource.card,
                    _settings.mapNotes,
                    (v) => _set(mapNotes: v),
                  ),
                  material(
                    'material-ai',
                    l.noteSavedAi,
                    OwnSource.researchNote,
                    _settings.researchNotes,
                    (v) => _set(researchNotes: v),
                  ),
                  material('material-image', l.noteImages, OwnSource.image, _settings.images, (v) => _set(images: v)),
                ]),
                row(l.noteOrganization, [
                  choice(
                    'organization-theme',
                    l.noteTheme,
                    _settings.organization == NoteOrganization.theme,
                    _ai ? () => _set(organization: NoteOrganization.theme) : null,
                    ai: true,
                  ),
                  choice(
                    'organization-source',
                    l.noteSourceOrder,
                    _settings.organization == NoteOrganization.source,
                    () => _set(organization: NoteOrganization.source),
                  ),
                  choice(
                    'organization-map',
                    l.noteMapOrder,
                    _settings.organization == NoteOrganization.map,
                    () => _set(organization: NoteOrganization.map),
                  ),
                ]),
                row(l.noteDepth, [
                  choice(
                    'depth-none',
                    l.noteLocal,
                    _settings.depth == NoteDepth.none,
                    () => _set(depth: NoteDepth.none),
                  ),
                  choice(
                    'depth-context',
                    l.noteAiContext,
                    _settings.depth == NoteDepth.context,
                    _ai ? () => _set(depth: NoteDepth.context) : null,
                    ai: true,
                  ),
                  choice(
                    'depth-deep',
                    l.noteAiDeep,
                    _settings.depth == NoteDepth.deep,
                    _ai ? () => _set(depth: NoteDepth.deep) : null,
                    ai: true,
                  ),
                ]),
                MMFormRow(
                  label: l.noteContext,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Slider(
                        key: const ValueKey('note-context-slider'),
                        value: _settings.contextSentences.toDouble(),
                        min: 0,
                        max: 3,
                        divisions: 3,
                        label: l.noteContextSentences(_settings.contextSentences),
                        onChanged: _busy ? null : (v) => _set(contextSentences: v.round()),
                      ),
                      Text(l.noteContextSentences(_settings.contextSentences), style: context.mmText.footnote),
                      const SizedBox(height: MMSpacing.s),
                      MMCheckbox(
                        value: _ai && _settings.depth != NoteDepth.none && _settings.completeFragments,
                        onChanged: _ai && _settings.depth != NoteDepth.none ? (v) => _set(completeFragments: v) : null,
                        label: l.noteComplete,
                      ),
                    ],
                  ),
                ),
                row(l.noteTemplate, [
                  for (final t in NoteTemplate.values)
                    choice(
                      'template-${t.name}',
                      noteTemplateLabel(l, t),
                      _template == t,
                      () => setState(() => _template = t),
                      thumbnail: t,
                    ),
                ]),
                if (!_ai)
                  MMButton(
                    label: l.assistantOpenSettings,
                    onPressed: () async {
                      await showSettings(context, tab: SettingsTab.models);
                      if (mounted) _configure();
                    },
                  ),
                if (_ai && _settings.depth != NoteDepth.none && all.highlights.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(MMSpacing.m),
                    child: Text(
                      l.noteSending(
                        sending.highlights.length,
                        sending.items.length - sending.highlights.length,
                        sending.items.fold<int>(
                          0,
                          (n, m) =>
                              n + m.text.runes.length + m.context.before.runes.length + m.context.after.runes.length,
                        ),
                        ref.watch(assistantDefaultModelProvider)?.model ?? '',
                      ),
                      style: context.mmText.footnote,
                    ),
                  ),
                if (all.highlights.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(MMSpacing.l),
                    child: Text(l.noteEmptyScope, style: context.mmText.body.copyWith(color: c.secondaryLabel)),
                  ),
                if (_busy) const LinearProgressIndicator(),
                if (_failed) Text(l.noteFailed, style: context.mmText.body.copyWith(color: c.critical)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
