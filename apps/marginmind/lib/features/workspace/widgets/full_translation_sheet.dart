import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/providers.dart';
import '../../../settings/settings_window.dart';
import '../../../shared/l10n.dart';
import '../../assistant/assistant_settings.dart';
import '../full_translation.dart';
import '../reader_compare.dart';
import '../reader_ocr.dart';
import '../reader_translation.dart';
import '../translation_schedulers.dart';
import '../workspace_controller.dart';
import 'reader_compare_controls.dart';
import 'reader_ocr_controls.dart';

Future<void> showFullTranslationSheet(
  BuildContext context, {
  required String studySetId,
  required String documentId,
  String? targetLang,
}) async {
  final container = ProviderScope.containerOf(context);
  final info = await container.read(compareDocumentInfoProvider((studySetId, documentId)).future);
  if (!context.mounted) return;
  final saved = container.read(sharedPreferencesProvider).getString('settings.translationLanguage');
  final language =
      targetLang ??
      (TranslationLanguage.fromCode(saved) != null && saved != info.language
          ? saved!
          : fullTranslationTargetLanguage(info.language));
  return showMMSheet<void>(
    context: context,
    width: MMSizes.fullTranslationSheetWidth,
    builder: (context) =>
        FullTranslationSheet(studySetId: studySetId, documentId: documentId, initialTargetLang: language),
  );
}

String fullTranslationTargetLanguage(String? sourceLanguage) => sourceLanguage == 'zh' ? 'en' : 'zh';

class FullTranslationSheet extends ConsumerStatefulWidget {
  const FullTranslationSheet({super.key, required this.studySetId, required this.documentId, this.initialTargetLang});

  final String studySetId;
  final String documentId;
  final String? initialTargetLang;

  @override
  ConsumerState<FullTranslationSheet> createState() => _FullTranslationSheetState();
}

