import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_book/mm_book.dart' as book;
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/providers.dart';
import '../../shared/l10n.dart';
import 'web_document.dart';
import 'workspace_browser.dart';
import 'workspace_controller.dart';

final webDocumentConverterProvider = Provider<WebDocumentConverter>((ref) => const WebDocumentConverter());
typedef WebCapture = Future<BrowserDocumentCapture> Function(BrowserSession, int, WebCaptureMode, bool Function());
final webCaptureProvider = Provider<WebCapture>(
  (ref) =>
      (session, generation, mode, cancelled) => session.captureDocument(
        navigationId: generation,
        mode: BrowserDocumentMode.values.byName(mode.name),
        cancelled: cancelled,
      ),
);

Future<void> showWebConversion(BuildContext context, Ref ref, String studySetId, BrowserSession session) async {
  final owner = ref.read(workspaceBrowserProvider(studySetId).notifier);
  if (!owner.beginConversion()) return;
  session.dismissPrompt();
  final generation = session.navigationId;
  final controller = ref.read(workspaceProvider(studySetId).notifier);
  final previous = controller.content.document(
    ref.read(workspaceBrowserProvider(studySetId)).replacingDocumentId ?? '',
  );
  final id = previous?.id ?? newId();
  var abandoned = false;
  bool cancelled() => abandoned || !ref.mounted || session.disposed || session.navigationId != generation;
  try {
    final repository = ref.read(contentRepositoryProvider);
    if (repository is! DocumentRepository) throw StateError('Document storage unavailable');
    final oldChapters = <String, String>{};
    if (previous?.contentManifest case final path?) {
      final manifest =
          jsonDecode(utf8.decode(await (repository as DocumentRepository).readDocumentFile(studySetId, path))) as Map;
      for (final entry in manifest['spine'] as List) {
        final chapter = jsonDecode(
          utf8.decode(
            await (repository as DocumentRepository).readDocumentFile(studySetId, (entry as Map)['path'] as String),
          ),
        ) as Map;
        oldChapters[chapter['id'] as String] = chapter['canonicalText'] as String;
      }
    }
    final converter = ref.read(webDocumentConverterProvider);
    var captureQueue = Future<void>.value();
    final captures = <bool, Future<BrowserDocumentCapture>>{};
    Future<PreparedWebDocument> prepare(WebCaptureMode mode) async {
      final original = mode == WebCaptureMode.original;
      final pending = captures.putIfAbsent(original, () {
        final next = captureQueue.then(
          (_) => ref.read(webCaptureProvider)(
            session,
            generation,
            original ? WebCaptureMode.original : WebCaptureMode.readable,
            cancelled,
          ),
        );
        captureQueue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
        return next;
      });
      final BrowserDocumentCapture capture;
      try {
        capture = await pending;
      } catch (_) {
        if (identical(captures[original], pending)) captures.remove(original);
        rethrow;
      }
      if (cancelled()) throw StateError('stale_capture');
      return converter.prepare(
        capture,
        id: id,
        title: previous?.title ?? (capture.title.trim().isEmpty ? capture.url.host : capture.title),
        mode: mode,
        previous: previous,
        oldChapters: oldChapters,
      );
    }

    if (!context.mounted || cancelled()) return;
    final PreparedWebDocument? prepared;
    if (previous != null) {
      prepared = await prepare(previous.origin!.mode);
    } else {
      prepared = await showMMSheet<PreparedWebDocument>(
        context: context,
        width: MMSizes.webConversionSheetWidth,
        builder: (_) => WebConversionSheet(prepare: prepare),
      );
    }
    if (prepared == null || !context.mounted || cancelled()) return;
    MMHud.show(context, context.l10n.docSaving);
    await controller.saveWebDocument(prepared.package, cancelled: cancelled);
    if (!context.mounted || cancelled()) return;
    owner.close();
    final review = controller.content.annotations.where((a) => a.documentId == id && a.needsReview).toList();
    MMHud.show(
      context,
      review.isNotEmpty
          ? context.l10n.annotationsNeedReviewHud(review.length)
          : previous == null
          ? context.l10n.docSaved(prepared.package.document.title)
          : context.l10n.docUpdated,
      action: review.isEmpty
          ? null
          : (context.l10n.viewAction, () => controller.showReaderPanel(ReaderPanelMode.annotations)),
    );
  } catch (_) {
    if (context.mounted && !session.disposed) {
      MMHud.show(
        context,
        context.l10n.docSaveFailed,
        icon: MMIcons.warning,
        action: (context.l10n.webRetry, () => showWebConversion(context, ref, studySetId, session)),
      );
    }
  } finally {
    abandoned = true;
    if (ref.mounted) owner.endConversion();
  }
}

