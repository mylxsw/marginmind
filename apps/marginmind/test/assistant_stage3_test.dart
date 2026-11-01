import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';

import 'dart:convert';

import 'package:flutter/gestures.dart' show kSecondaryButton, PointerDeviceKind;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/assistant_reader.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';

import 'assistant_background_test.dart' show GatedClient;
import 'assistant_support.dart';
import 'helpers.dart';

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('assistant-input')), text);
  await tester.pump();
}

Future<void> _send(WidgetTester tester, String text) async {
  await _type(tester, text);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}

double _sendOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.descendant(of: find.byKey(const ValueKey('assistant-send')), matching: find.byType(AnimatedOpacity)),
    )
    .opacity;

void main() {
  testWidgets('an undone proposal is pending again, applies again, and redo shows it applied', (tester) async {
    final topic = demoContent().cards.firstWhere((c) => c.title == '遗忘的规律').id;
    final ops = {
      'ops': [
        {'id': 'a', 'kind': 'addTopic', 'parentId': topic, 'title': '新主题'},
      ],
    };
    final app = await openAssistantApp(
      tester,
      realWrites: true,
      client: ScriptClient([call('propose_map_edits', jsonEncode(ops))]),
    );
    app.workspace.openPanel(RightPanel.assistant);
    await tester.pumpAndSettle();
    await _send(tester, '整理一下');
    await pumpFor(tester, 20);
    final count = app.workspace.content.cards.length;
    expect(find.text('应用 1 处'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('proposal-apply')));
    await pumpFor(tester, 30);
    expect(app.workspace.content.cards.length, count + 1);
    expect(app.workspace.state.panel, RightPanel.assistant);
    expect(app.workspace.state.tabs.current.reference, isNull);
    final added = app.workspace.content.cards.singleWhere((c) => c.title == '新主题');
    expect(app.workspace.state.selectedCardId, added.id);
    await tester.tap(find.byKey(const ValueKey('proposal-show')));
    await pumpFor(tester);
    expect(app.workspace.state.panel, RightPanel.assistant);
    expect(app.workspace.state.tabs.current.reference, isNull);
    expect(app.workspace.state.selectedCardId, added.id);
    expect(find.byKey(const ValueKey('proposal-undo')), findsOneWidget);

    // The card's undo: the topic goes and the proposal can be applied again.
    await tester.tap(find.byKey(const ValueKey('proposal-undo')));
    await pumpFor(tester, 30);
    expect(app.workspace.content.cards.length, count);
    expect(app.workspace.content.assistantReceipts, isEmpty);
    expect(find.text('应用 1 处'), findsOneWidget);
    expect(conversationOf(tester).messages.last.proposals.single.status, ProposalStatus.pending);

    // Redo (⇧⌘Z) brings the change and its receipt back.
    await app.workspace.redo();
    await pumpFor(tester, 30);
    expect(app.workspace.content.cards.length, count + 1);
    expect(find.byKey(const ValueKey('proposal-undo')), findsOneWidget);

    // ⌘Z, then applying again adds the topic once more.
    await app.workspace.undo();
    await pumpFor(tester, 30);
    expect(find.text('应用 1 处'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('proposal-apply')));
    await pumpFor(tester, 30);
    expect(app.workspace.content.cards.length, count + 1);
    expect(app.workspace.content.cards.where((c) => c.title == '新主题'), hasLength(1));
    expect(conversationOf(tester).messages.last.proposals.single.status, ProposalStatus.applied);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a new conversation leaves the answer running; sending waits for it', (tester) async {
    final client = GatedClient([answer('第一个回答'), answer('第二个回答')]);
    final gate = client.gate(0);
    final app = await openAssistantApp(tester, client: client, size: const Size(1800, 1000));
    app.workspace.openPanel(RightPanel.assistant);
    await tester.pumpAndSettle();
    await _send(tester, '第一个问题');
    await pumpFor(tester);
    final first = conversationOf(tester).id;
    expect(conversationOf(tester).running, isTrue);

    await tester.tap(find.byKey(const ValueKey('assistant-new')));
    await pumpFor(tester);
    expect(conversationOf(tester).messages, isEmpty);
    // History shows the other conversation still answering.
    await showAssistantHistory(tester);
    final row = find.byKey(ValueKey('history-$first'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('生成中')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assistant-history-button')));
    await pumpFor(tester);
    // Typing works; sending waits.
    await _type(tester, '第二个问题');
    expect(_sendOpacity(tester), lessThan(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFor(tester);
    expect(conversationOf(tester).messages, isEmpty);

    gate.complete();
    await pumpFor(tester, 20);
    expect(find.descendant(of: row, matching: find.text('生成中')), findsNothing);
    expect(_sendOpacity(tester), 1);

    await showAssistantHistory(tester);
    expect(find.descendant(of: row, matching: find.text('生成中')), findsNothing);
    expect(tester.getRect(row).left, greaterThanOrEqualTo(0));
    await tester.tap(row);
    await pumpFor(tester, 20);
    expect(conversationOf(tester).id, first);
    expect(conversationOf(tester).messages.last.text, '第一个回答');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('regenerate replaces the answer in place', (tester) async {
    final app = await openAssistantApp(tester, client: ScriptClient([answer('旧的回答'), answer('新的回答')]));
    app.workspace.openPanel(RightPanel.assistant);
    await tester.pumpAndSettle();
    await _send(tester, '问一下');
    await pumpFor(tester, 20);
    expect(find.textContaining('旧的回答'), findsOneWidget);
    final old = conversationOf(tester).messages.last;
    await tester.tap(find.byKey(ValueKey('assistant-regenerate-${old.id}')));
    await pumpFor(tester, 20);
    expect(find.textContaining('旧的回答'), findsNothing);
    expect(find.textContaining('新的回答'), findsOneWidget);
    expect(conversationOf(tester).messages, hasLength(2));
    expect(conversationOf(tester).messages.first.text, '问一下');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the root menu organizes or quizzes the whole map', (tester) async {
    final app = await openAssistantApp(tester, client: ScriptClient([answer('整理好了'), answer('出好了')]));
    final root = app.container.read(studySetProvider('demo-1'))!.title;
    Future<void> rootMenu(String item) async {
      await tester.tap(
        find.descendant(of: find.byType(MindMapCanvas), matching: find.text(root)),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('问助手'), findsOneWidget);
      expect(find.text('整理这个分支…'), findsOneWidget);
      expect(find.text('为这个分支出复习题…'), findsOneWidget);
      await tester.tap(find.text(item));
      await pumpFor(tester, 20);
    }

    await rootMenu('整理这个分支…');
    var question = conversationOf(tester).messages.first;
    expect(question.skill, 'organize');
    expect(question.contexts.first.kind, ContextKind.branch);
    expect(question.contexts.first.nodeId, assistantRootId);
    await rootMenu('为这个分支出复习题…');
    question = conversationOf(tester).messages[2];
    expect(question.skill, 'quiz');
    expect(question.contexts.first.nodeId, assistantRootId);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('settings have only what is needed (2.16 “not in settings”)', (tester) async {
    final app = await openAssistantApp(tester);
    app.workspace.openPanel(RightPanel.assistant);
    await tester.pumpAndSettle();
    await openAssistantModelSettings(tester);
    expect(find.byKey(const ValueKey('settings-models')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('service-header-legacy-claude')));
    await tester.pumpAndSettle();
    expect(find.text('API Key'), findsOneWidget);
    // Checked automatically; no protocol switch, capabilities or per-task models.
    for (final absent in ['检查连接', '已连接', '协议', '上下文长度', '工具调用', '翻译模型', '默认联网', '改动脑图前先预览']) {
      expect(find.text(absent), findsNothing, reason: absent);
    }
    await tester.tap(find.byKey(const ValueKey('settings-tab-webSearch')));
    await tester.pumpAndSettle();
    for (final absent in ['搜索次数上限', '内网拦截', '默认联网']) {
      expect(find.text(absent), findsNothing, reason: absent);
    }
  });
}
