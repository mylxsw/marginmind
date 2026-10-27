import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/research/research_controller.dart';
import 'package:marginmind/features/research/research_drafts.dart';
import 'package:marginmind/features/research/research_providers.dart';
import 'package:marginmind/features/research/research_settings.dart';
import 'package:marginmind/features/research/widgets/research_launcher.dart';
import 'package:marginmind/features/research/widgets/video_link_sheet.dart';
import 'package:marginmind/features/research/widgets/research_note_popover.dart';
import 'package:marginmind/features/research/widgets/research_note_view.dart';
import 'package:marginmind/features/research/widgets/research_widgets.dart';
import 'package:marginmind/features/research/widgets/save_note_sheet.dart';
import 'package:marginmind/features/workspace/widgets/right_panel.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:mm_research/mm_research.dart';

import 'helpers.dart';

const _claim = '一个明显随机的数字，竟能让估计相差将近一倍。';
const _other = '人们会从最初的数字出发调整。';
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

AiEvent _event(AiRequest r, AiEventKind kind, {String? text, ResearchCitation? citation}) =>
    AiEvent(sessionId: r.sessionId, requestId: r.requestId, kind: kind, text: text, citation: citation);

final _page = Uri.parse('https://example.org/anchoring');

/// A web answer citing one page, whose quote the page really contains.
Stream<AiEvent> _webAnswer(AiRequest r) async* {
  yield _event(
    r,
    AiEventKind.source,
    citation: ResearchCitation(url: _page, title: 'Anchoring'),
  );
  yield _event(
    r,
    AiEventKind.citation,
    citation: ResearchCitation(url: _page, title: 'Anchoring', quote: 'real quote'),
  );
  yield _event(r, AiEventKind.text, text: '## 结论\n- 结论可靠，但幅度要加限定。\n## 不同观点与限制\n- 专家也会受影响。\n');
  yield _event(r, AiEventKind.completed);
}

Stream<AiEvent> _offlineAnswer(AiRequest r) async* {
  yield _event(r, AiEventKind.text, text: '## 简短结论\n- 锚定指最先接触的信息成为参照。\n- 例子：先看到原价。\n');
  yield _event(r, AiEventKind.completed);
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
  _Extractor({this.fail = false});
  final bool fail;
  final read = <Uri>[];
  @override
  Future<ExtractedContent> extract(Uri url, CancellationToken cancellation) async {
    read.add(url);
    if (fail) throw const ResearchFailure(ResearchFailureKind.unavailable, 'login_required');
    return markdownArticle(
      ReadableHtml(
        url: url,
        title: 'Anchoring',
        html: '<h2>Results</h2><p>Here is the real quote in context.</p><p>A second paragraph.</p>',
      ),
    );
  }
}