class WebConversionSheet extends StatefulWidget {
  const WebConversionSheet({super.key, required this.prepare});
  final Future<PreparedWebDocument> Function(WebCaptureMode) prepare;
  @override
  State<WebConversionSheet> createState() => _WebConversionSheetState();
}

class _WebConversionSheetState extends State<WebConversionSheet> {
  final _title = TextEditingController();
  final _prepared = <WebCaptureMode, Future<PreparedWebDocument>>{};
  WebCaptureMode _mode = WebCaptureMode.readable;
  bool _edited = false;
  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final compact = MMBottomSheet.contains(context);
    return FutureBuilder<PreparedWebDocument>(
      future: _prepared.putIfAbsent(_mode, () => widget.prepare(_mode)),
      builder: (context, snapshot) {
        final value = snapshot.connectionState == ConnectionState.done ? snapshot.data : null;
        if (value != null && !_edited) _title.text = value.package.document.title;
        final titleField = MMTextField(
          controller: _title,
          placeholder: l.convertTitlePlaceholder,
          semanticLabel: l.convertTitlePlaceholder,
          onChanged: (_) => setState(() => _edited = true),
        );
        final segments = MMSegmentedControl<WebCaptureMode>(
          expand: true,
          value: _mode,
          segments: [
            MMSegment(value: WebCaptureMode.readable, label: l.convertReadable),
            MMSegment(value: WebCaptureMode.original, label: l.convertPdf),
            MMSegment(value: WebCaptureMode.markdown, label: l.convertMarkdown),
          ],
          onChanged: (mode) => setState(() => _mode = mode),
        );
        final preview = Container(
          width: compact ? double.infinity : MMSizes.webConversionPreviewWidth,
          height: compact ? MMSizes.webConversionPreviewCompactHeight : MMSizes.webConversionPreviewHeight,
          padding: const EdgeInsets.all(MMSpacing.m),
          decoration: BoxDecoration(
            color: context.mmColors.quaternaryFill,
            borderRadius: BorderRadius.circular(MMRadii.card),
          ),
          child: snapshot.hasError
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(l.docSaveFailed, style: context.mmText.body),
                    MMButton(
                      label: l.webRetry,
                      onPressed: () => setState(() {
                        _prepared.remove(_mode);
                      }),
                    ),
                  ],
                )
              : value == null
              ? const Center(child: CircularProgressIndicator())
              : _Preview(value: value, mode: _mode),
        );
        final save = MMButton(
          label: l.save,
          variant: MMButtonVariant.primary,
          onPressed: value == null || _title.text.trim().isEmpty
              ? null
              : () {
                  final package = value.package;
                  Navigator.of(context).pop(
                    PreparedWebDocument(
                      DocumentPackage(
                        document: package.document.copyWith(title: _title.text.trim()),
                        files: package.files,
                        reconcile: package.reconcile,
                        expectedRevision: package.expectedRevision,
                        expectedSnapshotFile: package.expectedSnapshotFile,
                      ),
                      value.book,
                      value.markdown,
                      value.preview,
                    ),
                  );
                },
        );
        return MMSheet(
          title: l.convertTitle,
          actions: [
            MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
            if (!compact) save,
          ],
          child: compact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    titleField,
                    const SizedBox(height: MMSpacing.m),
                    segments,
                    const SizedBox(height: MMSpacing.m),
                    preview,
                    const SizedBox(height: MMSpacing.m),
                    save,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    preview,
                    const SizedBox(width: MMSpacing.l),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          titleField,
                          const SizedBox(height: MMSpacing.m),
                          segments,
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.value, required this.mode});
  final PreparedWebDocument value;
  final WebCaptureMode mode;
  @override
  Widget build(BuildContext context) {
    if (mode == WebCaptureMode.original && value.preview != null) {
      return Image.memory(value.preview!, fit: BoxFit.contain);
    }
    if (mode == WebCaptureMode.markdown) {
      return SingleChildScrollView(child: Text(value.markdown ?? '', style: MMTypography.mono));
    }
    if (value.book.chapters.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final block in value.book.chapters.first.blocks)
            Padding(
              padding: const EdgeInsets.only(bottom: MMSpacing.s),
              child: block.kind == book.BlockKind.image && value.book.resources[block.resource] != null
                  ? Image.memory(
                      value.book.resources[block.resource]!,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    )
                  : Text.rich(
                      TextSpan(
                        children: [
                          for (final run in block.runs)
                            TextSpan(
                              text: run.text,
                              style: TextStyle(
                                fontWeight: run.strong ? FontWeight.bold : null,
                                fontStyle: run.emphasis ? FontStyle.italic : null,
                              ),
                            ),
                        ],
                      ),
                      style: block.kind == book.BlockKind.heading ? context.mmText.headline : context.mmText.body,
                    ),
            ),
        ],
      ),
    );
  }
}
