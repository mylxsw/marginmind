import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/providers.dart';
import '../../../settings/app_settings.dart';
import '../../../settings/settings_window.dart';
import '../../../shared/l10n.dart';
import '../../assistant/assistant_settings.dart';
import '../../assistant/widgets/assistant_overlays.dart' show inScope;
import '../../assistant/widgets/assistant_quick_actions.dart' show QuickActionsPlacement;
import '../reader_translation.dart';

Future<void> showSelectionTranslation(
  BuildContext context, {
  required String studySetId,
  required TranslationParagraph paragraph,
  required Rect toolbar,
  required Rect selection,
  required Rect viewport,
}) => showGeneralDialog<void>(
  context: context,
  barrierColor: Colors.transparent,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  transitionDuration: MMAppearance.duration(context, MMMotion.quick),
  pageBuilder: (_, _, _) => inScope(
    context,
    CustomSingleChildLayout(
      delegate: QuickActionsPlacement(toolbar: toolbar, selection: selection, viewport: viewport),
      child: SelectionTranslation(studySetId: studySetId, paragraph: paragraph),
    ),
  ),
  transitionBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
);

class SelectionTranslation extends ConsumerStatefulWidget {
  const SelectionTranslation({super.key, required this.studySetId, required this.paragraph});
  final String studySetId;
  final TranslationParagraph paragraph;
  @override
  ConsumerState<SelectionTranslation> createState() => _SelectionTranslationState();
}

enum _Problem { setup, offline, failed, tooLong, sameLanguage }

class _SelectionTranslationState extends ConsumerState<SelectionTranslation> {
  CancellationToken? _cancel;
  String? _answer;
  _Problem? _problem;
  late String _sourceText = widget.paragraph.text;
  late TranslationLanguage? _sourceLanguage = switch (ref.read(settingsProvider).selectionTranslationDirection) {
    SelectionTranslationDirection.automatic => null,
    SelectionTranslationDirection.englishToChinese => TranslationLanguage.english,
    SelectionTranslationDirection.chineseToEnglish => TranslationLanguage.chinese,
  };
  late TranslationLanguage _targetLanguage = TranslationLanguage.fromCode(
    ref.read(settingsProvider).selectionTranslationDirection.targetLanguage(widget.paragraph.text),
  )!;

  @override
  void initState() {
    super.initState();
    unawaited(_translate());
  }

  Future<void> _translate() async {
    _cancel?.cancel();
    final cancel = CancellationToken();
    _cancel = cancel;
    final sourceLanguage = _sourceLanguage, targetLanguage = _targetLanguage;
    final paragraph = TranslationParagraph(
      documentId: widget.paragraph.documentId,
      page: widget.paragraph.page,
      index: widget.paragraph.index,
      text: _sourceText,
      fingerprint: '',
      rects: widget.paragraph.rects,
    );
    bool current() => mounted && identical(_cancel, cancel) && !cancel.isCancelled;
    setState(() {
      _answer = null;
      _problem = null;
    });
    ParagraphTranslator? translator;
    try {
      if (sourceLanguage == targetLanguage) {
        setState(() => _problem = _Problem.sameLanguage);
        return;
      }
      final model = ref.read(assistantDefaultModelProvider);
      if (model == null) {
        setState(() => _problem = _Problem.setup);
        return;
      }
      final prefs = ref.read(sharedPreferencesProvider);
      final online = prefs.getBool(assistantOnlineKey(widget.studySetId)) ?? prefs.getBool('assistant.online') ?? true;
      if (!online && model.provider != AssistantProvider.ollama) {
        setState(() => _problem = _Problem.offline);
        return;
      }
      if (paragraph.text.length > 24000) {
        setState(() => _problem = _Problem.tooLong);
        return;
      }
      translator = await ref.read(paragraphTranslatorProvider)(model);
      if (!current()) return;
      final translated = await cancel
          .bind(
            translator.translate(paragraph, targetLanguage.code, cancel, 16384, sourceLanguage: sourceLanguage?.code),
          )
          .timeout(const Duration(seconds: 90));
      if (!current()) return;
      if (translated.text.trim().isEmpty) throw StateError('Empty translation');
      setState(() => _answer = translated.text.trim());
    } catch (error) {
      if (current()) {
        setState(
          () => _problem = error is ResearchFailure && error.kind == ResearchFailureKind.authentication
              ? _Problem.setup
              : _Problem.failed,
        );
      }
    } finally {
      cancel.cancel();
      translator?.close();
    }
  }

  void _setSource(String code) {
    final language = TranslationLanguage.fromCode(code);
    if (language == _sourceLanguage) return;
    setState(() => _sourceLanguage = language);
    unawaited(_translate());
  }

