import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_research/mm_research.dart';

import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import '../../workspace/workspace_controller.dart';
import '../research_answer.dart';
import '../research_controller.dart';
import '../research_drafts.dart';
import '../research_origin.dart';
import '../research_providers.dart';
import 'research_widgets.dart';

/// Where a research note goes.
enum NoteDestination { both, source, map }

/// Opens the save form for [points] of an answer, [clips] taken from sources,
/// or a source that could only be kept as a link ([linkOnly]).
Future<void> showSaveNoteSheet(
  BuildContext context, {
  required String studySetId,
  required String sessionId,
  List<AnswerPoint> points = const [],
  List<ResearchClip> clips = const [],
  ResearchSource? linkOnly,
}) => showMMSheet<void>(
  context: context,
  width: 520,
  builder: (_) =>
      SaveNoteSheet(studySetId: studySetId, sessionId: sessionId, points: points, clips: clips, linkOnly: linkOnly),
);

/// The save form (design 4.6): title, text, citations, where to save (source
/// and map, source only, map only), where in the map, splitting points into
/// cards. Saving is one undo step; a second click cannot save twice.
class SaveNoteSheet extends ConsumerStatefulWidget {
  const SaveNoteSheet({
    super.key,
    required this.studySetId,
    required this.sessionId,
    this.points = const [],
    this.clips = const [],
    this.linkOnly,
  });

  final String studySetId;
  final String sessionId;
  final List<AnswerPoint> points;
  final List<ResearchClip> clips;
  final ResearchSource? linkOnly;

  @override
  ConsumerState<SaveNoteSheet> createState() => _SaveNoteSheetState();
}

class _SaveNoteSheetState extends ConsumerState<SaveNoteSheet> {
  /// Fixed when the form opens: saving it again changes nothing.
  final _noteId = newId();
  late final ResearchSessionState _value = ref
      .read(researchSessionProvider((studySetId: widget.studySetId, sessionId: widget.sessionId)))
      .requireValue;
  late final List<String> _texts = [
    for (final p in widget.points) _value.drafts.edits[p.key] ?? p.text,
    for (final c in widget.clips) '“${c.evidence.quote}”',
    if (widget.linkOnly case final s?) '${s.title}\n${s.url}',
  ];
  late final String _defaultBody = _texts.join('\n');
  late final _title = TextEditingController(text: _defaultTitle());
  late final _body = TextEditingController(text: _defaultBody);
  late NoteDestination _destination;
  String? _parentId;
  bool _split = false;
  bool _saving = false;

  WorkspaceController get _workspace => ref.read(workspaceProvider(widget.studySetId).notifier);

  /// The source passage the research started from, if it still exists.
  PdfTarget? get _source {
    final target = _value.session.anchor?.target;
    if (target is! PdfTarget) return null;
    final doc = _workspace.content.document(target.documentId);
    if (doc == null || target.pages.any((p) => p.page < 1 || p.page > doc.pageCount)) return null;
    return target;
  }

