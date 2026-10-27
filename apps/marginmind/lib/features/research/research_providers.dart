import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:mm_research/mm_research.dart';

import '../../app/providers.dart';

typedef ResearchSessionKey = ({String studySetId, String sessionId});

final researchSessionRepositoryProvider = Provider<ResearchSessionRepository>(
  (ref) => ref.watch(contentRepositoryProvider) as ResearchSessionRepository,
);
final researchSnapshotRepositoryProvider = Provider<ResearchSnapshotRepository>(
  (ref) => ref.watch(contentRepositoryProvider) as ResearchSnapshotRepository,
);
final researchRecoveryProvider = Provider<ResearchRecovery>(
  (ref) => ResearchRecovery(
    ref.watch(researchSessionRepositoryProvider),
    () async => (await ref.read(studySetRepositoryProvider).watchAll().first).map((s) => s.id).toList(),
    now: ref.watch(clockProvider),
  ),
);
final researchReadyProvider = FutureProvider<void>((ref) => ref.watch(researchRecoveryProvider).ready);

/// P2-R3 sidebar API. Refreshed by every successful engine persistence operation.
final researchSessionsProvider = FutureProvider.family<List<ResearchSession>, String>((ref, studySetId) async {
  await ref.watch(researchReadyProvider.future);
  final sessions = await ref.watch(researchSessionRepositoryProvider).listResearchSessions(studySetId);
  return sessions..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
});
final researchSearchProvider = Provider<SearchProvider>((ref) => OpenAlexSearch());
final researchVideoTitlesProvider = Provider<VideoTitles?>((ref) => VideoTitles());
final researchCacheProvider = Provider<ResearchDocumentCache?>((ref) => null);
final researchExtractorProvider = Provider<ContentExtractor>(
  (ref) => MarkdownArticleExtractor(parser: WebKitArticleParser(), cache: ref.watch(researchCacheProvider)),
);

/// Deliberately not autoDispose: hiding a panel must not interrupt research.
final researchSessionProvider =
    AsyncNotifierProvider.family<ResearchSessionController, ResearchSessionState, ResearchSessionKey>(
      ResearchSessionController.new,
    );

class ResearchSessionController extends AsyncNotifier<ResearchSessionState> {
  ResearchSessionController(this.key);
  final ResearchSessionKey key;
  ResearchSessionEngine? _engine;
  @override
  Future<ResearchSessionState> build() async {
    var disposed = false;
    ref.onDispose(() {
      disposed = true;
    });
    final recovery = ref.watch(researchRecoveryProvider);
    await recovery.ready;
    final repository = ref.watch(researchSessionRepositoryProvider);
    final session = await repository.loadResearchSession(key.studySetId, key.sessionId);
    if (session == null) throw StateError('Unknown research session');
    if (disposed) throw StateError('Disposed research controller');
    final engine = _engine = ResearchSessionEngine(
      studySetId: key.studySetId,
      session: session,
      repository: repository,
      snapshots: ref.watch(researchSnapshotRepositoryProvider),
      recovery: recovery,
      newRequestId: newId,
      now: ref.watch(clockProvider),
      videoTitles: ref.watch(researchVideoTitlesProvider),
      onSaved: () {
        if (!disposed) ref.invalidate(researchSessionsProvider(key.studySetId));
      },
    );
    final subscription = engine.changes.listen((value) {
      if (!disposed) state = AsyncData(value);
    });
    ref.onDispose(() {
      unawaited(subscription.cancel());
      unawaited(engine.dispose());
    });
    return engine.state;
  }

  /// The latest state, including writes whose change events have not been
  /// delivered yet: what the next request will be based on.
  Future<ResearchSessionState> get current async => (await _ready).state;

  Future<ResearchSessionEngine> get _ready async {
    await future;
    return _engine!;
  }

  Future<void> answer({
    required AiProvider provider,
    required String question,
    required ResearchMode mode,
    String context = '',
    List<ResearchDocument> documents = const [],
    bool followUp = false,
    ResearchBudget budget = const ResearchBudget(),
  }) async => (await _ready).answer(
    provider: provider,
    question: question,
    mode: mode,
    context: context,
    documents: documents,
    followUp: followUp,
    budget: budget,
  );
  Future<void> disposeEngine() async => (await _ready).dispose();
  Future<void> cancel() async => (await _ready).cancel();
  Future<void> search(String query) async => (await _ready).search(ref.read(researchSearchProvider), query);
  Future<void> readSources(List<String> ids) async =>
      (await _ready).readSources(ref.read(researchExtractorProvider), ids);
  Future<void> updateDrafts(List<Map<String, Object?>> drafts) async => (await _ready).updateDrafts(drafts);
  Future<void> rename(String question) async => (await _ready).rename(question);
  Future<void> saveVideoLink(Uri url) async => (await _ready).saveVideoLink(url);
  Future<void> pasteSource(String sourceId, String text) async => (await _ready).pasteSource(sourceId, text);
}

/// Explicit creation captures origin once; changing the reader selection later
/// cannot mutate this session. Caller uses the returned key to open its provider.
Future<ResearchSessionKey> createResearchSession(
  Ref ref, {
  required String studySetId,
  required String question,
  SourceAnchor? origin,
  String contextScope = '',
  String intent = '',
}) async {
  await ref.read(researchReadyProvider.future);
  final now = ref.read(clockProvider)();
  final session = ResearchSession(
    id: newId(),
    question: question,
    anchor: origin,
    contextScope: contextScope,
    intent: intent,
    status: 'draft',
    createdAt: now,
    updatedAt: now,
  );
  await ref.read(researchSessionRepositoryProvider).saveResearchSession(studySetId, session);
  ref.invalidate(researchSessionsProvider(studySetId));
  return (studySetId: studySetId, sessionId: session.id);
}
