import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/app.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../shared/l10n.dart';
import '../assistant/assistant_settings.dart';
import '../workspace/reader_translation.dart';
import '../workspace/word_lookup.dart';
import '../workspace/workspace_browser.dart';
import '../workspace/workspace_controller.dart';
import 'vocabulary_controller.dart';
import 'vocabulary_source_flash.dart';

/// A single application-level destination, also usable by lookup/hit cards via
/// AppNavigation.showVocabulary(entryId: ...). Direct links reveal known words.
class VocabularyScreen extends ConsumerStatefulWidget {
  const VocabularyScreen({super.key, required this.route});
  final VocabularyRoute route;
  @override
  ConsumerState<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends ConsumerState<VocabularyScreen> {
  late String? _selected = widget.route.entryId;
  late bool _allSets = widget.route.studySetId == null || widget.route.entryId != null;
  late VocabularyStatus? _status = widget.route.entryId == null ? VocabularyStatus.learning : null;
  String _query = '';
  bool _pushed = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final data = ref.watch(vocabularyProvider);
    final setId = widget.route.studySetId;
    final window = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final compact =
        MMSizeClass.fromSize(Size(window.width - safe.horizontal, window.height - safe.vertical)) ==
        MMSizeClass.compact;
    final entries = data.value?.entries ?? const <VocabularyEntry>[];
    final documentId = setId == null ? null : ref.watch(workspaceProvider(setId).select((s) => s.activeDocumentId));
    final paragraphs = setId == null || documentId == null
        ? const <TranslationParagraph>[]
        : ref.watch(translationParagraphsProvider((setId, documentId))).value ?? const <TranslationParagraph>[];
    final counts = <String, int>{};
    final matcher = VocabularyMatcher(entries, showKnown: true);
    for (final p in paragraphs) {
      for (final hit in matcher.match(p.text)) {
        counts.update(hit.entryId, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final query = _query.trim().toLowerCase();
    final visible =
        entries
            .where(
              (e) =>
                  (_status == null || e.status == _status) &&
                  (_allSets || e.contexts.any((c) => c.studySetId == setId) || (counts[e.id] ?? 0) > 0) &&
                  (query.isEmpty ||
                      [
                        e.term,
                        e.gloss,
                        ...e.forms,
                        ...e.senses.map((s) => s.meaning),
                      ].any((v) => v.toLowerCase().contains(query))),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final selected = visible.where((e) => e.id == _selected).firstOrNull ?? (compact ? null : visible.firstOrNull);
    final showDetail = compact && (_pushed || widget.route.entryId != null) && selected != null;
    void back() {
      if (showDetail) {
        setState(() {
          _pushed = false;
          _selected = null;
        });
      } else {
        ref.read(navigationProvider.notifier).back();
      }
    }

    final now = ref.watch(clockProvider)().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    Widget list = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(MMSpacing.m),
          child: Column(
            children: [
              MMSearchField(placeholder: l.vocabularySearch, onChanged: (v) => setState(() => _query = v)),
              const SizedBox(height: MMSpacing.s),
              MMSegmentedControl<bool>(
                expand: true,
                value: _allSets,
                onChanged: (v) => setState(() => _allSets = v),
                segments: [
                  if (setId != null) MMSegment(value: false, label: l.vocabularyThisSet),
                  MMSegment(value: true, label: l.vocabularyAll),
                ],
              ),
              const SizedBox(height: MMSpacing.s),
              MMSegmentedControl<VocabularyStatus?>(
                expand: true,
                value: _status,
                onChanged: (v) => setState(() => _status = v),
                segments: [
                  MMSegment(value: VocabularyStatus.learning, label: l.vocabularyLearning),
                  MMSegment(value: VocabularyStatus.known, label: l.vocabularyKnown),
                  MMSegment(value: null, label: l.vocabularyAll),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(MMSpacing.xxl),
                  child: Text(query.isEmpty ? l.vocabularyEmpty : l.vocabularyNoMatch, style: context.mmText.headline),
                ),
              for (final recent in [true, false]) ...[
                if (visible.any((e) => !e.createdAt.toLocal().isBefore(today) == recent))
                  Padding(
                    padding: const EdgeInsets.all(MMSpacing.m),
                    child: Text(recent ? l.vocabularyToday : l.vocabularyEarlier, style: context.mmText.footnote),
                  ),
                for (final e in visible.where((e) => !e.createdAt.toLocal().isBefore(today) == recent))
                  MMInteractive(
                    key: ValueKey('vocabulary-row-${e.id}'),
                    selected: selected?.id == e.id,
                    semanticLabel: e.term,
                    onTap: () => setState(() {
                      _selected = e.id;
                      _pushed = true;
                    }),
                    builder: (context, state) => Container(
                      padding: const EdgeInsets.all(MMSpacing.m),
                      decoration: BoxDecoration(
                        color: selected?.id == e.id
                            ? context.mmColors.selectedRow
                            : state.hovered
                            ? context.mmColors.hover
                            : null,
                        borderRadius: BorderRadius.circular(MMRadii.row),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.term,
                                  style: context.mmText.headline,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  e.senses.isEmpty ? '—' : e.senses.map((s) => s.meaning).join('；'),
                                  style: context.mmText.footnote,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Tooltip(
                            message: e.status == VocabularyStatus.learning ? l.vocabularyLearning : l.vocabularyKnown,
                            child: Container(
                              width: MMSpacing.s,
                              height: MMSpacing.s,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: e.status == VocabularyStatus.learning
                                    ? context.mmColors.vocabulary
                                    : context.mmColors.secondaryLabel,
                              ),
                            ),
                          ),
                          if ((counts[e.id] ?? 0) > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: MMSpacing.s),
                              child: Tooltip(message: l.vocabularyOccurrences, child: MMCount(counts[e.id]!)),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
    Widget detail = selected == null
        ? const SizedBox.expand()
        : VocabularyDetail(key: ValueKey(selected.id), entry: selected, studySetId: setId);
    return MMBackHandler(
      onBack: () {
        if (!showDetail) return false;
        back();
        return true;
      },
      child: MMWindowScaffold(
        showsWindowButtons: WindowChrome.showsWindowButtons,
        onDragStart: WindowChrome.onDragStart,
        onTitleDoubleTap: WindowChrome.onTitleDoubleTap,
        toolbar: MMToolbar(
          title: l.vocabularyTitle,
          leading: MMIconButton(icon: MMIcons.chevronLeft, tooltip: l.back, onPressed: back),
        ),
        body: data.hasError
            ? Center(child: Text(l.somethingWentWrong))
            : data.isLoading
            ? const Center(child: CircularProgressIndicator())
            : compact
            ? (showDetail ? detail : list)
            : Row(
                children: [
                  SizedBox(width: MMSizes.vocabularyListWidth, child: list),
                  const VerticalDivider(width: MMSpacing.xxs),
                  Expanded(child: detail),
                ],
              ),
      ),
    );
  }
}

/// Detail edits always apply to the latest repository snapshot, including while
/// model requests are in flight. Nothing is written to a study set undo stack.
class VocabularyDetail extends ConsumerStatefulWidget {
  const VocabularyDetail({super.key, required this.entry, this.studySetId});
  final VocabularyEntry entry;
  final String? studySetId;
  @override
  ConsumerState<VocabularyDetail> createState() => _VocabularyDetailState();
}

class _VocabularyDetailState extends ConsumerState<VocabularyDetail> {
  late final _gloss = TextEditingController(text: widget.entry.gloss);
  late final _note = TextEditingController(text: widget.entry.note);
  final _form = TextEditingController();
  CancellationToken? _cancel;
  bool _busy = false;
  static const _editor = VocabularyEditor();

  @override
  void didUpdateWidget(VocabularyDetail old) {
    super.didUpdateWidget(old);
    if (old.entry.gloss != widget.entry.gloss && _gloss.text == old.entry.gloss) _gloss.text = widget.entry.gloss;
    if (old.entry.note != widget.entry.note && _note.text == old.entry.note) _note.text = widget.entry.note;
  }

  @override
  void dispose() {
    _cancel?.cancel();
    unawaited(MMSpeech.stop().catchError((Object _) {}));
    _gloss.dispose();
    _note.dispose();
    _form.dispose();
    super.dispose();
  }

  Future<void> _edit(List<VocabularyEntry> Function(List<VocabularyEntry>, DateTime) change, {String? message}) async {
    final owner = ref.read(vocabularyProvider.notifier);
    final now = ref.read(clockProvider)();
    final hud = context.findAncestorStateOfType<MMHudState>();
    final l = context.l10n;
    try {
      final undo = await owner.edit((entries) => change(entries, now));
      if (message == null || hud == null || !hud.mounted) return;
      hud.show(
        message,
        action: (
          l.undo,
          () async {
            try {
              await owner.undo(undo);
            } catch (_) {
              if (hud.mounted) hud.show(l.somethingWentWrong);
            }
          },
        ),
      );
    } catch (_) {
      if (hud?.mounted == true) hud!.show(l.somethingWentWrong);
    }
  }

  Future<void> _regenerate() async {
    final entry = widget.entry;
    final cancel = CancellationToken();
    _cancel = cancel;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(wordLookupProvider)
          .lookup(
            term: entry.term,
            sentence: entry.contexts.firstOrNull?.sentence ?? entry.term,
            sourceLanguage: entry.language,
            targetLanguage: Localizations.localeOf(context).languageCode,
            model: ref.read(assistantDefaultModelProvider),
            cancel: cancel,
            refresh: true,
            online:
                ref
                    .read(sharedPreferencesProvider)
                    .getBool('assistant.online.${widget.studySetId ?? entry.contexts.firstOrNull?.studySetId ?? ''}') ??
                ref.read(sharedPreferencesProvider).getBool('assistant.online') ??
                true,
          );
      if (!mounted || cancel.isCancelled) return;
      await _edit(
        (entries, now) => _editor.updateSenses(
          entries,
          entry.id,
          result.senses.map((s) => VocabularySense(partOfSpeech: s.pos, meaning: s.meaning)).toList(),
          now,
        ),
      );
    } catch (_) {
      if (mounted && !cancel.isCancelled) MMHud.show(context, context.l10n.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry, l = context.l10n;
    final model = ref.watch(assistantDefaultModelProvider);
    Widget section(String title, Widget child, {Widget? action}) => Padding(
      padding: const EdgeInsets.only(top: MMSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: context.mmText.subheadline.copyWith(color: context.mmColors.secondaryLabel)),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: MMSpacing.s),
          child,
        ],
      ),
    );
    Future<void> speak(String locale) async {
      try {
        await MMSpeech.speak(e.term, language: locale);
      } catch (_) {
        if (context.mounted) MMHud.show(context, l.somethingWentWrong);
      }
    }

    return ListView(
      padding: const EdgeInsets.all(MMSpacing.xxl),
      children: [
        Text(e.term, style: context.mmText.largeTitle),
        const SizedBox(height: MMSpacing.s),
        Wrap(
          spacing: MMSpacing.s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (label, phonetic, locale) in [
              (l.vocabularyUk, e.ukPhonetic, 'en-GB'),
              (l.vocabularyUs, e.usPhonetic, 'en-US'),
            ])
              if (phonetic != null && phonetic.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        '$label $phonetic',
                        style: context.mmText.footnote,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (MMSpeech.supported)
                      MMIconButton(icon: MMIcons.speaker, tooltip: l.vocabularyRead, onPressed: () => speak(locale)),
                  ],
                ),
            MMPill(
              e.status == VocabularyStatus.learning ? l.vocabularyLearning : l.vocabularyKnown,
              color: context.mmColors.vocabulary,
            ),
          ],
        ),
        section(
          l.vocabularySenses,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (e.senses.isEmpty) const Text('—'),
              for (final s in e.senses)
                Padding(
                  padding: const EdgeInsets.only(bottom: MMSpacing.xs),
                  child: Text('${s.partOfSpeech}  ${s.meaning}', style: context.mmText.body),
                ),
            ],
          ),
          action: MMIconButton(
            icon: MMIcons.organize,
            tooltip: model == null ? l.vocabularyModelRequired : l.vocabularyRegenerate,
            onPressed: model == null || _busy ? null : _regenerate,
          ),
        ),
        section(
          l.vocabularyGloss,
          MMTextField(
            key: const ValueKey('vocabulary-gloss'),
            controller: _gloss,
            placeholder: '—',
            onChanged: (v) {
              final value = String.fromCharCodes(v.runes.take(8));
              if (value != v) {
                _gloss.value = TextEditingValue(
                  text: value,
                  selection: TextSelection.collapsed(offset: value.length),
                );
              }
              unawaited(_edit((entries, now) => _editor.updateGloss(entries, e.id, value, now)));
            },
          ),
        ),
        section(
          l.vocabularyNote,
          MMTextField(
            key: const ValueKey('vocabulary-note'),
            controller: _note,
            maxLines: null,
            minLines: 3,
            onChanged: (v) => unawaited(_edit((entries, now) => _editor.updateNote(entries, e.id, v, now))),
          ),
        ),
        section(
          l.vocabularyForms,
          Wrap(
            spacing: MMSpacing.s,
            runSpacing: MMSpacing.s,
            children: [
              for (final form in e.forms)
                Container(
                  key: ValueKey('form-chip-$form'),
                  height: MMSizes.vocabularyChipHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    color: context.mmColors.quaternaryFill,
                    borderRadius: BorderRadius.circular(MMRadii.vocabularyCard),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(form, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.mmText.footnote),
                      ),
                      if (form != e.key)
                        MMIconButton(
                          key: ValueKey('remove-form-$form'),
                          size: 14,
                          iconSize: 10,
                          icon: MMIcons.close,
                          tooltip: l.vocabularyForgetForm,
                          onPressed: () => _edit((entries, now) {
                            final current = entries.where((v) => v.id == e.id).firstOrNull;
                            return _editor.updateForms(
                              entries,
                              e.id,
                              current?.forms.where((f) => f != form).toList() ?? [],
                              now,
                            );
                          }),
                        ),
                    ],
                  ),
                ),
              Container(
                key: const ValueKey('form-input-chip'),
                width: 112,
                height: MMSizes.vocabularyChipHeight,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  border: Border.all(color: context.mmColors.separator, width: .5),
                  borderRadius: BorderRadius.circular(MMRadii.vocabularyCard),
                ),
                alignment: Alignment.center,
                child: TextField(
                  key: const ValueKey('vocabulary-add-form'),
                  textAlignVertical: TextAlignVertical.center,
                  controller: _form,
                  style: context.mmText.footnote,
                  decoration: InputDecoration.collapsed(
                    hintText: l.vocabularyAddForm,
                    hintStyle: context.mmText.footnote,
                  ),
                  enabled: e.forms.length < 16,
                  onSubmitted: (v) async {
                    if (v.trim().isEmpty) return;
                    await _edit((entries, now) {
                      final current = entries.where((v) => v.id == e.id).firstOrNull;
                      return _editor.updateForms(entries, e.id, [...?current?.forms, v], now);
                    });
                    if (mounted) _form.clear();
                  },
                ),
              ),
            ],
          ),
        ),
        section(
          l.vocabularyExamples,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (e.contexts.isEmpty) Text(l.vocabularyNoExamples, style: context.mmText.body),
              for (final source in e.contexts)
                _VocabularyExample(
                  source: source,
                  currentSetId: widget.studySetId,
                  onDelete: () => _edit(
                    (entries, now) => _editor.removeContext(entries, e.id, source.id, now),
                    message: l.vocabularyExampleDeleted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: MMSpacing.xxl),
        Wrap(
          spacing: MMSpacing.m,
          runSpacing: MMSpacing.s,
          children: [
            MMButton(
              label: e.status == VocabularyStatus.learning ? l.vocabularyMarkKnown : l.vocabularyLearnAgain,
              onPressed: () => _edit(
                (entries, now) => _editor.setStatus(
                  entries,
                  e.id,
                  e.status == VocabularyStatus.learning ? VocabularyStatus.known : VocabularyStatus.learning,
                  now,
                ),
                message: e.status == VocabularyStatus.learning ? l.vocabularyKnown : l.vocabularyLearning,
              ),
            ),
            MMButton(
              label: l.vocabularyDelete,
              variant: MMButtonVariant.plain,
              color: context.mmColors.critical,
              onPressed: () => _edit((entries, now) => _editor.remove(entries, e.id), message: l.vocabularyRemoved),
            ),
          ],
        ),
      ],
    );
  }
}

class _VocabularyExample extends ConsumerWidget {
  const _VocabularyExample({required this.source, required this.currentSetId, required this.onDelete});
  final VocabularyContext source;
  final String? currentSetId;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final sets = ref.watch(studySetsProvider).value;
    final exists = sets?.any((s) => s.id == source.studySetId) == true;
    final content = exists ? ref.watch(contentProvider(source.studySetId)).value : null;
    final hit = RegExp(RegExp.escape(source.hit), caseSensitive: false).firstMatch(source.sentence);
    final canJump = content?.document(source.documentId) != null && (source.textAnchor != null || source.page != null);
    return Container(
      key: ValueKey('example-card-${source.id}'),
      margin: const EdgeInsets.only(bottom: MMSpacing.s),
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: context.mmColors.separator, width: .5),
        borderRadius: BorderRadius.circular(MMRadii.vocabularyCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: context.mmText.readingExcerpt.copyWith(fontWeight: FontWeight.w400),
              children: hit == null
                  ? [TextSpan(text: source.sentence)]
                  : [
                      TextSpan(text: source.sentence.substring(0, hit.start)),
                      TextSpan(
                        text: source.sentence.substring(hit.start, hit.end),
                        style: TextStyle(fontWeight: FontWeight.bold, color: context.mmColors.vocabulary),
                      ),
                      TextSpan(text: source.sentence.substring(hit.end)),
                    ],
            ),
          ),
          if (source.sentenceTranslation?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                source.sentenceTranslation!,
                style: context.mmText.body.copyWith(fontSize: 12, color: context.mmColors.secondaryLabel),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(MMIcons.document, size: 12, color: context.mmColors.secondaryLabel),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${source.studySetTitle} · ${source.documentTitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.mmText.footnote.copyWith(color: context.mmColors.secondaryLabel),
                ),
              ),
              if (canJump)
                MMButton(
                  label: currentSetId == source.studySetId ? l.vocabularyReturn : l.vocabularyOpenSet,
                  color: context.mmColors.accent,
                  icon: MMIcons.openExternal,
                  variant: MMButtonVariant.plain,
                  onPressed: () async {
                    try {
                      final content = await ref.read(contentProvider(source.studySetId).future);
                      if (content.document(source.documentId) == null || !ref.context.mounted) return;
                      final target = source.textAnchor != null
                          ? TextTarget(documentId: source.documentId, textAnchors: [source.textAnchor!])
                          : PdfTarget(
                              documentId: source.documentId,
                              pages: [AnnotationPage(page: source.page!, rects: source.rects)],
                              quote: source.sentence,
                            );
                      await ref.read(studySetRepositoryProvider).markOpened(source.studySetId);
                      if (!context.mounted) return;
                      final owner = ref.read(workspaceProvider(source.studySetId).notifier);
                      final flash = ref.read(vocabularySourceFlashProvider.notifier);
                      final navigation = ref.read(navigationProvider.notifier);
                      final browser = ref.read(workspaceBrowserProvider(source.studySetId).notifier);
                      browser.hide();
                      navigation.openStudySet(source.studySetId);
                      if (await owner.revealAnchor(SourceAnchor(target: target))) {
                        owner.setLayout(MMSplitMode.primary);
                        flash.show(source);
                      }
                    } catch (_) {
                      if (context.mounted) MMHud.show(context, l.somethingWentWrong);
                    }
                  },
                ),
              MMIconButton(
                key: ValueKey('delete-example-${source.id}'),
                icon: MMIcons.close,
                tooltip: l.vocabularyDeleteExample,
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
