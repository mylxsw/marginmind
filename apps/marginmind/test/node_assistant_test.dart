import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/assistant_reader.dart';
import 'package:marginmind/features/assistant/assistant_scope.dart';
import 'package:marginmind/features/assistant/widgets/assistant_panel.dart';
import 'package:marginmind/features/assistant/widgets/assistant_quick_actions.dart';
import 'package:marginmind/features/workspace/widgets/map_selection_bar.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:mm_assistant/mm_assistant.dart' show createAssistantRun, scopeFromContexts;
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_design/mm_design.dart';

import 'assistant_support.dart';
import 'helpers.dart';
import 'map_keyboard_test.dart' show focusMap, key, canvas;

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN3cAAAAASUVORK5CYII=',
);

Future<void> _open(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('node-bar-assistant'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.byType(AssistantQuickActions), findsOneWidget);
  expect(find.byType(AssistantPanel), findsNothing);
}

Future<void> _capture(WidgetTester tester, String name, {Rect? region}) async {
  final output = Platform.environment['MM_SCREENSHOTS'];
  if (output == null) return;
  final pane = tester.renderObject<RenderBox>(find.byType(MapPane));
  final bounds = pane.localToGlobal(Offset.zero) & pane.size;
  final rect = region == null ? bounds : region.intersect(bounds);
  final image = (await tester.runAsync(
    () => (tester.binding.renderViews.first.debugLayer! as OffsetLayer).toImage(rect, pixelRatio: 2),
  ))!;
  final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  await tester.runAsync(() => File('$output/$name.png').writeAsBytes(bytes.buffer.asUint8List()));
  image.dispose();
}