  @override
  void initState() {
    super.initState();
    _destination = _source != null ? NoteDestination.both : NoteDestination.map;
    _parentId = _defaultParent();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// The first point's first clause, else the first clip, else the link.
  String _defaultTitle() {
    final first = _texts.firstOrNull ?? '';
    final clause = first
        .replaceAll('“', '')
        .split(RegExp(r'[：:，,。；;\n]'))
        .firstWhere((p) => p.trim().isNotEmpty, orElse: () => first);
    final text = clause.trim();
    return text.runes.length <= 24 ? text : String.fromCharCodes(text.runes.take(24));
  }

  /// From a node: that node. From a page: the branch holding that page's
  /// excerpts, else where a new excerpt would go.
  String? _defaultParent() {
    final content = _workspace.content;
    final mapId = ref.read(workspaceProvider(widget.studySetId)).activeMapId;
    final anchor = _value.session.anchor;
    switch (anchor?.target) {
      case CardTarget(:final cardId) when content.node(cardId, mapId: mapId) != null:
        return cardId;
      case PdfTarget(:final documentId, :final pages):
        for (final card in content.cards) {
          final a = content.annotation(card.annotationId ?? '');
          if (a == null || a.documentId != documentId || a.page != pages.first.page) continue;
          final node = content.node(card.id, mapId: mapId);
          if (node != null) return node.parentId;
        }
      default:
    }
    return _workspace.excerptTargetId;
  }

  List<Evidence> get _evidence {
    final byId = <String, Evidence>{};
    for (final p in widget.points) {
      for (final cite in p.cites) {
        if (cite.evidenceId != null) {
          final e = _value.evidence.where((e) => e.id == cite.evidenceId).firstOrNull;
          if (e != null) byId[e.id] = e;
        } else {
          for (final e in _value.evidence) {
            if (e.sourceId == cite.sourceId) byId[e.id] = e;
          }
        }
      }
    }
    for (final c in widget.clips) {
      byId[c.evidence.id] = c.evidence;
    }
    return byId.values.toList();
  }

  String _path(StudySetContent content, String? cardId, String mapId) {
    final l = context.l10n;
    final root = content.map(mapId)?.title.isNotEmpty ?? false
        ? content.map(mapId)!.title
        : (ref.read(studySetProvider(widget.studySetId))?.title ?? l.mainMap);
    final titles = <String>[];
    var id = cardId;
    final seen = <String>{};
    while (id != null && seen.add(id)) {
      titles.insert(0, researchCardTitle(content, id));
      id = content.node(id, mapId: mapId)?.parentId;
    }
    return [root, ...titles].join(' › ');
  }

  void _pickParent(Offset position) {
    final content = _workspace.content;
    final mapId = ref.read(workspaceProvider(widget.studySetId)).activeMapId;
    final topics = [
      for (final n in content.nodes)
        if (n.mapId == mapId && content.card(n.cardId)?.kind == CardKind.topic) n.cardId,
    ];
    showMMMenu(
      context,
      position: position,
      entries: [
        MMMenuItem(_path(content, null, mapId), () => setState(() => _parentId = null)),
        for (final id in topics) MMMenuItem(_path(content, id, mapId), () => setState(() => _parentId = id)),
      ],
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final l = context.l10n;
    final title = _title.text.trim().isEmpty ? l.researchNoteDefaultTitle : _title.text.trim();
    setState(() => _saving = true);
    final evidence = _evidence;
    final sources = [
      for (final s in _value.sources)
        if (evidence.any((e) => e.sourceId == s.id)) s,
    ];
    final edited = widget.points.any((p) => _value.drafts.edits.containsKey(p.key)) || _body.text != _defaultBody;
    final origin = widget.linkOnly != null
        ? NoteOrigin.user
        : widget.points.isNotEmpty && widget.clips.isNotEmpty
        ? NoteOrigin.mixed
        : widget.clips.isNotEmpty
        ? (edited ? NoteOrigin.mixed : NoteOrigin.excerpt)
        : (edited ? NoteOrigin.mixed : NoteOrigin.ai);
    final now = ref.read(clockProvider)();
    final note = ResearchNote(
      id: _noteId,
      title: title,
      body: _body.text.trim(),
      question: _value.session.question,
      sessionId: _value.session.id,
      citations: [for (final e in evidence) EvidenceRef(e.id)],
      origin: origin,
      edited: edited,
      createdAt: now,
      updatedAt: now,
    );
    final toMap = _destination != NoteDestination.source;
    final layout = ref.read(workspaceProvider(widget.studySetId)).layout;
    final navigator = Navigator.of(context);
    final hud = navigator.context;
    try {
      final saved = await _workspace.saveResearchNote(
        note,
        source: _destination == NoteDestination.map ? null : _source,
        toMap: toMap,
        cardParentId: _parentId,
        splitPoints: toMap && _split && _texts.length > 1 ? _texts : const [],
        evidence: evidence,
        sources: sources,
      );
      await ref
          .read(researchPanelProvider(widget.studySetId).notifier)
          .saved(
            widget.sessionId,
            points: {for (final p in widget.points) p.key},
            clips: {for (final c in widget.clips) c.evidence.id},
          );
      if (navigator.mounted) navigator.pop();
      if (saved == null || !hud.mounted) return;
      final message = switch (_destination) {
        NoteDestination.both => l.researchSavedBoth,
        NoteDestination.source => l.researchSavedSource,
        NoteDestination.map => l.researchSavedMap,
      };
      // The map put aside: offer to show the card rather than switching.
      final mapHidden = toMap && layout == MMSplitMode.primary;
      MMHud.show(
        hud,
        message,
        action: mapHidden
            ? (l.researchShowInMap, () => unawaited(_workspace.locateNoteCard(note.id)))
            : (l.undo, () => unawaited(_workspace.undo())),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        MMHud.show(context, l.somethingWentWrong, icon: MMIcons.close);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final content = ref.watch(workspaceContentProvider(widget.studySetId)) ?? _workspace.content;
    final mapId = ref.watch(workspaceProvider(widget.studySetId).select((s) => s.activeMapId));
    final evidence = _evidence;
    final citedSources = [
      for (final s in _value.sources)
        if (evidence.any((e) => e.sourceId == s.id)) s,
    ];
    final source = _source;
    final noSourceReason = _value.session.anchor?.target is PdfTarget ? l.researchOriginGone : l.researchDestNoSource;
    return MMSheet(
      title: l.researchSaveTitle,
      actions: [
        MMButton(label: l.cancel, onPressed: _saving ? null : () => Navigator.of(context).pop()),
        MMButton(
          key: const ValueKey('save-note-confirm'),
          label: _saving ? l.researchSaving : l.save,
          variant: MMButtonVariant.primary,
          color: c.research,
          onPressed: _saving ? null : _save,
        ),
      ],
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.62),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ResearchFieldLabel(l.researchNoteTitle),
              MMTextField(
                key: const ValueKey('save-note-title'),
                controller: _title,
                semanticLabel: l.researchNoteTitle,
              ),
              const SizedBox(height: MMSpacing.m),
              ResearchFieldLabel(l.researchNoteBody),
              MMTextField(
                key: const ValueKey('save-note-body'),
                controller: _body,
                maxLines: 8,
                minLines: 3,
                semanticLabel: l.researchNoteBody,
              ),
              const SizedBox(height: MMSpacing.m),
              ResearchFieldLabel(l.researchCitationsLabel(citedSources.length)),
              if (citedSources.isEmpty)
                Text(l.researchNoExternalBasis, style: t.footnote.copyWith(color: c.secondaryLabel))
              else
                for (final s in citedSources)
                  Padding(
                    padding: const EdgeInsets.only(bottom: MMSpacing.xs),
                    child: Row(
                      children: [
                        CiteBadge(number: _value.numberOf(s.id), title: s.title),
                        const SizedBox(width: MMSpacing.s),
                        Expanded(
                          child: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.callout),
                        ),
                        MMPill(readState(context, s.readState).$1, color: readState(context, s.readState).$2),
                      ],
                    ),
                  ),
              const SizedBox(height: MMSpacing.m),
              ResearchFieldLabel(l.researchSaveTo),
              ResearchRadio(
                key: const ValueKey('dest-both'),
                selected: _destination == NoteDestination.both,
                label: l.researchDestBoth,
                badge: source != null ? l.researchRecommended : null,
                detail: source == null ? noSourceReason : null,
                onTap: source == null ? null : () => setState(() => _destination = NoteDestination.both),
              ),
              ResearchRadio(
                key: const ValueKey('dest-source'),
                selected: _destination == NoteDestination.source,
                label: l.researchDestSource,
                detail: source == null ? noSourceReason : null,
                onTap: source == null ? null : () => setState(() => _destination = NoteDestination.source),
              ),
              ResearchRadio(
                key: const ValueKey('dest-map'),
                selected: _destination == NoteDestination.map,
                label: l.researchDestMap,
                onTap: () => setState(() => _destination = NoteDestination.map),
              ),
              if (_destination != NoteDestination.source) ...[
                const SizedBox(height: MMSpacing.s),
                ResearchFieldLabel(l.researchAttachUnder),
                Builder(
                  builder: (context) => MMInteractive(
                    key: const ValueKey('save-note-parent'),
                    semanticLabel: l.researchAttachUnder,
                    onTap: () {
                      final box = context.findRenderObject() as RenderBox;
                      _pickParent(box.localToGlobal(Offset(0, box.size.height)));
                    },
                    builder: (context, s) => Container(
                      height: MMSizes.field,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: s.hovered ? c.fill : c.quaternaryFill,
                        borderRadius: BorderRadius.circular(MMRadii.field),
                      ),
                      child: Row(
                        children: [
                          Icon(MMIcons.mindMap, size: 12, color: c.icon),
                          const SizedBox(width: MMSpacing.s),
                          Expanded(
                            child: Text(
                              _path(content, _parentId, mapId),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.body,
                            ),
                          ),
                          Icon(MMIcons.popUp, size: 11, color: c.icon),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_texts.length > 1) ...[
                  const SizedBox(height: MMSpacing.s),
                  MMCheckbox(
                    key: const ValueKey('save-note-split'),
                    value: _split,
                    color: c.research,
                    label: l.researchSplitPoints(_texts.length),
                    onChanged: (v) => setState(() => _split = v),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
