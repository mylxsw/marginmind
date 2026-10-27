import 'dart:async';

import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_research/mm_research.dart';
import 'package:test/test.dart';

class GatedRepository extends InMemoryStudySetContentRepository {
  Future<void>? hold;
  Completer<void>? entered;
  bool failNext = false;
  @override
  Future<void> saveResearchSession(String studySetId, ResearchSession session) async {
    if (entered != null && !entered!.isCompleted) entered!.complete();
    if (hold != null) await hold;
    if (failNext) {
      failNext = false;
      throw StateError('disk full');
    }
    await super.saveResearchSession(studySetId, session);
  }
}

class Provider implements AiProvider {
  Provider(this.events);
  final Stream<AiEvent> Function(AiRequest, CancellationToken) events;
  @override
  Stream<AiEvent> generate(AiRequest request, CancellationToken cancellation) => events(request, cancellation);
}

class Search implements SearchProvider {
  Search(this.hits);
  final List<SearchHit> hits;
  @override
  Future<List<SearchHit>> search(SearchRequest request, CancellationToken cancellation) async => hits;
}

class Titles extends VideoTitles {
  Titles(this.title);
  String? title;
  int calls = 0;
  @override
  Future<String?> lookup(ResearchSource source, CancellationToken cancellation) async {
    calls++;
    return title;
  }
}

class Extractor implements ContentExtractor {
  Extractor(this.read);
  final Future<ExtractedContent> Function(Uri) read;
  @override
  Future<ExtractedContent> extract(Uri url, CancellationToken cancellation) => read(url);
}

AiEvent event(AiRequest r, AiEventKind kind, {String? text, ResearchCitation? citation}) =>
    AiEvent(sessionId: r.sessionId, requestId: r.requestId, kind: kind, text: text, citation: citation);