void main() {
  setUpAll(() async {
    if (Platform.environment['MM_SCREENSHOTS'] == null) return;
    Directory(Platform.environment['MM_SCREENSHOTS']!).createSync(recursive: true);
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
    await (FontLoader(
      'packages/lucide_icons_flutter/Lucide',
    )..addFont(rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets('all node types and multi-selection offer the local assistant', (tester) async {
    final app = await openAssistantApp(tester);
    final workspace = app.workspace;
    await workspace.rename('c6', '自定义摘录标题');
    await workspace.insertImages(bytes: _png);
    final image = workspace.content.cards.last;
    await workspace.excerptArea(
      'c1',
      const MMPdfArea(page: 1, rect: PageRect(0, 0, 100, 100), viewportRect: Rect.zero),
      () async => _png,
    );
    final area = workspace.content.cards.last;
    final note = await workspace.addNote('note');
    for (final id in ['c3', 'c6', note.id, image.id, area.id]) {
      workspace.selectCard(id);
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(MapNodeBar), matching: find.byType(Text)), findsNothing);
      await _open(tester);
      final popup = tester.widget<AssistantQuickActions>(find.byType(AssistantQuickActions));
      expect(popup.passage.nodeId, id);
      if (id == 'c6') {
        expect(popup.passage.displayText, contains('自定义摘录标题'));
        expect(popup.passage.displayText, contains('遗忘曲线'));
      }
      expect(popup.insertionTarget?.parentId, id);
      await key(tester, LogicalKeyboardKey.escape);
    }
    workspace.selectCards(['c3', image.id]);
    await tester.pumpAndSettle();
    await _open(tester);
    final multi = tester.widget<AssistantQuickActions>(find.byType(AssistantQuickActions));
    expect(multi.contexts.map((item) => item.nodeId), unorderedEquals(['c3', image.id]));
    await key(tester, LogicalKeyboardKey.escape);
    workspace.selectMapRoot();
    await tester.pumpAndSettle();
    await _open(tester);
    final root = tester.widget<AssistantQuickActions>(find.byType(AssistantQuickActions));
    expect(root.passage.nodeId, assistantRootId);
    expect(root.insertionTarget?.mapId, MindMap.defaultId);
    expect(root.insertionTarget?.parentId, isNull);
    await key(tester, LogicalKeyboardKey.escape);
    await settleHud(tester);
  });

  testWidgets('image question, follow-up and insertion keep the original node and support undo', (tester) async {
    final app = await openAssistantApp(
      tester,
      realWrites: true,
      client: ScriptClient([answer('图片的解读'), answer('补充说明')]),
    );
    await app.workspace.insertImages(bytes: _png);
    final image = app.workspace.content.cards.last;
    app.workspace.selectCard(image.id);
    await tester.pumpAndSettle();
    await _capture(tester, 'node-icon-menu');
    await _open(tester);
    await _capture(tester, 'node-local-assistant');
    await tester.enterText(find.byKey(const ValueKey('quick-input')), '解释这张图片');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quick-send')));
    await pumpFor(tester, 25);
    final controller = ProviderScope.containerOf(tester.element(find.byType(AssistantQuickActions)))
        .read(assistantControllerProvider.notifier);
    expect(controller.state.messages.first.contexts.single.nodeId, image.id);
    await tester.enterText(find.byKey(const ValueKey('quick-input')), '再解释一下');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quick-send')));
    await pumpFor(tester, 25);
    expect(controller.state.messages.where((m) => m.role == MessageRole.user), hasLength(2));
    final reply = controller.state.messages.last;
    app.workspace.selectCard('c4');
    await tester.pumpAndSettle();
    final save = find.byKey(ValueKey('assistant-save-${reply.id}'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpFor(tester, 25);
    final note = app.workspace.content.researchNotes.single;
    final card = app.workspace.content.cards.singleWhere((card) => card.researchNoteId == note.id);
    expect(note.body, '补充说明');
    expect(app.workspace.content.node(card.id)!.parentId, image.id);
    expect(app.workspace.content.node(card.id)!.mapId, MindMap.defaultId);
    await _capture(tester, 'node-answer-inserted');
    await key(tester, LogicalKeyboardKey.escape);
    await app.workspace.undo();
    await tester.pumpAndSettle();
    expect(app.workspace.content.card(card.id), isNull);
    expect(app.workspace.content.card(image.id), isNotNull);
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });

  testWidgets('image highlights also expose the same quick assistant', (tester) async {
    final app = await openAssistantApp(tester);
    await app.workspace.excerptArea(
      'c1',
      const MMPdfArea(page: 1, rect: PageRect(0, 0, 100, 100), viewportRect: Rect.zero),
      () async => _png,
    );
    final card = app.workspace.content.cards.last;
    app.workspace.tapHighlight(card.annotationId!);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-assistant')));
    await tester.pumpAndSettle();
    expect(find.byType(AssistantQuickActions), findsOneWidget);
    expect(tester.widget<AssistantQuickActions>(find.byType(AssistantQuickActions)).passage.nodeId, card.id);
    await key(tester, LogicalKeyboardKey.escape);
    app.workspace.dismissPending();
    await settleHud(tester);
  });

  testWidgets('the advertised shortcut opens the local node popup', (tester) async {
    final app = await openAssistantApp(tester);
    app.workspace.selectCard('c3');
    await tester.pumpAndSettle();
    await focusMap(tester);
    final shortcut = AppShortcuts.askAssistant;
    await key(tester, shortcut.trigger, primary: true, shift: shortcut.shift);
    expect(find.byType(AssistantQuickActions), findsOneWidget);
    expect(find.byType(AssistantPanel), findsNothing);
    await key(tester, LogicalKeyboardKey.escape);
    await settleHud(tester);
  });

  testWidgets(
    'node menus and local assistant visual evidence',
    (tester) async {
      final app = await openAssistantApp(
        tester,
        size: const Size(1280, 900),
        realWrites: true,
        prefs: {'settings.appearance': 'dark'},
        client: ScriptClient([
          answer(
            '**遗忘的速度会逐渐放慢。**\n\n刚学完时忘得快，之后逐渐变慢，所以复习应该尽早开始。\n\n**复习建议**\n\n- 学完后先尝试回忆一次。\n- 根据记忆情况，逐步拉长复习间隔。\n- 先主动回忆，再回看原文。',
          ),
        ]),
      );
      app.workspace.setLayout(MMSplitMode.secondary);
      app.workspace.selectCard('c3');
      await app.workspace.excerpt(
        'c1',
        const MMPdfSelection(page: 25, rects: [PageRect(10, 100, 220, 80)], text: '主动回忆比反复重读更能巩固记忆。'),
        MMAnnotationColor.yellow,
      );
      final second = app.workspace.content.cards.last.id;
      await settleHud(tester);
      Future<void> center(String id) async {
        app.workspace.selectCard(id);
        await tester.pumpAndSettle();
        await focusMap(tester);
        Actions.invoke(canvas(tester).focusNode.context!, const MindMapIntent(MindMapCommand.center));
        await tester.pumpAndSettle();
      }

      Rect nodeRect(String id) => tester.getRect(find.byKey(ValueKey(id)));
      await center('c6');
      var region = nodeRect('c6').expandToInclude(tester.getRect(find.byType(MapNodeBar))).inflate(28);
      await _capture(tester, '01-single-node-icons', region: region);
      app.workspace.selectCards(['c6', second]);
      await tester.pumpAndSettle();
      region = nodeRect('c6')
          .expandToInclude(nodeRect(second))
          .expandToInclude(tester.getRect(find.byType(MapSelectionBar)))
          .inflate(28);
      await _capture(tester, '02-multi-node-icons', region: region);
      await center('c6');
      await tester.tap(find.byKey(const ValueKey('node-bar-assistant')), kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      final popup = find.byType(AssistantQuickActions);
      region = nodeRect('c6')
          .expandToInclude(tester.getRect(popup))
          .expandToInclude(tester.getRect(find.byType(MapNodeBar)))
          .inflate(28);
      await _capture(tester, '03-local-ai-popup', region: region);
      await tester.enterText(find.byKey(const ValueKey('quick-input')), '帮我解释遗忘曲线，并给出复习建议');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('quick-send')), kind: ui.PointerDeviceKind.mouse);
      await pumpFor(tester, 25);
      final controller = ProviderScope.containerOf(tester.element(popup)).read(assistantControllerProvider);
      final save = find.byKey(ValueKey('assistant-save-${controller.messages.last.id}'));
      await tester.ensureVisible(save);
      region = tester.getRect(popup).inflate(40);
      await _capture(tester, '04-ai-answer-insert-action', region: region);
      await tester.tap(save, kind: ui.PointerDeviceKind.mouse);
      await pumpFor(tester, 25);
      await key(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final child = app.workspace.content.cards.singleWhere((card) => card.researchNoteId != null);
      expect(app.workspace.content.node(child.id)!.parentId, 'c6');
      await center(child.id);
      region = nodeRect('c6')
          .expandToInclude(nodeRect(child.id))
          .expandToInclude(tester.getRect(find.byType(MapNodeBar)))
          .inflate(28);
      await _capture(tester, '05-answer-as-child-node', region: region);
      await settleHud(tester);
    },
    skip: Platform.environment['MM_SCREENSHOTS'] == null,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  test('selected image bytes reach the model; branches never bulk-upload images', () async {
    final directory = await Directory.systemTemp.createTemp('marginmind-node-images-');
    addTearDown(() => directory.delete(recursive: true));
    final name = 'images/${'a' * 64}.png';
    final file = File('${directory.path}/$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(_png);
    final content = StudySetContent(
      cards: [Card(id: 'picture', kind: CardKind.image, imageFileName: name, createdAt: testNow)],
      nodes: const [MapNode(cardId: 'picture', parentId: null, order: 0)],
    );
    final item = nodeContext(mapId: MindMap.defaultId, nodeId: 'picture', title: '图片');
    final images = await loadAssistantNodeImages(
      content: content,
      contexts: [item, item],
      imagePath: (name) => '${directory.path}/$name',
    );
    expect(images, hasLength(1));
    final client = ScriptClient([answer('看到了图片')]);
    final run = createAssistantRun(
      client: client,
      model: 'fake',
      state: sdk.AgentState(sessionId: 'image'),
      requestId: 'request',
      reader: WorkspaceReader(
        content: () => content,
        contexts: [item],
        filePath: (_) => '',
        pageText: (_, _) async => null,
      ),
      scope: scopeFromContexts('set', [item]),
      mapId: MindMap.defaultId,
      baseRevision: 0,
      parents: {MindMap.defaultId: null, 'picture': MindMap.defaultId},
      images: images,
    );
    await run.run('解释图片').toList();
    final user = client.requests.single.whereType<sdk.UserMessage>().last;
    expect(user.contents.whereType<sdk.ImagePart>().single.base64Data, base64Encode(_png));
    expect(user.contents.whereType<sdk.ImagePart>().single.mimeType, 'image/png');
    expect(
      await loadAssistantNodeImages(
        content: content,
        contexts: [nodeContext(mapId: MindMap.defaultId, nodeId: assistantRootId, title: 'map', branch: true)],
        imagePath: (name) => '${directory.path}/$name',
      ),
      isEmpty,
    );
    var nextId = 0;
    final editor = StudySetEditor(newId: () => 'area-${++nextId}', now: () => testNow);
    final (withDoc, doc) = editor.addDocument(StudySetContent.empty, title: 'Book', fileName: 'a.pdf', pageCount: 1);
    final (withArea, areaCard) = editor.createAreaExcerpt(
      withDoc,
      documentId: doc.id,
      page: 1,
      rect: const PageRect(0, 0, 100, 100),
      imageFileName: name,
      colorIndex: 0,
    );
    final detached = withArea.copyWith(nodes: const []);
    final areaContext = imageAreaContext(
      annotation: detached.annotation(areaCard.annotationId!)!,
      cardId: areaCard.id,
      title: '截图',
    );
    expect(
      await loadAssistantNodeImages(
        content: detached,
        contexts: [areaContext],
        imagePath: (name) => '${directory.path}/$name',
      ),
      hasLength(1),
    );
    await file.delete();
    expect(
      loadAssistantNodeImages(content: content, contexts: [item], imagePath: (name) => '${directory.path}/$name'),
      throwsA(isA<ResearchFailure>()),
    );
  });
}
