import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/research/research_answer.dart';
import 'package:marginmind/features/research/research_controller.dart';
import 'package:marginmind/features/research/research_drafts.dart';
import 'package:marginmind/features/research/research_intents.dart';
import 'package:marginmind/features/research/research_origin.dart';
import 'package:marginmind/features/research/research_settings.dart';
import 'package:marginmind/features/research/widgets/research_reading.dart';
import 'package:marginmind/features/research/widgets/research_sources.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_research/mm_research.dart';

import 'helpers.dart';

void main() {
  group('intents', () {
    test('recommendation follows the selection', () {
      expect(recommendIntent('锚定效应', fromMap: false), ResearchIntent.explain);
      expect(recommendIntent('任何长度的文字', fromMap: true), ResearchIntent.explain);
      expect(recommendIntent('一个明显随机的数字，竟能让估计相差将近一倍。', fromMap: false), ResearchIntent.verify);
      expect(recommendIntent('The anchoring effect is a cognitive bias.', fromMap: false), ResearchIntent.translate);
      expect(
        recommendIntent('人们在估计时会先想到某个数字，然后从它出发进行调整，问题在于这种调整通常是不充分的，最初出现的数字会把最终的估计拉向自己，形成偏差。', fromMap: false),
        ResearchIntent.interpret,
      );
      expect(recommendIntent('人们在估计时会先想到某个参照物', fromMap: false), ResearchIntent.explain);
    });

    test('methods fall back to what is available; kinds follow the intent', () {
      expect(defaultMethod(ResearchIntent.verify, ai: true, web: true), ResearchMethod.web);
      expect(defaultMethod(ResearchIntent.verify, ai: true, web: false), ResearchMethod.offline);
      expect(defaultMethod(ResearchIntent.verify, ai: false, web: false), ResearchMethod.search);
      expect(defaultMethod(ResearchIntent.explain, ai: false, web: false), ResearchMethod.search);
      expect(defaultMethod(ResearchIntent.video, ai: true, web: true), ResearchMethod.search);
      expect(ResearchIntent.verify.kinds, {ResearchSourceKind.web, ResearchSourceKind.paper});
      expect(ResearchIntent.video.kinds, {ResearchSourceKind.video, ResearchSourceKind.image});
      expect(ResearchIntent.paper.kinds, {ResearchSourceKind.paper});
      expect(ResearchIntent.explain.kinds, {ResearchSourceKind.web});
      expect(ResearchMethod.parse('web'), ResearchMethod.web);
      expect(ResearchMethod.parse('bogus'), ResearchMethod.search);
      expect(ResearchMethod.search.mode, isNull);
      expect(ResearchMethod.offline.mode, ResearchMode.offline);
      expect(ResearchMethod.web.mode, ResearchMode.web);
    });

    test('keywords never use the whole passage', () {
      expect(researchTerm('锚定效应', fromMap: false), '锚定效应');
      expect(researchTerm('这种现象被称为「锚定效应」，很常见。', fromMap: false), '锚定效应');
      expect(researchTerm('研究者把这种现象称为 anchoring effect，并且做了很多实验。', fromMap: false), 'anchoring effect');
      expect(researchTerm('当人们需要估计一个未知的数量时，往往会先想到某个数字', fromMap: false), '当人们需要估计一个未知的');
      expect(suggestKeywords('研究者把这种现象称为 anchoring effect，并且 Kahneman 做了实验', fromMap: false), [
        'anchoring effect',
        'Kahneman',
      ]);
      expect(suggestKeywords('认知偏差', fromMap: true), ['认知偏差']);
    });
  });

  group('answers', () {
    test('sections, bullets, wrapped lines, markers and offsets', () {
      const answer = '## 结论\n- 结论**可靠** [source:0]\n  继续说明\n\n## 待解决的问题\n- 还不清楚\n\n第二段';
      final sections = parseAnswer(
        answer,
        turn: 2,
        documents: [
          {'sourceId': 's1', 'paragraphId': 'p1'},
        ],
        cites: [
          {'source': 's1', 'paragraph': 'p1', 'evidence': 'e1', 'at': 999},
        ],
      );
      expect(sections.map((s) => s.heading), ['结论', '待解决的问题']);
      final first = sections.first.points.single;
      expect(first.text, '结论可靠 继续说明');
      expect(first.key, '2.1.0');
      expect(first.cites.single.evidenceId, 'e1');
      expect(sections.last.openQuestions, isTrue);
      expect(sections.last.points.map((p) => p.text), ['还不清楚', '第二段']);
    });

    test('streamed offsets go to the point there; one cite per source keeps evidence', () {
      const answer = 'Intro line\n- first point\n- second point';
      final sections = parseAnswer(
        answer,
        cites: [
          {'source': 'a', 'at': 0},
          {'source': 'b', 'at': 12},
          {'source': 'b', 'evidence': 'eb', 'at': 13},
          {'source': 'c', 'at': 500},
          {'bogus': true},
        ],
      );
      final points = sections.single.points;
      expect(points[0].cites.map((c) => c.sourceId), ['a']);
      expect(points[1].cites.single, const AnswerCite('b', 'eb'));
      expect(points[2].cites.single.sourceId, 'c');
      expect(const AnswerCite('x').hashCode, const AnswerCite('x').hashCode);
    });

    test('turns skip empty answers and keep their method', () {
      final turns = AnswerTurn.all([
        {'question': 'q1', 'mode': 'web', 'answer': ''},
        {'question': 'q2', 'mode': 'offline', 'answer': '**Bold** [link](https://x.org) and *it*'},
      ]);
      expect(turns.single.index, 1);
      expect(turns.single.method, 'offline');
      expect(turns.single.points.single.text, 'Bold link and it');
      final evidence = [
        Evidence(
          id: 'e',
          sourceId: 's',
          sourceVersion: 1,
          quote: 'q',
          locator: const EvidenceLocator.paragraph('p'),
          acquisition: EvidenceAcquisition.auto,
          capturedAt: testNow,
        ),
      ];
      expect(evidenceParagraph(evidence, const AnswerCite('s', 'e')), 'p');
      expect(evidenceParagraph(evidence, const AnswerCite('s')), 'p');
      expect(evidenceParagraph(evidence, const AnswerCite('t')), isNull);
    });
  });

  test('drafts round trip through the session and ignore broken entries', () {
    final clip = ResearchClip(
      evidence: Evidence(
        id: 'e',
        sourceId: 's',
        sourceVersion: 1,
        quote: 'quote',
        locator: const EvidenceLocator.paragraph('p'),
        acquisition: EvidenceAcquisition.userPaste,
        capturedAt: testNow,
      ),
      sourceTitle: 'Source',
    );
    final drafts = const ResearchDrafts().copyWith(
      method: ResearchMethod.web,
      keywords: ['k'],
      kinds: {ResearchSourceKind.paper},
      context: 'ctx',
      later: true,
      checked: {'0.0.0'},
      edits: {'0.0.0': 'edited'},
      clips: [clip],
      chosen: {'s'},
      extra: ['more'],
      summaries: {'s@1': 'sum'},
    );
    final json = drafts.toJson();
    json['clips'] = [...json['clips'] as List, 'broken'];
    json['kinds'] = [...json['kinds'] as List, 'nope'];
    final session = ResearchSession(id: 'x', question: 'q', drafts: [json], createdAt: testNow, updatedAt: testNow);
    final read = ResearchDrafts.of(session);
    expect(read.method, ResearchMethod.web);
    expect(read.keywords, ['k']);
    expect(read.kinds, {ResearchSourceKind.paper});
    expect(read.context, 'ctx');
    expect(read.later, isTrue);
    expect(read.checked, {'0.0.0'});
    expect(read.edits, {'0.0.0': 'edited'});
    expect(read.clips.single.evidence.acquisition, EvidenceAcquisition.userPaste);
    expect(read.clips.single.sourceTitle, 'Source');
    expect(read.chosen, {'s'});
    expect(read.extra, ['more']);
    expect(read.summaries, {'s@1': 'sum'});
    expect(
      ResearchDrafts.of(ResearchSession(id: 'y', question: 'q', createdAt: testNow, updatedAt: testNow)).later,
      isFalse,
    );
    final state = ResearchSessionState(
      ResearchSession(
        id: 'z',
        question: 'q',
        drafts: [
          {
            'type': 'engine',
            'sources': [
              ResearchSource(
                id: 's',
                url: 'https://a.org',
                canonicalUrl: 'https://a.org',
                kind: 'web',
                title: 'A',
                fetchedAt: testNow,
              ).toJson(),
            ],
            'metadata': {
              's': {
                'pasted': [2],
                'error': 'login_required',
              },
            },
          },
        ],
        createdAt: testNow,
        updatedAt: testNow,
      ),
    );
    expect(state.numberOf('s'), 1);
    expect(state.numberOf('missing'), 0);
    expect(state.pastedVersions('s'), {2});
    expect(state.readError('s'), 'login_required');
  });

  test('settings: what is configured and the budget it gives', () {
    expect(const ResearchSettings().aiConfigured, isFalse);
    expect(const ResearchSettings(service: ResearchService.anthropic).aiConfigured, isFalse);
    const anthropic = ResearchSettings(service: ResearchService.anthropic, keySaved: true);
    expect(anthropic.aiConfigured, isTrue);
    expect(anthropic.webAvailable, isTrue);
    expect(const ResearchSettings(service: ResearchService.openai, keySaved: true).aiConfigured, isFalse);
    expect(const ResearchSettings(service: ResearchService.openai, keySaved: true, model: 'm').aiConfigured, isTrue);
    const local = ResearchSettings(
      service: ResearchService.compatible,
      model: 'llama',
      endpoint: 'http://localhost:11434/v1/chat/completions',
    );
    expect(local.aiConfigured, isTrue);
    expect(local.webAvailable, isFalse);
    expect(local.copyWith(endpoint: 'http://192.168.1.2/v1').aiConfigured, isFalse);
    expect(local.copyWith(endpoint: 'https://api.example.com/v1').aiConfigured, isFalse);
    expect(local.copyWith(endpoint: 'https://api.example.com/v1', keySaved: true).aiConfigured, isTrue);
    expect(local.copyWith(endpoint: 'not a url').endpointUri, isNull);
    for (final base in [
      'https://api.example.com',
      'https://api.example.com/',
      'https://api.example.com/v1',
      'https://api.example.com/v1/',
    ]) {
      expect(local.copyWith(endpoint: base).endpointUri.toString(), 'https://api.example.com/v1/chat/completions');
    }
    expect(
      local.copyWith(endpoint: 'https://api.example.com/custom/chat/completions').endpointUri!.path,
      '/custom/chat/completions',
    );
    expect(local.copyWith(endpoint: 'https://user:password@api.example.com/v1').endpointUri, isNull);
    final budget = const ResearchSettings(searches: 4, pages: 6, minutes: 3).budget;
    expect((budget.searches, budget.pages, budget.duration), (4, 6, const Duration(minutes: 3)));
  });

  test('origins: passage context, chapter and node path', () async {
    final content = demoContent();
    final doc = content.documents.first;
    final origin = await pdfOrigin(
      document: doc,
      pages: const [
        AnnotationPage(page: 24, rects: [PageRect(1, 2, 3, 1)]),
      ],
      quote: '被称为遗忘曲线。',
      pageText: (page) async => '前面的句子。这条先陡后平的曲线，被称为遗忘曲线。后面还有一句话。',
      outline: const [
        MMPdfOutlineItem(
          title: '第 2 章',
          page: 20,
          children: [
            MMPdfOutlineItem(title: '2.1 遗忘', page: 22),
            MMPdfOutlineItem(title: '2.2 记忆', page: 30),
          ],
        ),
        MMPdfOutlineItem(title: '第 3 章', page: 40),
      ],
    );
    expect(origin.fromMap, isFalse);
    expect(origin.page, 24);
    expect(origin.pdf!.documentId, doc.id);
    expect(origin.cardId, isNull);
    final kinds = {for (final p in origin.parts) p.kind: p};
    expect(kinds[ResearchContextKind.before]!.text, '前面的句子。这条先陡后平的曲线，');
    expect(kinds[ResearchContextKind.after]!.text, '后面还有一句话。');
    expect(kinds[ResearchContextKind.chapter]!.text, '第 2 章 › 2.1 遗忘');
    expect(kinds[ResearchContextKind.selection]!.required, isTrue);
    final bare = await pdfOrigin(
      document: doc,
      pages: const [AnnotationPage(page: 1, rects: [])],
      quote: 'x',
    );
    expect(bare.parts.map((p) => p.kind), [ResearchContextKind.selection]);

    final topic = content.cards.firstWhere((c) => c.title == '遗忘的规律');
    final node = nodeOrigin(content, topic.id, MindMap.defaultId, rootTitle: '根');
    expect(node.fromMap, isTrue);
    expect(node.cardId, topic.id);
    expect(node.path, ['根']);
    final children = node.parts.firstWhere((p) => p.kind == ResearchContextKind.children);
    expect(children.on, isFalse);
    expect(children.text, contains('遗忘曲线'));
  });

  test('the pane a research came from stays beside the panel', () {
    final pdf = PdfTarget(documentId: 'd', pages: const [], quote: 'q');
    expect(researchPanelOrigin(SourceAnchor(target: pdf)), PanelOrigin.reader);
    expect(researchPanelOrigin(const SourceAnchor(target: CardTarget(cardId: 'c'))), PanelOrigin.map);
    expect(researchPanelOrigin(null), PanelOrigin.toolbar);
  });

  test('card titles: topic, excerpt and research cards by what they show', () {
    final time = DateTime.utc(2026, 10, 27);
    var content = demoContent();
    final topic = content.cards.firstWhere((c) => c.title == '遗忘的规律');
    expect(researchCardTitle(content, topic.id), '遗忘的规律');
    expect(researchCardTitle(content, 'missing'), isEmpty);
    content = StudySetEditor(newId: () => 'card', now: () => time).saveResearchNote(
      content,
      ResearchNote(
        id: 'note',
        title: '复习间隔',
        body: '',
        question: 'q',
        citations: const [],
        origin: NoteOrigin.ai,
        createdAt: time,
        updatedAt: time,
      ),
      createCard: true,
    );
    expect(researchCardTitle(content, 'card'), '复习间隔');
  });

  test('reading blocks: headings, code, tables, lists and escapes', () {
    expect(ReadingBlock.parse('a', '## Results').heading, 2);
    expect(ReadingBlock.parse('a', '## Results').text, 'Results');
    final code = ReadingBlock.parse('b', '```dart\nvar a = 1;\n```');
    expect(code.code, isTrue);
    expect(code.text, 'var a = 1;');
    final table = ReadingBlock.parse('c', '| A | B |\n| --- | --- |\n| 1 | 2 |');
    expect(table.table, [
      ['A', 'B'],
      ['1', '2'],
    ]);
    expect(ReadingBlock.parse('d', '- one\n- **two** [link](https://x.org)').text, '• one\n• two link');
    expect(ReadingBlock.parse('e', r'a \* b \[c\]').text, 'a * b [c]');
  });

  test('external searches by kind', () {
    expect(externalSearches({}, 'q'), isEmpty);
    final all = externalSearches(ResearchSourceKind.values.toSet(), '锚定效应');
    expect(all.map((e) => e.$1), ['Google', 'YouTube', 'Bilibili', 'Google Images']);
    expect(all[1].$2.queryParameters['search_query'], '锚定效应');
  });
}
