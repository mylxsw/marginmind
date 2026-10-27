import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/assistant_scope.dart';
import 'package:marginmind/features/assistant/widgets/assistant_markdown.dart';
import 'package:marginmind/features/assistant/widgets/assistant_messages.dart';
import 'package:marginmind/features/assistant/widgets/assistant_panel.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'assistant_support.dart';

/// [child] in the app's theme and Chinese strings, as the panel shows it.
Widget _app(Widget child, {bool reduceMotion = false, Brightness brightness = Brightness.light}) => MaterialApp(
  theme: brightness == Brightness.light ? MMTheme.light() : MMTheme.dark(),
  locale: const Locale('zh'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: MMAppearance(
    reduceMotion: reduceMotion,
    child: Scaffold(body: SizedBox(width: 360, child: child)),
  ),
);

Message _answer({
  MessageStatus status = MessageStatus.done,
  List<TraceStep> traces = const [],
  String text = '',
  int seconds = 7,
}) {
  final start = DateTime(2026, 10, 27, 9);
  return Message(
    id: 'a',
    requestId: 'r',
    role: MessageRole.agent,
    status: status,
    text: text,
    traces: traces,
    startedAt: start,
    endedAt: status == MessageStatus.running ? null : start.add(Duration(seconds: seconds)),
  );
}

const _selection = '这条先陡后平的曲线，被称为遗忘曲线。';

void main() {
  group('process timeline', () {
    testWidgets('while working: the current step shimmers, the steps are open and cannot fold', (tester) async {
      await tester.pumpWidget(
        _app(
          ActivityTimeline(
            message: _answer(
              status: MessageStatus.running,
              traces: const [
                TraceStep('n', '', TraceStatus.done, narration: '先读一下所选内容。'),
                TraceStep('t', 'read_selection', TraceStatus.running),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Shimmer), findsOneWidget);
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(find.text('读取所选内容'), findsNWidgets(2)); // Title and row.
      expect(find.text('先读一下所选内容。'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('timeline-a')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('先读一下所选内容。'), findsOneWidget);
    });

    testWidgets('nothing done yet: thinking; reduced motion keeps it still', (tester) async {
      await tester.pumpWidget(
        _app(ActivityTimeline(message: _answer(status: MessageStatus.running)), reduceMotion: true),
      );
      expect(find.text('思考中…'), findsOneWidget);
      expect(find.byType(ShaderMask), findsNothing);
    });

    testWidgets('done: “worked for N s”, folded; failures counted with their raw names and reasons', (tester) async {
      await tester.pumpWidget(
        _app(
          ActivityTimeline(
            message: _answer(
              traces: const [
                TraceStep('n', '', TraceStatus.done, narration: '先读所选内容。'),
                TraceStep('1', 'read_selction', TraceStatus.error, reason: '模型请求了不存在的工具 read_selction'),
                TraceStep('2', 'read_selction', TraceStatus.error, reason: '模型请求了不存在的工具 read_selction'),
                TraceStep('3', 'read_pages', TraceStatus.done),
                TraceStep('4', 'read_pages', TraceStatus.done),
                TraceStep('5', 'web_search', TraceStatus.done),
              ],
            ),
          ),
        ),
      );
      expect(find.text('处理了 7 秒'), findsOneWidget);
      expect(find.text(' · 工具调用失败 2 次'), findsOneWidget);
      expect(find.byIcon(MMIcons.chevronRight), findsOneWidget);
      expect(find.text('read_selction ×2'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('timeline-a')));
      await tester.pumpAndSettle();
      expect(find.byIcon(MMIcons.chevronDown), findsOneWidget);
      // Never “working on it”: an unknown tool keeps its own name.
      expect(find.text('read_selction ×2'), findsOneWidget);
      expect(find.text('模型请求了不存在的工具 read_selction'), findsOneWidget);
      expect(find.text('读取原文 ×2'), findsOneWidget);
      expect(find.text('联网搜索'), findsOneWidget);
      expect(find.text('先读所选内容。'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('timeline-a')));
      await tester.pumpAndSettle();
      expect(find.text('先读所选内容。'), findsNothing);
    });

    testWidgets('no tool calls: the time only, nothing to open', (tester) async {
      await tester.pumpWidget(_app(ActivityTimeline(message: _answer(seconds: 0))));
      expect(find.text('处理了 1 秒'), findsOneWidget);
      expect(find.byIcon(MMIcons.chevronRight), findsNothing);
    });
  });

  group('answer body', () {
    const local = Citation(marker: '[page:3]', documentId: 'd', page: 3, quote: 'q');
    testWidgets('headings, quotes in the reading face, lists, tables, rules, code and citations', (tester) async {
      final cited = <Citation>[];
      final links = <Uri>[];
      await tester.pumpWidget(
        _app(
          AnswerBody(
            text:
                '**一句话：**结论 [page:3] [page:9]\n\n### 两种解释\n\n> 原文的一句话\n\n'
                '1. 甲\n   - 子项\n2. 乙\n\n| 环节 | 场景 |\n| --- | --- |\n| 调整 | 自己 |\n\n---\n\n'
                '`code` ~~旧~~ *斜* [站点](https://a.org) [坏](javascript:x)\n\n```\nprint(1)\n```',
            citations: const [local],
            onCitation: cited.add,
            onLink: links.add,
          ),
        ),
      );
      final heading = tester.widget<RichText>(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == '两种解释'),
      );
      final headingStyle = ((heading.text as TextSpan).children!.first as TextSpan).style!;
      expect(headingStyle.fontWeight, FontWeight.w600);
      expect(headingStyle.fontSize, 13.5);
      final quote = tester.widget<RichText>(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == '原文的一句话'),
      );
      expect(((quote.text as TextSpan).children!.first as TextSpan).style!.fontFamily, 'Songti SC');
      expect(find.byKey(const ValueKey('answer-table')), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('◦'), findsOneWidget);
      expect(find.text('print(1)'), findsOneWidget);
      // Only the registered citation shows.
      expect(find.text('p.3'), findsOneWidget);
      expect(find.text('p.9'), findsNothing);
      await tester.tap(find.text('p.3'));
      expect(cited.single.page, 3);
      await tester.tap(find.text('站点'));
      expect(links.single, Uri.parse('https://a.org'));
      expect(find.textContaining('坏'), findsOneWidget); // Plain text, not a link.
      expect(find.bySemanticsLabel('坏'), findsNothing);
    });

    testWidgets('a check opens with its verdict boxed; qualified verdicts in caution', (tester) async {
      Future<Color> verdict(String text) async {
        await tester.pumpWidget(
          _app(AnswerBody(text: text, citations: const [], onCitation: (_) {}, conclusion: true)),
        );
        final box = tester.widget<Container>(find.byKey(const ValueKey('answer-verdict')));
        return (box.decoration! as BoxDecoration).color!;
      }

      final positive = MMTheme.light().extension<MMColors>()!.positive;
      final caution = MMTheme.light().extension<MMColors>()!.caution;
      expect(await verdict('**可靠。**\n\n理由'), positive.withValues(alpha: .10));
      expect(await verdict('### 结论\n\n**部分可靠。**'), caution.withValues(alpha: .12));
    });

    testWidgets('while streaming, finished blocks are laid out and the open one shows its text', (tester) async {
      await tester.pumpWidget(
        _app(
          AnswerBody(
            text: '### 标题\n\n- 一\n- 二\n\n| a | b |\n| - |',
            citations: const [],
            onCitation: (_) {},
            cursor: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('•'), findsNWidgets(2));
      // The unfinished table is plain text for now.
      expect(find.byKey(const ValueKey('answer-table')), findsNothing);
      expect(find.byKey(const ValueKey('assistant-cursor')), findsOneWidget);
    });
  });

  group('in the panel', () {
    testWidgets('a tool failure: details, copied diagnostics, answer without tools, switch model', (tester) async {
      final archive = MemoryConversationArchive();
      final state = sdk.AgentState(sessionId: 'tools-1');
      state.metadata['assistant.view'] = Conversation(
        id: 'tools-1',
        studySetId: 'demo-1',
        title: '解释',
        model: const AssistantModel(
          provider: AssistantProvider.claude,
          model: 'claude-opus-5-5',
          endpoint: 'https://api.anthropic.com/v1/messages',
          serviceId: 'legacy-claude',
        ),
        messages: [
          Message(id: '1000-1', requestId: 'req-42', role: MessageRole.user, text: '解释一下这段话'),
          Message(
            id: '1000-2',
            requestId: 'req-42',
            role: MessageRole.agent,
            status: MessageStatus.error,
            errorKind: ResearchFailureKind.toolProtocol,
            diagnostics: AssistantDiagnostics(
              requestId: 'req-42',
              model: 'claude-opus-5-5',
              host: 'api.anthropic.com',
              failure: 'toolProtocol',
              httpStatus: 400,
              tools: const [
                TraceStep('', 'read_selction', TraceStatus.error, reason: 'x'),
                TraceStep('', 'read_selction', TraceStatus.error, reason: 'x'),
                TraceStep('', 'read_pages', TraceStatus.done),
              ],
            ),
          ),
        ],
      ).toJson();
      await archive.save(state);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await openAssistantApp(tester, archive: archive, client: ScriptClient([answer('不用工具的回答')]));
      await tester.tap(find.byKey(const ValueKey('sidebar-conversation-tools-1')));
      await pumpFor(tester, 20);
      expect(find.text('模型没能正确调用工具'), findsOneWidget);
      expect(find.text('不用工具重答'), findsOneWidget);
      expect(find.text('换个模型'), findsOneWidget);
      expect(find.text('复制诊断信息'), findsOneWidget);
      expect(find.byKey(const ValueKey('assistant-details-table')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('assistant-details-1000-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('assistant-details-table')), findsOneWidget);
      expect(find.text('claude-opus-5-5 · claude'), findsOneWidget);
      expect(find.text('api.anthropic.com'), findsOneWidget);
      expect(find.text('400'), findsOneWidget);
      expect(find.text('read_selction ×2'), findsOneWidget);
      expect(find.text('req-42'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('assistant-copy-details-1000-2')));
      await tester.pump();
      expect(copied, contains('请求 ID: req-42'));
      expect(copied, contains('HTTP 状态码: 400'));
      // No key and no question text.
      expect(copied, isNot(contains('test-key')));
      expect(copied, isNot(contains('解释一下这段话')));
      await settleHudFor(tester);
      // “Switch model” opens the model menu.
      await tester.tap(find.byKey(const ValueKey('assistant-switch-model-1000-2')));
      await tester.pumpAndSettle();
      expect(find.text('管理模型…'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('assistant-no-tools-1000-2')));
      await pumpFor(tester, 20);
      expect(conversationOf(tester).messages.last.text, '不用工具的回答');
      expect(conversationOf(tester).messages, hasLength(2));
    });

    testWidgets('a conversation already on the local model is not offered it again', (tester) async {
      final archive = MemoryConversationArchive();
      final state = sdk.AgentState(sessionId: 'local-1');
      state.metadata['assistant.view'] = Conversation(
        id: 'local-1',
        studySetId: 'demo-1',
        title: '本机',
        model: const AssistantModel(
          provider: AssistantProvider.ollama,
          model: 'llama',
          endpoint: 'http://localhost:11434',
          localEnabled: true,
          serviceId: 'legacy-ollama',
        ),
        messages: [
          Message(id: '1000-1', requestId: 'r', role: MessageRole.user, text: '问'),
          Message(
            id: '1000-2',
            requestId: 'r',
            role: MessageRole.agent,
            status: MessageStatus.error,
            errorKind: ResearchFailureKind.network,
          ),
        ],
      ).toJson();
      await archive.save(state);
      await openAssistantApp(
        tester,
        archive: archive,
        prefs: {'assistant.model.ollama': 'llama', 'assistant.localEnabled': true},
      );
      await tester.tap(find.byKey(const ValueKey('sidebar-conversation-local-1')));
      await pumpFor(tester, 20);
      expect(find.text('网络不可用'), findsOneWidget);
      expect(find.text('改用本机模型'), findsNothing);
    });

    testWidgets('“Organize into the map” asks again with the same context; hidden on organize answers', (tester) async {
      final app = await openAssistantApp(tester, client: ScriptClient([answer('解释'), answer('整理好了')]));
      await app.workspace.onSelectionCommitted(
        'c1',
        MMPdfSelection(
          page: 24,
          rects: const [PageRect(10, 100, 200, 88)],
          text: _selection,
          viewportRect: const Rect.fromLTWH(100, 200, 200, 20),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('selection-assistant')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-explain')));
      await pumpFor(tester, 20);
      final first = conversationOf(tester).messages.last;
      expect(find.byKey(ValueKey('assistant-organize-${first.id}')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('assistant-organize-${first.id}')));
      await pumpFor(tester, 20);
      final messages = conversationOf(tester).messages;
      final question = messages[messages.length - 2];
      expect(question.skill, 'organize');
      expect(question.text, '把这部分整理进脑图');
      expect(question.contexts.map((c) => c.kind), contains(ContextKind.selection));
      expect(find.byKey(ValueKey('assistant-organize-${messages.last.id}')), findsNothing);
    });

    testWidgets('entries are icons only; the header buttons sit at the right; page chips lead with the page', (
      tester,
    ) async {
      final app = await openAssistantApp(tester);
      final toolbar = find.byKey(const ValueKey('toolbar-assistant'));
      expect(find.descendant(of: toolbar, matching: find.byType(Text)), findsNothing);
      await app.workspace.onSelectionCommitted(
        'c1',
        MMPdfSelection(
          page: 24,
          rects: const [PageRect(10, 100, 200, 88)],
          text: _selection,
          viewportRect: const Rect.fromLTWH(100, 200, 200, 20),
        ),
      );
      await tester.pumpAndSettle();
      final ask = find.byKey(const ValueKey('selection-assistant'));
      expect(find.descendant(of: ask, matching: find.byType(Text)), findsNothing);
      expect(tester.widget<MMToolbarButton>(ask).tooltip, startsWith('问助手（A · '));
      await tester.tap(toolbar);
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byType(AssistantHeader));
      final close = tester.getRect(find.byKey(const ValueKey('assistant-close')));
      expect(close.right, closeTo(panel.right - 8, 1));
      expect(tester.getRect(find.byKey(const ValueKey('assistant-new'))).right, lessThan(close.left + 1));
      // The page being read is attached, page number first.
      expect(find.textContaining('第 '), findsWidgets);
      expect(find.textContaining('页 · 学习的底层逻辑'), findsWidgets);
      await tester.pump(const Duration(seconds: 3));
    });
  });
}

/// Lets the “copied” HUD go away.
Future<void> settleHudFor(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}
