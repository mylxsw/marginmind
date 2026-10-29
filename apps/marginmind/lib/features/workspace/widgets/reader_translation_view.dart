import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../settings/app_settings.dart';
import '../../../shared/l10n.dart';
import '../reader_compare.dart';
import '../reader_translation.dart';
import '../workspace_controller.dart';
import 'notices.dart';
import 'reader_compare_controls.dart';

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
    final visible = ref.read(readerTranslationProvider(widget.studySetId)).paragraphs.where((p) {
      final top = _top(p.fingerprint);
      final box = _keys[p.fingerprint]?.currentContext?.findRenderObject() as RenderBox?;
      return top != null && box != null && top + box.size.height > 0 && top < _line * 4;
    });
    if (_rightInput) _session.prioritize(visible.map((p) => p.index), p.index);
    if (!_rightInput || ref.read(readerCompareProvider(widget.studySetId))?.sync != true) return;
    final pair = ref.read(readerCompareProvider(widget.studySetId))!;
    final pdf = ref.read(readerCompareProvider(widget.studySetId).notifier).pdf(pair.leftDocumentId);
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
    final provider = readerTranslationProvider(widget.studySetId);
    final state = ref.watch(provider);
    final pair = ref.watch(readerCompareProvider(widget.studySetId))!;
    final animate = !state.failed && !state.complete && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_shimmer.isAnimating) _shimmer.repeat(reverse: true);
    if (!animate && _shimmer.isAnimating) _shimmer.stop();
    final language = (pair.right as AiCompareTarget).targetLang;
    final doc = ref.read(workspaceProvider(widget.studySetId).notifier).content.document(pair.leftDocumentId)!;
    final c = context.mmColors, l = context.l10n;
    final style = ref.watch(settingsProvider.select((s) => s.readerStyle));
    if (_document != doc.id) {
      _document = doc.id;
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
          _source(ref.read(readerCompareProvider(widget.studySetId).notifier).pdf(doc.id).readingPosition);
        }
      });
    });
    final annotations = <int, List<Annotation>>{};
    for (final a in ref.watch(workspaceContentProvider(widget.studySetId))?.annotations ?? const <Annotation>[]) {
      if (a.documentId != doc.id) continue;
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
                            : l.compareTranslationPageProgress(state.page, state.pageDone, state.pageParagraphs.length),
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
                        Container(
                          key: ValueKey('translation-page-$page'),
                          width: double.infinity,
                          constraints: BoxConstraints(minHeight: 720 * scale),
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: EdgeInsets.fromLTRB(54 * scale, 48 * scale, 54 * scale, 60 * scale),
                          decoration: BoxDecoration(
                            color: style.paperColor,
                            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 3, offset: Offset(0, 1))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final p in state.paragraphs.where((p) => p.page == page))
                                MouseRegion(
                                  key: _keys.putIfAbsent(p.fingerprint, GlobalKey.new),
                                  onEnter: (_) => _session.hover(p.fingerprint),
                                  onExit: (_) => _session.hover(null),
                                  child: Container(
                                    key: ValueKey('translation-paragraph-${p.index}'),
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                    decoration: BoxDecoration(
                                      color: state.hovered == p.fingerprint
                                          ? c.accent.withValues(alpha: .09)
                                          : marked(p),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: state.values.containsKey(p.fingerprint)
                                        ? SelectableText(
                                            state.values[p.fingerprint]!,
                                            style: MMTypography.readingBody.copyWith(
                                              color: style.inkColor,
                                              fontSize: 16.5 * scale,
                                              height: 1.7,
                                              fontWeight: p.heading ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                            contextMenuBuilder: (context, editable) =>
                                                AdaptiveTextSelectionToolbar.buttonItems(
                                                  anchors: editable.contextMenuAnchors,
                                                  buttonItems: [
                                                    ...editable.contextMenuButtonItems,
                                                    ContextMenuButtonItem(
                                                      label: l.excerptAction,
                                                      onPressed: () => _mark(p, editable, false),
                                                    ),
                                                    ContextMenuButtonItem(
                                                      label: l.highlightAction,
                                                      onPressed: () => _mark(p, editable, true),
                                                    ),
                                                  ],
                                                ),
                                          )
                                        : FadeTransition(
                                            opacity: Tween<double>(begin: .3, end: .6).animate(_shimmer),
                                            child: SizedBox(
                                              height: (p.bounds.top - p.bounds.bottom) * scale,
                                              child: Align(
                                                alignment: Alignment.topLeft,
                                                child: Container(
                                                  height: double.infinity,
                                                  decoration: BoxDecoration(
                                                    color: c.quaternaryFill,
                                                    borderRadius: BorderRadius.circular(4),
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
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
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
