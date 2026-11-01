import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../app/providers.dart';
import 'reader_compare.dart';
import 'reader_ocr.dart';
import 'reader_paragraphs.dart';
import 'reflow_document.dart';
import 'reflow_session.dart';
import 'workspace_controller.dart';
import 'translation_schedulers.dart';

final translationParagraphsProvider = FutureProvider.autoDispose.family<List<TranslationParagraph>, (String, String)>((
  ref,
  key,
) {
  final workspace = ref.read(workspaceProvider(key.$1).notifier);
  ref.watch(workspaceProvider(key.$1).select((s) => s.content?.document(key.$2)?.revision));
  final doc = workspace.content.document(key.$2);
  if (doc == null) return Future.value(<TranslationParagraph>[]);
  if (doc.contentManifest != null) {
    return ReflowDocument.load(
      ref.read(contentRepositoryProvider) as DocumentRepository,
      key.$1,
      doc,
    ).then(reflowParagraphs);
  }
  final path = workspace.filePath(doc);
  final ocr = ref.watch(readerOcrProvider(path));
  return MMPdfEngine.translationParagraphs(ocr.document?.path ?? path, doc.id);
}, dependencies: [workspaceProvider, readingPagesProvider]);

class ReaderTranslationState {
  const ReaderTranslationState({
    this.paragraphs = const [],
    this.values = const {},
    this.loading = true,
    this.failed = false,
    this.page = 1,
    this.position,
    this.hovered,
    this.textPosition,
  });
  final List<TranslationParagraph> paragraphs;
  final Map<String, String> values;
  final bool loading, failed;
  final int page;
  final String? hovered;
  final PdfReadingPosition? position;
  final TextReadingPosition? textPosition;
  Iterable<TranslationParagraph> get pageParagraphs => paragraphs.where((p) => translationGroup(p) == page);
  int get done => paragraphs.where((p) => values.containsKey(p.fingerprint)).length;
  int get pageDone => pageParagraphs.where((p) => values.containsKey(p.fingerprint)).length;
  bool get complete => !loading && !failed && pageParagraphs.every((p) => values.containsKey(p.fingerprint));

  ReaderTranslationState copyWith({
    Map<String, String>? values,
    bool? loading,
    bool? failed,
    int? page,
    PdfReadingPosition? position,
    TextReadingPosition? textPosition,
    String? hovered,
    bool clearHover = false,
  }) => ReaderTranslationState(
    paragraphs: paragraphs,
    values: values ?? this.values,
    loading: loading ?? this.loading,
    failed: failed ?? this.failed,
    page: page ?? this.page,
    position: position ?? this.position,
    textPosition: textPosition ?? this.textPosition,
    hovered: clearHover ? null : hovered ?? this.hovered,
  );
}

final readerTranslationProvider = NotifierProvider.autoDispose
    .family<ReaderTranslationController, ReaderTranslationState, String>(
      ReaderTranslationController.new,
      dependencies: [
        readingPagesProvider,
        workspaceProvider,
        readerCompareProvider,
        reflowSessionProvider,
        documentPdfProvider,
        translationParagraphsProvider,
      ],
    );

class ReaderTranslationController extends Notifier<ReaderTranslationState> {
  ReaderTranslationController(this.studySetId);
  final String studySetId;
  TranslationScheduler? _session;
  StreamSubscription<TranslationSchedulerState>? _subscription;
  int _generation = 0, _pageGeneration = 0;
  String? _identity;

  void _cancelPage() {
    _pageGeneration++;
    if (_session != null) unawaited(_session!.demand(const []));
  }