class _Links implements ExternalLinks {
  final opened = <Uri>[];
  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
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

class _Cache implements ResearchDocumentCache {
  var cleared = 0;
  @override
  Future<void> clear() async => cleared++;
  @override
  Future<String?> read(Uri url) async => null;
  @override
  Future<void> write(Uri url, String html) async {}
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

Future<void> _select(WidgetTester tester, WorkspaceController workspace, String text) async {
  await workspace.onSelectionCommitted(
    _docId,
    MMPdfSelection(page: 24, rects: const [_rect], text: text, viewportRect: const Rect.fromLTWH(100, 200, 200, 20)),
  );
  await _wait(tester);
}

Future<void> _openLauncher(WidgetTester tester, WorkspaceController workspace, String text) async {
  await _select(tester, workspace, text);
  await tester.tap(find.byKey(const ValueKey('selection-research')));
  await _wait(tester);
  expect(find.byType(ResearchLauncher), findsOneWidget);
}

Future<void> _press(WidgetTester tester, SingleActivator a) async {
  final modifiers = [
    if (a.control) LogicalKeyboardKey.controlLeft,
    if (a.meta) LogicalKeyboardKey.metaLeft,
    if (a.alt) LogicalKeyboardKey.altLeft,
    if (a.shift) LogicalKeyboardKey.shiftLeft,
  ];
  for (final m in modifiers) {
    await tester.sendKeyDownEvent(m);
  }
  await tester.sendKeyEvent(a.trigger);
  for (final m in modifiers.reversed) {
    await tester.sendKeyUpEvent(m);
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

String _question(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(of: find.byKey(const ValueKey('launcher-question')), matching: find.byType(TextField)),
    )
    .controller!
    .text;

ResearchSessionState _session(_App app, String id) =>
    app.container.read(researchSessionProvider((studySetId: 'demo-1', sessionId: id))).requireValue;

final _panel = find.byType(RightPanelView);
Finder _inPanel(Finder finder) => find.descendant(of: _panel, matching: finder);

void main() {
  testWidgets('historical citations open their own snapshot, returning to a source opens latest', (tester) async {
    final app = await _open(tester, prefs: const {});
    final now = DateTime(2026);
    final oldText = markdownArticle(ReadableHtml(url: _page, title: 'Old', html: '<p>Old retained evidence.</p>'));
    final newText = markdownArticle(ReadableHtml(url: _page, title: 'New', html: '<p>New changed page.</p>'));
    final oldFile = await app.repository.writeResearchSnapshot('demo-1', encodeSnapshot(oldText.paragraphs));
    final newFile = await app.repository.writeResearchSnapshot('demo-1', encodeSnapshot(newText.paragraphs));
    final source = ResearchSource(
      id: 'versioned',
      url: _page.toString(),
      canonicalUrl: _page.toString(),
      kind: 'web',
      title: 'Page',
      fetchedAt: now,
      readState: 'fullText',
      versions: [
        SourceVersion(version: 1, snapshotFile: oldFile, hash: 'old'),
        SourceVersion(version: 2, snapshotFile: newFile, hash: 'new'),
      ],
    );
    await app.repository.saveResearchSession(
      'demo-1',
      ResearchSession(
        id: 'versioned-session',
        question: 'Question',
        status: 'done',
        createdAt: now,
        updatedAt: now,
        drafts: [
          {
            'type': 'engine',
            'sources': [source.toJson()],
            'metadata': {
              'versioned': {
                'versions': {
                  '1': {'readState': 'abstractOnly', 'fetchedAt': now.toIso8601String()},
                },
              },
            },
          },
        ],
      ),
    );
    app.panel.show('versioned-session');
    app.panel.openReading('versioned', version: 1, paragraphId: oldText.paragraphs.keys.first);
    await _settle(tester);
    expect(find.text('Old retained evidence.'), findsOneWidget);
    expect(find.text('New changed page.'), findsNothing);
    expect(find.text('v1'), findsOneWidget);
    app.panel.openReading('versioned');
    await _settle(tester);
    expect(find.text('New changed page.'), findsOneWidget);
    expect(find.text('Old retained evidence.'), findsNothing);
    expect(app.container.read(researchPanelProvider('demo-1')).readingVersion, isNull);
  });

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

  testWidgets('video link sheet validates URLs, saves without extraction, and exposes external searches', (
    tester,
  ) async {
    final app = await _open(tester, prefs: const {});
    await _openLauncher(tester, app.workspace, _claim);
    await _tap(tester, find.text('Research Later'));
    await _settle(tester);
    final session = (await app.repository.listResearchSessions('demo-1')).single;
    app.panel.show(session.id, tab: ResearchTab.sources);
    await _settle(tester);
    unawaited(showVideoLinkSheet(tester.element(_panel), 'demo-1', session.id));
    await _settle(tester);
    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey('video-url')), matching: find.byType(TextField)),
      'https://youtube.com.evil.com/watch?v=dQw4w9WgXcQ',
    );
    await _tap(tester, find.byKey(const ValueKey('video-save')));
    expect(find.text('Enter a YouTube or Bilibili video URL.'), findsOneWidget);
    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey('video-url')), matching: find.byType(TextField)),
      'https://youtu.be/dQw4w9WgXcQ',
    );
    await _tap(tester, find.byKey(const ValueKey('video-save')));
    await _settle(tester);
    expect(_session(app, session.id).sources.single.readState, 'noTranscript');
    expect(find.byKey(const ValueKey('video-url')), findsNothing);
    expect(find.textContaining('dQw4w9WgXcQ'), findsWidgets);
    await settleHud(tester);
  });

  group('launcher', () {
    testWidgets('from a passage: suggested intent, question, keywords, method and what will be sent', (tester) async {
      final app = await _open(tester, ai: _Ai(_webAnswer));
      await _openLauncher(tester, app.workspace, _claim);
      expect(
        find.descendant(of: find.byKey(const ValueKey('intent-verify')), matching: find.text('Suggested')),
        findsOneWidget,
      );
      expect(_question(tester), startsWith('“一个明显随机的数字，竟能让估计相差将近一倍”'));
      expect(tester.widget<MMInteractive>(find.byKey(const ValueKey('method-web'))).selected, isTrue);
      // What a method does is a hover hint, not a line of text.
      expect(find.text('Up to 3 searches and 5 pages'), findsNothing);
      expect(find.byTooltip('Up to 3 searches and 5 pages'), findsOneWidget);
      // Keywords are the term, never the whole passage; they can be edited.
      expect(find.widgetWithText(ResearchChip, _claim), findsNothing);
      await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey('launcher-keyword')), matching: find.byType(TextField)),
        'anchoring',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('anchoring'), findsOneWidget);
      // What will be sent: the selection is always on.
      expect(find.textContaining('Sent to AI: Selection'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('launcher-context')));
      expect(tester.widget<MMSwitch>(find.byKey(const ValueKey('context-selection'))).onChanged, isNull);
      // Another intent rewrites the question and its defaults.
      await _tap(tester, find.byKey(const ValueKey('intent-explain')));
      expect(_question(tester), contains('mean?'));
      expect(tester.widget<MMInteractive>(find.byKey(const ValueKey('method-offline'))).selected, isTrue);
      await _tap(tester, find.byKey(const ValueKey('intent-deep')));
      expect(_question(tester), isEmpty);
      // An empty question does not start anything.
      await _tap(tester, find.byKey(const ValueKey('launcher-start')));
      expect(find.byType(ResearchLauncher), findsOneWidget);
      expect(await app.repository.listResearchSessions('demo-1'), isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ResearchLauncher), findsNothing);
      await settleHud(tester);
    });

    testWidgets('without AI only search is offered, with a way to set it up', (tester) async {
      final app = await _open(tester, prefs: const {});
      await _openLauncher(tester, app.workspace, _claim);
      expect(tester.widget<MMInteractive>(find.byKey(const ValueKey('method-search'))).selected, isTrue);
      expect(tester.widget<MMInteractive>(find.byKey(const ValueKey('method-web'))).enabled, isFalse);
      expect(tester.widget<MMInteractive>(find.byKey(const ValueKey('method-offline'))).enabled, isFalse);
      expect(find.text('No AI service set up'), findsOneWidget);
      expect(find.textContaining('Sent to AI'), findsNothing);
      await _tap(tester, find.text('Set Up AI…'));
      expect(find.text('Research Settings'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('research-settings-done')));
    });

    testWidgets('from a node: explained offline with its path; children are off', (tester) async {
      final app = await _open(tester, ai: _Ai(_offlineAnswer));
      final topic = app.workspace.content.cards.firstWhere((c) => c.title == '遗忘的规律');
      app.workspace.selectCard(topic.id);
      await tester.pumpAndSettle();
      // ⇧⌘E researches the selected node.
      await _press(tester, AppShortcuts.researchSelection);
      expect(find.byType(ResearchLauncher), findsOneWidget);
      expect(find.text('Research Node'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('intent-explain')), matching: find.text('Suggested')),
        findsOneWidget,
      );
      expect(tester.widget<MMInteractive>(find.byKey(const ValueKey('method-offline'))).selected, isTrue);
      expect(find.text('Keywords'), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('launcher-context')));
      expect(tester.widget<MMSwitch>(find.byKey(const ValueKey('context-children'))).value, isFalse);
      await _tap(tester, find.byKey(const ValueKey('launcher-start')));
      await _settle(tester);
      // The map stays and the source steps aside; the answer is marked offline.
      expect(app.container.read(workspaceProvider('demo-1')).layout, MMSplitMode.secondary);
      expect(find.byKey(const ValueKey('mode-badge-offline')), findsOneWidget);
      expect(find.text('锚定指最先接触的信息成为参照。'), findsOneWidget);
      expect(find.textContaining('no source'), findsNothing);
      await settleHud(tester);
    });
  });

  testWidgets('web research: cited and read sources, save to source and map, one note in both places, undo', (
    tester,
  ) async {
    final ai = _Ai(_webAnswer);
    final extractor = _Extractor();
    final app = await _open(tester, ai: ai, extractor: extractor);
    await _openLauncher(tester, app.workspace, _claim);
    await _tap(tester, find.byKey(const ValueKey('launcher-start')));
    await _settle(tester);

    // The source stays, the map steps aside; the panel shows the answer.
    expect(app.container.read(workspaceProvider('demo-1')).layout, MMSplitMode.primary);
    expect(ai.requests.single.mode, ResearchMode.web);
    expect(ai.requests.single.context, contains(_claim));
    expect(extractor.read, [_page]);
    expect(find.byKey(const ValueKey('mode-badge-web')), findsOneWidget);
    expect(find.textContaining('结论可靠，但幅度要加限定。'), findsOneWidget);
    expect(find.textContaining('1 source used'), findsWidgets);
    final sessionId = app.container.read(researchPanelProvider('demo-1')).sessionId!;
    final state = _session(app, sessionId);
    expect(state.evidence.single.quote, 'real quote');

    // A point cites its source: clicking opens it at the quoted paragraph.
    await _tap(tester, find.byType(CiteBadge).first);
    expect(find.text('Here is the real quote in context.'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('reading-back')));

    // Sources: read state and "used in answer".
    await _tap(tester, find.byKey(const ValueKey('research-tab-sources')));
    expect(find.text('Full text'), findsOneWidget);
    expect(find.text('Used in answer'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('research-tab-answer')));

    // Check the first point and save it.
    final point = state.session.history.length - 1;
    await _tap(tester, find.byKey(ValueKey('check-$point.1.0')));
    expect(find.text('1 selected'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('research-save-note')));
    expect(find.byType(SaveNoteSheet), findsOneWidget);
    expect(tester.widget<ResearchRadio>(find.byKey(const ValueKey('dest-both'))).selected, isTrue);
    expect(find.text('Anchoring'), findsWidgets);
    // Two quick clicks save once.
    await tester.tap(find.byKey(const ValueKey('save-note-confirm')));
    await tester.tap(find.byKey(const ValueKey('save-note-confirm')), warnIfMissed: false);
    await _settle(tester);
    var content = app.workspace.content;
    expect(content.researchNotes, hasLength(1));
    final note = content.researchNotes.single;
    expect(note.title, '结论可靠');
    expect(note.citations, hasLength(1));
    expect(note.sessionId, sessionId);
    expect(content.noteAttachments.map((a) => a.target.runtimeType), containsAll([PdfTarget, CardTarget]));
    final card = content.cards.singleWhere((c) => c.researchNoteId == note.id);
    expect(find.text('Saved to the source and the map'), findsOneWidget);
    // The checked point is no longer pending.
    expect(find.text('1 selected'), findsNothing);

    // The map's research card and the source's mark show the same note.
    app.workspace.setLayout(MMSplitMode.split);
    await app.workspace.locateNoteCard(note.id);
    await tester.pumpAndSettle();
    expect(find.text('Research note · 1 source'), findsWidgets);
    final attachment = content.noteAttachments.firstWhere((a) => a.target is PdfTarget);
    app.workspace.tapHighlight(noteMarkId(attachment.id));
    await tester.pumpAndSettle();
    expect(find.byType(ResearchNotePopover), findsOneWidget);
    expect(find.descendant(of: find.byType(ResearchNotePopover), matching: find.text('结论可靠')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('popover-open-note')));
    expect(_inPanel(find.byType(ResearchNoteView)), findsOneWidget);
    final title = find.descendant(of: find.byKey(ValueKey('note-title-${note.id}')), matching: find.byType(TextField));
    await tester.tap(title);
    await tester.enterText(title, '锚定效应可靠');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    content = app.workspace.content;
    expect(content.researchNote(note.id)!.title, '锚定效应可靠');
    expect(content.researchNote(note.id)!.edited, isTrue);
    expect(find.text('锚定效应可靠'), findsWidgets);
    app.workspace.tapHighlight(noteMarkId(attachment.id));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(ResearchNotePopover), matching: find.text('锚定效应可靠')), findsOneWidget);
    app.workspace.dismissPending();
    await tester.pumpAndSettle();

    // Edit, undo restores the title; undo again removes the whole save.
    await app.workspace.undo();
    await _settle(tester);
    expect(app.workspace.content.researchNote(note.id)!.title, '结论可靠');
    await app.workspace.undo();
    await _settle(tester);
    expect(app.workspace.content.researchNotes, isEmpty);
    expect(app.workspace.content.card(card.id), isNull);
    expect(app.workspace.content.noteAttachments, isEmpty);
    await settleHud(tester);
  });

  testWidgets('results stay with the research that asked, whatever is selected meanwhile', (tester) async {
    _holding = true;
    addTearDown(() => _holding = false);
    final first = StreamController<AiEvent>();
    late AiRequest firstRequest;
    final ai = _Ai((r) {
      if (r.question.contains('一倍')) {
        firstRequest = r;
        return first.stream;
      }
      return _offlineAnswer(r);
    });
    final app = await _open(tester, ai: ai);
    MMSplitMode layout() => app.container.read(workspaceProvider('demo-1')).layout;
    app.workspace.setLayout(MMSplitMode.split);
    await _openLauncher(tester, app.workspace, _claim);
    await _tap(tester, find.byKey(const ValueKey('launcher-start')));
    await _settle(tester);
    final a = app.container.read(researchPanelProvider('demo-1')).sessionId!;
    expect(find.byKey(const ValueKey('research-cancel')), findsOneWidget);
    expect(layout(), MMSplitMode.primary, reason: 'started from the source: the map steps aside');
    // Closed, then reopened from the sidebar: it opens beside its source.
    app.workspace.closePanel();
    await _wait(tester);
    expect(layout(), MMSplitMode.split);
    await _tap(tester, find.byKey(ValueKey('sidebar-research-$a')));
    expect(layout(), MMSplitMode.primary);

    // Another passage while A runs: the launcher offers new or join.
    await _openLauncher(tester, app.workspace, _other);
    expect(find.byKey(const ValueKey('launcher-as-new')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('intent-explain')));
    await _tap(tester, find.byKey(const ValueKey('launcher-start')));
    await _settle(tester);
    final b = app.container.read(researchPanelProvider('demo-1')).sessionId!;
    expect(b, isNot(a));

    // A's answer arrives after B was shown: it lands in A only.
    first.add(_event(firstRequest, AiEventKind.text, text: '- 这是 A 的回答。'));
    first.add(_event(firstRequest, AiEventKind.completed));
    await _settle(tester);
    expect(_session(app, a).answer, '- 这是 A 的回答。');
    expect(_session(app, b).answer, isNot(contains('A 的回答')));
    expect(find.text('这是 A 的回答。'), findsNothing);
    // A keeps its own starting point for saving.
    expect((_session(app, a).session.anchor!.target as PdfTarget).quote, _claim);
    expect((_session(app, b).session.anchor!.target as PdfTarget).quote, _other);

    // Joining while one runs adds context to it, keeping its starting point.
    final hold = StreamController<AiEvent>();
    final busy = _Ai((r) => hold.stream);
    app.panel.show(a);
    await _wait(tester);
    // Start A again with a request that waits, then join it.
    final retry = app.container.read(researchSessionProvider((studySetId: 'demo-1', sessionId: a)).notifier);
    unawaited(retry.answer(provider: busy, question: 'again', mode: ResearchMode.offline));
    await _settle(tester);
    await _openLauncher(tester, app.workspace, _other);
    await _tap(tester, find.byKey(const ValueKey('launcher-join')));
    await _tap(tester, find.byKey(const ValueKey('launcher-start')));
    await _settle(tester);
    expect(_session(app, a).drafts.extra.single, contains(_other));
    expect((_session(app, a).session.anchor!.target as PdfTarget).quote, _claim);
    await _tap(tester, find.byKey(const ValueKey('research-cancel')));
    expect(_session(app, a).session.status, 'cancelled');
    expect(find.text('Cancelled'), findsWidgets);
    unawaited(first.close());
    unawaited(hold.close());
    await settleHud(tester);
  });

  testWidgets('without AI: papers, a page that cannot be read, pasted text, evidence and a note from it', (
    tester,
  ) async {
    final search = _Search();
    final links = _Links();
    final app = await _open(
      tester,
      prefs: const {},
      search: search,
      extractor: _Extractor(fail: true),
      overrides: [researchLinksProvider.overrideWithValue(links)],
    );
    await _openLauncher(tester, app.workspace, _claim);
    await _tap(tester, find.byKey(const ValueKey('intent-paper')));
    await _tap(tester, find.byKey(const ValueKey('launcher-start')));
    await _settle(tester);
    expect(search.queries, isNotEmpty);
    // Search only: the sources tab, the abstract is not full text.
    expect(find.text('Abstract only'), findsOneWidget);
    expect(find.text('Subscription'), findsOneWidget);
    expect(find.textContaining('Tversky'), findsOneWidget);

    // The answer tab says search only, with no AI to answer from sources.
    await _tap(tester, find.byKey(const ValueKey('research-tab-answer')));
    expect(find.text('Search only: no answer'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('research-tab-sources')));

    // An unreadable page explains why, and offers the way around it.
    final sessionId = app.container.read(researchPanelProvider('demo-1')).sessionId!;
    final news = _session(app, sessionId).sources.firstWhere((s) => s.title.startsWith('Why'));
    await _tap(tester, find.byKey(ValueKey('read-${news.id}')));
    await _settle(tester);
    expect(find.text("Couldn't read the text"), findsOneWidget);
    expect(find.textContaining('sign-in'), findsOneWidget);
    await _tap(tester, find.text('Open Page'));
    expect(links.opened.single.host, 'news.example.com');
    await _tap(tester, find.byKey(const ValueKey('reading-paste')));
    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey('paste-text')), matching: find.byType(TextField)),
      'First pasted paragraph.\n\nSecond pasted paragraph.',
    );
    await _tap(tester, find.byKey(const ValueKey('paste-save')));
    await _settle(tester);
    expect(find.text('Pasted by you'), findsOneWidget);
    expect(find.text('First pasted paragraph.'), findsOneWidget);

    // Selecting text takes it as evidence, marked as pasted.
    final paragraph = find.widgetWithText(SelectableText, 'First pasted paragraph.');
    tester.widget<SelectableText>(paragraph).onSelectionChanged!(
      const TextSelection(baseOffset: 0, extentOffset: 14),
      SelectionChangedCause.drag,
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('reading-clip')));
    await _settle(tester);
    final clip = _session(app, sessionId).drafts.clips.single;
    expect(clip.evidence.quote, 'First pasted p');
    expect(clip.evidence.acquisition, EvidenceAcquisition.userPaste);

    // A note from the evidence, in the map only.
    await _tap(tester, find.byKey(const ValueKey('reading-back')));
    await _tap(tester, find.byKey(const ValueKey('research-tab-saved')));
    expect(find.text('Evidence (draft)'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('save-clips')));
    await _tap(tester, find.byKey(const ValueKey('dest-map')));
    await _tap(tester, find.byKey(const ValueKey('save-note-confirm')));
    await _settle(tester);
    final note = app.workspace.content.researchNotes.single;
    expect(note.origin, NoteOrigin.excerpt);
    expect(app.workspace.content.noteAttachments.single.target, isA<CardTarget>());
    expect(app.workspace.content.evidence.single.acquisition, EvidenceAcquisition.userPaste);
    expect(_session(app, sessionId).drafts.clips, isEmpty);
    expect(find.text('Saved research notes'), findsOneWidget);
    await _tap(tester, find.byKey(ValueKey('saved-${note.id}')));
    expect(find.byType(ResearchNoteView), findsOneWidget);
    expect(find.text('Not attached to the source'), findsOneWidget);
    expect(find.textContaining('Pasted by you'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('note-back')));
    await settleHud(tester);
  });

  testWidgets('a failed request says why and retries only when asked; interrupted research waits', (tester) async {
    var fail = true;
    final ai = _Ai((r) async* {
      if (fail) throw const ResearchFailure(ResearchFailureKind.unavailable);
      yield* _offlineAnswer(r);
    });
    final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    await repo.saveResearchSession(
      'demo-1',
      ResearchSession(id: 'old', question: '旧的问题', status: 'running', createdAt: testNow, updatedAt: testNow),
    );
    final app = await _open(tester, ai: ai, repository: repo);
    // Recovery marked the old request interrupted without sending it again.
    expect(find.byKey(const ValueKey('sidebar-research-old')), findsOneWidget);
    expect(find.text('Interrupted'), findsOneWidget);
    expect(ai.requests, isEmpty);

    await _openLauncher(tester, app.workspace, _other);
    await _tap(tester, find.byKey(const ValueKey('launcher-start')));
    await _settle(tester);
    expect(find.text("Can't reach the service"), findsWidgets);
    expect(ai.requests, hasLength(1));
    fail = false;
    await _tap(tester, find.byKey(const ValueKey('research-retry')));
    await _settle(tester);
    expect(ai.requests, hasLength(2));
    expect(find.text('锚定指最先接触的信息成为参照。'), findsOneWidget);

    // Edit a point, ask about another, then follow up.
    final id = app.container.read(researchPanelProvider('demo-1')).sessionId!;
    final turn = _session(app, id).session.history.length - 1;
    final key = '$turn.1.0';
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    final row = find.byKey(ValueKey('point-$key'));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(row));
    await tester.pumpAndSettle();
    await _tap(tester, find.descendant(of: row, matching: find.text('Edit')));
    await tester.enterText(
      find.descendant(of: find.byKey(ValueKey('edit-$key')), matching: find.byType(TextField)),
      '我改过的要点',
    );
    await _tap(tester, find.byKey(ValueKey('edit-save-$key')));
    await _settle(tester);
    expect(_session(app, id).drafts.edits[key], '我改过的要点');
    expect(find.textContaining('edited'), findsOneWidget);
    await gesture.moveTo(tester.getCenter(find.byKey(ValueKey('point-$key'))));
    await tester.pumpAndSettle();
    await _tap(tester, find.descendant(of: find.byKey(ValueKey('point-$key')), matching: find.text('Ask')));
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: find.byKey(const ValueKey('research-followup')), matching: find.byType(TextField)),
          )
          .controller!
          .text,
      contains('我改过的要点'),
    );
    await _tap(tester, find.byKey(const ValueKey('research-send')));
    await _settle(tester);
    expect(ai.requests.last.question, contains('我改过的要点'));
    expect(_session(app, id).session.history, hasLength(turn + 2));
    // ⌘↩ sends from the follow-up field, as it starts research in the launcher.
    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey('research-followup')), matching: find.byType(TextField)),
      '再举一个例子',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await _settle(tester);
    expect(ai.requests.last.question, contains('再举一个例子'));
    expect(_session(app, id).session.history, hasLength(turn + 3));
    await gesture.removePointer();

    // The old research opens from the sidebar with its retry.
    await _tap(tester, find.byKey(const ValueKey('sidebar-research-old')));
    expect(find.byKey(const ValueKey('research-retry')), findsOneWidget);
    await settleHud(tester);
  });

  testWidgets('later research waits in the sidebar and the start page, and continues', (tester) async {
    final ai = _Ai(_offlineAnswer);
    final app = await _open(tester, ai: ai);
    await _openLauncher(tester, app.workspace, _other);
    await _tap(tester, find.byKey(const ValueKey('intent-explain')));
    await _tap(tester, find.text('Research Later'));
    await _settle(tester);
    expect(find.text('Saved to Research Later'), findsOneWidget);
    final later = (await app.repository.listResearchSessions('demo-1')).single;
    expect(later.status, 'draft');
    expect(ResearchDrafts.of(later).later, isTrue);
    expect(ai.requests, isEmpty);
    final anchor = later.anchor!.toJson();
    await _select(tester, app.workspace, _claim);
    await _tap(tester, find.byKey(const ValueKey('sidebar-research-later')));
    expect(find.byKey(ValueKey('later-${later.id}')), findsOneWidget);
    await _tap(tester, find.text('Continue'));
    await _settle(tester);
    expect(find.text('锚定指最先接触的信息成为参照。'), findsOneWidget);
    expect(ResearchDrafts.of((await app.repository.listResearchSessions('demo-1')).single).later, isFalse);
    expect((await app.repository.listResearchSessions('demo-1')).single.anchor!.toJson(), anchor);
    expect(ai.requests, hasLength(1));
    await settleHud(tester);
  });

  testWidgets('the node menu researches with an intent; the map card of a node note opens its details', (tester) async {
    final app = await _open(tester, ai: _Ai(_offlineAnswer));
    await showWholeMap(tester);
    await tester.tap(find.text('遗忘的规律'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Research “遗忘的规律”'), findsOneWidget);
    await _tap(tester, find.text('Explain'));
    expect(find.text('Research Node'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('launcher-start')));
    await _settle(tester);
    final id = app.container.read(researchPanelProvider('demo-1')).sessionId!;
    final turn = _session(app, id).session.history.length - 1;
    await _tap(tester, find.byKey(ValueKey('check-$turn.1.0')));
    await _tap(tester, find.byKey(ValueKey('check-$turn.1.1')));
    await _tap(tester, find.byKey(const ValueKey('research-save-note')));
    // A node has no place in the source: only the map can take the note.
    expect(tester.widget<ResearchRadio>(find.byKey(const ValueKey('dest-map'))).selected, isTrue);
    expect(tester.widget<ResearchRadio>(find.byKey(const ValueKey('dest-both'))).onTap, isNull);
    expect(find.text('No external source'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('save-note-split')));
    await _tap(tester, find.byKey(const ValueKey('save-note-confirm')));
    await _settle(tester);
    final content = app.workspace.content;
    final note = content.researchNotes.single;
    final card = content.cards.singleWhere((c) => c.researchNoteId == note.id);
    final topic = content.cards.firstWhere((c) => c.title == '遗忘的规律');
    expect(content.node(card.id)!.parentId, topic.id);
    expect(content.childrenOf(card.id), hasLength(2));
    expect(note.citations, isEmpty);
    // The card's link opens the note in the details.
    await app.workspace.locateNoteCard(note.id);
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Full note and citations'));
    expect(_inPanel(find.byType(ResearchNoteView)), findsOneWidget);
    expect(_inPanel(find.text('Research Note')), findsOneWidget);
    // Delete asks first, then removes the card with the note.
    await _tap(tester, find.byKey(const ValueKey('delete-note')));
    expect(find.text('Delete this research note?'), findsOneWidget);
    await _tap(tester, find.text('Delete'));
    await _settle(tester);
    expect(app.workspace.content.researchNotes, isEmpty);
    expect(app.workspace.content.card(card.id), isNull);
    await settleHud(tester);
  });

  testWidgets('settings keep the key in the Keychain and clear the web cache', (tester) async {
    final secrets = _Secrets();
    final cache = _Cache();
    final app = await _open(
      tester,
      prefs: const {},
      fakeAi: false,
      secrets: secrets,
      overrides: [researchCacheProvider.overrideWithValue(cache)],
    );
    app.workspace.toggleResearchPanel();
    await tester.pumpAndSettle();
    await _tap(tester, _inPanel(find.byTooltip('Research Settings')));
    await _tap(tester, find.text('Anthropic'));
    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey('research-key')), matching: find.byType(TextField)),
      'sk-test',
    );
    await _tap(tester, find.byTooltip('+').first);
    await _tap(tester, find.byKey(const ValueKey('research-show-context')));
    await _tap(tester, find.byKey(const ValueKey('research-clear-cache')));
    expect(cache.cleared, 1);
    await _tap(tester, find.byKey(const ValueKey('research-settings-done')));
    final settings = app.container.read(researchSettingsProvider);
    expect(secrets.values, {'anthropic': 'sk-test'});
    expect(settings.service, ResearchService.anthropic);
    expect(settings.keySaved, isTrue);
    expect(settings.aiConfigured, isTrue);
    expect(settings.searches, 4);
    expect(settings.showContext, isFalse);
    // The factory reads the key only when a request is made.
    final provider = await app.container.read(researchAiFactoryProvider)();
    expect(provider, isA<AnthropicProvider>());
    await _tap(tester, _inPanel(find.byTooltip('Research Settings')));
    await _tap(tester, find.text('Remove'));
    expect(secrets.values, isEmpty);
    expect(app.container.read(researchSettingsProvider).aiConfigured, isFalse);
    await _tap(tester, find.byKey(const ValueKey('research-settings-done')));
    await settleHud(tester);
  });
}
