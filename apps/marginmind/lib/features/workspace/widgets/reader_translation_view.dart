import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../settings/app_settings.dart';
import '../../../shared/l10n.dart';
import '../full_translation.dart';
import '../reader_compare.dart';
import '../reader_translation.dart';
import '../workspace_controller.dart';
import 'full_translation_capsule.dart';
import 'full_translation_checkpoint.dart';
import 'notices.dart';
import 'reader_compare_controls.dart';
import 'reflow_translation_view.dart';
import 'translation_paragraph.dart';

class ReaderTranslationView extends ConsumerStatefulWidget {
  const ReaderTranslationView({super.key, required this.studySetId});
  final String studySetId;
  @override
  ConsumerState<ReaderTranslationView> createState() => _ReaderTranslationViewState();
}

class _ReaderTranslationViewState extends ConsumerState<ReaderTranslationView> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
  final _viewport = GlobalKey();
  final _keys = <String, GlobalKey>{};
  bool _moving = false, _fromRight = false, _rightInput = false;
  bool _recoveredHudShown = false;
  String? _recoveredHudKey;
  int _epoch = 0;
  String? _document;
  ReaderTranslationController get _session => ref.read(readerTranslationProvider(widget.studySetId).notifier);
  double get _line => (_viewport.currentContext?.findRenderObject() as RenderBox?)?.size.height == null
      ? 0
      : (_viewport.currentContext!.findRenderObject() as RenderBox).size.height * .25;
  double? _top(String key) {
    final box = _keys[key]?.currentContext?.findRenderObject() as RenderBox?;
    final viewport = _viewport.currentContext?.findRenderObject() as RenderBox?;
    return box == null || viewport == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero, ancestor: viewport).dy;
  }

  ({TranslationParagraph paragraph, double fraction, double delta})? _anchor() {
    final paragraphs = ref.read(readerTranslationProvider(widget.studySetId)).paragraphs;
    TranslationParagraph? closest;
    double distance = double.infinity;
    for (final p in paragraphs) {
      final top = _top(p.fingerprint);
      if (top == null) continue;
      final height = (_keys[p.fingerprint]!.currentContext!.findRenderObject() as RenderBox).size.height;
      final d = _line < top
          ? top - _line
          : _line > top + height
          ? _line - top - height
          : 0.0;
      if (d < distance) {
        closest = p;
        distance = d;
      }
    }
    if (closest == null) return null;
    final top = _top(closest.fingerprint)!;
    final height = (_keys[closest.fingerprint]!.currentContext!.findRenderObject() as RenderBox).size.height;
    return (paragraph: closest, fraction: ((_line - top) / height).clamp(0, 1), delta: top - _line);
  }

  void _jump(double offset) {
    if (!_scroll.hasClients) return;
    _moving = true;
    _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
    _moving = false;
  }

  void _source(PdfReadingPosition? position) {
    if (!mounted ||
        position == null ||
        !_scroll.hasClients ||
        ref.read(readerCompareProvider(widget.studySetId))?.sync != true) {
      return;
    }
    if (_fromRight || _rightInput) return;
    final paragraphs = ref.read(readerTranslationProvider(widget.studySetId)).paragraphs;
    final onPage = paragraphs.where((p) => p.page == position.page).toList();
    if (onPage.isEmpty) return;
    final p = onPage.lastWhere((p) => p.bounds.top >= position.y, orElse: () => onPage.first);
    final top = _top(p.fingerprint);
    if (top == null) return;
    final height = (_keys[p.fingerprint]!.currentContext!.findRenderObject() as RenderBox).size.height;
    final fraction = ((p.bounds.top - position.y) / (p.bounds.top - p.bounds.bottom)).clamp(0, 1);
    _jump(_scroll.offset + top + fraction * height - _line);
  }

  void _changed() {
    if (_moving || !mounted) return;
    final anchor = _anchor();
    if (anchor == null) return;
    final p = anchor.paragraph;
    final pair = ref.read(readerCompareProvider(widget.studySetId));
    if (pair?.right is AiCompareTarget) {
      ref
          .read(
            fullTranslationProvider((
              widget.studySetId,
              pair!.leftDocumentId,
              (pair.right as AiCompareTarget).targetLang,
            )).notifier,
          )
          .setCurrentReadingPage(p.page);
    }
    final visible = ref.read(readerTranslationProvider(widget.studySetId)).paragraphs.where((p) {
      final top = _top(p.fingerprint);
      final box = _keys[p.fingerprint]?.currentContext?.findRenderObject() as RenderBox?;
      return top != null && box != null && top + box.size.height > 0 && top < _line * 4;
    });
    if (_rightInput) _session.prioritize(visible.map((p) => p.index), p.index);
    if (!_rightInput || ref.read(readerCompareProvider(widget.studySetId))?.sync != true) return;
    final pdf = ref.read(readerCompareProvider(widget.studySetId).notifier).pdf(pair!.leftDocumentId);
    final epoch = _epoch;
    _fromRight = true;
    unawaited(
      pdf
          .jumpToReadingPosition(
            PdfReadingPosition(page: p.page, y: p.bounds.top - (p.bounds.top - p.bounds.bottom) * anchor.fraction),
          )
          .then((_) async {
            await WidgetsBinding.instance.endOfFrame;
            if (mounted && epoch == _epoch) _fromRight = false;
          }),
    );
  }

  void _jumpToPage(int page) {
    final pair = ref.read(readerCompareProvider(widget.studySetId));
    if (pair != null) {
      final pdf = ref.read(readerCompareProvider(widget.studySetId).notifier).pdf(pair.leftDocumentId);
      unawaited(pdf.jumpToReadingPosition(PdfReadingPosition(page: page, y: 1.0)));
    }
    final paragraphs = ref.read(readerTranslationProvider(widget.studySetId)).paragraphs;
    final onPage = paragraphs.where((p) => p.page == page).toList();
    if (onPage.isNotEmpty) {
      final top = _top(onPage.first.fingerprint);
      if (top != null) {
        _jump(_scroll.offset + top - _line);
      }
    }
  }

  void _input() {
    _rightInput = true;
    _epoch++;
    // A wheel event can move the child scrollable before this listener runs.
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _rightInput) _changed();
    });
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_changed);
  }

  @override
  void dispose() {
    _epoch++;
    _scroll.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(readerCompareProvider(widget.studySetId))?.leftDocumentId;
    if (ref.watch(workspaceContentProvider(widget.studySetId))?.document(source ?? '')?.contentManifest != null) {
      return ReflowTranslationView(studySetId: widget.studySetId);
    }
    final provider = readerTranslationProvider(widget.studySetId);
    final state = ref.watch(provider);
    final pair = ref.watch(readerCompareProvider(widget.studySetId));
    if (pair == null) return const SizedBox.shrink();
    final right = pair.right;
    if (right is! AiCompareTarget) return const SizedBox.shrink();
    final language = right.targetLang;
    final documentId = pair.leftDocumentId;
    final doc = ref.watch(workspaceContentProvider(widget.studySetId))?.document(documentId);
    final canFullTranslate =
        MMPlatformCapabilities.current.assistant &&
        MMSizeClass.of(context) != MMSizeClass.compact &&
        doc?.format == DocumentFormat.pdf;
    final animate = !state.failed && !state.complete && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_shimmer.isAnimating) _shimmer.repeat(reverse: true);
    if (!animate && _shimmer.isAnimating) _shimmer.stop();
    final fullState = ref.watch(fullTranslationProvider((widget.studySetId, documentId, language)));
    final c = context.mmColors, l = context.l10n;
    final style = ref.watch(settingsProvider.select((s) => s.readerStyle));

    final recoveredKey = '$documentId:$language:${fullState.job?.id}';
    if (_recoveredHudKey != recoveredKey) {
      _recoveredHudKey = recoveredKey;
      _recoveredHudShown = false;
    }

    ref.listen(fullTranslationProvider((widget.studySetId, documentId, language)).select((s) => s.recoveredQuit), (
      prev,
      isRecovered,
    ) {
      if (isRecovered == true && !_recoveredHudShown) {
        _recoveredHudShown = true;
        final current = ref.read(fullTranslationProvider((widget.studySetId, documentId, language)));
        final pausedPage = current.firstUnfinishedPage;
        MMHud.show(
          context,
          l.fullTranslationHudPausedAt(pausedPage),
          icon: MMIcons.pause,
          action: (
            l.fullTranslationHudContinue,
            () {
              if (mounted) {
                ref.read(fullTranslationProvider((widget.studySetId, documentId, language)).notifier).resume();
              }
            },
          ),
        );
      }
    });

    if (fullState.recoveredQuit && !_recoveredHudShown) {
      _recoveredHudShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final pausedPage = fullState.firstUnfinishedPage;
        MMHud.show(
          context,
          l.fullTranslationHudPausedAt(pausedPage),
          icon: MMIcons.pause,
          action: (
            l.fullTranslationHudContinue,
            () {
              if (mounted) {
                ref.read(fullTranslationProvider((widget.studySetId, documentId, language)).notifier).resume();
              }
            },
          ),
        );
      });
    }

    if (_document != documentId) {
      _document = documentId;
      _keys.clear();
      _epoch++;
      _fromRight = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jump(0);
      });
    }
    ref.listen(translationSourceInputProvider(widget.studySetId), (_, _) {
      _epoch++;
      _fromRight = false;
      _rightInput = false;
    });
    ref.listen(provider.select((s) => s.position), (_, position) {
      final epoch = _epoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && epoch == _epoch) _source(position);
      });
    });
    ref.listen(provider.select((s) => s.values), (_, _) {
      final anchor = _anchor(), epoch = _epoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || epoch != _epoch) return;
        if (anchor != null && anchor.paragraph.page == ref.read(provider).page) {
          final top = _top(anchor.paragraph.fingerprint);
          if (top != null) _jump(_scroll.offset + top - _line - anchor.delta);
        } else {
          _source(ref.read(readerCompareProvider(widget.studySetId).notifier).pdf(documentId).readingPosition);
        }
      });
    });
    final annotations = <int, List<Annotation>>{};
    for (final a in ref.watch(workspaceContentProvider(widget.studySetId))?.annotations ?? const <Annotation>[]) {
      if (a.documentId != documentId) continue;
      for (final page in a.isText ? <AnnotationPage>[] : a.pages) {
        (annotations[page.page] ??= []).add(a);
      }
    }
    Color? marked(TranslationParagraph p) {
      for (final a in annotations[p.page] ?? const <Annotation>[]) {
        if (a.quote.isNotEmpty &&
            state.values[p.fingerprint]?.contains(a.quote) == true &&
            !a.isText &&
            a.pages.any((page) => page.page == p.page && listEquals(page.rects, p.rects))) {
          return MMAnnotationColor.fromIndex(a.colorIndex).highlight;
        }
      }
      return null;
    }

    final pages = state.paragraphs.map((p) => p.page).toSet().toList();
    return Column(
      children: [
        Container(
          height: context.mmTouch ? MMSizes.touchTarget : MMSizes.readerCompareHeader,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.separator, width: .5)),
          ),
          child: Row(
            children: [
              ReaderCompareMenu(studySetId: widget.studySetId, document: doc, translationLanguage: language),
              const SizedBox(width: 6),
              if (canFullTranslate && fullState.job != null) ...[
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FullTranslationCapsule(
                      studySetId: widget.studySetId,
                      documentId: documentId,
                      targetLang: language,
                    ),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: Row(
                    children: [
                      if (!state.complete && !state.failed) ...[
                        const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: MMPill(
                          state.failed
                              ? l.compareTranslationFailed
                              : state.complete
                              ? (state.pageParagraphs.isEmpty
                                    ? l.compareTranslationPageEmpty
                                    : l.compareTranslationPageSaved(state.page))
                              : l.compareTranslationPageProgress(
                                  state.page,
                                  state.pageDone,
                                  state.pageParagraphs.length,
                                ),
                          key: const ValueKey('translation-status'),
                          icon: state.complete ? MMIcons.check : null,
                          color: state.failed
                              ? c.critical
                              : state.complete
                              ? c.positive
                              : null,
                        ),
                      ),
                      if (state.failed) TextButton(onPressed: _session.retry, child: Text(l.assistantRetry)),
                    ],
                  ),
                ),
              ],
              if (canFullTranslate && fullState.job == null) ...[
                const SizedBox(width: 6),
                FullTranslationCapsule(studySetId: widget.studySetId, documentId: documentId, targetLang: language),
              ],
              MMIconButton(
                key: const ValueKey('compare-exit'),
                icon: MMIcons.close,
                tooltip: '${l.compareExit} (Esc)',
                size: 24,
                iconSize: 12,
                onPressed: ref.read(readerCompareProvider(widget.studySetId).notifier).exit,
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  onPointerSignal: (_) => _input(),
                  onPointerDown: (_) => _input(),
                  onPointerPanZoomStart: (_) => _input(),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scale = ((constraints.maxWidth - 32) / 612).clamp(.3, 2.0);
                      return SingleChildScrollView(
                        key: _viewport,
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            for (final page in pages)
                              _buildPage(
                                context,
                                page,
                                scale,
                                state,
                                fullState,
                                style,
                                c,
                                l,
                                marked,
                                documentId,
                                language,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (fullState.job?.state == TranslationJobState.review)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Center(
                    child: FullTranslationCheckpoint(
                      studySetId: widget.studySetId,
                      documentId: documentId,
                      targetLang: language,
                      onJumpToPage: _jumpToPage,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPage(
    BuildContext context,
    int page,
    double scale,
    ReaderTranslationState state,
    FullTranslationState fullState,
    MMReaderStyle style,
    MMColors c,
    AppLocalizations l,
    Color? Function(TranslationParagraph) marked,
    String leftDocId,
    String language,
  ) {
    final pageParagraphs = state.paragraphs.where((p) => p.page == page).toList();
    final ps = fullState.pageState(page);
    final job = fullState.job;
    final live = job != null && job.state != TranslationJobState.done && job.state != TranslationJobState.stopped;

    Widget? placeholder;
    if (ps == TranslationPageState.none) {
      if (live && fullState.inRange(page)) {
        final batchOfPage = fullState.batchOf(page);
        placeholder = _PagePlaceholder(
          icon: MMIcons.later,
          title: l.fullTranslationPlaceholderBatch(batchOfPage),
          subtitle: l.fullTranslationPlaceholderPageSub(page),
        );
      } else if (live && !fullState.inRange(page)) {
        placeholder = _PagePlaceholder(
          icon: MMIcons.translate,
          title: l.fullTranslationPlaceholderOutOfRange,
          actionText: l.fullTranslationTranslatePage,
          onAction: () =>
              ref.read(fullTranslationProvider((widget.studySetId, leftDocId, language)).notifier).translatePage(page),
        );
      } else if (!live && pageParagraphs.every((p) => !state.values.containsKey(p.fingerprint))) {
        placeholder = _PagePlaceholder(
          icon: MMIcons.translate,
          title: l.fullTranslationPlaceholderUntranslated,
          actionText: l.fullTranslationTranslatePage,
          onAction: () =>
              ref.read(fullTranslationProvider((widget.studySetId, leftDocId, language)).notifier).translatePage(page),
        );
      }
    }

    return Container(
      key: ValueKey('translation-page-$page'),
      width: double.infinity,
      constraints: BoxConstraints(minHeight: 720 * scale),
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.fromLTRB(54 * scale, 48 * scale, 54 * scale, 60 * scale),
      decoration: BoxDecoration(
        color: style.paperColor,
        boxShadow: c.flat ? null : const [BoxShadow(color: Color(0x22000000), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (placeholder != null)
            placeholder
          else
            for (final p in pageParagraphs)
              MouseRegion(
                key: _keys.putIfAbsent(p.fingerprint, GlobalKey.new),
                onEnter: (_) => _session.hover(p.fingerprint),
                onExit: (_) => _session.hover(null),
                child: Container(
                  key: ValueKey('translation-paragraph-${p.index}'),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  decoration: BoxDecoration(
                    color: state.hovered == p.fingerprint ? c.accent.withValues(alpha: .09) : marked(p),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: TranslationParagraphView(
                    studySetId: widget.studySetId,
                    language: language,
                    paragraph: p,
                    value: state.values[p.fingerprint],
                    style: MMTypography.readingBody.copyWith(
                      color: style.inkColor,
                      fontSize: 16.5 * scale,
                      height: 1.7,
                      fontWeight: p.heading ? FontWeight.w600 : FontWeight.normal,
                    ),
                    contextMenuBuilder: (context, editable) => AdaptiveTextSelectionToolbar.buttonItems(
                      anchors: editable.contextMenuAnchors,
                      buttonItems: [
                        ...editable.contextMenuButtonItems,
                        ContextMenuButtonItem(label: l.excerptAction, onPressed: () => _mark(p, editable, false)),
                        ContextMenuButtonItem(label: l.highlightAction, onPressed: () => _mark(p, editable, true)),
                      ],
                    ),
                    placeholder: FadeTransition(
                      opacity: Tween<double>(begin: .3, end: .6).animate(_shimmer),
                      child: SizedBox(
                        height: (p.bounds.top - p.bounds.bottom) * scale,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                            height: double.infinity,
                            decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 28),
          Text(
            '$page',
            textAlign: TextAlign.center,
            style: context.mmText.footnote.copyWith(color: style.inkColor.withValues(alpha: .5)),
          ),
        ],
      ),
    );
  }

  Future<void> _mark(TranslationParagraph p, EditableTextState editable, bool highlight) async {
    final value = editable.textEditingValue;
    final selected = value.selection.textInside(value.text).trim();
    editable.hideToolbar();
    if (selected.isEmpty) return;
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    final selection = MMPdfSelection(page: p.page, rects: p.rects, text: selected);
    try {
      final notice = highlight
          ? await workspace.highlight(p.documentId, selection, ref.read(workspaceProvider(widget.studySetId)).color)
          : await workspace.excerpt(p.documentId, selection, ref.read(workspaceProvider(widget.studySetId)).color);
      if (mounted) showNotice(context, notice, rootTitle: '');
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong);
    }
  }
}

class _PagePlaceholder extends StatelessWidget {
  const _PagePlaceholder({required this.icon, required this.title, this.subtitle, this.actionText, this.onAction});

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return Container(
      constraints: const BoxConstraints(minHeight: 260),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: c.secondaryLabel.withValues(alpha: .6)),
          const SizedBox(height: 8),
          Text(title, style: context.mmText.body.copyWith(color: c.secondaryLabel, fontSize: 13)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: context.mmText.footnote.copyWith(color: c.secondaryLabel.withValues(alpha: .6))),
          ],
          if (actionText != null && onAction != null) ...[
            const SizedBox(height: 10),
            MMButton(label: actionText!, variant: MMButtonVariant.plain, color: c.accent, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}
