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

/// The workspace retains this registry while open, including outside compare
/// mode. Later full-document controls use the same document/language owners.
final translationSchedulersProvider = Provider.autoDispose.family<TranslationSchedulers, String>((ref, setId) {
  final registry = TranslationSchedulers(ref, setId);
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
