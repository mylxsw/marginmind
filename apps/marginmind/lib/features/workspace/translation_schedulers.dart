import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/providers.dart';
import '../assistant/assistant_settings.dart';
import 'reader_translation.dart';

final translationStoreProvider = FutureProvider.family<TranslationStore, String>((ref, setId) {
  final repository = ref.watch(contentRepositoryProvider);
  if (repository is! TranslationStoreRepository) throw StateError('Translation storage unavailable');
  return (repository as TranslationStoreRepository).translationStore(setId);
});

/// System/assistant online state for the given study set.
/// Can be overridden in tests or changed when network/toggle changes.
class TranslationOnlineNotifier extends Notifier<bool> {
  TranslationOnlineNotifier(this.studySetId);
  final String studySetId;

  @override
  bool build() {
    return assistantOnlineDefault(ref, studySetId);
  }

  void setOnline(bool online) {
    state = online;
  }
}

final translationOnlineProvider = NotifierProvider.autoDispose
    .family<TranslationOnlineNotifier, bool, String>(
      (key) => TranslationOnlineNotifier(key),
    );

/// The workspace retains this registry while open, including outside compare
/// mode. Later full-document controls use the same document/language owners.
final translationSchedulersProvider = Provider.autoDispose.family<TranslationSchedulers, String>((ref, setId) {
  final registry = TranslationSchedulers(ref, setId);
  ref.listen<bool>(translationOnlineProvider(setId), (_, online) {
    unawaited(registry.setOnline(online));
  });
  ref.listen(assistantDefaultModelProvider, (_, model) {
    unawaited(registry.updateModel(model));
  });
  ref.onDispose(() => unawaited(registry.close()));
  return registry;
});

class TranslationSchedulers {
  TranslationSchedulers(this.ref, this.setId);
  final Ref ref;
  final String setId;
  final _owners = <(String, String), Future<TranslationScheduler>>{};
  final _revisions = <(String, String), String?>{};
  bool _closed = false;

  Future<TranslationScheduler> get(
    String id,
    String language,
    List<TranslationParagraph> paragraphs, {
    required StudySetContent content,
  }) async {
    if (_closed) throw StateError('Workspace closed');
    final key = (id, language);
    final revision = '${content.document(id)?.revision}:${paragraphs.map((p) => p.fingerprint).join(',')}';
    if (_owners.containsKey(key) && _revisions[key] == revision) return _owners[key]!;
    final previous = _owners[key];
    _revisions[key] = revision;
    final storeFuture = ref.read(translationStoreProvider(setId).future);
    final factory = ref.read(paragraphTranslatorProvider);
    final model = ref.read(assistantDefaultModelProvider);
    final modelId = model == null ? '' : '${model.serviceId ?? model.provider.name}/${model.model}';
    final isOllama = model?.provider == AssistantProvider.ollama;
    final isOnline = isOllama || ref.read(translationOnlineProvider(setId));
    final opening = () async {
      if (previous != null) await (await previous).close();
      final store = await storeFuture;
      final snapshot = await store.importLegacy(
        id,
        language,
        paragraphs: paragraphs,
        caches: content.translationCaches,
      );
      final scheduler = TranslationScheduler(
        documentId: id,
        language: language,
        paragraphs: paragraphs,
        store: store,
        model: modelId,
        budget: const ResearchBudget(outputTokens: 16384, duration: Duration(minutes: 3)),
        online: isOnline,
        createTranslator: () {
          if (_closed || !ref.mounted) throw StateError('Workspace closed');
          final selected = ref.read(assistantDefaultModelProvider);
          if (selected == null) throw const ResearchFailure(ResearchFailureKind.invalidRequest);
          return factory(selected);
        },
      );
      await scheduler.initialize(snapshot: snapshot);
      if (_closed) await scheduler.close();
      return scheduler;
    }();
    _owners[key] = opening;
    try {
      return await opening;
    } catch (_) {
      if (identical(_owners[key], opening)) _owners.remove(key);
      rethrow;
    }
  }

  Future<void> setOnline(bool online) async {
    for (final future in _owners.values) {
      try {
        final scheduler = await future;
        final model = ref.read(assistantDefaultModelProvider);
        final isOllama = model?.provider == AssistantProvider.ollama;
        await scheduler.setOnline(isOllama || online);
      } catch (_) {}
    }
  }

  Future<void> updateModel(AssistantModel? model) async {
    final isOllama = model?.provider == AssistantProvider.ollama;
    final isOnline = ref.read(translationOnlineProvider(setId));
    await setOnline(isOllama || isOnline);
  }

  Future<void> removeTranslations(String id, String language) async {
    final key = (id, language);
    final existing = _owners.remove(key);
    _revisions.remove(key);
    if (existing != null) {
      try {
        final scheduler = await existing;
        await scheduler.close();
      } catch (_) {}
    }
    final store = await ref.read(translationStoreProvider(setId).future);
    await store.remove(id, language);
  }

  Future<void> close() async {
    _closed = true;
    await Future.wait(
      _owners.values.map((s) async {
        try {
          await (await s).close();
        } catch (_) {
          /* failed initialization has no owner */
        }
      }),
    );
  }
}
