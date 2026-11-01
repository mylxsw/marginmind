import '../workspace_controller.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../app/app_commands.dart';
import '../../../app/providers.dart';
import '../../../settings/app_settings.dart';
import '../../../settings/settings_window.dart';
import '../../../shared/l10n.dart';
import '../../assistant/assistant_settings.dart';
import '../../assistant/widgets/assistant_overlays.dart' show inScope;
import '../../assistant/widgets/assistant_quick_actions.dart' show QuickActionsPlacement;
import '../../vocabulary/vocabulary_controller.dart';
import '../selection_vocabulary_context.dart';
import '../word_lookup.dart';
import 'selection_translation.dart';
import 'vocabulary_add_button.dart';

Future<void> showSelectionLookup(
  BuildContext context, {
  required String studySetId,
  required TranslationParagraph paragraph,
  required Rect toolbar,
  required Rect selection,
  required Rect viewport,
  VoidCallback? onAsk,
}) {
  if (classifyVocabularySelection(paragraph.text) != VocabularySelectionKind.word) {
    return showSelectionTranslation(
      context,
      studySetId: studySetId,
      paragraph: paragraph,
      toolbar: toolbar,
      selection: selection,
      viewport: viewport,
    );
  }
  final placement = QuickActionsPlacement(
    toolbar: toolbar,
    selection: selection,
    viewport: viewport,
    maxWidth: MMSizes.vocabularyCardWidth,
  );
  return showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: MMMotion.popup,
    pageBuilder: (_, _, _) => inScope(
      context,
      CustomSingleChildLayout(
        delegate: placement,
        child: SelectionLookup(studySetId: studySetId, paragraph: paragraph, onAsk: onAsk, placement: placement),
      ),
    ),
    transitionBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
  );
}

class SelectionLookup extends ConsumerStatefulWidget {
  const SelectionLookup({super.key, required this.studySetId, required this.paragraph, this.onAsk, this.placement});
  final String studySetId;
  final TranslationParagraph paragraph;
  final VoidCallback? onAsk;
  final QuickActionsPlacement? placement;
  @override
  ConsumerState<SelectionLookup> createState() => _SelectionLookupState();
}

