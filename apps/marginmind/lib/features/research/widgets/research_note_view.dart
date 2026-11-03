import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../../../shared/content_input.dart';
import '../../../app/providers.dart';
import '../../assistant/widgets/assistant_conversations.dart' show openConversation;
import '../../workspace/widgets/notices.dart';
import '../../workspace/workspace_controller.dart';
import 'research_widgets.dart';

/// A research note in full (design 4.6 "after saving"): its title and text,
/// edited here for every place it is shown, its citations, the places it is
/// attached to, and Delete.
class ResearchNoteView extends ConsumerWidget {
  const ResearchNoteView({super.key, required this.studySetId, required this.noteId, this.onBack});

  final String studySetId;
  final String noteId;

  /// Shown as "‹ Research" when the note opened from the research panel.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    ref.watch(workspaceContentProvider(studySetId));
    final workspace = ref.read(workspaceProvider(studySetId).notifier);
    final content = workspace.content;
    final note = content.researchNote(noteId);
    final mapId = ref.watch(workspaceProvider(studySetId).select((s) => s.activeMapId));
    if (note == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onBack != null) _Back(onBack: onBack!),
          Expanded(
            child: MMEmptyState(icon: MMIcons.research, title: l.researchNoteGone),
          ),
        ],
      );
    }
    final attachments = [
      for (final a in content.noteAttachments)
        if (a.noteId == note.id) a,
    ];
    final evidence = [
      for (final citation in note.citations) ?content.evidence.where((e) => e.id == citation.evidenceId).firstOrNull,
    ];
    final sources = <ResearchSource>[
      for (final s in content.researchSources)
        if (evidence.any((e) => e.sourceId == s.id)) s,
    ];
    final locale = Localizations.localeOf(context).toLanguageTag();

    Widget section(String label, List<Widget> children) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [ResearchFieldLabel(label), ...children]);

    return ListView(
      padding: const EdgeInsets.fromLTRB(MMSpacing.l, MMSpacing.s, MMSpacing.l, MMSpacing.l),
      children: [
        if (onBack != null) _Back(onBack: onBack!),
        NoteTextField(
          key: ValueKey('note-title-${note.id}'),
          text: note.title,
          input: ContentInput(
            repository: ref.read(contentRepositoryProvider),
            studySetId: studySetId,
            paths: [
              ['researchNotes', note.id],
            ],
            read: (c) => c.researchNote(note.id)?.title,
          ),
          style: t.title3,
          semanticLabel: l.researchNoteTitle,
          onCommit: (text) => workspace.editResearchNote(note.id, title: text),
        ),
        const SizedBox(height: MMSpacing.xxs),
        Text(
          [
            DateFormat.yMd(locale).add_Hm().format(note.updatedAt),
            if (note.edited) l.researchEdited,
            if (note.question.isNotEmpty) note.question,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.footnote.copyWith(color: c.secondaryLabel),
        ),
        const SizedBox(height: MMSpacing.l),
        section(l.researchNoteBody, [
          NoteTextField(
            key: ValueKey('note-body-${note.id}'),
            text: note.body,
            input: ContentInput(
              repository: ref.read(contentRepositoryProvider),
              studySetId: studySetId,
              paths: [
                ['researchNotes', note.id],
              ],
              read: (c) => c.researchNote(note.id)?.body,
            ),
            style: t.body.copyWith(height: 20 / 13),
            multiline: true,
            allowEmpty: true,
            semanticLabel: l.researchNoteBody,
            onCommit: (text) => workspace.editResearchNote(note.id, body: text),
          ),
        ]),
        const SizedBox(height: MMSpacing.l),
        section(l.researchCitationsLabel(sources.length), [
          if (sources.isEmpty)
            Text(l.researchNoExternalBasis, style: t.footnote.copyWith(color: c.secondaryLabel))
          else
            for (final (i, s) in sources.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: MMSpacing.s),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CiteBadge(number: i + 1, title: s.title),
                    const SizedBox(width: MMSpacing.s),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.title, style: t.callout),
                          Text(
                            [
                              Uri.tryParse(s.url)?.host ?? '',

                              if (evidence.any(
                                (e) => e.sourceId == s.id && e.acquisition == EvidenceAcquisition.userPaste,
                              ))
                                l.researchPasted,
                            ].where((v) => v.isNotEmpty).join(' · '),
                            style: t.footnote.copyWith(color: c.secondaryLabel),
                          ),
                          for (final e in evidence)
                            if (e.sourceId == s.id)
                              Padding(
                                padding: const EdgeInsets.only(top: MMSpacing.xs),
                                child: EvidenceQuote(
                                  key: ValueKey('note-quote-${e.id}'),
                                  quote: e.quote,
                                  // Old research sessions open again once they are migrated.
                                  onOpen: null,
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ]),
        const SizedBox(height: MMSpacing.l),
        Row(
          children: [
            MMSwitch(
              key: const ValueKey('research-review-toggle'),
              semanticLabel: l.researchAddReview,
              value: content.researchReviewEnabled(note.id),
              onChanged: (value) => workspace.setResearchReview(note.id, enabled: value),
            ),
            const SizedBox(width: MMSpacing.s),
            Text(l.researchAddReview, style: t.body),
          ],
        ),
        const SizedBox(height: MMSpacing.l),
        section(l.researchPlaces, [
          if (!attachments.any((a) => (a.target is PdfTarget || a.target is TextTarget)))
            Text(l.researchNotInSource, style: t.footnote.copyWith(color: c.secondaryLabel)),
          for (final a in attachments)
            switch (a.target) {
              PdfTarget(:final documentId, :final pages) => _PlaceRow(
                key: ValueKey('place-${a.id}'),
                icon: MMIcons.document,
                label: content.document(documentId) == null
                    ? l.researchOriginGone
                    : l.researchPlaceSource(content.document(documentId)!.title, pages.first.page),
                actions: [
                  if (content.document(documentId) != null)
                    MMButton(
                      label: l.researchLocate,
                      variant: MMButtonVariant.plain,
                      onPressed: () => workspace.revealAnchor(SourceAnchor(target: a.target)),
                    ),
                  MMButton(
                    key: ValueKey('detach-${a.id}'),
                    label: l.researchDetach,
                    variant: MMButtonVariant.plain,
                    onPressed: () => workspace.detachResearchNote(a.id),
                  ),
                ],
              ),
              TextTarget(:final documentId) => _PlaceRow(
                key: ValueKey('place-${a.id}'),
                icon: MMIcons.document,
                label: content.document(documentId)?.title ?? l.researchOriginGone,
                actions: [
                  if (content.document(documentId) != null)
                    MMButton(
                      label: l.researchLocate,
                      variant: MMButtonVariant.plain,
                      onPressed: () => workspace.revealAnchor(SourceAnchor(target: a.target)),
                    ),
                  MMButton(
                    label: l.researchDetach,
                    variant: MMButtonVariant.plain,
                    onPressed: () => workspace.detachResearchNote(a.id),
                  ),
                ],
              ),
              CardTarget(:final cardId) => _PlaceRow(
                key: ValueKey('place-${a.id}'),
                icon: MMIcons.mindMap,
                label: l.researchInMap(
                  content.card(content.node(cardId, mapId: mapId)?.parentId ?? '')?.title ?? l.mainMap,
                ),
                actions: [
                  if (content.node(cardId, mapId: mapId) != null)
                    MMButton(
                      label: l.researchLocate,
                      variant: MMButtonVariant.plain,
                      onPressed: () => workspace.revealAnchor(SourceAnchor(target: a.target, mapId: mapId)),
                    ),
                ],
              ),
            },
        ]),
        const SizedBox(height: MMSpacing.l),
        Wrap(
          spacing: MMSpacing.s,
          runSpacing: MMSpacing.s,
          children: [
            if (note.conversationId case final conversation?)
              MMButton(
                key: const ValueKey('note-open-conversation'),
                label: l.assistantOpenConversation,
                icon: MMIcons.conversation,
                onPressed: () => openConversation(ref, studySetId, conversation),
              ),
            MMButton(
              key: const ValueKey('delete-note'),
              label: l.researchDeleteNote,
              icon: MMIcons.trash,
              onPressed: () async {
                final marks = attachments.where((a) => (a.target is PdfTarget || a.target is TextTarget)).length;
                final cards = content.cards
                    .where(
                      (card) => card.researchNoteId == note.id && card.id != StudySetContent.researchReviewId(note.id),
                    )
                    .length;
                final ok = await showConfirmSheet(
                  context,
                  title: l.researchDeleteTitle,
                  message: l.researchDeleteMessage(marks, cards).trim(),
                  confirmLabel: l.delete,
                );
                if (!ok) return;
                await workspace.deleteResearchNote(note.id);
                onBack?.call();
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _Back extends StatelessWidget {
  const _Back({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: MMButton(
      key: const ValueKey('note-back'),
      label: context.l10n.research,
      icon: MMIcons.chevronLeft,
      variant: MMButtonVariant.plain,
      onPressed: onBack,
    ),
  );
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({super.key, required this.icon, required this.label, required this.actions});

  final IconData icon;
  final String label;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 12, color: context.mmColors.icon),
      const SizedBox(width: MMSpacing.s),
      Expanded(child: Text(label, style: context.mmText.callout)),
      ...actions,
    ],
  );
}

/// Text edited where it is shown. Enter (⇧Enter for a new line when
/// [multiline]) or leaving the field keeps it; Esc puts the stored text back.
class NoteTextField extends StatefulWidget {
  const NoteTextField({
    super.key,
    required this.text,
    required this.style,
    required this.onCommit,
    required this.semanticLabel,
    this.multiline = false,
    this.allowEmpty = false,
    this.input,
  });

  final String text;
  final TextStyle style;
  final Future<void> Function(String text) onCommit;
  final String semanticLabel;
  final bool multiline;
  final bool allowEmpty;
  final ContentInput<String>? input;

  @override
  State<NoteTextField> createState() => _NoteTextFieldState();
}

class _NoteTextFieldState extends State<NoteTextField> {
  late final _controller = TextEditingController(text: widget.text);
  final _focus = FocusNode(debugLabel: 'NoteTextField');
  ContentInputSession<String>? _session;
  bool _opening = false, _saving = false, _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _begin();
      } else {
        _commit();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(NoteTextField old) {
    super.didUpdateWidget(old);
    // Undo or an edit made elsewhere changed the note.
    if (!_editing && !_opening && !_saving && widget.text != _controller.text) _controller.text = widget.text;
  }

  Future<void> _begin() async {
    if (_editing || _opening || _saving) return;
    if (widget.input?.requiresProtection != true) {
      _editing = true;
      return;
    }
    _opening = true;
    try {
      final session = await widget.input!.open();
      if (!mounted || !_focus.hasFocus) {
        await session.close();
        return;
      }
      _session = session;
      _controller.text = session.value;
      _editing = true;
    } catch (_) {
      if (mounted) {
        _focus.unfocus();
        MMHud.show(context, context.l10n.noteFailed);
      }
    } finally {
      _opening = false;
      if (mounted) setState(() {});
    }
  }

  String get _text => widget.multiline ? _controller.text.trimRight() : _controller.text.trim();
  bool _changes(String text) => text != (_session?.value ?? widget.text) && (text.isNotEmpty || widget.allowEmpty);

  Future<void> _commit() async {
    if (!_editing || _saving) return;
    _saving = true;
    if (mounted) setState(() {});
    try {
      final text = _text, save = widget.onCommit;
      if (_changes(text)) {
        if (_session case final session?) {
          await session.save(() => save(text));
        } else {
          await save(text);
        }
      } else {
        _controller.text = _session?.value ?? widget.text;
      }
      _editing = false;
      final session = _session;
      _session = null;
      await session?.close();
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.noteFailed);
    } finally {
      _saving = false;
      if (mounted) {
        setState(() {});
        if (_focus.hasFocus && !_editing) unawaited(_begin());
      }
    }
  }

  void _cancel() {
    if (_saving) return;
    _controller.text = _session?.value ?? widget.text;
    _editing = false;
    final session = _session;
    _session = null;
    _focus.unfocus();
    unawaited(session?.close());
  }

  @override
  void dispose() {
    // A save that already started keeps its lease until persistence completes.
    unawaited(_session?.close());
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xs, vertical: MMSpacing.xxs),
      decoration: BoxDecoration(
        color: _focus.hasFocus ? c.quaternaryFill : null,
        borderRadius: BorderRadius.circular(MMRadii.excerpt),
      ),
      child: MMInlineTextField(
        controller: _controller,
        readOnly: _saving || (widget.input?.requiresProtection == true && !_editing),
        focusNode: _focus,
        style: widget.style,
        multiline: widget.multiline,
        semanticLabel: widget.semanticLabel,
        onSubmitted: _focus.unfocus,
        onCancel: _cancel,
      ),
    );
  }
}
