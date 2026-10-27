import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/research/research_providers.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_research/mm_research.dart';

class Ai implements AiProvider {
  Ai(this.generateEvents);
  final Stream<AiEvent> Function(AiRequest) generateEvents;
  @override
  Stream<AiEvent> generate(AiRequest request, CancellationToken cancellation) => generateEvents(request);
}

class Search implements SearchProvider {
  @override
  Future<List<SearchHit>> search(SearchRequest request, CancellationToken cancellation) async => [
    SearchHit(url: Uri.parse('https://example.com'), title: 'source'),
  ];
}

class Extractor implements ContentExtractor {
  @override
  Future<ExtractedContent> extract(Uri url, CancellationToken cancellation) async =>
      markdownArticle(ReadableHtml(url: url, title: 'source', html: '<p>content</p>'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('sidebar recovery, create, hidden panel request, drafts and extraction share state', () async {
    final repository = InMemoryStudySetContentRepository();
    final now = DateTime.utc(2026);
    await repository.saveResearchSession(
      'set',
      ResearchSession(id: 'old', question: 'old', status: 'running', createdAt: now, updatedAt: now),
    );
    final creator = Provider<Future<ResearchSessionKey>>(
      (ref) => createResearchSession(
        ref,
        studySetId: 'set',
        question: 'new',
        origin: const SourceAnchor(target: CardTarget(cardId: 'selected')),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        contentRepositoryProvider.overrideWithValue(repository),
        researchRecoveryProvider.overrideWithValue(ResearchRecovery(repository, () async => ['set'])),
        researchSearchProvider.overrideWithValue(Search()),
        researchVideoTitlesProvider.overrideWithValue(null),
        researchExtractorProvider.overrideWithValue(Extractor()),
      ],
    );
    addTearDown(container.dispose);
    expect((await container.read(researchSessionsProvider('set').future)).single.status, 'interrupted');
    final key = await container.read(creator);
    final value = await container.read(researchSessionProvider(key).future);
    expect(value.session.status, 'draft');
    expect((value.session.anchor!.target as CardTarget).cardId, 'selected');
    expect(await container.read(researchSessionsProvider('set').future), hasLength(2));
    final controller = container.read(researchSessionProvider(key).notifier);
    await controller.search('q');
    var state = await container.read(researchSessionProvider(key).future);
    await controller.readSources([state.sources.single.id]);
    await controller.updateDrafts([
      {'checked': true},
    ]);
    final stream = StreamController<AiEvent>();
    late AiRequest request;
    final pending = controller.answer(
      provider: Ai((r) {
        request = r;
        return stream.stream;
      }),
      question: 'q',
      mode: ResearchMode.offline,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // No widget listener is necessary. Reading another selection/provider does
    // not change the engine's frozen origin or dispose the running request.
    stream.add(
      AiEvent(sessionId: request.sessionId, requestId: request.requestId, kind: AiEventKind.text, text: 'partial'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await controller.cancel();
    await pending;
    await stream.close();
    state = await container.read(researchSessionProvider(key).future);
    expect(state.session.status, 'cancelled');
    expect(state.answer, 'partial');
    expect(state.sources.single.versions, hasLength(1));
    expect((await container.read(researchSessionsProvider('set').future)).first.id, key.sessionId);
  });
  test('missing session exposes error and failed startup blocks list and new requests', () async {
    final repository = InMemoryStudySetContentRepository();
    final good = ProviderContainer(
      overrides: [
        contentRepositoryProvider.overrideWithValue(repository),
        researchRecoveryProvider.overrideWithValue(ResearchRecovery(repository, () async => ['set'])),
      ],
    );
    addTearDown(good.dispose);
    await expectLater(
      good.read(researchSessionProvider((studySetId: 'set', sessionId: 'missing')).future),
      throwsStateError,
    );
    final bad = ProviderContainer(
      overrides: [
        contentRepositoryProvider.overrideWithValue(repository),
        researchRecoveryProvider.overrideWithValue(ResearchRecovery(repository, () async => throw StateError('disk'))),
      ],
    );
    addTearDown(bad.dispose);
    await expectLater(bad.read(researchSessionsProvider('set').future), throwsA(anything));
  });
}