class _SelectionLookupState extends ConsumerState<SelectionLookup> {
  final _cancel = CancellationToken();
  final _add = GlobalKey<VocabularyAddButtonState>();
  WordLookupResult? _result;
  String? _problem;
  late TranslationParagraph _sentence = widget.paragraph;
  String get term => selectionTerm(widget.paragraph.text);
  VocabularyEntry? get entry => ref
      .read(vocabularyProvider)
      .asData
      ?.value
      .entries
      .where(
        (e) =>
            e.language == (vocabularyCjk.hasMatch(term) ? 'zh' : 'en') &&
            (e.key == vocabularyKey(_result?.lemma ?? term) || e.forms.contains(vocabularyKey(term))),
      )
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    unawaited(_lookup());
  }

  Future<void> _lookup() async {
    try {
      await ref.read(vocabularyProvider.future);
      _sentence = await selectionSentence(ref, widget.studySetId, widget.paragraph);
      if (!mounted || _cancel.isCancelled) return;
      final saved = entry;
      final settings = ref.read(settingsProvider);
      final target = settings.selectionTranslationDirection.targetLanguage(term);
      final sourceLanguage = switch (settings.selectionTranslationDirection) {
        SelectionTranslationDirection.automatic => null,
        SelectionTranslationDirection.englishToChinese => 'en',
        SelectionTranslationDirection.chineseToEnglish => 'zh',
      };
      final service = ref.read(wordLookupProvider(widget.studySetId));
      final prefs = ref.read(sharedPreferencesProvider);
      final online = prefs.getBool(assistantOnlineKey(widget.studySetId)) ?? prefs.getBool('assistant.online') ?? true;
      final source = saved?.contexts
          .where(
            (c) =>
                c.studySetId == widget.studySetId &&
                c.documentId == _sentence.documentId &&
                c.sentence == _sentence.text &&
                (c.sentenceTranslation ?? '').isNotEmpty,
          )
          .firstOrNull;
      WordLookupResult result;
      if (saved != null && saved.senses.isNotEmpty) {
        final wordContext = source != null
            ? WordContext(contextMeaning: saved.gloss, sentenceTranslation: source.sentenceTranslation!)
            : await service.lookupContext(
                lemma: saved.term,
                sentence: _sentence.text,
                sourceLanguage: sourceLanguage,
                targetLanguage: target,
                cancel: _cancel,
                online: online,
              );
        result = WordLookupResult(
          lemma: saved.term,
          ukPhonetic: saved.ukPhonetic ?? '',
          usPhonetic: saved.usPhonetic ?? '',
          senses: [for (final s in saved.senses) WordSense(pos: s.partOfSpeech, meaning: s.meaning)],
          context: wordContext,
          gloss: saved.gloss,
          forms: saved.forms,
        );
      } else {
        result = await service.lookup(
          term: term,
          sentence: _sentence.text,
          sourceLanguage: sourceLanguage,
          targetLanguage: target,
          cancel: _cancel,
          online: online,
        );
      }
      if (mounted && !_cancel.isCancelled) {
        setState(() => _result = result);
      }
    } catch (e) {
      if (mounted && !_cancel.isCancelled) {
        setState(
          () => _problem =
              e is ConfigurationFailure || e is ResearchFailure && e.kind == ResearchFailureKind.authentication
              ? context.l10n.vocabularySetup
              : e is ResearchFailure && e.kind == ResearchFailureKind.network
              ? context.l10n.vocabularyOffline
              : context.l10n.selectionTranslationFailed,
        );
      }
    }
  }

  @override
  void dispose() {
    _cancel.cancel();
    unawaited(MMSpeech.stop());
    super.dispose();
  }

  Future<void> _speak(String language) async {
    try {
      await MMSpeech.speak(_result?.lemma ?? term, language: language);
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(vocabularyProvider);
    final l = context.l10n, c = context.mmColors, t = context.mmText;
    final r = _result, saved = entry;
    final senses = saved != null && saved.senses.isNotEmpty
        ? [for (final s in saved.senses) WordSense(pos: s.partOfSpeech, meaning: s.meaning)]
        : r?.senses;
    Widget add({bool contextOnly = false}) => VocabularyAddButton(
      key: contextOnly ? null : _add,
      studySetId: widget.studySetId,
      paragraph: _sentence,
      selected: term,
      lookup: r,
      contextOnly: contextOnly,
    );
    return Actions(
      actions: {
        if (classifyVocabularySelection(widget.paragraph.text) != VocabularySelectionKind.sentence)
          AddVocabularyIntent: CallbackAction<AddVocabularyIntent>(
            onInvoke: (_) {
              unawaited(_add.currentState?.add() ?? Future<void>.value());
              return null;
            },
          ),
      },
      child: Shortcuts(
        shortcuts: {addVocabularyShortcut: const AddVocabularyIntent()},
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop()},
          child: FocusScope(
            autofocus: true,
            child: Material(
              type: MaterialType.transparency,
              child: SizedBox(
                width: MMSizes.vocabularyCardWidth,
                child: MMGlass(
                  key: const ValueKey('selection-lookup-result'),
                  borderRadius: BorderRadius.circular(MMRadii.sidebar),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(MMSpacing.l),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    saved?.term ?? r?.lemma ?? term,
                                    style: t.title2,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                add(),
                                const SizedBox(width: MMSpacing.xxxl),
                              ],
                            ),
                            if ((saved?.ukPhonetic ?? r?.ukPhonetic ?? '').isNotEmpty ||
                                (saved?.usPhonetic ?? r?.usPhonetic ?? '').isNotEmpty)
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  for (final phonetic in [
                                    (saved?.ukPhonetic ?? r?.ukPhonetic ?? '', 'en-GB'),
                                    (saved?.usPhonetic ?? r?.usPhonetic ?? '', 'en-US'),
                                  ])
                                    if (phonetic.$1.isNotEmpty) ...[
                                      Text(
                                        '${phonetic.$2 == 'en-GB' ? l.vocabularyUK : l.vocabularyUS} ${phonetic.$1}',
                                        style: t.footnote,
                                      ),
                                      if (MMSpeech.supported)
                                        MMIconButton(
                                          icon: MMIcons.speaker,
                                          tooltip: l.vocabularySpeak,
                                          onPressed: () => _speak(phonetic.$2),
                                        ),
                                    ],
                                ],
                              ),
                            const SizedBox(height: MMSpacing.m),
                            Flexible(
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    for (final sense in (senses ?? []).take(4))
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: MMSpacing.s),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: MMSpacing.xs,
                                                vertical: MMSpacing.xxs,
                                              ),
                                              decoration: BoxDecoration(
                                                color: c.quaternaryFill,
                                                borderRadius: BorderRadius.circular(MMRadii.vocabularyPos),
                                              ),
                                              child: Text(sense.pos, style: t.footnote),
                                            ),
                                            const SizedBox(width: MMSpacing.s),
                                            Expanded(child: Text(sense.meaning, style: t.body)),
                                          ],
                                        ),
                                      ),
                                    if (_problem != null)
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _problem!,
                                              style: t.body,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          MMButton(
                                            label: l.vocabularySettings,
                                            onPressed: () async {
                                              await showSettings(context, tab: SettingsTab.models);
                                              if (mounted) {
                                                setState(() => _problem = null);
                                                unawaited(_lookup());
                                              }
                                            },
                                          ),
                                        ],
                                      )
                                    else if (r == null) ...[
                                      for (final width in [1.0, .8, .6])
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: MMSpacing.s),
                                          child: FractionallySizedBox(
                                            alignment: Alignment.centerLeft,
                                            widthFactor: width,
                                            child: Container(
                                              key: ValueKey('lookup-skeleton-$width'),
                                              height: MMSpacing.l,
                                              decoration: BoxDecoration(
                                                color: c.quaternaryFill,
                                                borderRadius: BorderRadius.circular(MMRadii.row),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ] else ...[
                                      Container(
                                        padding: const EdgeInsets.all(MMSpacing.m),
                                        decoration: BoxDecoration(
                                          color: c.vocabularyTint,
                                          borderRadius: BorderRadius.circular(MMRadii.card),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    r.context.contextMeaning,
                                                    style: t.body.copyWith(fontWeight: FontWeight.w500),
                                                  ),
                                                ),
                                                add(contextOnly: true),
                                              ],
                                            ),
                                            const SizedBox(height: MMSpacing.s),
                                            Text.rich(
                                              TextSpan(children: _highlight(_sentence.text, term, c.vocabulary)),
                                              style: MMTypography.readingExcerpt.copyWith(
                                                color: c.label,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                            const SizedBox(height: MMSpacing.s),
                                            Text(
                                              r.context.sentenceTranslation,
                                              style: t.callout.copyWith(
                                                color: c.secondaryLabel,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: MMSpacing.m),
                            Row(
                              children: [
                                Flexible(
                                  child: MMButton(
                                    variant: MMButtonVariant.plain,
                                    label: l.vocabularySentence,
                                    icon: MMIcons.translate,
                                    color: c.accent,
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      showSelectionTranslation(
                                        context,
                                        studySetId: widget.studySetId,
                                        paragraph: _sentence,
                                        toolbar: widget.placement?.toolbar ?? Rect.zero,
                                        selection: widget.placement?.selection ?? Rect.zero,
                                        viewport:
                                            widget.placement?.viewport ?? Offset.zero & MediaQuery.sizeOf(context),
                                      );
                                    },
                                  ),
                                ),
                                Flexible(
                                  child: MMButton(
                                    variant: MMButtonVariant.plain,
                                    color: c.research,
                                    label: l.askAssistant,
                                    icon: MMIcons.conversation,
                                    onPressed: widget.onAsk == null
                                        ? null
                                        : () {
                                            Navigator.of(context).pop();
                                            widget.onAsk!();
                                          },
                                  ),
                                ),
                                if (saved != null)
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: MMButton(
                                        variant: MMButtonVariant.plain,
                                        label: l.vocabularyDetails,
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          ref
                                              .read(workspaceProvider(widget.studySetId).notifier)
                                              .openVocabularyReference(saved.id);
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: MMSpacing.s,
                        right: MMSpacing.s,
                        child: MMIconButton(
                          icon: MMIcons.close,
                          tooltip: l.closePanel,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<TextSpan> _highlight(String sentence, String term, Color color) {
  final matches = RegExp(
    r'(?<![\p{L}\p{N}])' + RegExp.escape(term) + r'(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  ).allMatches(sentence);
  var start = 0;
  final spans = <TextSpan>[];
  for (final m in matches) {
    spans.add(TextSpan(text: sentence.substring(start, m.start)));
    spans.add(
      TextSpan(
        text: m.group(0),
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
    start = m.end;
  }
  spans.add(TextSpan(text: sentence.substring(start)));
  return spans;
}
