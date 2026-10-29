import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../app/providers.dart';
import '../assistant/assistant_settings.dart';
import 'reader_compare.dart';
import 'reader_ocr.dart';
import 'workspace_controller.dart';

final translationParagraphsProvider = FutureProvider.autoDispose.family<List<TranslationParagraph>, (String, String)>((
  ref,
  key,
) {
  final workspace = ref.read(workspaceProvider(key.$1).notifier);
  final doc = workspace.content.document(key.$2)!;
  final path = workspace.filePath(doc);
  final ocr = ref.watch(readerOcrProvider(path));
  return MMPdfEngine.translationParagraphs(ocr.document?.path ?? path, doc.id);
});

final paragraphTranslatorProvider = Provider<Future<ParagraphTranslator> Function(AssistantModel)>((ref) {
  final secrets = ref.watch(assistantSecretsProvider);
  return (model) async {
    final key = await assistantModelKey(secrets, model);
    if (model.provider != AssistantProvider.ollama && (key == null || key.isEmpty)) {
      throw const ResearchFailure(ResearchFailureKind.authentication);
    }
    return ModelParagraphTranslator(connectAssistant(model, key ?? ''), model.model);
  };
});

class ReaderTranslationState {
  const ReaderTranslationState({
    this.paragraphs = const [],
    this.values = const {},
    this.loading = true,
    this.failed = false,
    this.position,
    this.hovered,
  });
  final List<TranslationParagraph> paragraphs;
  final Map<String, String> values;
  final bool loading, failed;
  final String? hovered;
  final PdfReadingPosition? position;
  int get done => paragraphs.where((p) => values.containsKey(p.fingerprint)).length;
  bool get complete => !loading && !failed && done == paragraphs.length && paragraphs.isNotEmpty;
}

final readerTranslationProvider = NotifierProvider.autoDispose
    .family<ReaderTranslationController, ReaderTranslationState, String>(ReaderTranslationController.new);

class ReaderTranslationController extends Notifier<ReaderTranslationState> {
  ReaderTranslationController(this.studySetId);
  final String studySetId;
  TranslationSession? _session;
  int _generation = 0;
  String? _identity;
  bool _modelChanged = false;
  @override
  ReaderTranslationState build() {
    ref.onDispose(() {
      _generation++;
      _session?.cancel();
    });
    ref.listen(readerCompareProvider(studySetId), (_, pair) {
      final key = pair?.right is AiCompareTarget
          ? '${pair!.leftDocumentId}:${(pair.right as AiCompareTarget).targetLang}'
          : null;
      if (key == _identity) return;
      _identity = key;
      _generation++;
      _session?.cancel();
      _session = null;
      if (key != null) unawaited(_load());
    });
    Future.microtask(() {
      if (ref.mounted && ref.read(readerCompareProvider(studySetId))?.right is AiCompareTarget) {
        final pair = ref.read(readerCompareProvider(studySetId))!;
        _identity = '${pair.leftDocumentId}:${(pair.right as AiCompareTarget).targetLang}';
        unawaited(_load());
      }
    });
    return const ReaderTranslationState();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _session?.cancel();
    _session = null;
    state = const ReaderTranslationState();
    final pair = ref.read(readerCompareProvider(studySetId));
    if (pair?.right is! AiCompareTarget) return;
    final id = pair!.leftDocumentId, language = (pair.right as AiCompareTarget).targetLang;
    bool current() => ref.mounted && generation == _generation;
    try {
      final paragraphs = await ref.read(translationParagraphsProvider((studySetId, id)).future);
      if (!current()) return;
      final cache = ref
          .read(workspaceProvider(studySetId).notifier)
          .content
          .translationCaches
          .where((c) => c.documentId == id && c.targetLang == language)
          .firstOrNull;
      final cached = {for (final p in paragraphs) p.fingerprint: ?cache?.paragraphs[p.fingerprint]};
      state = ReaderTranslationState(
        paragraphs: paragraphs,
        values: cached,
        loading: false,
        failed: paragraphs.isEmpty,
      );
      if (paragraphs.isEmpty || cached.length == paragraphs.length) return;
      final model = ref.read(assistantDefaultModelProvider);
      final modelId = model == null ? '' : '${model.serviceId ?? model.provider.name}/${model.model}';
      _modelChanged = cache != null && cache.model != modelId;
      if (model == null ||
          _modelChanged ||
          (!assistantOnlineDefault(ref, studySetId) && model.provider != AssistantProvider.ollama)) {
        state = ReaderTranslationState(paragraphs: paragraphs, values: cached, loading: false, failed: true);
        return;
      }
      final translator = await ref.read(paragraphTranslatorProvider)(model);
      if (!current()) {
        translator.close();
        return;
      }
      late TranslationSession session;
      session = TranslationSession(
        paragraphs: paragraphs,
        language: language,
        translator: translator,
        cached: cached,
        changed: () {
          if (current()) {
            state = ReaderTranslationState(
              paragraphs: paragraphs,
              values: Map.unmodifiable(session.values),
              loading: false,
              failed: session.failure != null,
              hovered: state.hovered,
              position: state.position,
            );
          }
        },
        save: (p, text) async {
          if (!current()) return;
          // Check generation inside the atomic update too: a queued disk write
          // may start after the reader already switched to another document.
          await ref.read(contentRepositoryProvider).update(studySetId, (content) {
            if (!current() || content.document(id) == null) return content;
            return ref
                .read(editorProvider)
                .mergeTranslationParagraphs(
                  content,
                  TranslationCache(
                    documentId: id,
                    targetLang: language,
                    model: modelId,
                    createdAt: cache?.createdAt ?? ref.read(clockProvider)(),
                    paragraphs: {p.fingerprint: text},
                  ),
                );
          });
        },
      );
      _session = session;
      final pdf = ref.read(documentPdfProvider((studySetId, id)));
      final position = pdf.readingPosition;
      final onPage = paragraphs.where((p) => p.page == (position?.page ?? 1)).toList();
      final initial = onPage.isEmpty
          ? paragraphs.last
          : onPage.lastWhere((p) => p.bounds.top >= (position?.y ?? double.infinity), orElse: () => onPage.first);
      session.prioritize(pdf.visibleParagraphs(paragraphs), focus: initial.index);
      await session.start();
    } catch (_) {
      if (current()) {
        state = ReaderTranslationState(
          paragraphs: state.paragraphs,
          values: state.values,
          loading: false,
          failed: true,
        );
      }
    }
  }

