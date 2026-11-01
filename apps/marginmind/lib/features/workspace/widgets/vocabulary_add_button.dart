import '../../vocabulary/vocabulary_source_flash.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/navigation.dart';
import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import '../../vocabulary/selection_vocabulary.dart';
import '../../vocabulary/vocabulary_controller.dart';
import '../workspace_controller.dart';

class VocabularyAddButton extends ConsumerStatefulWidget {
  const VocabularyAddButton({
    super.key,
    required this.studySetId,
    required this.paragraph,
    required this.selected,
    this.lookup,
    this.translation,
    this.contextOnly = false,
  });
  final String studySetId, selected;
  final TranslationParagraph paragraph;
  final WordLookupResult? lookup;
  final String? translation;
  final bool contextOnly;
  @override
  ConsumerState<VocabularyAddButton> createState() => VocabularyAddButtonState();
}

class VocabularyAddButtonState extends ConsumerState<VocabularyAddButton> {
  bool _busy = false;
  String get language => vocabularyCjk.hasMatch(widget.selected) ? 'zh' : 'en';
  VocabularyEntry? get entry => ref
      .read(vocabularyProvider)
      .asData
      ?.value
      .entries
      .where(
        (e) =>
            e.language == language &&
            (e.key == vocabularyKey(widget.lookup?.lemma ?? widget.selected) ||
                e.forms.contains(vocabularyKey(widget.selected))),
      )
      .firstOrNull;

  Future<void> _edit(
    List<VocabularyEntry> Function(List<VocabularyEntry>) change,
    String message, {
    bool flash = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final owner = ref.read(vocabularyProvider.notifier), l = context.l10n;
    try {
      final receipt = await owner.edit(change);
      if (!mounted) return;
      final added = flash ? entry : null;
      if (added != null) ref.read(vocabularyAddedFlashProvider.notifier).show(added.id);
      MMHud.show(
        context,
        message,
        action: (
          l.undo,
          () async {
            try {
              await owner.undo(receipt);
            } catch (_) {
              if (mounted) MMHud.show(context, l.somethingWentWrong);
            }
          },
        ),
      );
    } catch (_) {
      if (mounted) MMHud.show(context, l.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> add() async {
    if (_busy || classifyVocabularySelection(widget.selected) == VocabularySelectionKind.sentence) return;
    final p = widget.paragraph;
    final content = ref.read(workspaceProvider(widget.studySetId)).content;
    final source = VocabularyContext(
      id: newId(),
      studySetId: widget.studySetId,
      documentId: p.documentId,
      studySetTitle:
          ref.read(studySetsProvider).asData?.value.where((s) => s.id == widget.studySetId).firstOrNull?.title ??
          widget.studySetId,
      documentTitle: content?.document(p.documentId)?.title ?? '',
      sentence: p.text,
      hit: widget.selected,
      addedAt: ref.read(clockProvider)(),
      sentenceTranslation:
          widget.lookup?.context.sentenceTranslation ?? (p.text.trim() == widget.selected ? widget.translation : null),
      textAnchor: p.textAnchor,
      page: p.textAnchor == null ? p.page : null,
      rects: p.rects,
    );
    await _edit(
      (entries) => saveSelectionVocabulary(
        entries,
        selected: widget.selected,
        language: language,
        context: source,
        lookup: widget.lookup,
        translation: widget.translation,
      ),
      context.l10n.vocabularyAdded,
      flash: true,
    );
  }

  void _details(String id) {
    Navigator.of(context).pop();
    ref.read(navigationProvider.notifier).showVocabulary(studySetId: widget.studySetId, entryId: id);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(vocabularyProvider);
    final e = entry, l = context.l10n;
    final eligible = classifyVocabularySelection(widget.selected) != VocabularySelectionKind.sentence;
    if (widget.contextOnly) {
      if (e == null ||
          e.contexts.any(
            (c) =>
                c.studySetId == widget.studySetId &&
                c.documentId == widget.paragraph.documentId &&
                c.sentence.trim().replaceAll(RegExp(r'\s+'), ' ') ==
                    widget.paragraph.text.trim().replaceAll(RegExp(r'\s+'), ' '),
          )) {
        return const SizedBox.shrink();
      }
      return MMIconButton(icon: MMIcons.add, tooltip: l.vocabularyExample, onPressed: _busy ? null : add);
    }
    final VoidCallback? onPressed = !eligible || _busy
        ? null
        : e == null
        ? add
        : () async {
            final box = context.findRenderObject() as RenderBox;
            await showMMMenu(
              context,
              position: box.localToGlobal(Offset.zero) + Offset(0, box.size.height),
              entries: [
                MMMenuItem(l.vocabularyView, () => _details(e.id)),
                MMMenuItem(
                  l.vocabularyMarkKnown,
                  () => _edit(
                    (items) => const VocabularyEditor().setStatus(
                      items,
                      e.id,
                      VocabularyStatus.known,
                      ref.read(clockProvider)(),
                    ),
                    l.vocabularyKnown,
                  ),
                ),
                MMMenuItem(
                  l.vocabularyRemove,
                  () => _edit((items) => const VocabularyEditor().remove(items, e.id), l.vocabularyRemove),
                ),
              ],
            );
          };
    final tooltip = !eligible
        ? l.vocabularyLongSelection
        : e == null
        ? '${l.vocabularyAdd}（S）'
        : e.status == VocabularyStatus.known
        ? l.vocabularyKnown
        : l.vocabularyLearning;
    return MMIconButton(
      icon: e == null ? MMIcons.star : MMIcons.starFill,
      tooltip: tooltip,
      color: e == null ? null : MMInkColor.yellow.color,
      selected: e != null,
      onPressed: onPressed,
    );
  }
}