  void _setTarget(TranslationLanguage language) {
    if (language == _targetLanguage) return;
    setState(() => _targetLanguage = language);
    unawaited(_translate());
  }

  void _swap() {
    final answer = _answer;
    final source = _sourceLanguage;
    if (answer == null || source == null) return;
    setState(() {
      _sourceText = answer;
      _sourceLanguage = _targetLanguage;
      _targetLanguage = source;
    });
    unawaited(_translate());
  }

  @override
  void dispose() {
    _cancel?.cancel();
    // Cancellation reaches the request immediately; its finally closes the connection.
    super.dispose();
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _answer!));
      if (mounted) MMHud.show(context, context.l10n.copiedHud);
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, c = context.mmColors, t = context.mmText;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop()},
      child: FocusScope(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: MMGlass(
            key: const ValueKey('selection-translation-result'),
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  key: const ValueKey('selection-translation-header'),
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: MMPopUpButton<String>(
                              key: const ValueKey('translation-source-language'),
                              value: _sourceLanguage?.code ?? 'auto',
                              items: [
                                ('auto', l.translationDetectLanguage),
                                for (final language in TranslationLanguage.values)
                                  (language.code, l.translationLanguageName(language)),
                              ],
                              onChanged: _setSource,
                              semanticLabel: l.translationSourceLanguage,
                              maxWidth: 132,
                            ),
                          ),
                          MMIconButton(
                            key: const ValueKey('translation-swap-languages'),
                            icon: MMIcons.swapSides,
                            tooltip: _sourceLanguage == null
                                ? l.translationChooseSourceToSwap
                                : l.translationSwapLanguages,
                            size: 28,
                            onPressed: _answer == null || _sourceLanguage == null ? null : _swap,
                          ),
                          Flexible(
                            child: MMPopUpButton<TranslationLanguage>(
                              key: const ValueKey('translation-target-language'),
                              value: _targetLanguage,
                              items: [
                                for (final language in TranslationLanguage.values)
                                  (language, l.translationLanguageName(language)),
                              ],
                              onChanged: _setTarget,
                              semanticLabel: l.translationTargetLanguage,
                              maxWidth: 132,
                            ),
                          ),
                        ],
                      ),
                    ),
                    MMIconButton(
                      icon: MMIcons.close,
                      tooltip: l.closePanel,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('selection-translation-scroll'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _sourceText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: t.footnote.copyWith(color: c.secondaryLabel),
                        ),
                        const SizedBox(height: 12),
                        if (_answer != null)
                          SelectableText(_answer!, key: const ValueKey('selection-translation-answer'), style: t.body)
                        else if (_problem != null) ...[
                          Text(switch (_problem!) {
                            _Problem.setup => l.assistantConnectFirst,
                            _Problem.offline => l.selectionTranslationOffline,
                            _Problem.tooLong => l.selectionTranslationTooLong,
                            _Problem.failed => l.selectionTranslationFailed,
                            _Problem.sameLanguage => l.translationSameLanguage,
                          }, style: t.body),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              if (_problem == _Problem.setup)
                                MMButton(
                                  label: l.assistantConfigureModels,
                                  onPressed: () async {
                                    await showSettings(context, tab: SettingsTab.models);
                                    if (mounted) unawaited(_translate());
                                  },
                                )
                              else if (_problem != _Problem.tooLong && _problem != _Problem.sameLanguage)
                                MMButton(label: l.assistantRetry, onPressed: _translate),
                            ],
                          ),
                        ] else
                          Row(
                            children: [
                              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(width: 10),
                              Expanded(child: Text(l.selectionTranslationLoading, style: t.body)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                if (_answer != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _TranslationCopyButton(onPressed: _copy),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet answer action, outside the scrolling prose so it stays reachable.
class _TranslationCopyButton extends StatelessWidget {
  const _TranslationCopyButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final label = context.l10n.selectionTranslationCopy;
    return MMInteractive(
      key: const ValueKey('selection-translation-copy'),
      tooltip: label,
      semanticLabel: label,
      onTap: onPressed,
      builder: (context, state) => AnimatedContainer(
        duration: MMAppearance.duration(context, MMMotion.quick),
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: state.pressed
              ? c.pressed
              : state.hovered
              ? c.hover
              : c.quaternaryFill,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: state.focused ? c.accent : c.separator),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(MMIcons.copy, size: 11, color: c.icon),
            const SizedBox(width: 5),
            Text(label, style: context.mmText.footnote.copyWith(color: c.label)),
          ],
        ),
      ),
    );
  }
}