  @override
  ReaderTranslationState build() {
    ref.watch(translationSchedulersProvider(studySetId));
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      _generation++;
      _cancelPage();
    });
    ref.listen(readerCompareProvider(studySetId), (_, pair) {
      final key = pair?.right is AiCompareTarget
          ? '${pair!.leftDocumentId}:${(pair.right as AiCompareTarget).targetLang}'
          : null;
      if (key == _identity) return;
      _identity = key;
      _generation++;
      _cancelPage();
      if (key != null) unawaited(_load());
    });
    ref.listen(
      workspaceProvider(studySetId).select((s) => s.content?.documents.map((d) => '${d.id}:${d.revision}').join('|')),
      (before, after) {
        if (before != after && ref.read(readerCompareProvider(studySetId))?.right is AiCompareTarget) {
          _generation++;
          _cancelPage();
          unawaited(_load());
        }
      },
    );
    Future.microtask(() {
      if (ref.mounted && ref.read(readerCompareProvider(studySetId))?.right is AiCompareTarget) {
        final pair = ref.read(readerCompareProvider(studySetId))!;
        _identity = '${pair.leftDocumentId}:${(pair.right as AiCompareTarget).targetLang}';
        unawaited(_load());
      }
    });
    return const ReaderTranslationState();
  }

  /// Rebinds the compare pane to the fresh owner after removing translations.
  /// Clearing data does not itself authorize another model request.
  Future<void> reloadAfterRemoval(String documentId, String language) async {
    final pair = ref.read(readerCompareProvider(studySetId));
    if (pair?.leftDocumentId != documentId ||
        pair?.right is! AiCompareTarget ||
        (pair!.right as AiCompareTarget).targetLang != language) {
      return;
    }
    await _load(translateCurrentPage: false);
  }

  Future<void> _load({bool translateCurrentPage = true}) async {
    final generation = ++_generation;
    _cancelPage();
    state = const ReaderTranslationState();
    final pair = ref.read(readerCompareProvider(studySetId));
    if (pair?.right is! AiCompareTarget) return;
    final id = pair!.leftDocumentId, language = (pair.right as AiCompareTarget).targetLang;
    bool current() => ref.mounted && generation == _generation;
    try {
      // Local paragraph geometry is indexed once. Only the selected page's
      // missing paragraphs are ever passed to a model.
      final paragraphs = await ref.read(translationParagraphsProvider((studySetId, id)).future);
      if (!current()) return;
      final session = await ref
          .read(translationSchedulersProvider(studySetId))
          .get(id, language, paragraphs, content: ref.read(workspaceProvider(studySetId).notifier).content);
      if (!current()) return;
      await _subscription?.cancel();
      _session = session;
      _subscription = session.states.listen((event) {
        if (current()) state = state.copyWith(values: event.values, failed: event.failure != null);
      });
      final cached = session.values;
      final document = ref.read(workspaceProvider(studySetId).notifier).content.document(id);
      final textPosition = document?.contentManifest == null
          ? null
          : ref.read(reflowSessionProvider((studySetId, id))).position;
      final pdf = ref.read(documentPdfProvider((studySetId, id)));
      final position = document?.contentManifest == null ? pdf.readingPosition : null;
      final fallback =
          ref.read(readingPagesProvider(studySetId))[id] ??
          ref.read(workspaceProvider(studySetId).notifier).content.document(id)?.lastPage ??
          1;
      final page = textPosition == null
          ? position?.page ?? fallback
          : translationGroup(paragraphAt(paragraphs, textPosition) ?? paragraphs.first);
      state = ReaderTranslationState(
        paragraphs: paragraphs,
        values: cached,
        loading: false,
        failed: paragraphs.isEmpty,
        page: page,
        position: position,
        textPosition: textPosition,
      );
      if (translateCurrentPage && paragraphs.isNotEmpty) await _translatePage(page);
    } catch (_) {
      if (current()) state = state.copyWith(loading: false, failed: true);
    }
  }

  Future<void> _translatePage(int page) async {
    _cancelPage();
    final documentGeneration = _generation, pageGeneration = _pageGeneration;
    final pairAtStart = ref.read(readerCompareProvider(studySetId));
    final sourceId = pairAtStart?.leftDocumentId;
    final revision = ref.read(workspaceProvider(studySetId).notifier).content.document(sourceId ?? '')?.revision;
    bool current() =>
        ref.mounted &&
        documentGeneration == _generation &&
        pageGeneration == _pageGeneration &&
        ref.read(workspaceProvider(studySetId).notifier).content.document(sourceId ?? '')?.revision == revision;
    final paragraphs = state.paragraphs.where((p) => translationGroup(p) == page).toList();
    // Cached pages, including a partially cached document opened offline, do
    // not read credentials, create a connection or queue any translation.
    if (paragraphs.every((p) => state.values.containsKey(p.fingerprint))) return;
    final pair = ref.read(readerCompareProvider(studySetId));
    if (pair?.right is! AiCompareTarget) return;
    if (_session?.job?.isActive == true) return;
    try {
      final session = _session;
      if (session == null || !current() || session.job?.isActive == true) return;
      if (paragraphs.first.textAnchor != null) {
        session.prioritize(paragraphs.map((p) => p.index), focus: paragraphs.first.index);
        await session.demand([page]);
        return;
      }
      final pdf = ref.read(documentPdfProvider((studySetId, sourceId!)));
      final position = pdf.readingPosition;
      final initial = paragraphs.lastWhere(
        (p) => p.bounds.top >= (position?.y ?? double.infinity),
        orElse: () => paragraphs.first,
      );
      session.prioritize(pdf.visibleParagraphs(paragraphs), focus: initial.index);
      await session.demand([page]);
    } catch (_) {
      if (current()) state = state.copyWith(failed: true);
    }
  }

  void _showPage(int page, {Iterable<int> visible = const [], int? focus}) {
    if (state.loading) return;
    if (page != state.page) {
      state = state.copyWith(page: page, failed: false);
      unawaited(_translatePage(page));
    } else {
      _session?.prioritize(visible, focus: focus);
    }
  }

  void sourceChanged(PdfReadingPosition? position) {
    if (position == null) return;
    _showPage(position.page);
    state = state.copyWith(position: position);
  }

  void textSourceChanged(TextReadingPosition position) {
    final p = paragraphAt(state.paragraphs, position);
    if (p == null) return;
    _showPage(translationGroup(p));
    state = state.copyWith(textPosition: position);
  }

  void prioritize(Iterable<int> visible, int focus) {
    final paragraph = state.paragraphs.where((p) => p.index == focus).firstOrNull;
    if (paragraph != null) _showPage(translationGroup(paragraph), visible: visible, focus: focus);
  }

  void hover(String? key) => state = state.copyWith(hovered: key, clearHover: key == null);

  Future<void> retry() async {
    if (_session != null) {
      if (_session!.job?.isActive == true) return;
      for (final p in state.pageParagraphs.where((p) => !state.values.containsKey(p.fingerprint)).toList()) {
        await _session!.retry(p);
      }
      return;
    }
    state = state.copyWith(failed: false);
    await _translatePage(state.page);
  }
}

/// Explicit source input invalidates an outstanding translation-driven jump.
final translationSourceInputProvider = NotifierProvider.autoDispose.family<TranslationSourceInput, int, String>(
  TranslationSourceInput.new,
  dependencies: const [],
);

class TranslationSourceInput extends Notifier<int> {
  TranslationSourceInput(this.id);
  final String id;
  @override
  int build() => 0;
  void take() => state++;
}
