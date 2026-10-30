import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../app/providers.dart';
import '../../shared/l10n.dart';
import '../workspace/workspace_controller.dart';
import 'note_text_source.dart';

String noteTemplateLabel(AppLocalizations l, NoteTemplate template) => switch (template) {
  NoteTemplate.reading => l.noteReading,
  NoteTemplate.cornell => l.noteCornell,
  NoteTemplate.review => l.noteReview,
};

Future<void> showNoteSetupSheet(BuildContext context, WidgetRef ref, String setId, {BranchScope? branch}) =>
    showMMSheet<void>(
      context: context,
      width: MMSizes.noteSetupSheetWidth,
      builder: (_) => NoteSetupSheet(studySetId: setId, branch: branch),
    );

class NoteSetupSheet extends ConsumerStatefulWidget {
  const NoteSetupSheet({super.key, required this.studySetId, this.branch});
  final String studySetId;
  final BranchScope? branch;
  @override
  ConsumerState<NoteSetupSheet> createState() => _NoteSetupSheetState();
}

class _NoteSetupSheetState extends ConsumerState<NoteSetupSheet> {
  late NoteScope _scope;
  late NoteSettings _settings;
  var _template = NoteTemplate.reading;
  var _busy = false, _failed = false;
  late final DateTime _now;
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
  }

  void _set({
    NoteOrganization? organization,
    int? contextSentences,
    bool? marginNotes,
    bool? mapNotes,
    bool? researchNotes,
    bool? images,
  }) => setState(() {
    _settings = NoteSettings(
      organization: organization ?? _settings.organization,
      depth: NoteDepth.none,
      contextSentences: contextSentences ?? _settings.contextSentences,
      completeFragments: false,
      marginNotes: marginNotes ?? _settings.marginNotes,
      mapNotes: mapNotes ?? _settings.mapNotes,
      researchNotes: researchNotes ?? _settings.researchNotes,
      images: images ?? _settings.images,
      mapId: _settings.mapId,
    );
  });

  Future<void> _generate() async {
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
      final note = await owner.organizeStudyNote(title, _scope, _settings, _template, text: text);
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
    );
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
        message: ai ? l.noteNextPhase : label,
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
        actions: [
          MMButton(label: l.cancel, onPressed: _busy ? null : () => Navigator.of(context).pop()),
          MMButton(
            key: const ValueKey('note-generate'),
            label: l.noteGenerate,
            variant: MMButtonVariant.primary,
            onPressed: _busy || all.highlights.isEmpty ? null : _generate,
          ),
        ],
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
                  choice('organization-theme', l.noteTheme, false, null, ai: true),
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
                  choice('depth-none', l.noteLocal, true, null),
                  choice('depth-context', l.noteAiContext, false, null, ai: true),
                  choice('depth-deep', l.noteAiDeep, false, null, ai: true),
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
                      MMCheckbox(value: false, onChanged: null, label: l.noteComplete),
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
