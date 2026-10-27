import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../../workspace/widgets/notices.dart';
import '../../workspace/workspace_controller.dart';
import '../research_controller.dart';
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
    final panel = ref.read(researchPanelProvider(studySetId).notifier);

    Widget section(String label, List<Widget> children) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [ResearchFieldLabel(label), ...children]);

    return ListView(
      padding: const EdgeInsets.fromLTRB(MMSpacing.l, MMSpacing.s, MMSpacing.l, MMSpacing.l),
      children: [
        if (onBack != null) _Back(onBack: onBack!),
        NoteTextField(
          key: ValueKey('note-title-${note.id}'),
          text: note.title,
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
                              l.researchFetchedAt(DateFormat.yMd(locale).format(s.fetchedAt)),
                              if (evidence.any(
                                (e) => e.sourceId == s.id && e.acquisition == EvidenceAcquisition.userPaste,
                              ))
                                l.researchPasted,
                            ].where((v) => v.isNotEmpty).join(' · '),
                            style: t.footnote.copyWith(color: c.secondaryLabel),
                          ),
                          for (final e in evidence)
                            if (e.sourceId == s.id)
                              Container(
                                margin: const EdgeInsets.only(top: MMSpacing.xs),
                                padding: const EdgeInsets.only(left: MMSpacing.s),
                                decoration: BoxDecoration(
                                  border: Border(left: BorderSide(color: c.research, width: 2)),
                                ),
                                child: Text(
                                  e.quote,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.readingExcerpt,
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
        section(l.researchPlaces, [
          if (!attachments.any((a) => a.target is PdfTarget))
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
                      onPressed: () => workspace.revealNoteInSource(note.id),
                    ),
                  MMButton(
                    key: ValueKey('detach-${a.id}'),
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
                      onPressed: () => workspace.locateNoteCard(note.id),
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
            if (note.sessionId != null)
              MMButton(
                label: l.researchOpenResearch,
                icon: MMIcons.research,
                onPressed: () => panel.show(note.sessionId!, tab: ResearchTab.saved),
              ),
            MMButton(
              key: const ValueKey('delete-note'),
              label: l.researchDeleteNote,
              icon: MMIcons.trash,
              onPressed: () async {
                final marks = attachments.where((a) => a.target is PdfTarget).length;
                final cards = content.cards.where((card) => card.researchNoteId == note.id).length;
                final ok = await showConfirmSheet(
                  context,
                  title: l.researchDeleteTitle,
                  message: l.researchDeleteMessage(marks, cards),
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
  });

  final String text;
  final TextStyle style;
  final Future<void> Function(String text) onCommit;
  final String semanticLabel;
  final bool multiline;
  final bool allowEmpty;

  @override
  State<NoteTextField> createState() => _NoteTextFieldState();
}

class _NoteTextFieldState extends State<NoteTextField> {
  late final _controller = TextEditingController(text: widget.text);
  final _focus = FocusNode(debugLabel: 'NoteTextField');

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(NoteTextField old) {
    super.didUpdateWidget(old);
    // Undo or an edit made elsewhere changed the note.
    if (!_focus.hasFocus && widget.text != _controller.text) _controller.text = widget.text;
  }

  void _commit() {
    final text = widget.multiline ? _controller.text.trimRight() : _controller.text.trim();
    if (text == widget.text) return;
    if (text.isEmpty && !widget.allowEmpty) {
      _controller.text = widget.text;
      return;
    }
    unawaited(widget.onCommit(text));
  }

  @override
  void dispose() {
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
        focusNode: _focus,
        style: widget.style,
        multiline: widget.multiline,
        semanticLabel: widget.semanticLabel,
        onSubmitted: _focus.unfocus,
        onCancel: () {
          _controller.text = widget.text;
          _focus.unfocus();
        },
      ),
    );
  }
}
