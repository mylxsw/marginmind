import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/research/research_controller.dart';
import 'package:marginmind/features/research/research_providers.dart';
import 'package:marginmind/features/research/research_settings.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_research/mm_research.dart';

import 'helpers.dart';

const _claim = '一个明显随机的数字，竟能让估计相差将近一倍。';
const _docId = 'c1';
const _rect = PageRect(10, 100, 200, 88);

/// AI configured (Anthropic with a saved key).
const _aiPrefs = <String, Object>{'research.service': 'anthropic', 'research.key.anthropic': true};

class _Ai implements AiProvider {
  _Ai(this.script);

  final Stream<AiEvent> Function(AiRequest request) script;
  final requests = <AiRequest>[];

  @override
  Stream<AiEvent> generate(AiRequest request, CancellationToken cancellation) {
    requests.add(request);
    return script(request);
  }
}

class _Search implements SearchProvider {
  final queries = <String>[];
  @override
  Future<List<SearchHit>> search(SearchRequest request, CancellationToken cancellation) async {
    queries.add(request.query);
    return [
      SearchHit(
        url: Uri.parse('https://doi.org/10.1126/science.185.4157.1124'),
        title: 'Judgment under Uncertainty',
        snippet: 'Three heuristics are employed in making judgments under uncertainty.',
        kind: 'paper',
        doi: '10.1126/science.185.4157.1124',
        authors: const ['Tversky', 'Kahneman'],
        publishedAt: DateTime(1974),
        openAccess: false,
      ),
      SearchHit(url: Uri.parse('https://news.example.com/anchor'), title: 'Why the first price sticks', kind: 'paper'),
    ];
  }
}

class _Extractor implements ContentExtractor {
  final read = <Uri>[];
  @override
  Future<ExtractedContent> extract(Uri url, CancellationToken cancellation) async {
    read.add(url);
    return markdownArticle(
      ReadableHtml(
        url: url,
        title: 'Anchoring',
        html: '<h2>Results</h2><p>Here is the real quote in context.</p><p>A second paragraph.</p>',
      ),
    );
  }
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

typedef _App = ({
  ProviderContainer container,
  WorkspaceController workspace,
  ResearchPanelController panel,
  InMemoryStudySetContentRepository repository,
});

Future<_App> _open(
  WidgetTester tester, {
  _Ai? ai,
  bool fakeAi = true,
  Map<String, Object> prefs = _aiPrefs,
  ContentExtractor? extractor,
  SearchProvider? search,
  List<Override> overrides = const [],
  _Secrets? secrets,
  InMemoryStudySetContentRepository? repository,
  Size size = const Size(1400, 900),
}) async {
  final repo = repository ?? InMemoryStudySetContentRepository({'demo-1': demoContent()});
  final container = await pumpApp(
    tester,
    prefs: prefs,
    size: size,
    content: repo,
    overrides: [
      researchRecoveryProvider.overrideWithValue(ResearchRecovery(repo, () async => ['demo-1'])),
      if (fakeAi) researchAiFactoryProvider.overrideWithValue(() async => ai),
      researchExtractorProvider.overrideWithValue(extractor ?? _Extractor()),
      researchSearchProvider.overrideWithValue(search ?? _Search()),
      researchVideoTitlesProvider.overrideWithValue(null),
      researchSecretStoreProvider.overrideWithValue(secrets ?? _Secrets()),
      ...overrides,
    ],
  );
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  return (
    container: container,
    workspace: container.read(workspaceProvider('demo-1').notifier),
    panel: container.read(researchPanelProvider('demo-1').notifier),
    repository: repo,
  );
}

/// While a request is held open its spinner never stops: settling would run
/// fake time into the request's time limit. Tests holding one pump frames.
var _holding = false;

Future<void> _wait(WidgetTester tester) async {
  if (!_holding) {
    await tester.pumpAndSettle();
    return;
  }
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

/// Lets the in-memory engine finish its writes.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  await _wait(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await _wait(tester);
  await tester.tap(finder);
  // Cards also take double clicks: a single click lands after that timeout.
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));
  await _wait(tester);
}

void main() {
  testWidgets('PDF-only note opts into review without creating a visible card; undo restores opt-out', (tester) async {
    final app = await _open(tester);
    final now = DateTime(2026);
    await app.workspace.saveResearchNote(
      ResearchNote(
        id: 'review-note',
        title: 'Conclusion',
        question: 'Why?',
        body: 'Answer',
        createdAt: now,
        updatedAt: now,
      ),
      source: PdfTarget(
        documentId: _docId,
        pages: const [
          AnnotationPage(page: 24, rects: [_rect]),
        ],
        quote: _claim,
      ),
    );
    app.panel.showNote('review-note');
    await _settle(tester);
    final count = app.workspace.content.nodes.length;
    final toggle = find.byKey(const ValueKey('research-review-toggle'));
    expect(tester.widget<MMSwitch>(toggle).value, isFalse);
    await _tap(tester, toggle);
    await _settle(tester);
    expect(app.workspace.content.researchReviewEnabled('review-note'), isTrue);
    expect(app.workspace.content.nodes.length, count);
    await app.workspace.undo();
    await _settle(tester);
    expect(tester.widget<MMSwitch>(toggle).value, isFalse);
  });
}
