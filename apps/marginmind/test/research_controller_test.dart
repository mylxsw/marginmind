import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/research/research_controller.dart';
import 'package:marginmind/features/research/research_drafts.dart';
import 'package:marginmind/features/research/research_intents.dart';
import 'package:marginmind/features/research/research_origin.dart';
import 'package:marginmind/features/research/research_providers.dart';
import 'package:marginmind/features/research/research_settings.dart';
import 'package:marginmind/features/workspace/widgets/notices.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_research/mm_research.dart';

import 'helpers.dart';

class _Ai implements AiProvider {
  _Ai(this.script);
  final Stream<AiEvent> Function(AiRequest) script;
  final requests = <AiRequest>[];
  @override
  Stream<AiEvent> generate(AiRequest request, CancellationToken cancellation) {
    requests.add(request);
    return script(request);
  }
}

AiEvent _e(AiRequest r, AiEventKind k, {String? text, ResearchCitation? citation}) =>
    AiEvent(sessionId: r.sessionId, requestId: r.requestId, kind: k, text: text, citation: citation);

class _Search implements SearchProvider {
  @override
  Future<List<SearchHit>> search(SearchRequest request, CancellationToken cancellation) async => [
    SearchHit(url: Uri.parse('https://example.org/page'), title: 'Page', kind: 'paper'),
  ];
}

class _Extractor implements ContentExtractor {
  @override
  Future<ExtractedContent> extract(Uri url, CancellationToken cancellation) async =>
      markdownArticle(ReadableHtml(url: url, title: 'Page', html: '<p>Kept text one.</p><p>Kept text two.</p>'));
}

const _prefs = <String, Object>{'research.service': 'anthropic', 'research.key.anthropic': true};

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  await tester.pumpAndSettle();
}

