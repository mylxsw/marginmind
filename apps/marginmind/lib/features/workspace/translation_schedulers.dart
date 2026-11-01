import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/providers.dart';
import '../assistant/assistant_settings.dart';
import 'document_translation_runtime.dart';

final translationStoreProvider = FutureProvider.family<TranslationStore, String>((ref, setId) {
  final repository = ref.watch(contentRepositoryProvider);
  if (repository is! TranslationStoreRepository) throw StateError('Translation storage unavailable');
  return (repository as TranslationStoreRepository).translationStore(setId);
});

/// OS network changes; no remote probe or document work is performed.
final translationConnectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  try {
    yield !(await connectivity.checkConnectivity()).contains(ConnectivityResult.none);
    yield* connectivity.onConnectivityChanged.map((results) => !results.contains(ConnectivityResult.none)).distinct();
  } on MissingPluginException {
    // Hosts without the plugin retain the assistant's existing default.
    yield true;
  } on PlatformException {
    yield true;
  }
});

/// System/assistant online state for the given study set.
/// Can be overridden in tests or changed when network/toggle changes.
class TranslationOnlineNotifier extends Notifier<bool> {
  TranslationOnlineNotifier(this.studySetId);
  final String studySetId;

  @override
  bool build() {
    return ref.watch(translationConnectivityProvider).value ?? assistantOnlineDefault(ref, studySetId);
  }

  void setOnline(bool online) {
    state = online;
  }
}

final translationOnlineProvider = NotifierProvider.autoDispose.family<TranslationOnlineNotifier, bool, String>(
  (key) => TranslationOnlineNotifier(key),
);

/// The workspace retains this registry while open, including outside compare
/// mode. Later full-document controls use the same document/language owners.
final translationSchedulersProvider = Provider.autoDispose.family<TranslationSchedulers, String>((ref, setId) {
  final registry = TranslationSchedulers(ref, setId);
  ref.listen<bool>(translationOnlineProvider(setId), (_, online) {
    unawaited(registry.setOnline(online));
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
  final _changes = StreamController<(String, String)>.broadcast(sync: true);
  final _ready = <(String, String), TranslationScheduler>{};
  final _subscriptions = <(String, String), StreamSubscription<TranslationSchedulerState>>{};
  Stream<(String, String)> get changes => _changes.stream;
  TranslationScheduler? peek(String id, String language) => _ready[(id, language)];
  void _notify((String, String) key) {
    if (!_changes.isClosed) _changes.add(key);
  }

  Future<TranslationScheduler> get(
    String id,
    String language,
    List<TranslationParagraph> paragraphs, {
    required StudySetContent content,
    ModelReference? modelOverride,
  }) async {
    if (_closed) throw StateError('Workspace closed');
    final key = (id, language);
    final revision = '${content.document(id)?.revision}:${paragraphs.map((p) => p.fingerprint).join(',')}';
    if (_owners.containsKey(key) && _revisions[key] == revision) return _owners[key]!;
    final previous = _owners[key];
    _revisions[key] = revision;
    final storeFuture = ref.read(translationStoreProvider(setId).future);
    final factory = ref.read(documentTranslatorFactoryProvider);
    final isOnline = ref.read(translationOnlineProvider(setId));
    final opening = () async {
      await _subscriptions.remove(key)?.cancel();
      _ready.remove(key);
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
        model: 'document_translate',
        budget: const ResearchBudget(outputTokens: 16384, duration: Duration(minutes: 3)),
        online: isOnline,
        createTranslator: () {
          if (_closed || !ref.mounted) throw StateError('Workspace closed');
          return factory((setId: setId, documentId: id, language: language, model: modelOverride), paragraphs);
        },
      );
      await scheduler.initialize(snapshot: snapshot);
      if (_closed) {
        await scheduler.close();
      } else {
        _ready[key] = scheduler;
        _subscriptions[key] = scheduler.states.listen((_) => _notify(key));
        await scheduler.setOnline(ref.read(translationOnlineProvider(setId)));
        _notify(key);
      }
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
    await Future.wait(
      _owners.values.toList().map((future) async {
        try {
          final scheduler = await future;
          if (_closed || !ref.mounted) return;
          await scheduler.setOnline(online);
        } catch (_) {
          /* Failed owners have no running task. */
        }
      }),
    );
  }

  Future<void> removeTranslations(String id, String language) async {
    final storeFuture = ref.read(translationStoreProvider(setId).future);
    final prefs = ref.read(sharedPreferencesProvider);
    final key = (id, language);
    final existing = _owners.remove(key);
    await _subscriptions.remove(key)?.cancel();
    _ready.remove(key);
    _revisions.remove(key);
    if (existing != null) {
      try {
        final scheduler = await existing;
        await scheduler.close();
      } catch (_) {}
    }
    final store = await storeFuture;
    final epochKey = documentTranslationEpochKey(setId, id, language);
    if (!await prefs.setInt(epochKey, (prefs.getInt(epochKey) ?? 0) + 1)) {
      throw StateError('Translation cache invalidation failed');
    }
    await store.remove(id, language);
    _notify(key);
  }

  Future<void> close() async {
    _closed = true;
    for (final sub in _subscriptions.values.toList()) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _ready.clear();
    await _changes.close();
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
