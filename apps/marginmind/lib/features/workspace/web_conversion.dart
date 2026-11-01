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
    return FutureBuilder<PreparedWebDocument>(
      future: _prepared.putIfAbsent(_mode, () => widget.prepare(_mode)),
      builder: (context, snapshot) {
        final value = snapshot.connectionState == ConnectionState.done ? snapshot.data : null;
        if (value != null && !_edited) _title.text = value.package.document.title;
        final c = context.mmColors;
        final titleField = MMTextField(
          controller: _title,
          placeholder: l.convertTitlePlaceholder,
          semanticLabel: l.convertDocumentName,
          maxLines: 1,
          onChanged: (_) => setState(() => _edited = true),
        );
        final formats = [
          (WebCaptureMode.readable, l.convertReadable, MMIcons.document),
          (WebCaptureMode.original, l.convertPdf, MMIcons.pdf),
          (WebCaptureMode.markdown, l.convertMarkdown, MMIcons.markdown),
        ];
        final segments = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: MMSpacing.s,
          children: [
            for (final (mode, label, icon) in formats)
              _FormatOption(
                label: label,
                icon: icon,
                selected: _mode == mode,
                onTap: () => setState(() => _mode = mode),
              ),
          ],
        );
        final preview = Semantics(
          label: l.convertPreview,
          container: true,
          child: SizedBox.expand(
            key: const ValueKey('web-conversion-preview'),
            child: snapshot.hasError
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l.docSaveFailed, style: context.mmText.body),
                        const SizedBox(height: MMSpacing.m),
                        MMButton(
                          label: l.webRetry,
                          onPressed: () => setState(() {
                            _prepared.remove(_mode);
                          }),
                        ),
                      ],
                    ),
                  )
                : value == null
                ? const Center(child: CircularProgressIndicator())
                : _Preview(value: value, mode: _mode),
          ),
        );
        final save = MMButton(
          label: l.convertSave,
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
        Widget section(String label, Widget child) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: context.mmText.body.copyWith(color: c.secondaryLabel)),
            const SizedBox(height: MMSpacing.s),
            child,
          ],
        );
        return MMSheet(
          title: l.convertTitle,
          titleStyle: context.mmText.title3.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
          actions: [
            MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
            save,
          ],
          child: LayoutBuilder(
            builder: (context, constraints) {
              final settings = Column(
                key: const ValueKey('web-conversion-settings'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  section(l.convertDocumentName, titleField),
                  const SizedBox(height: MMSpacing.xxl),
                  section(l.convertFormat, segments),
                ],
              );
              final split = constraints.maxWidth >= 720;
              final previewHeight = (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom - 210)
                  .clamp(220.0, 600.0);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (split)
                    SizedBox(
                      height: previewHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 65, child: preview),
                          const SizedBox(width: MMSpacing.xl),
                          VerticalDivider(width: 1, thickness: 0.5, color: c.hairline),
                          const SizedBox(width: MMSpacing.xl),
                          Expanded(flex: 35, child: SingleChildScrollView(child: settings)),
                        ],
                      ),
                    )
                  else ...[
                    settings,
                    const SizedBox(height: MMSpacing.xl),
                    SizedBox(height: 300, child: preview),
                  ],
                  const SizedBox(height: MMSpacing.m),
                  Divider(height: 1, thickness: 0.5, color: c.hairline),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _FormatOption extends StatelessWidget {
  const _FormatOption({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: MMInteractive(
        semanticLabel: label,
        selected: selected,
        onTap: onTap,
        builder: (context, state) => Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? c.accentTint : (state.hovered || state.pressed ? c.hover : c.quaternaryFill),
            borderRadius: BorderRadius.circular(MMRadii.row),
            border: Border.all(color: selected || state.focused ? c.accent : c.hairline, width: selected ? 1 : 0.5),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: selected ? c.accent : c.secondaryLabel),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: context.mmText.headline)),
              const SizedBox(width: 8),
              Icon(
                selected ? MMIcons.radioSelected : MMIcons.radio,
                size: 16,
                color: selected ? c.accent : c.secondaryLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.value, required this.mode});
  final PreparedWebDocument value;
  final WebCaptureMode mode;
  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final origin = value.package.document.origin;
    final date = origin?.capturedAt.toLocal();
    final sourceHost = origin == null ? null : Uri.tryParse(origin.url)?.host;
    final dateLabel = date == null
        ? ''
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final blocks = value.book.chapters.isEmpty
        ? <book.BookBlock>[]
        : value.book.chapters.first.blocks.where((block) {
            if (block.kind == book.BlockKind.heading && block.text.trim() == value.book.title.trim()) return false;
            if (sourceHost != null && block.text.startsWith('$sourceHost · ')) return false;
            return true;
          });
    // Desktop scroll views add a scrollbar automatically. Disable its painting,
    // while retaining wheel, trackpad, touch and keyboard scrolling.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        key: ValueKey('web-conversion-preview-scroll-${mode.name}'),
        primary: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sourceHost != null) ...[
              Text('$sourceHost · $dateLabel', style: context.mmText.callout.copyWith(color: c.secondaryLabel)),
              const SizedBox(height: MMSpacing.m),
            ],
            Text(value.package.document.title, style: context.mmText.title2.copyWith(fontSize: 20, height: 1.4)),
            const SizedBox(height: MMSpacing.xl),
            if (mode == WebCaptureMode.original && value.preview != null)
              Image.memory(value.preview!, fit: BoxFit.fitWidth)
            else if (mode == WebCaptureMode.markdown)
              Text(value.markdown ?? '', style: MMTypography.mono.copyWith(color: c.label, height: 1.6))
            else
              for (final block in blocks)
                Padding(
                  padding: const EdgeInsets.only(bottom: MMSpacing.l),
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
                          style: block.kind == book.BlockKind.heading
                              ? context.mmText.headline.copyWith(fontSize: 16, height: 1.5)
                              : context.mmText.body.copyWith(fontSize: 15, height: 1.75),
                        ),
                ),
          ],
        ),
      ),
    );
  }
}
