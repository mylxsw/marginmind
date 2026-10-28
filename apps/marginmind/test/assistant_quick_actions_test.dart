import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/assistant_scope.dart';
import 'package:marginmind/features/assistant/widgets/assistant_quick_actions.dart';
import 'package:marginmind/features/assistant/widgets/assistant_panel.dart';
import 'package:marginmind/features/workspace/widgets/selection_toolbar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'assistant_support.dart';
import 'assistant_background_test.dart' show GatedClient;
import 'helpers.dart';

const quote = '互联网的可借鉴之处是它改变了做事方式，使信息传送的层级减少。';
const response = '这里的重点是**信息流通方式**。\n\n过去，一条信息需要经过多层管理者才能传到员工手里；在线社区让员工直接看到信息、表达意见，减少了中间环节。\n\n> 简单说：让信息少绕路，让沟通更直接。';
final _output = Platform.environment['MM_SCREENSHOTS'];

ProviderContainer scope(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SelectionToolbar)));
Conversation view(WidgetTester tester) => scope(tester).read(assistantControllerProvider);

Future<void> select(WidgetTester tester, AssistantApp app, {Rect rect = const Rect.fromLTWH(100, 150, 250, 40)}) async {
  await app.workspace.onSelectionCommitted(
    'c1',
    MMPdfSelection(page: 24, rects: const [PageRect(10, 100, 200, 50)], text: quote, viewportRect: rect),
  );
  await tester.pumpAndSettle();
}

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('selection-assistant')));
  await pumpFor(tester, 16);
  expect(find.byType(AssistantQuickActions), findsOneWidget);
}

Future<void> screenshot(WidgetTester tester, String name) async {
  if (_output == null) return;
  final box = tester.renderObject<RenderBox>(find.byKey(const ValueKey('assistant-quick-actions')));
  final rect = box.localToGlobal(Offset.zero) & box.size;
  final image = (await tester.runAsync(() {
    final renderView = tester.binding.renderViews.first;
    return (renderView.debugLayer! as OffsetLayer).toImage(rect, pixelRatio: 2);
  }))!;
  final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  await tester.runAsync(() => File('$_output/$name.png').writeAsBytes(bytes.buffer.asUint8List()));
  image.dispose();
}