  void sourceChanged(PdfReadingPosition? position) {
    if (position == null) return;
    final onPage = state.paragraphs.where((p) => p.page == position.page).toList();
    if (onPage.isNotEmpty) {
      final focus = onPage.lastWhere((p) => p.bounds.top >= position.y, orElse: () => onPage.first);
      final id = ref.read(readerCompareProvider(studySetId))?.leftDocumentId;
      if (id != null) {
        prioritize(ref.read(documentPdfProvider((studySetId, id))).visibleParagraphs(state.paragraphs), focus.index);
      }
    }
    state = ReaderTranslationState(
      paragraphs: state.paragraphs,
      values: state.values,
      loading: state.loading,
      failed: state.failed,
      hovered: state.hovered,
      position: position,
    );
  }

  void prioritize(Iterable<int> visible, int focus) => _session?.prioritize(visible, focus: focus);
  void hover(String? key) => state = ReaderTranslationState(
    paragraphs: state.paragraphs,
    values: state.values,
    loading: state.loading,
    failed: state.failed,
    hovered: key,
    position: state.position,
  );
  Future<void> retry() async {
    final model = ref.read(assistantDefaultModelProvider);
    if (model == null || (!assistantOnlineDefault(ref, studySetId) && model.provider != AssistantProvider.ollama)) {
      return;
    }
    if (_session != null) {
      await _session!.retry();
      return;
    }
    if (_modelChanged) {
      final pair = ref.read(readerCompareProvider(studySetId));
      if (pair?.right is! AiCompareTarget) return;
      await ref
          .read(contentRepositoryProvider)
          .removeTranslationCache(studySetId, pair!.leftDocumentId, (pair.right as AiCompareTarget).targetLang);
    }
    await _load();
  }
}

/// Explicit source input invalidates an outstanding translation-driven jump.
final translationSourceInputProvider = NotifierProvider.autoDispose.family<TranslationSourceInput, int, String>(
  TranslationSourceInput.new,
);

class TranslationSourceInput extends Notifier<int> {
  TranslationSourceInput(this.id);
  final String id;
  @override
  int build() => 0;
  void take() => state++;
}
