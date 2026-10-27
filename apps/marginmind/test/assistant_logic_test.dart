import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/assistant_entry.dart';
import 'package:marginmind/features/assistant/assistant_reader.dart';
import 'package:marginmind/features/assistant/assistant_scope.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/widgets/assistant_markdown.dart';
import 'package:marginmind/features/assistant/widgets/assistant_overlays.dart';
import 'package:marginmind/features/assistant/widgets/assistant_proposal.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_support.dart';
import 'helpers.dart';

const _model = AssistantModel(provider: AssistantProvider.claude, model: 'm', endpoint: 'https://x/v1/messages');
const _local = Citation(marker: '[page:3]', documentId: 'd', page: 3, quote: 'q');
const _web = Citation(
  marker: '[source:1]',
  sourceId: 's1',
  version: 2,
  url: 'https://www.example.org/a',
  quote: 'web quote',
);
const _paper = Citation(marker: '[source:2]', sourceId: 's2', version: 1, url: 'https://doi.org/10.1/x', quote: 'p');

void main() {
  group('answer text', () {
    test('blocks: headings, lists, conclusion boxes and paragraphs', () {
      final blocks = parseAnswer('## 结论\n> 部分可靠\n> 需要限定\n第一行\n第二行\n\n- 甲\n2. 乙\n\n尾');
      expect(blocks.map((b) => b.runtimeType.toString()), [
        'HeadingBlock',
        'ConclusionBlock',
        'ParagraphBlock',
        'ListItemBlock',
        'ListItemBlock',
        'ParagraphBlock',
      ]);
      expect(blocks[1].text, '部分可靠\n需要限定');
      expect(blocks[2].text, '第一行\n第二行');
      expect((blocks[4] as ListItemBlock).marker, '2.');
    });

    test('inline: emphasis, links, valid citations only', () {
      const text = '**粗** *斜* [站点](https://a.org) [坏](javascript:x) [page:3] [page:9] [source:1] [source:7]';
      final runs = parseInline(text, const [_local, _web], sourceNumbers(text, const [_local, _web]));
      final textRuns = runs.whereType<TextRun>().toList();
      expect(textRuns.firstWhere((r) => r.bold).text, '粗');
      expect(textRuns.firstWhere((r) => r.italic).text, '斜');
      expect(textRuns.firstWhere((r) => r.text == '站点').url, Uri.parse('https://a.org'));
      expect(textRuns.firstWhere((r) => r.text == '坏').url, isNull);
      expect(runs.whereType<CitationRun>().map((r) => r.label), ['p.3', '1']);
    });

    test('sources are numbered by first citation; copies carry footnotes', () {
      const text = 'A [source:2] B [source:1] C [source:2] [page:3]';
      expect(sourceNumbers(text, const [_local, _web, _paper]), {'s2': 1, 's1': 2});
      final copy = copyableAnswer(text, const [_local, _web, _paper]);
      expect(copy, startsWith('A [^1] B [^2] C [^1] (p.3)'));
      expect(copy, contains('[^1]: https://doi.org/10.1/x'));
      expect(copy, contains('[^2]: https://www.example.org/a'));
      expect(copyableAnswer('x [page:5]', const []), 'x ');
    });

    test('a marker cut by streaming is hidden until it closes', () {
      expect(visibleWhileStreaming('see [pa'), 'see ');
      expect(visibleWhileStreaming('see [page:1'), 'see ');
      expect(visibleWhileStreaming('see [page:1]'), 'see [page:1]');
    });

    test('source kind and title come from the address', () {
      expect(sourceKind(_web), SourceKind.web);
      expect(sourceKind(_paper), SourceKind.paper);
      expect(sourceKind(const Citation(marker: 'm', sourceId: 'v', url: 'https://youtu.be/x')), SourceKind.video);
      expect(sourceTitle(_web), 'example.org');
      expect(sourceTitle(const Citation(marker: 'm', sourceId: 'id')), 'id');
      expect(sourceIcon(_paper), MMIcons.paper);
    });
  });

  group('reader', () {
    late StudySetContent content;
    late WorkspaceReader reader;
    final cancel = CancellationToken();
    setUp(() {
      content = demoContent();
      final selection = selectionContext(documentId: 'c1', page: 24, quote: '选中的话');
      reader = WorkspaceReader(
        content: () => content,
        contexts: [selection],
        filePath: (d) => d.fileName,
        pageText: (path, page) async => page == 3 ? '' : '$path:$page',
      );
    });

    test('selection text comes from the question; scope is checked again', () async {
      final id = selectionContext(documentId: 'c1', page: 24, quote: '选中的话').id;
      final pages = await reader.readSelection(id, ReadScope(studySetId: 'demo-1', selections: {id}), cancel);
      expect(pages.single.text, '选中的话');
      expect(pages.single.page, 24);
      expect(reader.readSelection(id, ReadScope(studySetId: 'demo-1'), cancel), throwsA(isA<ResearchFailure>()));
      expect(
        await reader.readSelection('other', ReadScope(studySetId: 'demo-1', selections: {'other'}), cancel),
        isEmpty,
      );
    });

    test('pages: within scope and the document, empty pages skipped', () async {
      final scope = ReadScope(studySetId: 'demo-1', documents: {'c1'});
      final pages = await reader.readPages('c1', 2, 4, scope, cancel);
      expect(pages.map((p) => p.page), [2, 4]);
      expect(pages.first.text, 'a.pdf:2');
      expect(await reader.readPages('missing', 1, 1, scope, cancel), isEmpty);
      expect(
        reader.readPages(
          'c1',
          1,
          1,
          ReadScope(
            studySetId: 'demo-1',
            pages: {
              'c2': {1},
            },
          ),
          cancel,
        ),
        throwsA(isA<ResearchFailure>()),
      );
    });

    test('search finds excerpts and nodes inside scope only', () async {
      final topic = content.cards.firstWhere((c) => c.title == '遗忘的规律').id;
      final whole = ReadScope(studySetId: 'demo-1', documents: {'c1'}, maps: {MindMap.defaultId});
      expect((await reader.searchStudySet('遗忘', 10, whole, cancel)).map((h) => h.locator), [
        'page:c1:24',
        'node:main:$topic',
        'node:main:${content.cards.firstWhere((c) => c.kind == CardKind.excerpt).id}',
      ]);
      final branch = ReadScope(
        studySetId: 'demo-1',
        branches: {
          MindMap.defaultId: {topic},
        },
      );
      expect((await reader.searchStudySet('遗忘', 10, branch, cancel)).length, 2);
      expect(await reader.searchStudySet('  ', 10, whole, cancel), isEmpty);
      expect(await reader.searchStudySet('遗忘', 1, whole, cancel), hasLength(1));
      final root = ReadScope(
        studySetId: 'demo-1',
        branches: {
          MindMap.defaultId: {assistantRootId},
        },
      );
      expect(await reader.searchStudySet('对策', 10, root, cancel), hasLength(1));
      expect(await reader.searchStudySet('对策', 10, ReadScope(studySetId: 'demo-1'), cancel), isEmpty);
    });

    test('branches: the node and what is under it; the root is the whole map', () async {
      final topic = content.cards.firstWhere((c) => c.title == '遗忘的规律').id;
      final scope = ReadScope(studySetId: 'demo-1', maps: {MindMap.defaultId});
      final branch = await reader.readBranch(MindMap.defaultId, topic, scope, cancel);
      expect(branch.first.id, topic);
      expect(branch.first.parentId, assistantRootId);
      expect(branch, hasLength(2));
      expect(await reader.readBranch(MindMap.defaultId, assistantRootId, scope, cancel), hasLength(3));
      expect(await reader.readBranch(MindMap.defaultId, 'gone', scope, cancel), isEmpty);
      expect(reader.readBranch('other', topic, scope, cancel), throwsA(isA<ResearchFailure>()));
      expect(mapParents(content, MindMap.defaultId)[topic], MindMap.defaultId);
      expect(mapParents(content, MindMap.defaultId)[MindMap.defaultId], isNull);
    });
  });

  group('conversations', () {
    Conversation conversation(String id, List<Message> messages, {String title = 't'}) =>
        Conversation(id: id, studySetId: 'set', model: _model, title: title, messages: messages);
    Message msg(String id, MessageRole role, {MessageStatus status = MessageStatus.done, String? note}) =>
        Message(id: id, requestId: 'r', role: role, status: status, noteId: note);

    test('summaries: questions, notes, state and order', () {
      final saved = ConversationSummary.of(
        conversation('100-0', [
          msg('200-1', MessageRole.user),
          msg('200-2', MessageRole.agent, status: MessageStatus.running),
        ]),
      );
      expect(saved.state, ConversationState.unfinished);
      expect(saved.questions, 1);
      expect(saved.stamp, 200);
      final live = conversation('100-0', [
        msg('300-1', MessageRole.user),
        msg('300-2', MessageRole.agent, status: MessageStatus.running),
      ]);
      expect(ConversationSummary.of(live, live: true).state, ConversationState.running);
      final failed = ConversationSummary.of(
        conversation('50-0', [msg('50-1', MessageRole.agent, status: MessageStatus.error, note: 'n')]),
      );
      expect(failed.state, ConversationState.failed);
      expect(failed.notes, 1);
      final merged = mergeLive([saved, failed], live);
      expect(merged.map((s) => (s.id, s.state)), [
        ('100-0', ConversationState.running),
        ('50-0', ConversationState.failed),
      ]);
      expect(mergeLive([saved], conversation('new', const [])), [saved]);
      expect(ConversationSummary.of(conversation('x', const [])).stamp, 0);
    });

    test('the list reads saved conversations of this study set and skips broken ones', () async {
      final archive = MemoryConversationArchive();
      Future<void> put(String id, String set, {bool empty = false}) async {
        final s = sdk.AgentState(sessionId: id);
        s.metadata['assistant.view'] = Conversation(
          id: id,
          studySetId: set,
          model: _model,
          messages: empty ? const [] : [msg('$id-1', MessageRole.user)],
        ).toJson();
        await archive.save(s);
      }

      await put('10', 'set');
      await put('20', 'set');
      await put('30', 'other');
      await put('40', 'set', empty: true);
      await archive.save(sdk.AgentState(sessionId: 'no-view'));
      archive.files['broken'] = '{';
      final container = ProviderContainer(
        overrides: [assistantArchiveProvider.overrideWith((ref, id) => archive.archive)],
      );
      addTearDown(container.dispose);
      final list = await container.read(assistantConversationsProvider('set').future);
      expect(list.map((s) => s.id), ['20', '10']);
      await renameSavedConversation(archive.archive, '10', ' 新名字 ');
      container.invalidate(assistantConversationsProvider('set'));
      expect((await container.read(assistantConversationsProvider('set').future)).last.title, '新名字');
      await renameSavedConversation(archive.archive, 'no-view', 'x');
      expect(await archive.exist('no-view'), isTrue);
      await archive.delete('no-view');
      expect(await archive.exist('no-view'), isFalse);
    });

    test('the default archive keeps files only for file repositories', () async {
      final overrides = await testOverrides();
      final container = ProviderContainer(overrides: overrides);
      addTearDown(container.dispose);
      expect(container.read(assistantArchiveProvider('demo-1')).storage, isA<MemoryConversationArchive>());
      expect(container.read(assistantNetworkProvider), isNull);
    });
  });

  group('panel state', () {
    test('contexts: attach, replace, remove; automatic ones left out once', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ui = container.read(assistantUiProvider('s').notifier);
      final node = nodeContext(mapId: 'm', nodeId: 'n', title: 'N');
      final auto = nodeContext(mapId: 'm', nodeId: 'n', title: 'N', auto: true);
      final page = pageContext(
        document: Document(id: 'd', title: 'D', fileName: 'd.pdf', pageCount: 5, importedAt: testNow),
        page: 2,
        auto: true,
      );
      ui.addContext(node);
      ui.addContext(
        node,
        anchor: SourceAnchor(target: CardTarget(cardId: 'n')),
      );
      expect(container.read(assistantUiProvider('s')).contexts, [node]);
      expect(container.read(assistantUiProvider('s')).anchors.keys, [node.id]);
      // An automatic duplicate of an attached node is not sent twice.
      expect(outgoingContexts(container.read(assistantUiProvider('s')), [auto, page]), [node, page]);
      ui.toggleAuto(page.id);
      expect(outgoingContexts(container.read(assistantUiProvider('s')), [auto, page]), [node]);
      ui.toggleAuto(page.id);
      ui.toggleAuto(page.id);
      ui.sent();
      expect(container.read(assistantUiProvider('s')).contexts, isEmpty);
      expect(outgoingContexts(container.read(assistantUiProvider('s')), [page]), [page]);
      ui.addContext(node);
      ui.removeContext(node.id);
      expect(container.read(assistantUiProvider('s')).contexts, isEmpty);
      ui.openSource(_web);
      expect(container.read(assistantUiProvider('s')).source, _web);
      ui.showHistory(true);
      expect(container.read(assistantUiProvider('s')).source, isNull);
      ui.openSource(_web);
      ui.closeSource();
      expect(container.read(assistantUiProvider('s')).source, isNull);
      ui.ask('q', skill: 'explain');
      final request = container.read(assistantUiProvider('s')).request!;
      expect(container.read(assistantUiProvider('s')).history, isFalse);
      ui.handled(request.id + 1);
      expect(container.read(assistantUiProvider('s')).request, isNotNull);
      ui.handled(request.id);
      expect(container.read(assistantUiProvider('s')).request, isNull);
      final preview = container.read(assistantPreviewProvider('s').notifier);
      preview.show({'a'});
      expect(container.read(assistantPreviewProvider('s')), {'a'});
      preview.clear();
      expect(container.read(assistantPreviewProvider('s')), isEmpty);
      expect(
        documentContext(Document(id: 'd', title: 'D', fileName: 'f', pageCount: 1, importedAt: testNow)).kind,
        ContextKind.document,
      );
      expect(mapContext(mapId: 'm', title: 'M').kind, ContextKind.map);
    });

    test('notes go under the topic, the card’s parent, or the root', () {
      final c = demoContent();
      final topic = c.cards.firstWhere((x) => x.title == '遗忘的规律').id;
      final excerpt = c.cards.firstWhere((x) => x.kind == CardKind.excerpt).id;
      ContextItem node(String id) => nodeContext(mapId: MindMap.defaultId, nodeId: id, title: '');
      expect(notePlace(c, 'main', [node(topic)], 'R').parentId, topic);
      expect(notePlace(c, 'main', [node(excerpt)], 'R').parentId, topic);
      expect(notePlace(c, 'main', [node(assistantRootId)], 'R').title, 'R');
      expect(notePlace(c, 'main', [node('gone')], 'R').parentId, isNull);
      expect(notePlace(c, 'main', const [], 'R').parentId, isNull);
      expect(noteTitleFrom('解释：锚定效应'), '锚定效应');
      expect(noteTitleFrom('Explain: anchoring'), 'anchoring');
      expect(noteTitleFrom('没有前缀'), '没有前缀');
    });

    test('proposals: stale targets and what an item outlines', () {
      final c = demoContent();
      final topic = c.cards.firstWhere((x) => x.title == '遗忘的规律').id;
      final p = MapEditProposal(
        id: 'p',
        studySetId: 's',
        mapId: MindMap.defaultId,
        baseRevision: 0,
        operations: [
          MapEditOperation(id: 'a', kind: MapEditKind.addTopic, parentId: topic, title: 'A'),
          const MapEditOperation(id: 'b', kind: MapEditKind.addNote, parentId: 'new:a', title: 'B', body: 'x'),
          const MapEditOperation(id: 'c', kind: MapEditKind.rename, nodeId: 'gone', title: 'C'),
          const MapEditOperation(id: 'd', kind: MapEditKind.addTopic, parentId: MindMap.defaultId, title: 'D'),
        ],
      );
      expect(staleOperations(c, p), {'c'});
      expect(previewTargets(p, p.operations[0]), {topic});
      expect(previewTargets(p, p.operations[1]), isEmpty);
      expect(previewTargets(p, p.operations[2]), {'gone'});
      // The map's root is outlined as the canvas root.
      expect(previewTargets(p, p.operations[3]), {assistantRootId});
    });
  });

  group('settings', () {
    test('saved per service, the model menu, and whether it is configured', () async {
      SharedPreferences.setMockInitialValues({'assistant.model.responses': 'gpt', 'assistant.model.ollama': 'llama'});
      final prefs = await SharedPreferences.getInstance();
      final secrets = FakeSecrets();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          assistantSecretsProvider.overrideWithValue(secrets),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(assistantSettingsProvider.notifier);
      expect(container.read(assistantSettingsProvider).model, 'claude-opus-5-5');
      expect(await container.read(assistantConfiguredProvider.future), isFalse);
      await notifier.saveKey('k');
      expect(await container.read(assistantConfiguredProvider.future), isTrue);
      expect(notifier.models().map((m) => m.provider), [AssistantProvider.claude, AssistantProvider.responses]);
      await notifier.select(AssistantProvider.responses);
      expect(container.read(assistantSettingsProvider).model, 'gpt');
      expect(container.read(assistantSettingsProvider).endpoint, 'https://api.openai.com/v1/responses');
      expect(await container.read(assistantConfiguredProvider.future), isFalse);
      expect(notifier.saved(AssistantProvider.compatible).model, '');
      // Refused before any request: no model.
      const invalid = AssistantModel(provider: AssistantProvider.claude, model: '', endpoint: 'https://x/v1/messages');
      expect(await container.read(assistantConnectionTesterProvider)(invalid, 'k'), ResearchFailureKind.invalidRequest);
    });
  });

  testWidgets('the cursor stays still with reduced motion', (tester) async {
    Widget body(bool reduce) => MaterialApp(
      theme: MMTheme.light(),
      home: MMAppearance(
        reduceMotion: reduce,
        child: Scaffold(
          body: AnswerBody(text: '写到一半 [pa', citations: const [], onCitation: (_) {}, cursor: true),
        ),
      ),
    );
    await tester.pumpWidget(body(true));
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(of: find.byKey(const ValueKey('assistant-cursor')), matching: find.byType(Opacity)),
          )
          .opacity,
      1,
    );
    expect(find.textContaining('[pa'), findsNothing);
    await tester.pumpWidget(body(false));
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(of: find.byKey(const ValueKey('assistant-cursor')), matching: find.byType(Opacity)),
          )
          .opacity,
      0,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
