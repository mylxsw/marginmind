import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';
import '../reader_ocr.dart';
import '../workspace_controller.dart';

/// Shared by the native menu and the reader's quick entry.
Future<void> showReaderOcrOptions(BuildContext context, WidgetRef ref, String studySetId) async {
  final workspace = ref.read(workspaceProvider(studySetId).notifier);
  final id = ref.read(workspaceProvider(studySetId)).activeDocumentId;
  final doc = id == null ? null : workspace.content.document(id);
  if (doc == null || !ref.read(pdfOcrServiceProvider).supported) return;
  final source = workspace.filePath(doc);
  await ref.read(readerOcrProvider(source).notifier).inspect();
  if (!context.mounted || !ref.context.mounted) return;
  final state = ref.read(readerOcrProvider(source));
  if (state.running || state.document == null) return;
  final page = workspace.activePage ?? 1;
  await showMMSheet<void>(
    context: context,
    builder: (_) => _OcrOptions(source: source, page: page, pageCount: doc.pageCount),
  );
}

class ReaderOcrControls extends ConsumerStatefulWidget {
  const ReaderOcrControls({
    super.key,
    required this.source,
    required this.studySetId,
    required this.documentId,
    required this.initialPage,
    required this.onRecognize,
  });
  final String source;
  final String studySetId;
  final String documentId;
  final int initialPage;
  final VoidCallback onRecognize;

  @override
  ConsumerState<ReaderOcrControls> createState() => _ReaderOcrControlsState();
}

class _ReaderOcrControlsState extends ConsumerState<ReaderOcrControls> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) unawaited(ref.read(readerOcrProvider(widget.source).notifier).inspect());
    });
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final page =
        ref.watch(readingPagesProvider(widget.studySetId).select((pages) => pages[widget.documentId])) ??
        widget.initialPage;
    final state = ref.watch(readerOcrProvider(source));
    final l = context.l10n;
    final document = state.document;
    if (state.running) return const SizedBox.shrink();
    if (document == null && !state.failed) return const SizedBox.shrink();
    final hasText = document?.textPages.contains(page) ?? false;
    if (!state.running && hasText && !document!.hasCopy && !state.failed) return const SizedBox.shrink();
    final label = state.failed
        ? l.ocrFailed
        : state.cancelled
        ? l.ocrCancelled
        : hasText
        ? l.ocrReady
        : l.ocrNoText;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.s),
      child: Container(
        padding: const EdgeInsets.all(MMSpacing.s),
        decoration: BoxDecoration(
          color: context.mmColors.card,
          borderRadius: BorderRadius.circular(MMRadii.field),
          border: Border.all(color: context.mmColors.separator),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [Text(label, style: context.mmText.footnote)],
              ),
            ),
            const SizedBox(width: MMSpacing.s),
            if (!hasText || (document?.textPages.length ?? 0) < (document?.pageCount ?? 0))
              MMButton(label: l.ocrRecognize, onPressed: widget.onRecognize),
          ],
        ),
      ),
    );
  }
}

class ReaderOcrProgress extends ConsumerWidget {
  const ReaderOcrProgress({super.key, required this.source});
  final String source;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(readerOcrProvider(source));
    if (!state.running) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s),
      decoration: BoxDecoration(
        color: context.mmColors.card,
        borderRadius: BorderRadius.circular(MMRadii.capsule),
        border: Border.all(color: context.mmColors.separator),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.l10n.ocrProgress(state.done, state.total), style: context.mmText.footnote),
          const SizedBox(width: MMSpacing.s),
          SizedBox(
            width: MMSpacing.xxxl,
            child: MMProgressBar(value: state.total == 0 ? 0 : state.done / state.total),
          ),
          MMToolbarButton(
            icon: MMIcons.close,
            tooltip: context.l10n.cancel,
            onPressed: state.cancelling ? null : () => ref.read(readerOcrProvider(source).notifier).cancel(),
          ),
        ],
      ),
    );
  }
}

class _OcrOptions extends ConsumerStatefulWidget {
  const _OcrOptions({required this.source, required this.page, required this.pageCount});
  final String source;
  final int page;
  final int pageCount;
  @override
  ConsumerState<_OcrOptions> createState() => _OcrOptionsState();
}

enum _Scope { all, current, range }

class _OcrOptionsState extends ConsumerState<_OcrOptions> {
  _Scope _scope = _Scope.all;
  PdfOcrLanguage _language = PdfOcrLanguage.chineseEnglish;
  late final _first = TextEditingController(text: '${widget.page}');
  late final _last = TextEditingController(text: '${widget.pageCount}');

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final first = switch (_scope) {
      _Scope.all => 1,
      _Scope.current => widget.page,
      _Scope.range => int.tryParse(_first.text.trim()) ?? 0,
    };
    final last = switch (_scope) {
      _Scope.all => widget.pageCount,
      _Scope.current => widget.page,
      _Scope.range => int.tryParse(_last.text.trim()) ?? 0,
    };
    final valid = first >= 1 && last >= first && last <= widget.pageCount;
    return MMSheet(
      title: l.ocrRecognize,
      actions: [
        MMButton(label: l.cancel, onPressed: () => Navigator.pop(context)),
        MMButton(
          label: l.ocrStart,
          variant: MMButtonVariant.primary,
          onPressed: !valid
              ? null
              : () {
                  final controller = ref.read(readerOcrProvider(widget.source).notifier);
                  Navigator.pop(context);
                  unawaited(controller.recognize(first, last, _language));
                },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.ocrScope, style: context.mmText.footnote),
          const SizedBox(height: MMSpacing.s),
          MMSegmentedControl<_Scope>(
            value: _scope,
            segments: [
              MMSegment(value: _Scope.all, label: l.ocrAllPages),
              MMSegment(value: _Scope.current, label: l.ocrCurrentPage),
              MMSegment(value: _Scope.range, label: l.ocrPageRange),
            ],
            onChanged: (value) => setState(() => _scope = value),
          ),
          if (_scope == _Scope.range) ...[
            const SizedBox(height: MMSpacing.s),
            Row(
              children: [
                Expanded(
                  child: MMTextField(
                    key: const ValueKey('ocr-first'),
                    controller: _first,
                    semanticLabel: l.ocrFirstPage,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: MMSpacing.s),
                Expanded(
                  child: MMTextField(
                    key: const ValueKey('ocr-last'),
                    controller: _last,
                    semanticLabel: l.ocrLastPage,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (!valid) Text(l.ocrInvalidRange(widget.pageCount), style: context.mmText.footnote),
          ],
          const SizedBox(height: MMSpacing.m),
          Text(l.ocrLanguage, style: context.mmText.footnote),
          const SizedBox(height: MMSpacing.s),
          MMSegmentedControl<PdfOcrLanguage>(
            value: _language,
            segments: [
              MMSegment(value: PdfOcrLanguage.chineseEnglish, label: l.ocrChineseEnglish),
              MMSegment(value: PdfOcrLanguage.chinese, label: l.ocrChinese),
              MMSegment(value: PdfOcrLanguage.english, label: l.ocrEnglish),
            ],
            onChanged: (value) => setState(() => _language = value),
          ),
        ],
      ),
    );
  }
}