class _FullTranslationSheetState extends ConsumerState<FullTranslationSheet> {
  late String _targetLang;
  String? _sourceLang;
  String? _sourceChoice;
  bool _rangeAll = true;
  late final TextEditingController _fromController;
  late final TextEditingController _toController;
  late final TextEditingController _noteController;
  final _noteFocus = FocusNode();
  late TranslationMode _mode;
  int _batchSize = 10;
  Timer? _estimateDebounce;
  int _pageCount = 1;
  bool _initialized = false;
  bool _starting = false;
  String? _startError;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(sharedPreferencesProvider);
    final savedMode = prefs.getString('translation.full.mode');
    _mode = savedMode == 'all' ? TranslationMode.all : TranslationMode.batch;
    _targetLang = widget.initialTargetLang ?? prefs.getString('settings.translationLanguage') ?? 'zh';
    _fromController = TextEditingController(text: '1');
    _toController = TextEditingController(text: '1');
    _noteController = TextEditingController();
    _noteFocus.addListener(_onInputChanged);
    _fromController.addListener(_onInputChanged);
    _toController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _estimateDebounce?.cancel();
    _fromController.dispose();
    _toController.dispose();
    _noteController.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    setState(() {});
  }

  int get _from => int.tryParse(_fromController.text.trim()) ?? 1;
  int get _to => int.tryParse(_toController.text.trim()) ?? _pageCount;

  bool get _isValidRange {
    if (_rangeAll) return _pageCount >= 1;
    final f = int.tryParse(_fromController.text.trim());
    final t = int.tryParse(_toController.text.trim());
    return f != null && t != null && f >= 1 && t <= _pageCount && f <= t;
  }

  Future<void> _start(
    Document doc,
    FullTranslationEstimation estimation,
    String modelName, {
    bool viewSaved = false,
  }) async {
    if (!_isValidRange) return;
    final f = _rangeAll ? 1 : _from;
    final t = _rangeAll ? _pageCount : _to;
    final firstTo = doc.contentManifest == null && _mode == TranslationMode.batch ? math.min(t, f + _batchSize - 1) : t;
    final l = context.l10n;
    final hudMessage = doc.contentManifest == null && _mode == TranslationMode.batch
        ? l.fullTranslationHudStartBatch(f, firstTo)
        : l.fullTranslationHudStartAll;
    final readerWidth = ReaderCompareWidth.of(context);
    final language = _targetLang;
    final sourceLanguage = _sourceChoice ?? _sourceLang;
    final mode = doc.contentManifest != null ? TranslationMode.all : _mode;
    final batchSize = _batchSize;

    if (_starting) return;
    setState(() {
      _starting = true;
      _startError = null;
    });
    final prefs = ref.read(sharedPreferencesProvider);
    final compareController = ref.read(readerCompareProvider(widget.studySetId).notifier);
    final controller = ref.read(fullTranslationProvider((widget.studySetId, widget.documentId, language)).notifier);
    final note = _noteController.text;
    try {
      await prefs.setString('translation.full.mode', mode.name);
      if (!mounted) return;
      if (!viewSaved) {
        await controller.startJob(
          from: f,
          to: t,
          mode: mode,
          batchSize: batchSize,
          note: note,
          sourceLang: sourceLanguage,
          modelName: modelName,
          estimatedTokens: estimation.tokens,
        );
      }
      if (!mounted) return;
      // Install the job before mounting the translation view. Otherwise the
      // view can issue an unconfirmed current-page request with stale settings.
      await compareController.openAi(language, documentId: widget.documentId, readerWidth: readerWidth);
      if (!mounted) return;
      if (doc.contentManifest == null) compareController.pdf(widget.documentId).jumpToPage(f);
      if (!viewSaved) MMHud.show(context, hudMessage);
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _starting = false;
          _startError = context.l10n.fullTranslationStartFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final l = context.l10n;
    final content = ref.watch(workspaceContentProvider(widget.studySetId));
    final doc = content?.document(widget.documentId);
    if (doc == null) return const SizedBox.shrink();
    final isText = doc.contentManifest != null;

    final info = ref.watch(compareDocumentInfoProvider((widget.studySetId, widget.documentId))).value;
    _sourceLang = info?.language;
    final docPath = ref.read(workspaceProvider(widget.studySetId).notifier).filePath(doc);
    final ocr = ref.watch(readerOcrProvider(docPath));
    final paragraphsAsync = ref.watch(translationParagraphsProvider((widget.studySetId, widget.documentId)));
    final paragraphs = paragraphsAsync.value ?? const <TranslationParagraph>[];
    if (isText && paragraphs.isNotEmpty) {
      _sourceLang = detectTranslationLanguage(paragraphs.take(8).map((p) => p.text).join(' ')) ?? _sourceLang;
    }

    if (!_initialized && paragraphs.isNotEmpty) {
      _initialized = true;
      _pageCount = paragraphs.map((p) => p.unit).fold(isText ? 0 : doc.pageCount, math.max);
      if (_toController.text == '1' && _pageCount > 1) {
        _toController.text = '$_pageCount';
      }
    } else if (!_initialized && doc.pageCount > 0) {
      _pageCount = doc.pageCount;
      if (_toController.text == '1' && _pageCount > 1) {
        _toController.text = '$_pageCount';
      }
    }

    final model = ref.watch(assistantDefaultModelProvider);
    final modelName = model == null
        ? ''
        : (model.serviceId?.isNotEmpty == true ? '${model.serviceId}/${model.model}' : model.model);
    final isOllama = model?.provider == AssistantProvider.ollama;
    final isOnline = isOllama || ref.watch(translationOnlineProvider(widget.studySetId));
    final credentialState = ref.watch(assistantCredentialStateProvider).value;

    final isScanned = doc.capabilities().ocr && ocr.document?.hasCopy != true && paragraphs.isEmpty && !ocr.running;
    final noModel = model == null || credentialState == AssistantCredentialState.unconfigured;
    final badKey =
        credentialState == AssistantCredentialState.missingKey ||
        credentialState == AssistantCredentialState.unavailable;
    final isOffline = !isOnline && !isOllama;

    final fullState = ref.watch(fullTranslationProvider((widget.studySetId, widget.documentId, _targetLang)));

    final f = _rangeAll ? 1 : _from;
    final t = _rangeAll ? _pageCount : _to;
    final valid = _isValidRange;
    final estimation = valid
        ? estimateFullTranslation(
            paragraphs: paragraphs,
            from: f,
            to: t,
            targetLang: _targetLang,
            values: fullState.values,
          )
        : null;

    final nothing = estimation != null && estimation.paras == 0;
    final viewSaved = _rangeAll && nothing && estimation.reused > 0;
    final disabled =
        _starting ||
        fullState.loading ||
        fullState.loadError != null ||
        !valid ||
        (!viewSaved &&
            (nothing || isScanned || noModel || badKey || credentialState != AssistantCredentialState.ready)) ||
        (_sourceChoice ?? _sourceLang) == _targetLang;
    final firstTo = _mode == TranslationMode.batch ? math.min(t, f + _batchSize - 1) : t;
    final primaryLabel = viewSaved
        ? l.fullTranslationViewSaved
        : nothing
        ? l.fullTranslationNothingToTranslate
        : !isText && _mode == TranslationMode.batch
        ? l.fullTranslationStartBatch(f, firstTo)
        : l.fullTranslationStartAll;

    Widget? blockedBanner;
    if (fullState.loadError != null) {
      blockedBanner = _buildBanner(icon: MMIcons.warning, title: l.fullTranslationCapsuleError, desc: '');
    } else if (isScanned) {
      blockedBanner = _buildBanner(
        icon: MMIcons.text,
        title: l.fullTranslationBlockedScannedTitle,
        desc: l.fullTranslationBlockedScannedDesc,
        action: MMButton(
          label: l.fullTranslationActionOcr,
          onPressed: () {
            Navigator.of(context).pop();
            showReaderOcrOptions(context, ref, widget.studySetId);
          },
        ),
      );
    } else if (!viewSaved && (noModel || badKey)) {
      blockedBanner = _buildBanner(
        icon: MMIcons.ai,
        title: badKey ? l.fullTranslationBlockedBadKeyTitle : l.fullTranslationBlockedNoModelTitle,
        desc: l.fullTranslationBlockedModelDesc,
        action: MMButton(
          label: l.fullTranslationActionSettings,
          onPressed: () {
            Navigator.of(context).pop();
            showSettings(context, tab: SettingsTab.models);
          },
        ),
      );
    } else if (!viewSaved && isOffline) {
      blockedBanner = _buildBanner(
        icon: MMIcons.wifiOff,
        title: l.fullTranslationBlockedOfflineTitle,
        desc: l.fullTranslationBlockedOfflineDesc,
      );
    }

    final isBig = estimation != null && estimation.tokens > 50000;

    return FocusScope(
      child: CallbackShortcuts(
        bindings: {
          if (!_noteFocus.hasFocus)
            const SingleActivator(LogicalKeyboardKey.enter): () {
              if (!_noteFocus.hasFocus && !disabled && estimation != null) {
                _start(doc, estimation, modelName, viewSaved: viewSaved);
              }
            },
        },
        child: Focus(
          autofocus: true,
          child: MMSheet(
            title: l.fullTranslationTitle,
            icon: MMIcons.layers,
            subtitle: isText ? doc.title : l.fullTranslationDocSubtitle(doc.title, _pageCount),
            footer: Text(
              l.fullTranslationFooterNote,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
            ),
            actions: [
              MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
              MMButton(
                label: primaryLabel,
                variant: MMButtonVariant.primary,
                onPressed: disabled || estimation == null
                    ? null
                    : () => _start(doc, estimation, modelName, viewSaved: viewSaved),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.fullTranslationConfirmIntro, style: context.mmText.callout.copyWith(color: c.secondaryLabel)),
                const SizedBox(height: 16),
                if (_startError != null) ...[
                  Text(_startError!, style: context.mmText.callout.copyWith(color: c.critical)),
                  const SizedBox(height: 12),
                ],
                if (blockedBanner != null) ...[blockedBanner, const SizedBox(height: 16)],
                _buildFormRow(
                  label: l.language,
                  child: Row(
                    children: [
                      Flexible(
                        child: MMPopUpButton<String>(
                          key: const ValueKey('full-translation-source-language'),
                          value: _sourceChoice ?? 'auto',
                          items: [
                            ('auto', _detectedLabel(l)),
                            for (final lang in TranslationLanguage.values) (lang.code, l.translationLanguageName(lang)),
                          ],
                          onChanged: _starting
                              ? null
                              : (val) => setState(() => _sourceChoice = val == 'auto' ? null : val),
                          semanticLabel: l.translationSourceLanguage,
                          maxWidth: 180,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('→', style: context.mmText.callout.copyWith(color: c.secondaryLabel)),
                      ),
                      Flexible(
                        child: MMPopUpButton<String>(
                          key: const ValueKey('full-translation-target-language'),
                          value: _targetLang,
                          items: [
                            for (final lang in TranslationLanguage.values) (lang.code, l.translationLanguageName(lang)),
                          ],
                          onChanged: _starting
                              ? null
                              : (val) {
                                  setState(() => _targetLang = val);
                                  ref.read(sharedPreferencesProvider).setString('settings.translationLanguage', val);
                                },
                          semanticLabel: l.translationTargetLanguage,
                          maxWidth: 160,
                        ),
                      ),
                    ],
                  ),
                ),
                if ((_sourceChoice ?? _sourceLang) == _targetLang) ...[
                  const SizedBox(height: 8),
                  Text(l.fullTranslationSameLanguage, style: context.mmText.footnote.copyWith(color: c.critical)),
                ],
                if (!isText) ...[
                  const SizedBox(height: 12),
                  _buildFormRow(
                    label: l.fullTranslationRange,
                    child: Row(
                      children: [
                        MMSegmentedControl<bool>(
                          value: _rangeAll,
                          onChanged: (val) {
                            setState(() {
                              _rangeAll = val;
                              if (val) {
                                _fromController.text = '1';
                                _toController.text = '$_pageCount';
                              }
                            });
                          },
                          segments: [
                            MMSegment(value: true, label: l.fullTranslationRangeAll),
                            MMSegment(value: false, label: l.fullTranslationRangePages),
                          ],
                        ),
                        const SizedBox(width: 12),
                        _numberField(_fromController),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text('–', style: context.mmText.callout.copyWith(color: c.secondaryLabel)),
                        ),
                        _numberField(_toController),
                        if (!valid) ...[
                          const SizedBox(width: 8),
                          Text('1–$_pageCount', style: context.mmText.footnote.copyWith(color: c.critical)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildFormRow(
                    label: l.fullTranslationMode,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    child: Row(
                      children: [
                        Expanded(
                          child: _ModeCard(
                            title: l.fullTranslationModeBatch,
                            desc: l.fullTranslationModeBatchDesc,
                            selected: _mode == TranslationMode.batch,
                            onTap: () => setState(() => _mode = TranslationMode.batch),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ModeCard(
                            title: l.fullTranslationModeAll,
                            desc: l.fullTranslationModeAllDesc,
                            selected: _mode == TranslationMode.all,
                            onTap: () => setState(() => _mode = TranslationMode.all),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_mode == TranslationMode.batch) ...[
                    const SizedBox(height: 12),
                    _buildFormRow(
                      label: l.fullTranslationBatchSize,
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: MMSegmentedControl<int>(
                              value: _batchSize,
                              onChanged: (val) => setState(() => _batchSize = val),
                              segments: [
                                for (final size in [5, 10, 20, 50])
                                  MMSegment(value: size, label: l.fullTranslationBatchPages(size)),
                              ],
                            ),
                          ),
                          Text(
                            l.fullTranslationBatchCount(valid ? ((t - f + 1) / _batchSize).ceil() : 0),
                            style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                _buildFormRow(
                  label: l.fullTranslationNote,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  child: TextField(
                    controller: _noteController,
                    focusNode: _noteFocus,
                    maxLines: 2,
                    maxLength: 1000,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    style: context.mmText.callout,
                    decoration: InputDecoration(
                      hintText: l.fullTranslationNotePlaceholder,
                      hintStyle: context.mmText.callout.copyWith(color: c.secondaryLabel),
                      filled: true,
                      fillColor: c.quaternaryFill,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.all(10),
                    ),
                  ),
                ),
                if (estimation != null && !isScanned) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildEstimateRow(
                          icon: MMIcons.translate,
                          content: l.fullTranslationEstNeeds(
                            '${estimation.paras - estimation.dupe}',
                            '${estimation.uniqueChars}',
                          ),
                          trailing: l.fullTranslationEstMinutes(estimation.minutes),
                        ),
                        if (estimation.reused > 0) ...[
                          const SizedBox(height: 6),
                          _buildEstimateRow(
                            icon: MMIcons.recycle,
                            iconColor: c.positive,
                            content: estimation.reusedPages > 0
                                ? l.fullTranslationEstReused(estimation.reused, estimation.reusedPages)
                                : l.fullTranslationEstReusedNoPages(estimation.reused),
                            contentColor: c.positive,
                          ),
                        ],
                        const SizedBox(height: 6),
                        _buildEstimateRow(
                          icon: MMIcons.skip,
                          content: l.fullTranslationEstSkip(
                            [
                              l.fullTranslationEstSkipMargin(estimation.skipped),
                              if (estimation.same > 0)
                                l.fullTranslationEstSkipSame(
                                  l.translationLanguageCodeName(_targetLang),
                                  estimation.same,
                                ),
                              if (estimation.dupe > 0) l.fullTranslationEstSkipDupe(estimation.dupe),
                            ].join(' · '),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildEstimateRow(
                          icon: MMIcons.ai,
                          iconColor: isBig ? c.caution : c.secondaryLabel,
                          content:
                              '${l.fullTranslationEstModel(modelName.isNotEmpty ? modelName : 'AI', formatTokens(estimation.tokens))}${isBig || _mode == TranslationMode.all ? l.fullTranslationEstBudgetWarning : ''}',
                          contentColor: isBig ? c.caution : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _numberField(TextEditingController controller) {
    final c = context.mmColors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: c.hairline, width: 0.5),
    );
    return Opacity(
      opacity: _rangeAll ? 0.45 : 1,
      child: SizedBox(
        width: 52,
        height: 24,
        child: TextField(
          controller: controller,
          enabled: !_rangeAll,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: context.mmText.footnote.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          decoration: InputDecoration(
            contentPadding: EdgeInsets.zero,
            filled: true,
            fillColor: c.card,
            border: border,
            enabledBorder: border,
            disabledBorder: border,
            focusedBorder: border.copyWith(borderSide: BorderSide(color: c.accent, width: 2)),
          ),
        ),
      ),
    );
  }

  String _detectedLabel(AppLocalizations l) {
    final detected = TranslationLanguage.fromCode(_sourceLang);
    return detected == null
        ? l.fullTranslationSourceLangDetect
        : l.fullTranslationSourceDetected(l.translationLanguageName(detected));
  }

  Widget _buildBanner({required IconData icon, required String title, required String desc, Widget? action}) {
    final c = context.mmColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: c.secondaryLabel),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.mmText.callout.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(desc, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
                if (action != null) ...[const SizedBox(height: 8), action],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormRow({
    required String label,
    required Widget child,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
  }) {
    final c = context.mmColors;
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: context.mmText.callout.copyWith(color: c.secondaryLabel)),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildEstimateRow({
    required IconData icon,
    Color? iconColor,
    required String content,
    Color? contentColor,
    String? trailing,
  }) {
    final c = context.mmColors;
    return Row(
      children: [
        Icon(icon, size: 14, color: iconColor ?? c.secondaryLabel),
        const SizedBox(width: 8),
        Expanded(
          child: Text(content, style: context.mmText.footnote.copyWith(color: contentColor ?? c.label)),
        ),
        if (trailing != null) Text(trailing, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.title, required this.desc, required this.selected, required this.onTap});

  final String title;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.quaternaryFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? c.accent : Colors.transparent, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(top: 2, right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? c.accent : c.secondaryLabel, width: 1.5),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.mmText.callout.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(desc, style: context.mmText.footnote.copyWith(color: c.secondaryLabel, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
