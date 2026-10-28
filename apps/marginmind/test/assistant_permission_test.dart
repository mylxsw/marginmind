import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/assistant_reader.dart';

import 'assistant_support.dart';

Future<void> openPanel(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
  await tester.pumpAndSettle();
}

void main() {
  for (final allow in [true, false]) {
    testWidgets('additional read waits for the user to ${allow ? 'allow' : 'deny'} it', (tester) async {
      final client = ScriptClient([
        call('read_branch', '{"mapId":"main","nodeId":"__root__"}'),
        answer(allow ? '已根据脑图内容回答。' : '仅根据已有资料回答。'),
      ]);
      final app = await openAssistantApp(tester, client: client, size: const Size(1000, 700));
      await openPanel(tester);
      final execution = assistantOf(tester).send('帮我梳理一下内容');
      await pumpFor(tester);
      final before = conversationOf(tester).messages.last;
      expect(before.status, MessageStatus.running);
      expect(before.waitingForPermission, true);
      expect(before.traces.single.status, TraceStatus.running);
      expect(client.calls, 1);
      expect(find.text('需要你的授权'), findsOneWidget);
      expect(find.text('等待授权'), findsOneWidget);
      expect(find.text('整张脑图'), findsOneWidget);
      expect(find.byKey(const ValueKey('assistant-cursor')), findsNothing);
      final id = before.permissions.single.request.id;
      final storedBefore = jsonDecode(app.archive.files[conversationOf(tester).id]!) as Map;
      expect(storedBefore['metadata']['assistant.view']['messages'].last['permissions'].single['status'], 'pending');
      final button = find.byKey(ValueKey('permission-${allow ? 'allow' : 'deny'}-$id'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await pumpFor(tester);
      await execution;
      final after = conversationOf(tester).messages.last;
      expect(after.status, MessageStatus.done);
      expect(after.waitingForPermission, false);
      expect(after.permissions.single.status, allow ? ReadPermissionStatus.allowed : ReadPermissionStatus.denied);
      expect(after.traces.single.status, allow ? TraceStatus.done : TraceStatus.denied);
      expect(find.byKey(const ValueKey('timeline-failures')), findsNothing);
      final resultText = jsonEncode(client.requests.last.last.toJson());
      expect(resultText.contains('遗忘的规律'), allow);
      expect(find.text(allow ? '已根据脑图内容回答。' : '仅根据已有资料回答。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await assistantOf(tester).resolveReadPermission(after.id, id, allow: !allow);
      expect(conversationOf(tester).messages.last.permissions.single.status, after.permissions.single.status);
    });
  }

  testWidgets('stop cancels a pending read; restored history never resumes an old permission request', (tester) async {
    final client = ScriptClient([call('read_branch', '{"mapId":"main","nodeId":"__root__"}')]);
    final app = await openAssistantApp(tester, client: client);
    await openPanel(tester);
    final controller = assistantOf(tester);
    final execution = controller.send('读取脑图');
    await pumpFor(tester);
    final conversation = conversationOf(tester);
    final pending = conversation.messages.last;
    final permissionId = pending.permissions.single.request.id;
    final savedPending = app.archive.files[conversation.id]!;
    await controller.stop();
    await execution;
    await pumpFor(tester);
    final stopped = conversationOf(tester).messages.last;
    expect(stopped.status, MessageStatus.stopped);
    expect(stopped.permissions.single.status, ReadPermissionStatus.cancelled);
    expect(find.byKey(ValueKey('permission-allow-$permissionId')), findsNothing);
    await controller.resolveReadPermission(stopped.id, permissionId, allow: true);
    expect(client.calls, 1);

    await controller.newConversation();
    app.archive.files[conversation.id] = savedPending;
    await controller.openConversation(conversation.id);
    await pumpFor(tester);
    final restored = conversationOf(tester).messages.last;
    expect(restored.status, MessageStatus.interrupted);
    expect(restored.permissions.single.status, ReadPermissionStatus.cancelled);
    expect(find.text('请求已取消'), findsOneWidget);
    expect(find.byKey(ValueKey('permission-allow-$permissionId')), findsNothing);
    expect(client.calls, 1);
  });

  testWidgets('permission resolver offers only existing targets in the current study set', (tester) async {
    final app = await openAssistantApp(tester);
    final reader = WorkspaceReader(
      content: () => app.workspace.content,
      contexts: const [],
      filePath: (document) => document.fileName,
      pageText: (_, _) async => throw StateError('describing a request must not read content'),
    );
    expect(reader.describeReadPermission('read_pages', {'documentId': 'outside', 'from': 1, 'to': 1}), isNull);
    expect(reader.describeReadPermission('read_pages', {'documentId': 'c1', 'from': 164, 'to': 165}), isNull);
    expect(reader.describeReadPermission('read_branch', {'mapId': 'outside', 'nodeId': '__root__'}), isNull);
    expect(reader.describeReadPermission('read_branch', {'mapId': 'main', 'nodeId': 'missing'}), isNull);
    final request = reader.describeReadPermission('read_pages', {'documentId': 'c1', 'from': 23, 'to': 25});
    expect(request!.title, '学习的底层逻辑');
    expect([request.from, request.to], [23, 25]);
  });
}
