import 'dart:async';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/assistant_entry.dart';
import 'package:marginmind/features/assistant/assistant_scope.dart';
import 'package:marginmind/features/assistant/widgets/assistant_markdown.dart';
import 'package:marginmind/features/assistant/widgets/assistant_panel.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'assistant_support.dart';
import 'helpers.dart';

const _claim = '这条先陡后平的曲线，被称为遗忘曲线。';
const _rect = PageRect(10, 100, 200, 88);

class _LockedSecrets extends FakeSecrets {
  @override
  Future<String?> read(String name) async => throw const ResearchFailure(ResearchFailureKind.authentication);
}

class _ToggleKeyStore extends FakeSecrets {
  bool blocked = false;
  @override
  Future<String?> read(String account) async {
    if (blocked) throw const ResearchFailure(ResearchFailureKind.authentication, 'secret_store');
    return super.read(account);
  }
}

Future<void> _selectText(WidgetTester tester, WorkspaceController workspace) async {
  await workspace.onSelectionCommitted(
    'c1',
    MMPdfSelection(page: 24, rects: const [_rect], text: _claim, viewportRect: const Rect.fromLTWH(100, 200, 200, 20)),
  );
  await tester.pumpAndSettle();
}

String _selectionId() => selectionContext(documentId: 'c1', page: 24, quote: _claim).id;

String _cardId(WorkspaceController w, String title) => w.content.cards.firstWhere((c) => c.title == title).id;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('assistant-input')), text);
  await tester.pump();
}

