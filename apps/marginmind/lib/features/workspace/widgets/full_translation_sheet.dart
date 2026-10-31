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
  final language = targetLang ?? fullTranslationTargetLanguage(info.language);
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
  bool _rangeAll = true;
  late final TextEditingController _fromController;
  late final TextEditingController _toController;
  late final TextEditingController _noteController;
  late TranslationMode _mode;
  int _batchSize = 10;
  Timer? _estimateDebounce;
  int _pageCount = 1;
  bool _initialized = false;
  bool _starting = false;

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
    _fromController.addListener(_onInputChanged);
    _toController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _estimateDebounce?.cancel();
    _fromController.dispose();
    _toController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    setState(() {});
  }

  int get _from => int.tryParse(_fromController.text.trim()) ?? 1;
  int get _to => int.tryParse(_toController.text.trim()) ?? _pageCount;

  bool get _isValidRange {
    final f = _rangeAll ? 1 : _from;
    final t = _rangeAll ? _pageCount : _to;
    return f >= 1 && t <= _pageCount && f <= t;
  }

  Future<void> _start(Document doc, FullTranslationEstimation estimation, String modelName) async {
    if (!_isValidRange) return;
    final f = _rangeAll ? 1 : _from;
    final t = _rangeAll ? _pageCount : _to;
    final firstTo = _mode == TranslationMode.batch ? math.min(t, f + _batchSize - 1) : t;
    final l = context.l10n;
    final hudMessage = _mode == TranslationMode.batch
        ? l.fullTranslationHudStartBatch(f, firstTo)
        : l.fullTranslationHudStartAll;
    final readerWidth = ReaderCompareWidth.of(context);

    if (_starting) return;
    setState(() => _starting = true);
    final prefs = ref.read(sharedPreferencesProvider);
    final compareController = ref.read(readerCompareProvider(widget.studySetId).notifier);
    final controller = ref.read(fullTranslationProvider((widget.studySetId, widget.documentId, _targetLang)).notifier);
    final note = _noteController.text;
    try {
      await prefs.setString('translation.full.mode', _mode.name);
      if (!mounted) return;
      await compareController.openAi(_targetLang, documentId: widget.documentId, readerWidth: readerWidth);
      if (!mounted) return;
      await controller.startJob(
        from: f,
        to: t,
        mode: _mode,
        batchSize: _batchSize,
        note: note,
        sourceLang: _sourceLang,
        modelName: modelName,
        estimatedTokens: estimation.tokens,
      );
      if (!mounted) return;
      compareController.pdf(widget.documentId).jumpToPage(f);
      MMHud.show(context, hudMessage);
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final l = context.l10n;
    final content = ref.watch(workspaceContentProvider(widget.studySetId));
    final doc = content?.document(widget.documentId);
    if (doc == null) return const SizedBox.shrink();

    final info = ref.watch(compareDocumentInfoProvider((widget.studySetId, widget.documentId))).value;
    _sourceLang = info?.language;
    final docPath = ref.read(workspaceProvider(widget.studySetId).notifier).filePath(doc);
    final ocr = ref.watch(readerOcrProvider(docPath));
    final paragraphsAsync = ref.watch(translationParagraphsProvider((widget.studySetId, widget.documentId)));
    final paragraphs = paragraphsAsync.value ?? const <TranslationParagraph>[];

    if (!_initialized && paragraphs.isNotEmpty) {
      _initialized = true;
      _pageCount = paragraphs.map((p) => p.page).fold(doc.pageCount, math.max);
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
    final disabled =
        _starting ||
        fullState.loading ||
        fullState.loadError != null ||
        !valid ||
        nothing ||
        isScanned ||
        noModel ||
        badKey;
    final firstTo = _mode == TranslationMode.batch ? math.min(t, f + _batchSize - 1) : t;
    final primaryLabel = nothing
        ? l.fullTranslationNothingToTranslate
        : _mode == TranslationMode.batch
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
    } else if (noModel || badKey) {
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
    } else if (isOffline) {
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
          const SingleActivator(LogicalKeyboardKey.enter): () {
            if (!disabled && estimation != null) {
              _start(doc, estimation, modelName);
            }
          },
        },
        child: Focus(
          autofocus: true,
          child: MMSheet(
            title: l.fullTranslationTitle,
            titleTrailing: Text(
              l.fullTranslationDocSubtitle(doc.title, _pageCount),
              style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
            ),
            actions: [
              MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
              MMButton(
                label: primaryLabel,
                variant: MMButtonVariant.primary,
                onPressed: disabled || estimation == null ? null : () => _start(doc, estimation, modelName),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (blockedBanner != null) ...[blockedBanner, const SizedBox(height: 16)],
                _buildFormRow(
                  label: l.language,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: c.quaternaryFill,
                          borderRadius: BorderRadius.circular(MMRadii.row),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _sourceLang == 'zh' ? l.languageCodeZh : l.languageCodeEn,
                              style: context.mmText.callout,
                            ),
                            Text(
                              '（${l.fullTranslationSourceLangDetect}）',
                              style: context.mmText.callout.copyWith(color: c.secondaryLabel),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('→', style: context.mmText.callout.copyWith(color: c.secondaryLabel)),
                      ),
                      MMDropdownButton<String>(
                        width: 140,
                        onSelected: (val) {
                          setState(() => _targetLang = val);
                          ref.read(sharedPreferencesProvider).setString('settings.translationLanguage', val);
                        },
                        itemBuilder: (_) => [
                          for (final lang in TranslationLanguage.values)
                            MMDropdownItem(
                              value: lang.code,
                              child: Text(
                                lang.code == 'zh' ? l.languageCodeZh : l.languageCodeEn,
                                style: context.mmText.callout,
                              ),
                            ),
                        ],
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _targetLang == 'zh' ? l.languageCodeZh : l.languageCodeEn,
                              style: context.mmText.callout,
                            ),
                            const SizedBox(width: 4),
                            const Icon(MMIcons.chevronDown, size: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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
                      SizedBox(
                        width: 56,
                        height: 28,
                        child: TextField(
                          controller: _fromController,
                          enabled: !_rangeAll,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: context.mmText.callout,
                          decoration: InputDecoration(
                            contentPadding: EdgeInsets.zero,
                            filled: true,
                            fillColor: _rangeAll ? c.quaternaryFill.withValues(alpha: 0.5) : c.quaternaryFill,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text('–', style: context.mmText.callout.copyWith(color: c.secondaryLabel)),
                      ),
                      SizedBox(
                        width: 56,
                        height: 28,
                        child: TextField(
                          controller: _toController,
                          enabled: !_rangeAll,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: context.mmText.callout,
                          decoration: InputDecoration(
                            contentPadding: EdgeInsets.zero,
                            filled: true,
                            fillColor: _rangeAll ? c.quaternaryFill.withValues(alpha: 0.5) : c.quaternaryFill,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
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
                const SizedBox(height: 12),
                _buildFormRow(
                  label: l.fullTranslationNote,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  child: TextField(
                    controller: _noteController,
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
                        if (estimation.skipped > 0 || estimation.same > 0 || estimation.dupe > 0) ...[
                          const SizedBox(height: 6),
                          _buildEstimateRow(
                            icon: MMIcons.skip,
                            content: l.fullTranslationEstSkip(
                              [
                                if (estimation.skipped > 0) l.fullTranslationEstSkipMargin(estimation.skipped),
                                if (estimation.same > 0) l.fullTranslationEstSkipSame(estimation.same),
                                if (estimation.dupe > 0) l.fullTranslationEstSkipDupe(estimation.dupe),
                              ].join(' · '),
                            ),
                          ),
                        ],
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
                const SizedBox(height: 14),
                Text(l.fullTranslationFooterNote, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
              ],
            ),
          ),
        ),
      ),
    );
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
