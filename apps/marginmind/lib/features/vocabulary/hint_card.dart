import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../shared/l10n.dart';
import 'hint_geometry.dart';
import 'vocabulary_controller.dart';

Future<void> showVocabularyHit(
  BuildContext context, {
  Rect? anchor,
  required String studySetId,
  required VocabularyHit hit,
  required Future<List<VocabularyHit>> Function(bool Function()) occurrences,
  required Future<void> Function(VocabularyHit) reveal,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierColor: Colors.transparent,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  transitionDuration: MMAppearance.duration(context, MMMotion.quick),
  pageBuilder: (_, _, _) => MMFloatingToolbarLayout(
    anchor: anchor ?? Rect.fromCenter(center: MediaQuery.sizeOf(context).center(Offset.zero), width: 1, height: 1),
    child: Material(
      type: MaterialType.transparency,
      child: VocabularyHitCard(studySetId: studySetId, hit: hit, occurrences: occurrences, reveal: reveal),
    ),
  ),
);

class VocabularyHitCard extends ConsumerStatefulWidget {
  const VocabularyHitCard({
    super.key,
    required this.studySetId,
    required this.hit,
    required this.occurrences,
    required this.reveal,
  });
  final String studySetId;
  final VocabularyHit hit;
  final Future<List<VocabularyHit>> Function(bool Function()) occurrences;
  final Future<void> Function(VocabularyHit) reveal;
  @override
  ConsumerState<VocabularyHitCard> createState() => _VocabularyHitCardState();
}

class _VocabularyHitCardState extends ConsumerState<VocabularyHitCard> {
  List<VocabularyHit> _hits = [];
  int _index = 0;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _hits = [widget.hit];
    _load();
  }

  Future<void> _load() async {
    try {
      final hits = await widget.occurrences(() => mounted);
      if (!mounted || hits.isEmpty) return;
      final index = hits.indexWhere(
        (h) =>
            h.page == widget.hit.page &&
            h.anchor?.chapterId == widget.hit.anchor?.chapterId &&
            h.anchor?.start == widget.hit.anchor?.start &&
            (h.anchor != null || h.rects.first == widget.hit.rects.first),
      );
      setState(() {
        _hits = hits;
        _index = index < 0 ? 0 : index;
      });
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong);
    }
  }

  Future<void> _navigate(int delta) async {
    if (_busy || _hits.length < 2) return;
    setState(() => _busy = true);
    final next = (_index + delta) % _hits.length;
    try {
      await widget.reveal(_hits[next]);
      if (mounted) setState(() => _index = next);
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(VocabularyEntry entry, bool remove) async {
    if (_busy) return;
    setState(() => _busy = true);
    final owner = ref.read(vocabularyProvider.notifier), l = context.l10n;
    try {
      final receipt = await owner.edit(
        (entries) => remove
            ? const VocabularyEditor().remove(entries, entry.id)
            : const VocabularyEditor().setStatus(entries, entry.id, VocabularyStatus.known, ref.read(clockProvider)()),
      );
      if (!mounted) return;
      final messengerContext = Navigator.of(context).context;
      Navigator.of(context).pop();
      MMHud.show(
        context,
        remove ? l.vocabularyRemoved : l.vocabularyKnown,
        action: (
          l.undo,
          () async {
            try {
              await owner.undo(receipt);
            } catch (_) {
              if (messengerContext.mounted) MMHud.show(messengerContext, l.somethingWentWrong);
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

  @override
  Widget build(BuildContext context) {
    final entry = ref.watch(vocabularyProvider).value?.entries.where((e) => e.id == widget.hit.entryId).firstOrNull;
    if (entry == null) return const SizedBox.shrink();
    final c = context.mmColors, t = context.mmText, l = context.l10n;
    return SizedBox(
      width: MMSizes.vocabularyHitCardWidth,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height - MediaQuery.paddingOf(context).vertical - MMSpacing.xxl * 2,
        ),
        child: MMGlass(
          padding: const EdgeInsets.all(MMSpacing.m),
          borderRadius: BorderRadius.circular(MMRadii.sidebar),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(entry.term, style: t.title3)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s, vertical: MMSpacing.xxs),
                      decoration: BoxDecoration(
                        color: c.vocabularyTint,
                        borderRadius: BorderRadius.circular(MMRadii.capsule),
                      ),
                      child: Text(
                        entry.status == VocabularyStatus.known ? l.vocabularyKnown : l.vocabularyLearning,
                        style: t.footnote.copyWith(color: c.vocabulary),
                      ),
                    ),
                  ],
                ),
                if ([entry.ukPhonetic, entry.usPhonetic].any((p) => p?.isNotEmpty == true))
                  Padding(
                    padding: const EdgeInsets.only(top: MMSpacing.xs),
                    child: Text(
                      [entry.ukPhonetic, entry.usPhonetic].whereType<String>().where((p) => p.isNotEmpty).join('  '),
                      style: t.footnote.copyWith(color: c.secondaryLabel),
                    ),
                  ),
                for (final sense in entry.senses.take(2))
                  Padding(
                    padding: const EdgeInsets.only(top: MMSpacing.s),
                    child: Text('${sense.partOfSpeech}  ${sense.meaning}'.trim(), style: t.body),
                  ),
                if (entry.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: MMSpacing.s),
                    child: Text(entry.note, style: t.footnote.copyWith(color: c.secondaryLabel)),
                  ),
                const SizedBox(height: MMSpacing.s),
                Row(
                  children: [
                    MMIconButton(
                      key: const ValueKey('vocabulary-hit-previous'),
                      icon: MMIcons.chevronLeft,
                      tooltip: l.findPrevious,
                      onPressed: _busy || _hits.length < 2 ? null : () => _navigate(-1),
                    ),
                    Text('${_index + 1} / ${_hits.length}', style: t.footnote),
                    MMIconButton(
                      key: const ValueKey('vocabulary-hit-next'),
                      icon: MMIcons.chevronRight,
                      tooltip: l.findNext,
                      onPressed: _busy || _hits.length < 2 ? null : () => _navigate(1),
                    ),
                    const SizedBox(width: MMSpacing.xs),
                    MMIconButton(
                      icon: MMIcons.check,
                      tooltip: l.vocabularyMarkKnown,
                      onPressed: _busy || entry.status == VocabularyStatus.known ? null : () => _edit(entry, false),
                    ),
                    MMIconButton(
                      icon: MMIcons.trash,
                      tooltip: l.vocabularyRemove,
                      onPressed: _busy ? null : () => _edit(entry, true),
                    ),
                    Expanded(
                      child: MMInteractive(
                        semanticLabel: l.vocabularyDetails,
                        builder: (context, state) => Text(
                          l.vocabularyDetails,
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.callout.copyWith(color: c.accent),
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          ref
                              .read(navigationProvider.notifier)
                              .showVocabulary(studySetId: widget.studySetId, entryId: entry.id);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