void main() {
  late ProviderContainer container;
  late WorkspaceController workspace;
  late ResearchPanelController panel;
  late _Ai ai;

  Future<void> open(WidgetTester tester, {Map<String, Object> prefs = _prefs}) async {
    final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    ai = _Ai((r) async* {
      if (r.question.startsWith('Summarize')) {
        yield _e(r, AiEventKind.text, text: 'A short summary. [source:1]');
      } else if (r.mode == ResearchMode.sources) {
        final d = r.documents.first;
        yield _e(
          r,
          AiEventKind.citation,
          citation: ResearchCitation(
            sourceId: d.sourceId,
            version: d.version,
            paragraphId: d.paragraphId,
            quote: d.text,
          ),
        );
        yield _e(r, AiEventKind.text, text: '- From the chosen source [source:0]\n');
      } else {
        yield _e(r, AiEventKind.text, text: '- An answer.\n');
      }
      yield _e(r, AiEventKind.completed);
    });
    container = await pumpApp(
      tester,
      prefs: prefs,
      size: const Size(1400, 900),
      content: repo,
      overrides: [
        researchRecoveryProvider.overrideWithValue(ResearchRecovery(repo, () async => ['demo-1'])),
        researchAiFactoryProvider.overrideWithValue(() async => ai),
        researchSearchProvider.overrideWithValue(_Search()),
        researchExtractorProvider.overrideWithValue(_Extractor()),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    workspace = container.read(workspaceProvider('demo-1').notifier);
    panel = container.read(researchPanelProvider('demo-1').notifier);
  }

  ResearchSessionState state(String id) =>
      container.read(researchSessionProvider((studySetId: 'demo-1', sessionId: id))).requireValue;

  ResearchLaunch launch(ResearchMethod method, {Set<ResearchSourceKind> kinds = const {ResearchSourceKind.paper}}) {
    final content = workspace.content;
    return ResearchLaunch(
      origin: ResearchOrigin(
        anchor: SourceAnchor(
          target: PdfTarget(
            documentId: content.documents.first.id,
            pages: const [
              AnnotationPage(page: 24, rects: [PageRect(10, 100, 200, 88)]),
            ],
            quote: '遗忘曲线',
          ),
        ),
        text: '遗忘曲线',
        fromMap: false,
        documentTitle: content.documents.first.title,
        page: 24,
        path: const [],
      ),
      intent: ResearchIntent.paper,
      question: '遗忘曲线可靠吗？',
      method: method,
      keywords: const ['遗忘曲线'],
      kinds: kinds,
      context: 'ctx',
    );
  }

  testWidgets('later resumes once with its saved anchor; missing AI keeps it pending', (tester) async {
    await open(tester, prefs: const {});
    final futureId = panel.later(launch(ResearchMethod.web));
    await _settle(tester);
    final id = await futureId;
    await _settle(tester);
    final before = state(id).session.anchor!.toJson();
    final first = panel.run(id);
    final second = panel.run(id);
    expect(identical(first, second), isTrue);
    await _settle(tester);
    expect(await first, ResearchBlock.noWeb);
    await _settle(tester);
    expect(state(id).drafts.later, isTrue);
    expect(state(id).session.anchor!.toJson(), before);
    expect(ai.requests, isEmpty);
  });

  testWidgets('video-only discovery does not ask AI to summarize unavailable transcripts', (tester) async {
    await open(tester);
    final id = await panel.start(launch(ResearchMethod.web, kinds: {ResearchSourceKind.video}));
    await _settle(tester);
    expect(ai.requests, isEmpty);
    expect(container.read(researchPanelProvider('demo-1')).tab, ResearchTab.sources);
    await panel.saveVideoLink(id, Uri.parse('https://youtu.be/dQw4w9WgXcQ'));
    await _settle(tester);
    final source = state(id).sources.single;
    expect(await panel.summarize(id, source, language: 'English'), isNull);
    expect(ai.requests, isEmpty);
  });

  testWidgets('search, read, choose, answer from sources, summarize, clips and drafts', (tester) async {
    await open(tester);
    final id = await panel.start(launch(ResearchMethod.search));
    await _settle(tester);
    expect(container.read(researchPanelProvider('demo-1')).tab, ResearchTab.sources);
    final source = state(id).sources.single;
    await panel.read(source.id, sessionId: id);
    await _settle(tester);
    expect(state(id).sources.single.readState, 'fullText');
    expect(await panel.answerFromChosen(id), isNull);
    expect(ai.requests, isEmpty);
    await panel.toggleChosen(id, source.id);
    await _settle(tester);
    expect(state(id).drafts.chosen, {source.id});
    await panel.answerFromChosen(id);
    await _settle(tester);
    expect(ai.requests.single.mode, ResearchMode.sources);
    expect(ai.requests.single.documents.map((d) => d.text), ['Kept text one.', 'Kept text two.']);
    expect(state(id).answer, contains('From the chosen source'));
    expect(state(id).evidence, isNotEmpty);
    expect(state(id).drafts.doneAt, testNow);
    // Retry repeats the last request, not the session's search.
    await panel.retry(id);
    await _settle(tester);
    expect(ai.requests.map((r) => r.mode), [ResearchMode.sources, ResearchMode.sources]);

    // A summary is kept apart, on request, per source version.
    await panel.summarize(id, state(id).sources.single, language: 'English');
    await _settle(tester);
    expect(state(id).drafts.summaries.values.single, 'A short summary.');
    // Checks, edits, clips: each change applies to the one before.
    unawaited(panel.toggleChecked(id, '0.0.0'));
    unawaited(panel.toggleChecked(id, '0.0.1'));
    unawaited(panel.editPoint(id, '0.0.0', '  edited  '));
    await _settle(tester);
    expect(state(id).drafts.checked, {'0.0.0', '0.0.1'});
    expect(state(id).drafts.edits, {'0.0.0': 'edited'});
    await panel.toggleChecked(id, '0.0.1');
    await panel.editPoint(id, '0.0.0', ' ');
    await panel.clearChecked(id);
    final clip = ResearchClip(evidence: state(id).evidence.first, sourceTitle: 'Page');
    await panel.addClip(id, clip);
    await panel.addClip(id, clip);
    await _settle(tester);
    expect(state(id).drafts.clips, hasLength(1));
    expect(state(id).drafts.edits, isEmpty);
    expect(state(id).drafts.checked, isEmpty);
    await panel.removeClip(id, clip.evidence.id);
    await panel.join(id, 'more context');
    await panel.rename(id, '更好的问题');
    await _settle(tester);
    expect(state(id).drafts.clips, isEmpty);
    expect(state(id).drafts.extra, ['more context']);
    expect(state(id).session.question, '更好的问题');

    // Follow-ups carry the joined context; panel views switch as asked.
    await panel.followUp(id, '  ');
    expect(ai.requests, hasLength(3));
    await panel.followUp(id, 'And then?');
    await _settle(tester);
    expect(ai.requests.last.context, contains('more context'));
    expect(ai.requests.last.mode, ResearchMode.offline);
    panel.openReading(source.id, paragraphId: 'p');
    expect(container.read(researchPanelProvider('demo-1')).readingSourceId, source.id);
    panel.setFilter(ResearchSourceKind.paper);
    expect(container.read(researchPanelProvider('demo-1')).filter, ResearchSourceKind.paper);
    panel.setFilter(null);
    panel.setTab(ResearchTab.saved);
    expect(container.read(researchPanelProvider('demo-1')).readingSourceId, isNull);
    panel.showNote('n');
    panel.closeNote();
    panel.showStart();
    expect(container.read(researchPanelProvider('demo-1')).sessionId, isNull);
    await settleHud(tester);
  });

  testWidgets('without AI a run is blocked and says so; search without papers searches nothing', (tester) async {
    await open(tester, prefs: const {});
    final id = await panel.start(launch(ResearchMethod.search, kinds: {ResearchSourceKind.web}));
    await _settle(tester);
    expect(state(id).sources, isEmpty);
    expect(state(id).session.status, 'draft');
    final offline = await panel.start(launch(ResearchMethod.web));
    await _settle(tester);
    expect(container.read(researchPanelProvider('demo-1')).blocked[offline], ResearchBlock.noWeb);
    expect(await panel.followUp(offline, 'q'), isNull);
    await settleHud(tester);
  });

  testWidgets('saving to source and map, editing, detaching, deleting and going back to the origin', (tester) async {
    await open(tester);
    final content = workspace.content;
    final doc = content.documents.first;
    final topic = content.cards.firstWhere((c) => c.title == '遗忘的规律');
    final note = ResearchNote(id: 'n1', title: '结论', body: '正文', createdAt: testNow, updatedAt: testNow);
    final target = PdfTarget(
      documentId: doc.id,
      pages: const [
        AnnotationPage(page: 24, rects: [PageRect(10, 100, 200, 88)]),
      ],
    );
    final saved = await workspace.saveResearchNote(
      note,
      source: target,
      toMap: true,
      cardParentId: topic.id,
      splitPoints: ['一', '二'],
    );
    await tester.pumpAndSettle();
    expect(saved!.inSource, isTrue);
    expect(workspace.content.childrenOf(saved.cardId), hasLength(2));
    // Saving the same note again does nothing.
    expect(await workspace.saveResearchNote(note, toMap: true), isNull);
    expect(workspace.content.researchNotes, hasLength(1));

    // A research card is edited through its note, not in place.
    workspace.beginEditing(saved.cardId!);
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).panel, RightPanel.details);
    expect(container.read(workspaceProvider('demo-1')).editingCardId, isNull);
    await workspace.editResearchNote('n1', title: '新结论');
    expect(workspace.content.researchNote('n1')!.title, '新结论');

    // Back to the source; back to a node; a place that is gone.
    workspace.revealNoteInSource('n1');
    expect(container.read(workspaceProvider('demo-1')).reveal!.page, 24);
    await workspace.locateNoteCard('n1');
    expect(container.read(workspaceProvider('demo-1')).selectedCardId, saved.cardId);
    expect(await workspace.revealAnchor(SourceAnchor(target: target)), isTrue);
    expect(
      await workspace.revealAnchor(
        SourceAnchor(
          target: CardTarget(cardId: topic.id),
          mapId: MindMap.defaultId,
        ),
      ),
      isTrue,
    );
    expect(container.read(workspaceProvider('demo-1')).selectedCardId, topic.id);
    expect(await workspace.revealAnchor(const SourceAnchor(target: CardTarget(cardId: 'gone'))), isFalse);
    expect(
      await workspace.revealAnchor(
        SourceAnchor(
          target: PdfTarget(
            documentId: 'gone',
            pages: const [AnnotationPage(page: 1, rects: [])],
          ),
        ),
      ),
      isFalse,
    );

    // A click on the mark opens its card; unknown marks are ignored.
    final attachment = workspace.content.noteAttachments.firstWhere((a) => a.target is PdfTarget);
    workspace.tapHighlight('note:missing');
    expect(container.read(workspaceProvider('demo-1')).pending, isNull);
    workspace.tapHighlight(noteMarkId(attachment.id));
    expect(container.read(workspaceProvider('demo-1')).pending, isA<PendingResearchNote>());
    await workspace.detachResearchNote(attachment.id);
    expect(container.read(workspaceProvider('demo-1')).pending, isNull);
    expect(workspace.content.noteAttachments.any((a) => a.target is PdfTarget), isFalse);
    await workspace.deleteResearchNote('n1');
    expect(workspace.content.researchNotes, isEmpty);
    await workspace.undo();
    expect(workspace.content.researchNotes, hasLength(1));
    await tester.pumpAndSettle();
    final element = tester.element(find.byType(MMWindowScaffold));
    for (final (notice, text) in [
      (const ResearchNoteSavedNotice(noteId: 'n', cardId: 'c', inSource: true), 'Saved to the source and the map'),
      (const ResearchNoteSavedNotice(noteId: 'n', cardId: 'c', inSource: false), 'Saved to the map'),
      (const ResearchNoteSavedNotice(noteId: 'n', inSource: true), 'Saved to the source'),
    ]) {
      showNotice(element, notice, rootTitle: '');
      await tester.pump();
      expect(find.text(text), findsOneWidget);
    }
    await settleHud(tester);
  });

  test('settings controller persists limits, model, endpoint and context choice', () async {
    final overrides = await testOverrides(prefs: const {'research.service': 'compatible'});
    final c = ProviderContainer(overrides: [...overrides, researchSecretStoreProvider.overrideWithValue(_Secrets())]);
    addTearDown(c.dispose);
    final controller = c.read(researchSettingsProvider.notifier);
    await controller.setModel(' llama ');
    await controller.setEndpoint('http://localhost:11434/v1/chat/completions');
    await controller.setLimits(searches: 99, pages: 0, minutes: 3);
    await controller.setShowContext(false);
    var s = c.read(researchSettingsProvider);
    expect((s.model, s.searches, s.pages, s.minutes, s.showContext), ('llama', 10, 1, 3, false));
    expect(s.aiConfigured, isTrue);
    expect(await c.read(researchAiFactoryProvider)(), isA<OpenAiCompatibleProvider>());
    await controller.saveKey('k');
    expect(c.read(researchSettingsProvider).keySaved, isTrue);
    await controller.setService(ResearchService.openai);
    s = c.read(researchSettingsProvider);
    expect((s.service, s.model, s.keySaved), (ResearchService.openai, '', false));
    expect(await c.read(researchAiFactoryProvider)(), isNull);
    await controller.setModel('gpt');
    await controller.saveKey('k2');
    expect(await c.read(researchAiFactoryProvider)(), isA<OpenAiResponsesProvider>());
    await controller.setService(ResearchService.none);
    await controller.saveKey('ignored');
    expect(await c.read(researchAiFactoryProvider)(), isNull);
  });
}

class _Secrets implements SecretStore {
  final values = <String, String>{};
  @override
  Future<void> delete(String account) async => values.remove(account);
  @override
  Future<String?> read(String account) async => values[account];
  @override
  Future<void> write(String account, String value) async => values[account] = value;
}
