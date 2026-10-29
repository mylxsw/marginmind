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

enum _Problem { setup, offline, failed, tooLong }

class _SelectionTranslationState extends ConsumerState<SelectionTranslation> {
  CancellationToken? _cancel;
  ParagraphTranslator? _translator;
  String? _answer;
  _Problem? _problem;
  late final String _language = ref
      .read(settingsProvider)
      .selectionTranslationDirection
      .targetLanguage(widget.paragraph.text);

  @override
  void initState() {
    super.initState();
    unawaited(_translate());
  }

  Future<void> _translate() async {
    final cancel = CancellationToken();
    _cancel = cancel;
    setState(() {
      _answer = null;
      _problem = null;
    });
    ParagraphTranslator? translator;
    try {
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
      if (widget.paragraph.text.length > 24000) {
        setState(() => _problem = _Problem.tooLong);
        return;
      }
      translator = await ref.read(paragraphTranslatorProvider)(model);
      if (!mounted || cancel.isCancelled) return;
      _translator = translator;
      final translated = await cancel
          .bind(translator.translate(widget.paragraph, _language, cancel, 16384))
          .timeout(const Duration(seconds: 90));
      if (!mounted || cancel.isCancelled) return;
      if (translated.text.trim().isEmpty) throw StateError('Empty translation');
      setState(() => _answer = translated.text.trim());
    } catch (error) {
      if (mounted && !cancel.isCancelled) {
        setState(
          () => _problem = error is ResearchFailure && error.kind == ResearchFailureKind.authentication
              ? _Problem.setup
              : _Problem.failed,
        );
      }
    } finally {
      cancel.cancel();
      if (identical(_translator, translator)) _translator = null;
      translator?.close();
    }
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
                  children: [
                    Icon(MMIcons.translate, color: c.icon, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _language == 'zh'
                            ? l.selectionTranslationEnglishToChinese
                            : l.selectionTranslationChineseToEnglish,
                        style: t.body,
                      ),
                    ),
                    if (_answer != null)
                      MMIconButton(icon: MMIcons.copy, tooltip: l.selectionTranslationCopy, onPressed: _copy),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.paragraph.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: t.footnote.copyWith(color: c.secondaryLabel),
                        ),
                        const SizedBox(height: 12),
                        if (_answer != null)
                          SelectableText(_answer!, style: t.body)
                        else if (_problem != null) ...[
                          Text(switch (_problem!) {
                            _Problem.setup => l.assistantConnectFirst,
                            _Problem.offline => l.selectionTranslationOffline,
                            _Problem.tooLong => l.selectionTranslationTooLong,
                            _Problem.failed => l.selectionTranslationFailed,
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
                              else if (_problem != _Problem.tooLong)
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