void main() {
  final now = DateTime.utc(2026, 10, 27);
  late InMemoryStudySetContentRepository repository;
  late ResearchSessionEngine engine;
  late ResearchRecovery recovery;
  ResearchSession session(String id, String status) => ResearchSession(
    id: id,
    question: 'question',
    status: status,
    anchor: const SourceAnchor(target: CardTarget(cardId: 'original')),
    createdAt: now,
    updatedAt: now,
  );
  setUp(() async {
    repository = GatedRepository();
    recovery = ResearchRecovery(repository, () async => ['set']);
    await repository.saveResearchSession('set', session('session', 'draft'));
    var sequence = 0;
    engine = ResearchSessionEngine(
      studySetId: 'set',
      session: session('session', 'draft'),
      repository: repository,
      snapshots: repository,
      recovery: recovery,
      newRequestId: () => '${++sequence}',
      now: () => now,
    );
  });
  tearDown(() => engine.dispose());
  Future<void> until(bool Function() predicate) async {
    for (var i = 0; i < 100 && !predicate(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(predicate(), isTrue);
  }

  Future<void> ask(
    Provider provider, {
    ResearchMode mode = ResearchMode.web,
    bool followUp = false,
    List<ResearchDocument> documents = const [],
    Duration duration = const Duration(seconds: 1),
  }) => engine.answer(
    provider: provider,
    question: 'next',
    mode: mode,
    followUp: followUp,
    documents: documents,
    budget: ResearchBudget(duration: duration),
  );

  test('a saved video link shows its title, or its link until a later save finds one', () async {
    final titles = Titles(null);
    final titled = ResearchSessionEngine(
      studySetId: 'set',
      session: session('session', 'draft'),
      repository: repository,
      snapshots: repository,
      recovery: recovery,
      newRequestId: () => 'r',
      now: () => now,
      videoTitles: titles,
    );
    addTearDown(titled.dispose);
    await titled.saveVideoLink(Uri.parse('https://youtu.be/dQw4w9WgXcQ'));
    expect(titled.state.sources.single.title, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    titles.title = 'Never Gonna Give You Up';
    await titled.saveVideoLink(Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ'));
    expect(titled.state.sources.single.title, 'Never Gonna Give You Up');
    expect(titles.calls, 2);
  });

  test('video links survive restart, deduplicate and never reach extraction', () async {
    await engine.saveVideoLink(Uri.parse('https://youtu.be/dQw4w9WgXcQ'));
    await engine.saveVideoLink(Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ&utm_source=x'));
    final source = engine.state.sources.single;
    expect(source.kind, 'video');
    expect(source.readState, 'noTranscript');
    await engine.readSources(Extractor((_) async => throw StateError('must not extract video')), [source.id]);
    expect(engine.state.sources.single.readState, 'noTranscript');
    expect(engine.state.sources.single.versions, isEmpty);
    expect(engine.state.evidence, isEmpty);
    final restored = ResearchSessionState((await repository.loadResearchSession('set', 'session'))!);
    expect(restored.sources.single.toJson(), source.toJson());
  });

  test('refetch keeps old evidence and monotonically versions identical content', () async {
    await engine.search(Search([SearchHit(url: Uri.parse('https://example.com/page'), title: 'Page')]), 'q');
    final id = engine.state.sources.single.id;
    final extractor = Extractor(
      (url) async => markdownArticle(ReadableHtml(url: url, title: 'Page', html: '<p>Old text</p>')),
    );
    await engine.readSources(extractor, [id]);
    final old = engine.state.sources.single.versions.single;
    await engine.readSources(extractor, [id]);
    final fresh = engine.state.sources.single.versions.last;
    expect(fresh.version, old.version + 1);
    expect(fresh.snapshotFile, old.snapshotFile);
    expect(snapshotParagraphs(await repository.readResearchSnapshot('set', old.snapshotFile)).values, ['Old text']);
    await engine.readSources(Extractor((_) async => throw StateError('offline')), [id]);
    expect(engine.state.sources.single.versions, hasLength(2));
    final meta = engine.state.metadata[id] as Map;
    expect((meta['versions'] as Map).keys, containsAll(['1', '2']));
  });

  test('startup recovery completes globally before first request and never regenerates', () async {
    await repository.saveResearchSession('set', session('old', 'running'));
    await repository.saveResearchSession('set', session('legacy', 'idle'));
    var calls = 0;
    await ask(
      Provider((r, t) async* {
        calls++;
        expect((await repository.loadResearchSession('set', 'old'))!.status, 'interrupted');
        expect((await repository.loadResearchSession('set', 'legacy'))!.status, 'draft');
        yield event(r, AiEventKind.completed);
      }),
    );
    await recovery.ready;
    expect(calls, 1);
    expect(engine.state.session.status, 'done');
  });

  test('mismatched session/request ignored; origin is frozen; each chunk is persisted', () async {
    await ask(
      Provider((r, t) async* {
        yield const AiEvent(sessionId: 'other', requestId: '1', kind: AiEventKind.text, text: 'bad');
        yield AiEvent(sessionId: r.sessionId, requestId: 'stale', kind: AiEventKind.text, text: 'bad');
        yield event(r, AiEventKind.text, text: 'first');
        yield event(r, AiEventKind.text, text: ' second');
        yield event(r, AiEventKind.completed);
      }),
    );
    final saved = (await repository.loadResearchSession('set', 'session'))!;
    expect(ResearchSessionState(saved).answer, 'first second');
    expect((saved.anchor!.target as CardTarget).cardId, 'original');
  });

  test('cancel retains partial response and sources; replacing request ignores late response', () async {
    final stream = StreamController<AiEvent>();
    late AiRequest original;
    final first = ask(
      Provider((r, t) {
        original = r;
        return stream.stream;
      }),
    );
    await until(() => engine.state.session.status == 'running');
    stream.add(event(original, AiEventKind.text, text: 'partial'));
    await until(() => engine.state.answer == 'partial');
    await engine.cancel();
    await first;
    expect(engine.state.session.status, 'cancelled');
    expect(engine.state.answer, 'partial');
    await ask(
      Provider((r, t) async* {
        yield event(original, AiEventKind.text, text: 'late');
        yield event(r, AiEventKind.text, text: 'new');
        yield event(r, AiEventKind.completed);
      }),
    );
    expect(engine.state.answer, 'new');
    expect(engine.state.session.history.first['answer'], 'partial');
    await stream.close();
  });

  test('cancel during disk write keeps accepted chunk and discards queued data', () async {
    final repo = repository as GatedRepository;
    final stream = StreamController<AiEvent>();
    final started = Completer<AiRequest>();
    final work = ask(
      Provider((r, t) {
        started.complete(r);
        return stream.stream;
      }),
    );
    final request = await started.future;
    final gate = Completer<void>();
    repo.entered = Completer<void>();
    repo.hold = gate.future;
    stream.add(event(request, AiEventKind.text, text: 'accepted'));
    await repo.entered!.future;
    stream.add(event(request, AiEventKind.text, text: 'discarded'));
    final cancelled = engine.cancel();
    gate.complete();
    repo.hold = null;
    await cancelled;
    await work;
    await stream.close();
    expect(engine.state.answer, 'accepted');
    expect(engine.state.session.status, 'cancelled');
    expect(ResearchSessionState((await repo.loadResearchSession('set', 'session'))!).answer, 'accepted');
  });
  test('disk failure cannot publish successful answer and does not poison later writes', () async {
    await ask(
      Provider((r, t) async* {
        (repository as GatedRepository).failNext = true;
        yield event(r, AiEventKind.text, text: 'not committed');
        yield event(r, AiEventKind.completed);
      }),
    );
    expect(engine.state.session.status, 'failed');
    expect(engine.state.answer, isEmpty);
    await ask(
      Provider((r, t) async* {
        yield event(r, AiEventKind.completed);
      }),
    );
    expect(engine.state.session.status, 'done');
  });

  test('stage deadline bounds a silent provider and permits explicit retry', () async {
    final stream = StreamController<AiEvent>();
    await ask(Provider((r, t) => stream.stream), duration: const Duration(milliseconds: 10));
    expect(engine.state.session.status, 'failed');
    expect(engine.state.error, 'timeout');
    await stream.close();
    await ask(
      Provider((r, t) async* {
        yield event(r, AiEventKind.completed);
      }),
    );
    expect(engine.state.session.status, 'done');
    expect(engine.state.error, isNull);
  });

  test('disconnect and missing completion preserve partial text; budget cancels', () async {
    await ask(
      Provider((r, t) async* {
        yield event(r, AiEventKind.text, text: 'saved');
        throw const ResearchFailure(ResearchFailureKind.unavailable);
      }),
    );
    expect(engine.state.error, 'unavailable');
    expect(engine.state.answer, 'saved');
    await ask(
      Provider((r, t) async* {
        yield event(r, AiEventKind.text, text: 'truncated');
      }),
    );
    expect(engine.state.error, 'incomplete_stream');
    await ask(
      Provider((r, t) async* {
        throw const ResearchFailure(ResearchFailureKind.budget);
      }),
    );
    expect(engine.state.session.status, 'cancelled');
  });

  test('URL and DOI duplicates merge; source failures do not abort other reads; snapshots deduplicated with separate fetch versions', () async {
    await engine.search(
      Search([
        SearchHit(
          url: Uri.parse('https://example.com/a?utm_source=x'),
          title: 'A',
          doi: '10.1234/a',
          snippet: 'abstract',
        ),
        SearchHit(url: Uri.parse('https://example.org/reprint'), title: 'A copy', doi: 'https://doi.org/10.1234/A'),
        SearchHit(url: Uri.parse('https://example.com/b'), title: 'B'),
      ]),
      'query',
    );
    expect(engine.state.sources, hasLength(2));
    final source = engine.state.sources.first;
    expect(source.readState, 'abstractOnly');
    expect((engine.state.metadata[source.id] as Map)['aliases'], hasLength(2));
    final extractor = Extractor((url) async {
      if (url.path == '/b') throw const ResearchFailure(ResearchFailureKind.authentication, 'login_required');
      return markdownArticle(ReadableHtml(url: url, title: 'Read A', html: '<p>真实证据</p>'));
    });
    await engine.readSources(extractor, engine.state.sources.map((s) => s.id).toList());
    expect(engine.state.sources.first.readState, 'fullText');
    expect(engine.state.sources.last.readState, 'failed');
    expect(engine.state.session.status, 'done');
    await engine.readSources(extractor, [source.id]);
    expect(engine.state.sources.first.versions, hasLength(3));
    expect(engine.state.sources.first.versions[1].snapshotFile, engine.state.sources.first.versions[2].snapshotFile);
    final content = await repository.readResearchSnapshot('set', engine.state.sources.first.versions.last.snapshotFile);
    expect(snapshotParagraphs(content).values, ['真实证据']);
  });

  test('reading timeout is per source; cancellation leaves acquired snapshot intact', () async {
    await engine.search(
      Search([
        SearchHit(url: Uri.parse('https://example.com/a'), title: 'A'),
        SearchHit(url: Uri.parse('https://example.com/b'), title: 'B'),
      ]),
      'q',
    );
    await engine.readSources(
      Extractor(
        (uri) => uri.path == '/a'
            ? Completer<ExtractedContent>().future
            : Future.value(markdownArticle(ReadableHtml(url: uri, title: 'B', html: '<p>ok</p>'))),
      ),
      engine.state.sources.map((s) => s.id).toList(),
      timeout: const Duration(milliseconds: 10),
    );
    expect(engine.state.sources.map((s) => s.readState), ['failed', 'fullText']);
    final pending = engine.readSources(Extractor((uri) => Completer<ExtractedContent>().future), [
      engine.state.sources.first.id,
    ]);
    await until(() => engine.state.session.status == 'running');
    await engine.cancel();
    await pending;
    expect(engine.state.sources.last.versions, hasLength(1));
  });

  test('document citations validate persisted paragraph; followups use session history', () async {
    await engine.search(Search([SearchHit(url: Uri.parse('https://example.com/a'), title: 'A')]), 'q');
    await engine.readSources(
      Extractor((url) async => markdownArticle(ReadableHtml(url: url, title: 'A', html: '<p>real quote</p>'))),
      [engine.state.sources.single.id],
    );
    final source = engine.state.sources.single;
    final paragraphs = snapshotParagraphs(
      await repository.readResearchSnapshot('set', source.versions.single.snapshotFile),
    );
    final doc = ResearchDocument(
      sourceId: source.id,
      version: 1,
      paragraphId: paragraphs.keys.single,
      title: 'A',
      text: 'real quote',
    );
    final provider = Provider((r, t) async* {
      yield event(
        r,
        AiEventKind.citation,
        citation: ResearchCitation(sourceId: source.id, version: 1, paragraphId: doc.paragraphId, quote: 'fabricated'),
      );
      for (var i = 0; i < 2; i++) {
        yield event(
          r,
          AiEventKind.citation,
          citation: ResearchCitation(
            sourceId: source.id,
            version: 1,
            paragraphId: doc.paragraphId,
            quote: 'real quote',
          ),
        );
      }
      yield event(r, AiEventKind.text, text: 'answer');
      yield event(r, AiEventKind.completed);
    });
    await ask(provider, mode: ResearchMode.sources, documents: [doc]);
    expect(engine.state.evidence, hasLength(1));
    await ask(
      Provider((r, t) async* {
        expect(r.context, contains('answer'));
        yield event(r, AiEventKind.completed);
      }),
      followUp: true,
    );
    await ask(
      provider,
      mode: ResearchMode.sources,
      documents: [
        ResearchDocument(sourceId: source.id, version: 1, paragraphId: doc.paragraphId, title: 'A', text: 'forged'),
      ],
    );
    expect(engine.state.error, 'invalid_paragraph');
    await ask(
      provider,
      mode: ResearchMode.sources,
      documents: [const ResearchDocument(sourceId: 'missing', version: 1, paragraphId: 'missing', title: '', text: '')],
    );
    expect(engine.state.error, 'missing_snapshot');
  });

  test('paper abstracts can ground answers without claiming full text and duplicate search is idempotent', () async {
    final search = Search([
      SearchHit(
        url: Uri.parse('https://example.com/paper'),
        title: 'Paper',
        kind: 'paper',
        snippet: 'Only the abstract is available.',
        openAccess: false,
      ),
    ]);
    await engine.search(search, 'q');
    await engine.search(search, 'q');
    final source = engine.state.sources.single;
    expect(source.readState, 'abstractOnly');
    expect(source.versions, hasLength(1));
    final paragraphs = snapshotParagraphs(
      await repository.readResearchSnapshot('set', source.versions.single.snapshotFile),
    );
    final document = ResearchDocument(
      sourceId: source.id,
      version: source.versions.single.version,
      paragraphId: paragraphs.keys.single,
      title: source.title,
      text: paragraphs.values.single,
    );
    await ask(
      Provider((r, t) async* {
        yield event(
          r,
          AiEventKind.citation,
          citation: ResearchCitation(
            sourceId: source.id,
            version: document.version,
            paragraphId: document.paragraphId,
            quote: document.text,
          ),
        );
        yield event(r, AiEventKind.completed);
      }),
      mode: ResearchMode.sources,
      documents: [document],
    );
    expect(engine.state.evidence, hasLength(1));
    expect(engine.state.sources.single.readState, 'abstractOnly');
  });

  test('explicit canonical reprint merges into original without replacing old evidence', () async {
    await engine.search(
      Search([
        SearchHit(url: Uri.parse('https://example.com/original'), title: 'Original'),
        SearchHit(url: Uri.parse('https://example.org/reprint'), title: 'Reprint'),
      ]),
      'q',
    );
    final originalId = engine.state.sources.first.id;
    final reprintId = engine.state.sources.last.id;
    await engine.readSources(
      Extractor(
        (url) async => markdownArticle(
          ReadableHtml(
            url: url,
            title: 'Article',
            canonicalUrl: Uri.parse('https://example.com/original'),
            html: '<p>Shared full article</p>',
          ),
        ),
      ),
      [reprintId],
    );
    expect(engine.state.sources.single.id, originalId);
    expect(engine.state.sources.single.versions, hasLength(1));
    expect((engine.state.metadata[originalId] as Map)['aliases'], hasLength(2));
    expect(engine.state.session.sourceIds, [originalId]);
    await engine.search(
      Search([SearchHit(url: Uri.parse('https://example.org/reprint?utm_source=again'), title: 'Reprint')]),
      'q',
    );
    expect(engine.state.sources, hasLength(1));
  });

  test('web quote becomes evidence only after local verification; offline discards citations', () async {
    final provider = Provider((r, t) async* {
      yield event(
        r,
        AiEventKind.citation,
        citation: ResearchCitation(url: Uri.parse('https://example.com'), title: 'A', quote: 'real quote'),
      );
      yield event(r, AiEventKind.toolError);
      yield event(r, AiEventKind.completed);
    });
    await ask(provider, mode: ResearchMode.offline);
    expect(engine.state.sources, isEmpty);
    await ask(provider);
    expect(engine.state.sources, hasLength(1));
    expect(engine.state.evidence, isEmpty);
    await engine.readSources(
      Extractor((url) async => markdownArticle(ReadableHtml(url: url, title: 'A', html: '<p>real quote</p>'))),
      [engine.state.sources.single.id],
    );
    expect(engine.state.evidence, hasLength(1));
    await engine.updateDrafts([
      {'checked': true},
    ]);
    expect(engine.state.evidence, hasLength(1));
    expect(engine.state.session.drafts.first['checked'], isTrue);
    await expectLater(
      engine.updateDrafts([
        {'type': 'engine'},
      ]),
      throwsArgumentError,
    );
  });

  test('citations record where they fall in the answer, with the cited paragraph', () async {
    final page = Uri.parse('https://example.com/a');
    await ask(
      Provider((r, t) async* {
        yield event(r, AiEventKind.text, text: '- first\n');
        yield event(
          r,
          AiEventKind.source,
          citation: ResearchCitation(url: page, title: 'A'),
        );
        yield event(
          r,
          AiEventKind.citation,
          citation: ResearchCitation(url: page, title: 'A', quote: 'q'),
        );
        yield event(
          r,
          AiEventKind.citation,
          citation: ResearchCitation(url: page, title: 'A', start: 2),
        );
        yield event(r, AiEventKind.text, text: '- second\n');
        yield event(r, AiEventKind.completed);
      }),
    );
    final cites = (engine.state.session.history.last['cites'] as List).cast<Map>();
    final source = engine.state.sources.single.id;
    expect(cites.map((c) => (c['source'], c['at'])), [(source, 8), (source, 2)]);

    await engine.readSources(
      Extractor((url) async => markdownArticle(ReadableHtml(url: url, title: 'A', html: '<p>real quote</p>'))),
      [source],
    );
    final paragraph = snapshotParagraphs(
      await repository.readResearchSnapshot('set', engine.state.sources.single.versions.single.snapshotFile),
    ).keys.single;
    final doc = ResearchDocument(sourceId: source, version: 1, paragraphId: paragraph, title: 'A', text: 'real quote');
    await ask(
      Provider((r, t) async* {
        yield event(
          r,
          AiEventKind.citation,
          citation: ResearchCitation(sourceId: source, version: 1, paragraphId: paragraph, quote: 'real'),
        );
        yield event(r, AiEventKind.text, text: 'answer');
        yield event(r, AiEventKind.completed);
      }),
      mode: ResearchMode.sources,
      documents: [doc],
    );
    final cite = (engine.state.session.history.last['cites'] as List).single as Map;
    expect(cite['paragraph'], paragraph);
    expect(cite['evidence'], engine.state.evidence.firstWhere((e) => e.quote == 'real').id);
    expect(cite['at'], 0);
  });

  test('the question can be rewritten; pasted text becomes a marked version of a failed source', () async {
    await engine.rename('  a better question  ');
    expect(engine.state.session.question, 'a better question');
    await expectLater(engine.rename('   '), throwsArgumentError);

    await engine.search(Search([SearchHit(url: Uri.parse('https://example.com/login'), title: 'Login')]), 'q');
    final id = engine.state.sources.single.id;
    await engine.readSources(
      Extractor((url) async => throw const ResearchFailure(ResearchFailureKind.unavailable, 'login_required')),
      [id],
    );
    expect(engine.state.sources.single.readState, 'failed');
    await expectLater(engine.pasteSource(id, '  \n\n '), throwsArgumentError);
    await expectLater(engine.pasteSource('missing', 'text'), throwsArgumentError);
    await engine.pasteSource(id, 'First <b>paragraph</b>.\n\nSecond paragraph.');
    var source = engine.state.sources.single;
    expect(source.readState, 'fullText');
    expect(source.versions.single.version, 1);
    expect((engine.state.metadata[id] as Map)['pasted'], [1]);
    expect((engine.state.metadata[id] as Map)['error'], isNull);
    final paragraphs = snapshotParagraphs(
      await repository.readResearchSnapshot('set', source.versions.single.snapshotFile),
    );
    expect(paragraphs.values, ['First \\<b\\>paragraph\\</b\\>.', 'Second paragraph.']);
    // The same text again is the same version.
    await engine.pasteSource(id, 'First <b>paragraph</b>.\n\nSecond paragraph.');
    source = engine.state.sources.single;
    expect(source.versions, hasLength(1));
    await engine.pasteSource(id, 'Other text.');
    expect(engine.state.sources.single.versions.map((v) => v.version), [1, 2]);
    expect((engine.state.metadata[id] as Map)['pasted'], [1, 2]);
  });
}
