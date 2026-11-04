import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart' show RoutingRowState, splitWebMarkdown, webFormatPromptVersion;
import 'package:mm_book/mm_book.dart' as book;
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../app/providers.dart';
import '../../shared/l10n.dart';
import '../assistant/settings/ai_task_status.dart' show routingIssueBlocks;
import 'web_document.dart';
import 'web_format_runtime.dart';
import 'web_format_session.dart';
import 'widgets/notices.dart' show showConfirmSheet;
import 'widgets/web_format_panel.dart';
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
  if (!owner.beginConversion(session.id)) return;
  session.dismissPrompt();
  final generation = session.navigationId;
  final controller = ref.read(workspaceProvider(studySetId).notifier);
  final previous = controller.content.document(
    ref.read(workspaceBrowserProvider(studySetId)).page(session.id)?.replacingDocumentId ?? '',
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
    Future<BrowserDocumentCapture> captureFor(WebCaptureMode mode) async {
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
      return capture;
    }

    Future<PreparedWebDocument> prepare(WebCaptureMode mode) async {
      final capture = await captureFor(mode);
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
    const parser = book.WebBookParser();
    final note = context.l10n.webFormatSourceNote;
    final formatting = WebFormatHost(
      executor: ref.read(webFormatExecutorProvider(studySetId)),
      load: () async {
        final capture = await captureFor(WebCaptureMode.readable);
        final resources = parser.sanitizeResources(capture.resources);
        return (
          markdown: parser.markdown(parser.sanitizeHtml(capture.html, resources.keys.toSet())),
          pageTitle: capture.title,
          resources: resources,
        );
      },
      prepare: (mode, body, title, origin) async {
        final capture = await captureFor(WebCaptureMode.readable);
        final resources = parser.sanitizeResources(capture.resources);
        final markdown = parser.withMarkdownAttribution(body, title, capture.url, capture.capturedAt, note: note);
        final pdf = mode == WebCaptureMode.original
            ? await session.printDocument(
                navigationId: generation,
                html: parser.printableHtml(markdown, resources.keys.toSet()),
                resources: resources,
                cancelled: cancelled,
              )
            : null;
        if (cancelled()) throw StateError('stale_capture');
        return converter.prepare(
          capture,
          id: id,
          title: title,
          mode: mode,
          previous: previous,
          oldChapters: oldChapters,
          formatted: WebFormattedContent(markdown: markdown, origin: origin, pdf: pdf),
        );
      },
    );
    final PreparedWebDocument? prepared;
    // Silently refetching must not call a model or overwrite approved text, so
    // AI documents come back through the sheet with formatting offered.
    if (previous != null && previous.origin!.formatting == null) {
      prepared = await prepare(previous.origin!.mode);
    } else {
      prepared = await showMMSheet<PreparedWebDocument>(
        context: context,
        width: MMSizes.webConversionSheetWidth,
        initialFraction: MMSizes.phoneSheetExpanded,
        builder: (_) => WebConversionSheet(
          prepare: prepare,
          formatting: formatting,
          initialMode: previous?.origin?.mode ?? WebCaptureMode.readable,
          initialFormatting: previous != null,
          initialTitle: previous?.title,
        ),
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

typedef WebFormatPageSource = ({String markdown, String pageTitle, Map<String, Uint8List> resources});

/// What the sheet needs to offer AI formatting; absent where it can't run.
class WebFormatHost {
  const WebFormatHost({required this.executor, required this.load, required this.prepare});
  final WebFormatExecutor executor;

  /// The extraction as Markdown, without title or provenance.
  final Future<WebFormatPageSource> Function() load;

  /// Builds the document from the approved [body]. May print, so it can fail.
  final Future<PreparedWebDocument> Function(
    WebCaptureMode mode,
    String body,
    String title,
    DocumentOriginFormatting origin,
  )
  prepare;
}

class WebConversionSheet extends StatefulWidget {
  const WebConversionSheet({
    super.key,
    required this.prepare,
    this.formatting,
    this.initialMode = WebCaptureMode.readable,
    this.initialFormatting = false,
    this.initialTitle,
  });
  final Future<PreparedWebDocument> Function(WebCaptureMode) prepare;
  final WebFormatHost? formatting;
  final WebCaptureMode initialMode;

  /// Starts with the switch on, for documents that were formatted before.
  final bool initialFormatting;

  /// Keeps an existing document's name instead of the page title.
  final String? initialTitle;
  @override
  State<WebConversionSheet> createState() => _WebConversionSheetState();
}

class _WebConversionSheetState extends State<WebConversionSheet> {
  final _title = TextEditingController();
  final _prepared = <WebCaptureMode, Future<PreparedWebDocument>>{};
  final _reveal = ValueNotifier<int?>(null);
  final _cardKey = GlobalKey();
  late WebCaptureMode _mode = widget.initialMode;
  late bool _edited = widget.initialTitle != null;
  late bool _aiOn = widget.initialFormatting;
  ModelReference? _aiModel;
  RoutingRowState? _route;
  Future<WebFormatPageSource>? _source;
  WebFormatPageSource? _pageSource;
  WebFormatSession? _session;
  WebFormatTab _tab = WebFormatTab.preview;
  bool _closing = false, _saving = false, _saveFailed = false, _idlePreview = false;
  (String, String, Future<PreparedWebDocument>)? _formattedPdf;
  String? _appliedTitle;

  bool get _aiReady => _aiOn && !_routeBlocked;
  bool get _routeBlocked => _route == null || routingIssueBlocks(_route!.issue);

  @override
  void initState() {
    super.initState();
    if (widget.initialTitle != null) _title.text = widget.initialTitle!;
    if (_aiOn && widget.formatting != null) unawaited(_loadSource().then<void>((_) {}, onError: (Object _) {}));
  }

  @override
  void dispose() {
    _session?.removeListener(_sessionChanged);
    _session?.dispose();
    _reveal.dispose();
    _title.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    final session = _session;
    if (!mounted || session == null) return;
    final proposed = session.proposedTitle;
    // Offered once per proposal; a name the user typed always wins.
    if (session.finished && proposed != null && !_edited && proposed != _appliedTitle) {
      _appliedTitle = proposed;
      _title.text = proposed;
    }
    setState(() {});
  }

  /// Shared by the job-size note and the run. Page capture happens only once.
  Future<WebFormatPageSource> _loadSource() {
    final source = _source ??= widget.formatting!.load();
    source.then(
      (value) {
        if (!mounted || _pageSource != null) return;
        setState(() => _pageSource = value);
      },
      onError: (Object _) {
        if (mounted && identical(_source, source)) setState(() => _source = null);
      },
    );
    return source;
  }

  Future<void> _start() async {
    final host = widget.formatting!;
    setState(() => _saveFailed = false);
    final session = WebFormatSession(executor: host.executor, pageTitle: _title.text.trim(), model: _aiModel)
      ..addListener(_sessionChanged);
    setState(() => _session = session);
    try {
      final source = await _loadSource();
      if (!mounted || _session != session || session.phase != WebFormatPhase.preparing) return;
      session.start(source.markdown);
    } catch (_) {
      if (!mounted || _session != session) return;
      _drop(session);
      setState(() => _saveFailed = true);
    }
  }

  void _drop(WebFormatSession session) {
    session.removeListener(_sessionChanged);
    session.dispose();
    _session = null;
    _tab = WebFormatTab.preview;
    _formattedPdf = null;
  }

  bool get _hasWork {
    final session = _session;
    return session != null && (session.running || session.formattedCount > 0 || session.edited);
  }

  Future<void> _close() async {
    final l = context.l10n;
    if (!_hasWork) {
      Navigator.of(context).pop();
      return;
    }
    {
      final discard = await showConfirmSheet(
        context,
        title: l.webFormatConfirmCloseTitle,
        message: _session!.edited ? l.webFormatConfirmCloseEdited : l.webFormatConfirmClose,
        confirmLabel: l.webFormatDiscard,
      );
      if (!discard || !mounted) return;
    }
    _session?.stop();
    setState(() => _closing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _discardFormatting() async {
    final l = context.l10n;
    final session = _session!;
    final discard = await showConfirmSheet(
      context,
      title: l.webFormatConfirmDiscardTitle,
      message: session.edited ? l.webFormatConfirmDiscardEdited : l.webFormatConfirmDiscard,
      confirmLabel: l.webFormatDiscard,
    );
    if (!discard || !mounted || _session != session) return;
    setState(() {
      _drop(session);
      _aiOn = false;
      if (_appliedTitle != null && _title.text == _appliedTitle) {
        _title.clear();
        _appliedTitle = null;
      }
    });
  }

  Future<void> _revert() async {
    final l = context.l10n;
    final session = _session!;
    final revert = await showConfirmSheet(
      context,
      title: l.webFormatConfirmRevertTitle,
      message: l.webFormatConfirmRevert,
      confirmLabel: l.webFormatRevertAction,
    );
    if (revert && mounted && _session == session) {
      session.revertEdits();
      _formattedPdf = null;
    }
  }

  DocumentOriginFormatting _origin(WebFormatSession session) => DocumentOriginFormatting(
    model: _route?.modelLabel ?? '',
    promptVersion: webFormatPromptVersion,
    edited: session.edited,
    unformattedSections: session.sections.length - session.formattedCount,
  );

  Future<PreparedWebDocument> _prepareFormatted(WebFormatSession session) =>
      widget.formatting!.prepare(_mode, session.markdown, _title.text.trim(), _origin(session));

  /// Printing takes seconds, so it runs once per text. The preview tolerates a
  /// name still being typed; saving prints again if the name in it is outdated.
  Future<PreparedWebDocument> _pdfFor(WebFormatSession session, {bool exactTitle = false}) {
    final title = _title.text.trim();
    final cached = _formattedPdf;
    if (cached == null || cached.$1 != session.markdown || (exactTitle && cached.$2 != title)) {
      _formattedPdf = (session.markdown, title, _prepareFormatted(session));
    }
    return _formattedPdf!.$3;
  }

  Future<void> _saveFormatted(WebFormatSession session) async {
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      final prepared = _mode == WebCaptureMode.original
          ? await _pdfFor(session, exactTitle: true)
          : await _prepareFormatted(session);
      if (!mounted) return;
      setState(() => _closing = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(prepared);
      });
    } catch (_) {
      _formattedPdf = null;
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openCompare(int index) {
    setState(() => _tab = WebFormatTab.compare);
    _reveal.value = index;
  }

  void _revealSection(int index) {
    final session = _session!;
    setState(() {
      if (session.finished && (session.edited || _mode != WebCaptureMode.readable)) {
        _tab = WebFormatTab.compare;
      } else {
        _tab = WebFormatTab.preview;
      }
    });
    _reveal.value = index;
  }

  Widget _formattedPdfPreview(WebFormatSession session) => FutureBuilder<PreparedWebDocument>(
    future: _pdfFor(session),
    builder: (context, snapshot) {
      final l = context.l10n;
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.webFormatPdfFailed, style: context.mmText.body),
              const SizedBox(height: MMSpacing.m),
              MMButton(label: l.webRetry, onPressed: () => setState(() => _formattedPdf = null)),
            ],
          ),
        );
      }
      if (snapshot.connectionState != ConnectionState.done || snapshot.data == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return _Preview(value: snapshot.data!, mode: WebCaptureMode.original);
    },
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final activeSession = _session;
    return PopScope(
      canPop: _closing || !_hasWork,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: FutureBuilder<PreparedWebDocument>(
        // Formatting always starts from the readable extraction, so a PDF choice
        // must not print the page here: that happens from the approved Markdown.
        future: _prepared.putIfAbsent(
          activeSession != null || _aiReady ? WebCaptureMode.readable : _mode,
          () => widget.prepare(activeSession != null || _aiReady ? WebCaptureMode.readable : _mode),
        ),
        builder: (context, snapshot) {
          final value = snapshot.connectionState == ConnectionState.done ? snapshot.data : null;
          if (value != null && !_edited && _appliedTitle == null) _title.text = value.package.document.title;
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
          final session = activeSession;
          Widget plainPreview() => snapshot.hasError
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
              : _Preview(value: value, mode: _aiReady ? WebCaptureMode.readable : _mode);
          // Always the same widget in the same place: its scroll position,
          // follow state and pending reveal must survive switching tabs.
          Widget previewPane({Widget? settings}) => Semantics(
            label: l.convertPreview,
            container: true,
            child: SizedBox.expand(
              key: const ValueKey('web-conversion-preview'),
              child: session != null
                  ? WebFormatPane(
                      session: session,
                      mode: _mode,
                      tab: _tab,
                      onTab: (tab) => setState(() => _tab = tab),
                      header: _FormatHeader(host: value?.package.document.origin, title: _title.text.trim()),
                      resources: _pageSource?.resources ?? const {},
                      pdf: (_) => _formattedPdfPreview(session),
                      reveal: _reveal,
                      onRevert: _revert,
                      settings: settings,
                    )
                  : plainPreview(),
            ),
          );
          final save = MMButton(
            label: l.convertSave,
            variant: MMButtonVariant.primary,
            onPressed: value == null || _title.text.trim().isEmpty || _saving || (session?.running ?? false)
                ? null
                : session != null
                ? () => unawaited(_saveFormatted(session))
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
              Text(label, style: context.mmText.callout.copyWith(color: c.secondaryLabel)),
              const SizedBox(height: MMSpacing.s),
              child,
            ],
          );
          final card = widget.formatting == null
              ? null
              : WebFormatCard(
                  enabled: _aiOn,
                  onEnabled: (value) {
                    setState(() => _aiOn = value);
                    // Where the text will be sent must be seen before starting.
                    if (value) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final card = _cardKey.currentContext;
                        if (card == null || !card.mounted) return;
                        Scrollable.ensureVisible(
                          card,
                          duration: MMMotion.standard,
                          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
                        );
                      });
                    }
                    if (value) unawaited(_loadSource().then<void>((_) {}, onError: (Object _) {}));
                  },
                  scope: _pageSource == null
                      ? null
                      : (chars: _pageSource!.markdown.length, sections: splitWebMarkdown(_pageSource!.markdown).length),
                  model: _aiModel,
                  onModel: (model) => setState(() => _aiModel = model),
                  onRoute: (row) {
                    if (mounted && !identical(row, _route)) setState(() => _route = row);
                  },
                );
          final start = MMButton(
            label: l.webFormatStart,
            variant: MMButtonVariant.primary,
            onPressed: value == null || _title.text.trim().isEmpty ? null : () => unawaited(_start()),
          );
          final running = session?.running ?? false;
          final compact = MMBottomSheet.contains(context);
          return LayoutBuilder(
            builder: (context, sheet) => MMSheet(
              title: l.convertTitle,
              // Phones keep the main action in the title row, like every other form.
              titleTrailing: !compact
                  ? null
                  : running
                  ? MMButton(label: l.webFormatStop, icon: MMIcons.stop, onPressed: session!.stop)
                  : session == null && _aiReady
                  ? start
                  : save,
              footer: compact
                  ? (_saveFailed
                        ? Text(l.docSaveFailed, style: context.mmText.footnote.copyWith(color: c.critical))
                        : null)
                  : running
                  ? Text(l.webFormatStopNote, style: context.mmText.footnote.copyWith(color: c.secondaryLabel))
                  : _saveFailed
                  ? Text(l.docSaveFailed, style: context.mmText.footnote.copyWith(color: c.critical))
                  : null,
              actions: [
                MMButton(label: l.cancel, onPressed: () => unawaited(_close())),
                if (!compact) ...[
                  if (running) MMButton(label: l.webFormatStop, icon: MMIcons.stop, onPressed: session!.stop),
                  if (session == null && _aiReady) start else save,
                ],
              ],
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final settings = Column(
                    key: const ValueKey('web-conversion-settings'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // While running, a phone's progress tab is about progress.
                      if (!(compact && running)) ...[
                        section(l.convertDocumentName, titleField),
                        const SizedBox(height: MMSpacing.xxl),
                        section(l.convertFormat, segments),
                        if (session != null) const SizedBox(height: MMSpacing.xxl),
                      ],
                      if (session != null) ...[
                        WebFormatProgress(
                          session: session,
                          onReveal: _revealSection,
                          onCompare: _openCompare,
                          onDiscard: () => unawaited(_discardFormatting()),
                        ),
                      ] else if (card != null) ...[
                        const SizedBox(height: MMSpacing.xxl),
                        section(l.webFormatSectionLabel, KeyedSubtree(key: _cardKey, child: card)),
                      ],
                    ],
                  );
                  final split = constraints.maxWidth >= 720;
                  final wide =
                      split &&
                      session != null &&
                      session.finished &&
                      (_tab == WebFormatTab.edit || _tab == WebFormatTab.compare);
                  final previewHeight =
                      (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom - 210).clamp(
                        220.0,
                        600.0,
                      );
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
                              Expanded(flex: 65, child: previewPane()),
                              if (!wide) ...[
                                const SizedBox(width: MMSpacing.xl),
                                VerticalDivider(width: 1, thickness: 0.5, color: c.hairline),
                                const SizedBox(width: MMSpacing.xl),
                                Expanded(flex: 35, child: SingleChildScrollView(child: settings)),
                              ],
                            ],
                          ),
                        )
                      else if (session != null)
                        // The whole sheet is the work area, above any keyboard.
                        SizedBox(
                          height: (sheet.maxHeight - (compact ? 172 : 140)).clamp(300.0, double.infinity),
                          child: previewPane(settings: settings),
                        )
                      else if (widget.formatting != null) ...[
                        MMSegmentedControl<bool>(
                          expand: true,
                          segments: [
                            MMSegment(value: false, label: l.webFormatTabSettings),
                            MMSegment(value: true, label: l.webFormatTabPreview),
                          ],
                          value: _idlePreview,
                          onChanged: (value) => setState(() => _idlePreview = value),
                        ),
                        const SizedBox(height: MMSpacing.m),
                        SizedBox(
                          height: (sheet.maxHeight - 228).clamp(300.0, double.infinity),
                          child: _idlePreview ? previewPane() : SingleChildScrollView(child: settings),
                        ),
                      ] else ...[
                        settings,
                        const SizedBox(height: MMSpacing.xl),
                        SizedBox(height: 300, child: previewPane()),
                      ],
                      const SizedBox(height: MMSpacing.m),
                      Divider(height: 1, thickness: 0.5, color: c.hairline),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FormatHeader extends StatelessWidget {
  const _FormatHeader({required this.host, required this.title});
  final DocumentOrigin? host;
  final String title;
  @override
  Widget build(BuildContext context) {
    final origin = host;
    final date = origin?.capturedAt.toLocal().toIso8601String().substring(0, 10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (origin != null) ...[
          Text(
            '${Uri.tryParse(origin.url)?.host} · $date',
            style: (MMInput.of(context).phone ? context.mmText.footnote : context.mmText.callout).copyWith(
              color: context.mmColors.secondaryLabel,
            ),
          ),
          const SizedBox(height: MMSpacing.m),
        ],
        Text(title, style: context.mmText.title2.copyWith(fontSize: 20, height: 1.4)),
        SizedBox(height: MMInput.of(context).phone ? MMSpacing.m : MMSpacing.xl),
      ],
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
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sourceHost != null) ...[
          Text('$sourceHost · $dateLabel', style: context.mmText.callout.copyWith(color: c.secondaryLabel)),
          const SizedBox(height: MMSpacing.m),
        ],
        Text(value.package.document.title, style: context.mmText.title2.copyWith(fontSize: 20, height: 1.4)),
        const SizedBox(height: MMSpacing.xl),
      ],
    );
    if (mode == WebCaptureMode.original) {
      final document = value.package.document;
      final data = value.package.files[document.sourceFileName ?? document.fileName];
      if (data == null) return Center(child: Text(context.l10n.docSaveFailed, style: context.mmText.body));
      return MMPdfDataPreview(
        key: const ValueKey('web-conversion-pdf'),
        data: data,
        sourceName: document.sourceFileName ?? document.fileName,
        header: header,
        errorBuilder: (context, _, _) => Center(child: Text(context.l10n.docSaveFailed, style: context.mmText.body)),
      );
    }
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
            header,
            if (mode == WebCaptureMode.markdown)
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
                              : context.mmText.body.copyWith(
                                  fontSize: MMInput.of(context).phone ? 16 : 15,
                                  height: 1.75,
                                ),
                        ),
                ),
          ],
        ),
      ),
    );
  }
}