/// Right-clicks the node titled [title] and picks [item] from its menu.
Future<void> _nodeMenu(WidgetTester tester, String title, String item) async {
  final click = await tester.startGesture(
    tester.getCenter(find.text(title).last),
    buttons: kSecondaryButton,
    kind: PointerDeviceKind.mouse,
  );
  await click.up();
  await click.removePointer();
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await pumpFor(tester, 20);
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

void main() {
  testWidgets('storage becoming inaccessible during a question is not reported as an invalid API key', (tester) async {
    final secrets = _ToggleKeyStore();
    await openAssistantApp(tester, secretStore: secrets);
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    secrets.blocked = true;
    await _type(tester, '解释这段内容');
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await pumpFor(tester, 20);
    expect(conversationOf(tester).messages.last.diagnostics?.failure, 'secret_store');
    expect(find.text('模型暂不可用'), findsOneWidget);
    expect(find.text('重试读取'), findsNothing);
    expect(find.text('API Key 无效'), findsNothing);
    secrets.blocked = false;
    await tester.tap(find.byKey(const ValueKey('assistant-open-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-models')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('service-header-legacy-claude')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey('service-key')), matching: find.byType(EditableText)),
      'test-key',
    );
    await tester.tap(find.byKey(const ValueKey('service-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-connect')), findsNothing);
    await _type(tester, '解释这段内容');
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await pumpFor(tester, 20);
    expect(conversationOf(tester).messages.last.status, MessageStatus.done);
  });

  testWidgets('locked credentials leave the reader and model settings link usable', (tester) async {
    final app = await openAssistantApp(tester, secretStore: _LockedSecrets());
    expect(app.workspace.content.documents, isNotEmpty);
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-connect')), findsOneWidget);
    expect(find.byKey(const ValueKey('connect-key')), findsNothing);
    expect(find.text('请重新填写 API Key'), findsOneWidget);
    expect(find.textContaining('这不代表 Key 无效'), findsNothing);
    expect(find.text('重试读取'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('assistant-configure-models')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-models')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pumpAndSettle();
    app.container.read(navigationProvider.notifier).showLibrary();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-connect')), findsNothing);
  });

  testWidgets('opening and reopening a study set never reads the Keychain', (tester) async {
    final app = await openAssistantApp(tester);
    expect(app.secrets.reads, isEmpty);
    expect(app.workspace.content.documents, isNotEmpty);
    app.container.read(navigationProvider.notifier).showLibrary();
    await tester.pumpAndSettle();
    app.container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    expect(app.secrets.reads, isEmpty);
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    expect(app.secrets.reads, contains('anthropic'));
    expect(find.byKey(const ValueKey('assistant-input')), findsOneWidget);
  });

  testWidgets('scene 1: ask about a selection, explain it, jump back with p.24, copy and save as note', (tester) async {
    final client = ScriptClient([
      call('read_selection', jsonEncode({'selectionId': _selectionId()})),
      answer('## 要点\n这句话说的是**遗忘曲线** [page:24]。\n- 先陡\n- 后平 [page:99]'),
    ]);
    final app = await openAssistantApp(tester, client: client);
    await _selectText(tester, app.workspace);
    expect(find.byKey(const ValueKey('selection-assistant')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('selection-assistant')));
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('assistant-quick-actions')), findsOneWidget);
    expect(app.container.read(workspaceProvider('demo-1')).panel, isNot(RightPanel.assistant));
    expect(client.calls, 0);
    await tester.tap(find.byKey(const ValueKey('quick-sidebar')));
    await pumpFor(tester);
    // The optional sidebar entry carries the same passage.
    expect(app.container.read(workspaceProvider('demo-1')).panel, RightPanel.assistant);
    expect(app.container.read(workspaceProvider('demo-1')).layout, MMSplitMode.split);
    expect(tester.widget<MMSplitView>(find.byType(MMSplitView)).mode, MMSplitMode.split);
    expect(find.byKey(const ValueKey('assistant-context-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-context-list')), findsNothing);
    for (final s in [AssistantSkill.explain, AssistantSkill.summarize]) {
      expect(find.byKey(ValueKey('quick-${s.name}')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('quick-more')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-translate')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('quick-explain')));
    await pumpFor(tester, 20);
    final c = conversationOf(tester);
    expect(c.messages.first.skill, 'explain');
    expect(c.messages.first.contexts.first.displayText, _claim);
    expect(c.messages.last.status, MessageStatus.done);
    // Manual chips are cleared by sending.
    expect(find.byKey(ValueKey('context-chip-${_selectionId()}')), findsNothing);
    // The quote block above the question, the answer, a valid p.24 chip only.
    expect(find.descendant(of: find.byType(AssistantPanel), matching: find.text(_claim)), findsOneWidget);
    expect(find.text('p.24'), findsOneWidget);
    expect(find.text('p.99'), findsNothing);
    expect(find.textContaining('[page:'), findsNothing);
    // Steps folded after the answer; open on click.
    expect(find.textContaining('处理了'), findsOneWidget);
    expect(find.text('读取所选内容'), findsNothing);
    await tester.tap(find.textContaining('处理了'));
    await tester.pumpAndSettle();
    expect(find.text('读取所选内容'), findsOneWidget);
    // p.24 goes back to the passage.
    await tester.tap(find.text('p.24'));
    await tester.pumpAndSettle();
    expect(app.container.read(workspaceProvider('demo-1')).reveal?.page, 24);
    // Copy keeps the page as text.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await tester.tap(find.byKey(ValueKey('assistant-copy-${c.messages.last.id}')));
    await tester.pump();
    expect(copied, contains('(p.24)'));
    await tester.pump(const Duration(seconds: 3));
    // Save as note: both places offered for a passage; none checked disables Save.
    await tester.tap(find.byKey(ValueKey('assistant-save-${c.messages.last.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('save-note-popover')), findsOneWidget);
    expect(find.textContaining('附到原文第 24 页'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-note-map')));
    await tester.tap(find.byKey(const ValueKey('save-note-source')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-note-confirm')));
    await tester.pump();
    expect(app.notes.notes, isEmpty);
    await tester.tap(find.byKey(const ValueKey('save-note-map')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-note-confirm')));
    await tester.pumpAndSettle();
    final request = app.notes.requests.values.single;
    expect(request.mapId, MindMap.defaultId);
    expect(request.parentId, isNull);
    expect(request.anchor, isNull);
    expect(find.byKey(ValueKey('assistant-saved-${c.messages.last.id}')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('node menu entries send at once or attach; card details asks about the card', (tester) async {
    final app = await openAssistantApp(tester, client: ScriptClient([answer('一'), answer('二')]));
    final topic = _cardId(app.workspace, '遗忘的规律');
    expect(find.text('问助手'), findsNothing);
    await _nodeMenu(tester, '遗忘的规律', '解释这个主题');
    expect(app.container.read(workspaceProvider('demo-1')).layout, MMSplitMode.split);
    final c = conversationOf(tester);
    expect(c.messages.first.contexts.first.kind, ContextKind.node);
    expect(c.messages.first.contexts.first.displayText, '遗忘的规律');
    // Details → Ask: the panel switches to the assistant with the card attached.
    app.workspace.showDetails(topic);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('details-ask-assistant')));
    await tester.pumpAndSettle();
    expect(app.container.read(workspaceProvider('demo-1')).panel, RightPanel.assistant);
    await tester.tap(find.byKey(const ValueKey('assistant-context-summary')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('context-chip-node-main-$topic')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('composer: IME, shift-return, slash menu, @ menu and automatic chips', (tester) async {
    final app = await openAssistantApp(tester, client: ScriptClient([answer('总结'), answer('翻译'), answer('三')]));
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-suggestions')), findsOneWidget);
    // Empty text: send is disabled.
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await tester.pump();
    expect(conversationOf(tester).messages, isEmpty);
    // Composing with an input method: Return commits, does not send.
    await tester.tap(find.byKey(const ValueKey('assistant-input')));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'zhong',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      ),
    );
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.enter);
    expect(conversationOf(tester).messages, isEmpty);
    // "/" opens the commands; typing filters; arrows and Return pick.
    await _type(tester, '/');
    expect(find.byKey(const ValueKey('assistant-slash-menu')), findsOneWidget);
    expect(find.text('/找视频'), findsOneWidget);
    await _type(tester, '/翻');
    expect(find.text('/翻译'), findsOneWidget);
    expect(find.text('/解释'), findsNothing);
    await _type(tester, '/zzz');
    expect(find.byKey(const ValueKey('assistant-slash-menu')), findsNothing);
    await _type(tester, '/');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.byKey(const ValueKey('assistant-slash-menu')), findsNothing);
    // The page being read is attached automatically: a command sends at once.
    await _type(tester, '/总');
    await _press(tester, LogicalKeyboardKey.enter);
    await pumpFor(tester, 20);
    final first = conversationOf(tester).messages.first;
    expect(first.skill, 'summarize');
    expect(first.contexts.single.auto, isTrue);
    expect(first.contexts.single.kind, ContextKind.page);
    // The reference manager leaves an automatic item out of the next message only.
    final auto = first.contexts.single.id;
    await tester.tap(find.byKey(const ValueKey('assistant-context-summary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('context-remove-$auto')));
    await tester.pump();
    await _type(tester, '翻译这一句');
    await _press(tester, LogicalKeyboardKey.enter);
    await pumpFor(tester, 20);
    final second = conversationOf(tester).messages[2];
    expect(second.text, '翻译这一句');
    expect(second.contexts, isEmpty);
    expect(find.text('引用 1 项'), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-context-list')), findsNothing);
    // Typed "/command text" picks the skill and keeps the text.
    await _type(tester, '/解释 曲线');
    expect(find.byKey(const ValueKey('assistant-slash-menu')), findsNothing);
    // @ adds a reference and does not stay in the text.
    await _type(tester, '/解释 曲线@');
    await tester.pumpAndSettle();
    expect(find.text('整张脑图'), findsOneWidget);
    await tester.tap(find.text('整张脑图'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assistant-context-summary')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('context-chip-map-main')), findsOneWidget);
    expect(find.text('/解释 曲线'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assistant-input')));
    await _press(tester, LogicalKeyboardKey.enter, shift: true);
    await _press(tester, LogicalKeyboardKey.enter);
    await pumpFor(tester, 20);
    final third = conversationOf(tester).messages[4];
    expect(third.skill, 'explain');
    expect(third.text, '曲线');
    expect(third.contexts.first.kind, ContextKind.map);
    expect(app.archive.files, hasLength(1));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('stop with Esc keeps the partial answer; the trace stays open while running', (tester) async {
    final output = StreamController<sdk.StreamingMessage>();
    final client = StreamClient((_) => output.stream);
    await openAssistantApp(tester, client: client);
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    await _type(tester, '问题');
    await _press(tester, LogicalKeyboardKey.enter);
    await pumpFor(tester);
    output.add(
      sdk.StreamingMessage(
        modelMessage: sdk.ModelMessage(model: 'fake', textOutput: '部分回'),
      ),
    );
    await pumpFor(tester);
    expect(conversationOf(tester).running, isTrue);
    expect(find.byKey(const ValueKey('assistant-stop')), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-cursor')), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.escape);
    await pumpFor(tester);
    final last = conversationOf(tester).messages.last;
    expect(last.status, MessageStatus.stopped);
    expect(last.text, '部分回');
    expect(find.text('已停止'), findsOneWidget);
    expect(find.byKey(ValueKey('assistant-regenerate-${last.id}')), findsOneWidget);
    await output.close();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('scene 3: proposals preview on the map, leave items out, apply and show; dismiss and reopen', (
    tester,
  ) async {
    final repo = demoContent();
    final topic = repo.cards.firstWhere((c) => c.title == '遗忘的规律').id;
    final other = repo.cards.firstWhere((c) => c.title == '对策一：间隔重复').id;
    final ops = {
      'ops': [
        {'id': 'a', 'kind': 'addTopic', 'parentId': topic, 'title': '新主题'},
        {'id': 'b', 'kind': 'addReviewCard', 'parentId': 'new:a', 'question': '问题？', 'answer': '答案'},
        {'id': 'c', 'kind': 'rename', 'nodeId': other, 'title': '改名'},
      ],
    };
    final client = ScriptClient([
      call('propose_map_edits', jsonEncode(ops)),
      call('propose_map_edits', jsonEncode(ops)),
    ]);
    final app2 = await openAssistantApp(tester, client: client);
    await _nodeMenu(tester, '遗忘的规律', '整理这个分支…');
    expect(conversationOf(tester).messages.first.contexts.first.kind, ContextKind.branch);
    expect(find.text('修改脑图'), findsOneWidget);
    expect(find.text('应用 3 处'), findsOneWidget);
    // Hover outlines the parent of a new node on the map.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey('proposal-op-a'))));
    await tester.pump();
    expect(app2.container.read(assistantPreviewProvider('demo-1')), {topic});
    expect(find.byKey(ValueKey('map-preview-$topic')), findsOneWidget);
    await gesture.moveTo(Offset.zero);
    await tester.pump();
    expect(app2.container.read(assistantPreviewProvider('demo-1')), isEmpty);
    // Leaving out the new topic leaves out the card under it.
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('proposal-op-a')), matching: find.byType(MMCheckbox)),
    );
    await pumpFor(tester);
    expect(find.text('应用 1 处'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('proposal-op-c')), matching: find.byType(MMCheckbox)),
    );
    await pumpFor(tester);
    expect(find.text('应用 0 处'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('proposal-apply')));
    await pumpFor(tester);
    expect(app2.executor.applied, isEmpty);
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('proposal-op-b')), matching: find.byType(MMCheckbox)),
    );
    await pumpFor(tester);
    expect(find.text('应用 2 处'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('proposal-apply')));
    await pumpFor(tester, 30);
    expect(app2.executor.applied.map((o) => o.id), ['a', 'b']);
    expect(find.text('已应用'), findsOneWidget);
    expect(find.byKey(const ValueKey('proposal-show')), findsOneWidget);
    expect(find.byKey(const ValueKey('proposal-undo')), findsOneWidget);
    // A second proposal: dismissed, then reviewed again.
    await _type(tester, '再整理');
    await _press(tester, LogicalKeyboardKey.enter);
    await pumpFor(tester, 20);
    await tester.tap(find.byKey(const ValueKey('proposal-dismiss')).last);
    await pumpFor(tester);
    expect(find.text('已忽略'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('proposal-reopen')));
    await pumpFor(tester);
    expect(find.text('已忽略'), findsNothing);
    // A deleted target is left out and marked.
    await app2.workspace.removeCards([other]);
    await pumpFor(tester);
    expect(find.text('目标已删除'), findsOneWidget);
    expect(find.text('应用 2 处'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('failure states name the reason and the next step', (tester) async {
    final app = await openAssistantApp(tester);
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    // No key: the run cannot start.
    app.secrets.values.clear();
    await _type(tester, '问题');
    await _press(tester, LogicalKeyboardKey.enter);
    await pumpFor(tester, 20);
    expect(find.text('API Key 无效'), findsOneWidget);
    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-models')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pumpAndSettle();
    app.secrets.values['anthropic'] = 'k';
    await _type(tester, '再问一次');
    await _press(tester, LogicalKeyboardKey.enter);
    await pumpFor(tester, 20);
    expect(conversationOf(tester).messages.last.status, MessageStatus.done);
  });

  testWidgets('scene 7: an interrupted answer is offered again, never resent by itself', (tester) async {
    final archive = MemoryConversationArchive();
    final state = sdk.AgentState(sessionId: 'old-1');
    state.metadata['assistant.view'] = Conversation(
      id: 'old-1',
      studySetId: 'demo-1',
      title: '没完成的对话',
      model: const AssistantModel(provider: AssistantProvider.claude, model: 'm', endpoint: 'https://x/v1/messages'),
      messages: [
        Message(id: '1000-1', requestId: 'r', role: MessageRole.user, text: '问'),
        Message(id: '1000-2', requestId: 'r', role: MessageRole.agent, text: '一半', status: MessageStatus.running),
      ],
    ).toJson();
    await archive.save(state);
    final client = ScriptClient([answer('完整')]);
    await openAssistantApp(tester, archive: archive, client: client);
    await showAssistantHistory(tester);
    expect(find.byKey(const ValueKey('history-old-1')), findsOneWidget);
    expect(find.text('未完成'), findsOneWidget);
    await openAssistantConversation(tester, 'old-1');
    expect(find.text('上次退出时没有完成'), findsOneWidget);
    expect(client.calls, 0);
    await tester.tap(find.text('继续'));
    await pumpFor(tester, 20);
    expect(client.calls, 1);
    expect(conversationOf(tester).messages.last.text, '完整');
  });

  for (final touch in [false, true]) {
    testWidgets('[$touch] history: list, open, rename and delete; new conversation; Esc closes the panel', (
      tester,
    ) async {
      final app = await openAssistantApp(
        tester,
        client: ScriptClient([answer('一'), answer('二')]),
        size: const Size(1800, 900),
      );
      await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
      await tester.pumpAndSettle();
      await _type(tester, '第一个问题');
      await _press(tester, LogicalKeyboardKey.enter);
      await pumpFor(tester, 20);
      final first = conversationOf(tester).id;
      expect(find.descendant(of: find.byType(MMSidebar), matching: find.text('对话')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('assistant-new')));
      await pumpFor(tester, 20);
      expect(conversationOf(tester).messages, isEmpty);
      await tester.tap(find.byKey(const ValueKey('assistant-history-button')));
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('assistant-history')), findsOneWidget);
      expect(find.textContaining('1 个问题'), findsOneWidget);
      if (touch) {
        await tester.longPress(find.byKey(ValueKey('history-$first')));
        await tester.pumpAndSettle();
        expect(find.text('重命名…'), findsOneWidget);
        await _press(tester, LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(ValueKey('history-$first')));
      await pumpFor(tester, 20);
      expect(conversationOf(tester).id, first);
      // Rename and delete through the history row's menu.
      await showAssistantHistory(tester);
      if (touch) {
        await tester.longPress(find.byKey(ValueKey('history-$first')));
      } else {
        await tester.tap(
          find.byKey(ValueKey('history-$first')),
          buttons: kSecondaryButton,
          kind: PointerDeviceKind.mouse,
        );
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, '改过的名字');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(conversationOf(tester).title, '改过的名字');
      if (touch) {
        await tester.longPress(find.byKey(ValueKey('history-$first')));
      } else {
        await tester.tap(
          find.byKey(ValueKey('history-$first')),
          buttons: kSecondaryButton,
          kind: PointerDeviceKind.mouse,
        );
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除…'));
      await tester.pumpAndSettle();
      expect(find.text('已存的笔记会保留。'), findsOneWidget);
      await tester.tap(find.text('删除').last);
      await pumpFor(tester, 20);
      expect(app.archive.files.containsKey(first), isFalse);
      expect(find.byKey(ValueKey('history-$first')), findsNothing);
      // Return to the chat before checking its Escape shortcut.
      await tester.tap(find.byKey(const ValueKey('assistant-history-button')));
      await pumpFor(tester);
      // Esc in the panel closes it when nothing else is open.
      await tester.tap(find.byKey(const ValueKey('assistant-input')));
      await _press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(app.container.read(workspaceProvider('demo-1')).panel, isNull);
    });
  }

  for (final width in [1000.0, 1400.0]) {
    testWidgets('history conversations preserve sidebar visibility and manual choices at $width pt', (tester) async {
      final archive = MemoryConversationArchive();
      for (final id in ['saved-1', 'saved-2']) {
        final state = sdk.AgentState(sessionId: id);
        state.metadata['assistant.view'] = Conversation(
          id: id,
          studySetId: 'demo-1',
          title: id,
          model: const AssistantModel(
            provider: AssistantProvider.claude,
            model: 'm',
            endpoint: 'https://x/v1/messages',
          ),
          messages: [Message(id: '$id-question', requestId: id, role: MessageRole.user, text: '已保存的问题')],
        ).toJson();
        await archive.save(state);
      }
      final app = await openAssistantApp(tester, archive: archive, size: Size(width, 800));
      bool sidebarShown() => tester.widget<MMWindowScaffold>(find.byType(MMWindowScaffold)).sidebarVisible;
      final sidebar = find.byType(MMSidebar);
      expect(find.descendant(of: sidebar, matching: find.text('对话')), findsNothing);
      expect(find.descendant(of: sidebar, matching: find.text('saved-1')), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-new-conversation')), findsNothing);
      for (final id in ['saved-1', 'saved-2']) {
        await openAssistantConversation(tester, id);
        expect(conversationOf(tester).id, id);
        expect(sidebarShown(), isTrue);
        expect(app.container.read(workspaceProvider('demo-1')).sidebarAutoCollapsed, isFalse);
        expect(tester.widget<MMSplitView>(find.byType(MMSplitView)).mode, MMSplitMode.split);
      }
      expect(find.byKey(const ValueKey('assistant-close')), findsNothing);
      await _type(tester, '还没发送的草稿');
      final historyButton = find.byKey(const ValueKey('assistant-history-button'));
      await tester.tap(find.byKey(const ValueKey('assistant-title')));
      await tester.pump();
      expect(find.byKey(const ValueKey('assistant-history')), findsNothing);
      await tester.tap(historyButton);
      await pumpFor(tester);
      expect(tester.widget<MMToolbarButton>(historyButton).selected, isTrue);
      await tester.tap(historyButton);
      await pumpFor(tester);
      expect(tester.widget<MMToolbarButton>(historyButton).selected, isFalse);
      expect(tester.widget<EditableText>(find.byType(EditableText).last).controller.text, '还没发送的草稿');

      // A manual hide survives closing and reopening the conversation panel.
      await tester.tap(find.byIcon(MMIcons.sidebar).hitTestable().first);
      await tester.pumpAndSettle();
      expect(sidebarShown(), isFalse);
      await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
      await tester.pumpAndSettle();
      expect(sidebarShown(), isFalse);
      await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
      await tester.pumpAndSettle();
      expect(sidebarShown(), isFalse);
      await tester.tap(find.byIcon(MMIcons.sidebar).hitTestable().first);
      await tester.pumpAndSettle();
      expect(sidebarShown(), isTrue);
      expect(app.container.read(workspaceProvider('demo-1')).panel, RightPanel.assistant);
      app.workspace.closePanel();
      await tester.pumpAndSettle();
      expect(sidebarShown(), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('narrow window and dark appearance keep the panel usable', (tester) async {
    final app = await openAssistantApp(tester, size: const Size(1000, 700), prefs: {'settings.appearance': 'dark'});
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AssistantPanel)).width, MMSizes.rightPanelNarrowWidth);
    expect(app.container.read(workspaceProvider('demo-1')).panel, RightPanel.assistant);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sources: numbered row, drawer over the panel, browser, Esc closes the drawer first', (tester) async {
    final archive = MemoryConversationArchive();
    final state = sdk.AgentState(sessionId: 'web-1');
    final web = Citation(
      marker: '[source:1]',
      sourceId: 's1',
      version: 1,
      title: '快照标题',
      fetchedAt: DateTime(2026, 10, 27, 12, 30),
      snapshotFile: 'research/snapshots/s1.md',
      url: 'https://www.example.org/anchoring',
      quote: '被引用的段落',
    );
    state.metadata['assistant.view'] = Conversation(
      id: 'web-1',
      studySetId: 'demo-1',
      title: '查证：锚定',
      model: const AssistantModel(provider: AssistantProvider.claude, model: 'm', endpoint: 'https://x/v1/messages'),
      messages: [
        Message(id: '1-1', requestId: 'r', role: MessageRole.user, text: '可靠吗', skill: 'verify'),
        Message(
          id: '1-2',
          requestId: 'r',
          role: MessageRole.agent,
          text: '> 部分可靠\n见 [source:1] 与 [链接](https://example.org/more)。',
          citations: [web],
          online: true,
          traces: const [
            TraceStep('t1', 'web_search', TraceStatus.done),
            TraceStep('t2', 'fetch_source', TraceStatus.error),
          ],
        ),
      ],
    ).toJson();
    await archive.save(state);
    final app = await openAssistantApp(tester, archive: archive);
    await openAssistantConversation(tester, 'web-1');
    // The process: worked for a while, one tool call failed.
    expect(find.textContaining('处理了'), findsOneWidget);
    expect(find.text(' · 工具调用失败 1 次'), findsOneWidget);
    expect(find.text('未联网'), findsNothing);
    expect(find.text('快照标题'), findsOneWidget);
    // The link opens in the browser.
    await tester.tap(find.text('链接'));
    await tester.pump();
    expect(app.links.opened.single, Uri.parse('https://example.org/more'));
    // The inline [1] and the row open the same drawer.
    await tester.tap(find.byType(CitationChip));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('source-drawer')), findsOneWidget);
    expect(find.text('[1] 网页'), findsOneWidget);
    final drawer = find.byKey(const ValueKey('source-drawer'));
    expect(find.descendant(of: drawer, matching: find.text('快照标题')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.textContaining('2026')), findsOneWidget);
    expect(find.text('被引用的段落'), findsOneWidget);
    await tester.tap(find.text('在浏览器打开'));
    await tester.pump();
    expect(app.links.opened.last, Uri.parse(web.url!));
    await _press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('source-drawer')), findsNothing);
    expect(app.container.read(workspaceProvider('demo-1')).panel, RightPanel.assistant);
    await tester.tap(find.text('快照标题'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('source-drawer')), findsNothing);
  });

  testWidgets('each failure kind has its reason and its one next step', (tester) async {
    final archive = MemoryConversationArchive();
    final state = sdk.AgentState(sessionId: 'errors-1');
    var n = 0;
    Message failed(ResearchFailureKind kind) => Message(
      id: '9-${n++}',
      requestId: 'r$n',
      role: MessageRole.agent,
      text: '',
      status: MessageStatus.error,
      errorKind: kind,
    );
    state.metadata['assistant.view'] = Conversation(
      id: 'errors-1',
      studySetId: 'demo-1',
      title: '错误',
      model: const AssistantModel(provider: AssistantProvider.claude, model: 'm', endpoint: 'https://x/v1/messages'),
      messages: [
        Message(id: '8-0', requestId: 'r1', role: MessageRole.user, text: '问', skill: 'verify'),
        failed(ResearchFailureKind.network),
        failed(ResearchFailureKind.rateLimited),
        failed(ResearchFailureKind.budget),
        failed(ResearchFailureKind.refusal),
        failed(ResearchFailureKind.protocol),
        Message(id: '9-9', requestId: 'r1', role: MessageRole.agent, text: '没联网的回答'),
      ],
    ).toJson();
    await archive.save(state);
    await openAssistantApp(
      tester,
      archive: archive,
      client: ScriptClient([answer('重试后')]),
      prefs: {'assistant.model.ollama': 'llama', 'assistant.localEnabled': true},
    );
    await openAssistantConversation(tester, 'errors-1');
    for (final reason in ['网络不可用', '服务暂时不可用', '超出本次上限', '模型拒绝回答', '请求失败']) {
      expect(find.text(reason), findsOneWidget, reason: reason);
    }
    expect(find.text('改用本机模型'), findsOneWidget);
    // A verification answered without the network says so.
    expect(find.text('未联网'), findsOneWidget);
    await tester.tap(find.text('改用本机模型'));
    await pumpFor(tester, 20);
    expect(conversationOf(tester).model.provider, AssistantProvider.ollama);
    expect(conversationOf(tester).online, false);
    // The retried answer takes the failed one's place.
    expect(conversationOf(tester).messages, hasLength(7));
    expect(conversationOf(tester).messages[1].text, '重试后');
    expect(find.text('网络不可用'), findsNothing);
  });

  testWidgets('the window composition runs and reports a bad endpoint', (tester) async {
    await openAssistantApp(
      tester,
      realFactory: true,
      prefs: {'assistant.endpoint.claude': 'http://insecure.example/v1/messages'},
    );
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    await _type(tester, '问');
    await _press(tester, LogicalKeyboardKey.enter);
    await pumpFor(tester, 20);
    expect(conversationOf(tester).messages.last.status, MessageStatus.error);
    expect(find.text('请求失败'), findsOneWidget);
  });

  testWidgets('a migrated research conversation is read only: no input, copy only', (tester) async {
    final archive = MemoryConversationArchive();
    final state = sdk.AgentState(sessionId: 'legacy-1');
    state.metadata['assistant.view'] = Conversation(
      id: 'legacy-1',
      studySetId: 'demo-1',
      title: '旧研究',
      readOnly: true,
      model: const AssistantModel(provider: AssistantProvider.claude, model: 'm', endpoint: 'https://x/v1/messages'),
      messages: [
        Message(id: '5-1', requestId: 'r', role: MessageRole.user, text: '旧问题'),
        Message(id: '5-2', requestId: 'r', role: MessageRole.agent, text: '旧回答'),
      ],
    ).toJson();
    await archive.save(state);
    await openAssistantApp(tester, archive: archive);
    await openAssistantConversation(tester, 'legacy-1');
    expect(find.text('旧回答'), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-input')), findsNothing);
    expect(find.byKey(const ValueKey('assistant-copy-5-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-save-5-2')), findsNothing);
    expect(find.byKey(const ValueKey('assistant-regenerate-5-2')), findsNothing);
    // A new conversation brings the input back.
    await tester.tap(find.byKey(const ValueKey('assistant-new')));
    await pumpFor(tester, 20);
    expect(find.byKey(const ValueKey('assistant-input')), findsOneWidget);
  });
}