void main() {
  setUpAll(() async {
    if (_output == null) return;
    Directory(_output!).createSync(recursive: true);
    final font = Platform.environment['MM_FONT'] ?? '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
    final data = ByteData.sublistView(File(font).readAsBytesSync());
    for (final family in [
      '.AppleSystemUIFont',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'Songti SC',
    ]) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
    final pub = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
    final iconDir = Directory('$pub/hosted/pub.dev')
        .listSync()
        .whereType<Directory>()
        .lastWhere((d) => d.path.contains('cupertino_icons-'));
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          Future.value(ByteData.sublistView(File('${iconDir.path}/assets/CupertinoIcons.ttf').readAsBytesSync())),
        ))
        .load();
  });

  for (final dark in [false, true]) {
    testWidgets('local explain, copy, source note, follow-up and same-conversation sidebar dark=$dark', (tester) async {
      final client = ScriptClient([answer(response), answer('信息传达更直接。')]);
      final app = await openAssistantApp(
        tester,
        client: client,
        size: const Size(1440, 1024),
        prefs: {if (dark) 'settings.appearance': 'dark'},
        realWrites: true,
      );
      app.workspace.setLayout(MMSplitMode.primary);
      await select(tester, app);
      final pending = app.container.read(workspaceProvider('demo-1')).pending;
      await open(tester);
      expect(client.calls, 0);
      expect(find.byType(AssistantPanel), findsNothing);
      expect(app.container.read(workspaceProvider('demo-1')).pending, same(pending));
      await screenshot(tester, 'quick-actions-${dark ? 'dark' : 'light'}');
      await tester.tap(find.byKey(const ValueKey('quick-action-explain')));
      await pumpFor(tester, 25);
      expect(view(tester).messages.first.contexts.single.displayText, quote);
      expect(view(tester).messages.first.skill, 'explain');
      expect(view(tester).messages.last.status, MessageStatus.done);
      expect(find.byType(AssistantPanel), findsNothing);
      final id = view(tester).id;
      await screenshot(tester, 'quick-answer-${dark ? 'dark' : 'light'}');
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      await tester.tap(find.byKey(const ValueKey('quick-copy')));
      await tester.pump();
      expect(copied, contains('信息流通方式'));
      await tester.tap(find.byKey(const ValueKey('quick-save')));
      await pumpFor(tester);
      expect(view(tester).messages.last.noteId, isNotNull);
      final saved = app.workspace.content.researchNotes.single;
      expect(saved.body, response);
      expect(saved.conversationId, id);
      expect(app.workspace.content.noteAttachments.single.target, isA<PdfTarget>());
      expect((app.workspace.content.noteAttachments.single.target as PdfTarget).quote, quote);
      await tester.enterText(find.byKey(const ValueKey('quick-input')), '再简短一点');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpFor(tester, 25);
      expect(view(tester).id, id);
      expect(view(tester).messages.length, 4);
      expect(view(tester).messages.last.text, '信息传达更直接。');
      await tester.tap(find.byKey(const ValueKey('quick-sidebar')));
      await pumpFor(tester);
      expect(find.byType(AssistantQuickActions), findsNothing);
      expect(find.byType(AssistantPanel), findsOneWidget);
      expect(conversationOf(tester).id, id);
      expect(conversationOf(tester).messages.length, 4);
      expect(app.container.read(workspaceProvider('demo-1')).pending, isNull);
      expect(tester.takeException(), isNull);
      await settleHud(tester);
    });
  }

  testWidgets('opening, Esc and outside click keep selection and existing chat intact', (tester) async {
    final client = ScriptClient([answer('原来的回答')]);
    final app = await openAssistantApp(tester, client: client);
    await select(tester, app);
    final originalRun = scope(tester).read(assistantControllerProvider.notifier).send('原来的问题');
    await pumpFor(tester, 25);
    await originalRun;
    final original = view(tester).id;
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AssistantQuickActions), findsNothing);
    expect(find.byType(SelectionToolbar), findsOneWidget);
    expect(view(tester).id, original);
    await open(tester);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byType(AssistantQuickActions), findsNothing);
    expect(find.byType(SelectionToolbar), findsOneWidget);
    expect(client.calls, 1);
  });

  testWidgets('new passage conversation does not inherit chat history or sidebar attachments', (tester) async {
    final app = await openAssistantApp(tester, client: ScriptClient([answer('之前'), answer('本次')]));
    await select(tester, app);
    final container = scope(tester);
    final controller = container.read(assistantControllerProvider.notifier);
    final oldRun = controller.send('旧对话');
    await pumpFor(tester, 25);
    await oldRun;
    final old = view(tester).id;
    final unrelated = nodeContext(mapId: 'main', nodeId: 'unrelated', title: '其他引用');
    app.container.read(assistantUiProvider('demo-1').notifier).addContext(unrelated);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('quick-action-summarize')));
    await pumpFor(tester, 25);
    expect(view(tester).id, isNot(old));
    expect(view(tester).messages.length, 2);
    expect(view(tester).messages.first.contexts.length, 1);
    expect(app.container.read(assistantUiProvider('demo-1')).contexts, [unrelated]);
    final previous = await app.archive.loadOrCreate(old, null);
    expect(
      Conversation.fromJson(Map<String, dynamic>.from(previous.metadata['assistant.view'])).messages.first.text,
      '旧对话',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await open(tester);
    expect(view(tester).messages.last.text, '本次');
    expect(find.byKey(const ValueKey('quick-copy')), findsOneWidget);
  });

  testWidgets('closing a running answer keeps it alive and reopening resumes it; stop works', (tester) async {
    final stream = StreamController<sdk.StreamingMessage>();
    final app = await openAssistantApp(tester, client: StreamClient((_) => stream.stream));
    await select(tester, app);
    final container = scope(tester);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('quick-action-explain')));
    await pumpFor(tester);
    expect(view(tester).running, isTrue);
    final id = view(tester).id;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(assistantControllerProvider).running, isTrue);
    await open(tester);
    expect(view(tester).id, id);
    expect(tester.widget<MMIconButton>(find.byKey(const ValueKey('quick-send'))).icon, MMIcons.stop);
    await tester.tap(find.byKey(const ValueKey('quick-send')));
    await pumpFor(tester);
    expect(view(tester).running, isFalse);
    expect(view(tester).messages.last.status, MessageStatus.stopped);
    await stream.close();
  });

  testWidgets('unconfigured AI opens setup locally without sending', (tester) async {
    final client = ScriptClient([]);
    final app = await openAssistantApp(tester, key: false, client: client);
    await select(tester, app);
    await open(tester);
    expect(find.byKey(const ValueKey('assistant-configure-models')), findsOneWidget);
    expect(find.byType(AssistantPanel), findsNothing);
    expect(client.calls, 0);
  });

  testWidgets('highlight entry, outline and More actions use the selected passage', (tester) async {
    final app = await openAssistantApp(tester, client: ScriptClient([answer('大纲'), answer('查证结果')]));
    final annotation = app.workspace.content.annotations.first;
    app.workspace.tapHighlight(annotation.id, const Rect.fromLTWH(120, 150, 200, 40));
    await tester.pumpAndSettle();
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('quick-action-outline')));
    await pumpFor(tester, 25);
    expect(view(tester).messages.first.text, contains('不要修改脑图'));
    expect(view(tester).messages.first.skill, isNull);
    expect(view(tester).messages.first.contexts.single.displayText, annotation.quote);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-actions-more')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('quick-action-verify')));
    await tester.tap(find.byKey(const ValueKey('quick-action-verify')));
    await pumpFor(tester, 25);
    expect(view(tester).messages[2].skill, 'verify');
  });

  testWidgets('selection change dismisses the floating route', (tester) async {
    final app = await openAssistantApp(tester);
    await select(tester, app);
    await open(tester);
    app.workspace.dismissPending();
    await tester.pumpAndSettle();
    expect(find.byType(AssistantQuickActions), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('free question starts locally; unavailable credentials expose model settings in place', (tester) async {
    final app = await openAssistantApp(tester);
    await select(tester, app);
    await open(tester);
    app.secrets.values.remove('anthropic');
    await tester.enterText(find.byKey(const ValueKey('quick-input')), '这段内容的关键是什么？');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quick-send')));
    await pumpFor(tester, 25);
    expect(view(tester).messages.first.text, '这段内容的关键是什么？');
    expect(view(tester).messages.last.status, MessageStatus.error);
    expect(find.byKey(const ValueKey('assistant-open-settings')), findsOneWidget);
    expect(find.byType(AssistantPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('another running chat cannot be replaced by a quick action', (tester) async {
    final client = GatedClient([answer('另一条回答')]);
    final gate = client.gate(0);
    final app = await openAssistantApp(tester, client: client);
    await select(tester, app);
    final controller = scope(tester).read(assistantControllerProvider.notifier);
    final execution = controller.send('另一个问题');
    await pumpFor(tester);
    final id = view(tester).id;
    await open(tester);
    expect(find.text('另一个对话正在回答，完成后即可提问。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quick-action-explain')));
    await pumpFor(tester);
    expect(view(tester).id, id);
    expect(client.calls, 1);
    gate.complete();
    await pumpFor(tester, 25);
    await execution;
  });

  testWidgets('read authorization is actionable within the floating answer', (tester) async {
    final client = ScriptClient([call('read_branch', '{"mapId":"main","nodeId":"__root__"}'), answer('已读取脑图。')]);
    final app = await openAssistantApp(tester, client: client);
    await select(tester, app);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('quick-action-explain')));
    await pumpFor(tester);
    final permission = view(tester).messages.last.permissions.single;
    expect(permission.status, ReadPermissionStatus.pending);
    final allow = find.byKey(ValueKey('permission-allow-${permission.request.id}'));
    await tester.ensureVisible(allow);
    await tester.tap(allow);
    await pumpFor(tester, 25);
    expect(view(tester).messages.last.permissions.single.status, ReadPermissionStatus.allowed);
    expect(view(tester).messages.last.text, '已读取脑图。');
    expect(find.byType(AssistantPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('a tall selection leaves enough height for the floating answer', () {
    final delegate = QuickActionsPlacement(
      toolbar: const Rect.fromLTWH(600, 350, 310, 34),
      selection: const Rect.fromLTWH(395, 390, 730, 100),
      viewport: const Rect.fromLTWH(244, 100, 1036, 720),
    );
    final constraints = delegate.getConstraintsForChild(const BoxConstraints.tightFor(width: 1280, height: 820));
    expect(constraints.maxHeight, greaterThanOrEqualTo(400));
    final offset = delegate.getPositionForChild(
      const Size(1280, 820),
      Size(constraints.maxWidth, constraints.maxHeight),
    );
    expect(offset.dy, greaterThan(384));
    expect(offset.dy + constraints.maxHeight, lessThanOrEqualTo(812));
  });

  for (final size in [const Size(1000, 760), const Size(800, 600)]) {
    testWidgets('long answer fits and scrolls inside reader at $size', (tester) async {
      final app = await openAssistantApp(
        tester,
        size: size,
        client: ScriptClient([answer(List.filled(40, response).join('\n\n'))]),
      );
      app.workspace.setLayout(MMSplitMode.primary);
      await select(tester, app, rect: Rect.fromLTWH(250, size.height - 220, 200, 30));
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('quick-action-explain')));
      await pumpFor(tester, 25);
      await screenshot(tester, 'quick-answer-narrow-${size.width.toInt()}');
      final popup = tester.getRect(find.byKey(const ValueKey('assistant-quick-actions')));
      expect(popup.left, greaterThanOrEqualTo(0));
      expect(popup.right, lessThanOrEqualTo(size.width));
      expect(popup.bottom, lessThanOrEqualTo(size.height));
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: find.byKey(const ValueKey('quick-content')), matching: find.byType(Scrollable)).first,
      );
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(find.byKey(const ValueKey('quick-input')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
