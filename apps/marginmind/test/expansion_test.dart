import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Card;
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton, PointerDeviceKind;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/expansion_context.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:marginmind/features/assistant/assistant_scope.dart' show nodeContext, MemoryConversationArchive;
import 'package:marginmind/features/assistant/widgets/assistant_quick_actions.dart';
import 'package:marginmind/features/assistant/expansion_controller.dart';
import 'package:marginmind/features/assistant/assistant_reader.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/assistant/widgets/expansion_widgets.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'assistant_support.dart';
import 'helpers.dart';
import 'map_keyboard_test.dart' show key, focusMap;

class ControlledExpander implements IdeaExpander {
  final output = StreamController<ExpansionDraft>();
  final started = Completer<void>();
  final requests = <ExpansionRequest>[];
  final contexts = <ExpansionContext>[];
  int closed = 0;
  @override
  Stream<ExpansionDraft> expand(ExpansionRequest request, ExpansionContext context, CancellationToken cancel) {
    if (!started.isCompleted) started.complete();
    requests.add(request);
    contexts.add(context);
    return output.stream;
  }

  @override
  Future<List<ExpansionPlanItem>> plan(ExpansionContext context, int breadth, CancellationToken cancel) async => [];
  @override
  void close() {
    closed++;
  }
}

class BatchExpander implements IdeaExpander {
  BatchExpander(this.owner);
  final BatchModels owner;
  @override
  Future<List<ExpansionPlanItem>> plan(ExpansionContext context, int breadth, CancellationToken cancel) async {
    owner.plans++;
    owner.planContext = context;
    if (owner.planFailure != null) throw owner.planFailure!;
    if (owner.planGate != null) await owner.planGate!.future;
    return owner.items;
  }

  @override
  Stream<ExpansionDraft> expand(ExpansionRequest request, ExpansionContext context, CancellationToken cancel) async* {
    owner.active++;
    owner.maximum = owner.maximum < owner.active ? owner.active : owner.maximum;
    owner.requests.add(request);
    try {
      if (owner.gate != null) await owner.gate!.future;
      cancel.check();
      final target = context.targets.values.single;
      final count = request.scope == ExpansionScope.group ? 1 : context.limits['T1'] ?? owner.count;
      for (var i = 0; i < count; i++) {
        yield ExpansionDraft(id: '${context.draftPrefix}$i', parentRef: target, title: '思路-$target-$i');
      }
      if (owner.failure != null) throw owner.failure!;
    } finally {
      owner.active--;
    }
  }

  @override
  void close() {
    owner.closed++;
  }
}

class BatchModels {
  int active = 0, maximum = 0, closed = 0, plans = 0, count = 2;
  final requests = <ExpansionRequest>[];
  ExpansionContext? planContext;
  Completer<void>? gate, planGate;
  ResearchFailure? failure, planFailure;
  List<ExpansionPlanItem> items = const [];
  Future<IdeaExpander> create() async => BatchExpander(this);
}

Future<void> capture(WidgetTester tester, String name, {Finder? region, Rect? clip}) async {
  final output = Platform.environment['MM_SCREENSHOTS'];
  if (output == null) return;
  Directory(output).createSync(recursive: true);
  final pane = tester.renderObject<RenderBox>(
    region ?? (clip == null ? find.byType(MapPane) : find.byKey(const ValueKey('quick-actions-layer'))),
  );
  final image = await tester.runAsync(
    () => (tester.binding.renderViews.first.debugLayer! as OffsetLayer).toImage(
      clip ?? pane.localToGlobal(Offset.zero) & pane.size,
      pixelRatio: 2,
    ),
  );
  final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
  File('$output/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  image!.dispose();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.clearAccessibilityFeaturesTestValue();
  });
  setUpAll(() async {
    if (Platform.environment['MM_SCREENSHOTS'] == null) return;
    final data = ByteData.sublistView(File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf').readAsBytesSync());
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
  test('context budgets pages and structure; ungrounded never reads', () async {
    final content = demoContent(), reads = <int>[];
    final reader = WorkspaceReader(
      content: () => content,
      contexts: const [],
      filePath: (d) => d.fileName,
      pageText: (_, p) async {
        reads.add(p);
        return 'Source $p';
      },
    );
    final builder = ExpansionContextBuilder(reader);
    ExpansionRequest request({bool grounded = true, String target = 'c3'}) =>
        ExpansionRequest(studySetId: 'demo-1', mapId: MindMap.defaultId, targetIds: [target], grounded: grounded);
    final context = await builder.build(content, request(), excludedTitles: ['Old']);
    expect(context.targets, {'T1': 'c3'});
    expect(context.details['T1']!.pages.keys, [23, 24, 25]);
    expect(reads, [23, 24, 25]);
    reads.clear();
    expect((await builder.build(content, request(grounded: false))).details['T1']!.pages, isEmpty);
    expect(reads, isEmpty);
    await expectLater(builder.build(content, request(), tokenBudget: 1), throwsA(isA<ResearchFailure>()));
    await expectLater(builder.build(content, request(target: 'missing')), throwsA(isA<ResearchFailure>()));
    await expectLater(
      builder.build(content, request(), cancellation: CancellationToken()..cancel()),
      throwsA(isA<ResearchFailure>()),
    );
    final draft = await builder.build(
      content,
      request(target: 'new:d1'),
      draftTargets: [const ExpansionDraft(id: 'd1', parentRef: 'c3', title: 'Draft')],
    );
    expect(draft.details['T1']!.path, contains('遗忘的规律'));
  });
  testWidgets('stream, cascade, edit, keep, one-step undo and redo', (tester) async {
    final model = ControlledExpander();
    final app = await openAssistantApp(
      tester,
      realWrites: true,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(() async => model)],
    );
    app.workspace.selectCard('c3');
    await focusMap(tester);
    final provider = expansionControllerProvider('demo-1');
    await key(tester, LogicalKeyboardKey.tab, alt: true);
    expect(app.container.read(provider)!.phase, ExpansionPhase.generating);
    await key(tester, LogicalKeyboardKey.tab);
    expect(find.text('正在生成内容，请等待完成，或点击“停止”'), findsOneWidget);
    await capture(tester, 'expansion-generating');
    model.output.add(
      const ExpansionDraft(id: 'd1', parentRef: 'c3', title: '主动回忆', tag: ExpansionDirection.action, page: 24),
    );
    model.output.add(const ExpansionDraft(id: 'd2', parentRef: 'new:d1', title: '闭卷自测'));
    await tester.pumpAndSettle();
    expect(find.byType(MapGhostNode), findsNWidgets(2));
    expect(app.workspace.content.card('d1'), isNull);
    await model.output.close();
    await tester.pumpAndSettle();
    expect(find.text('p.24'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(MapGhostNode).first, matching: find.byIcon(MMIcons.document)),
      findsOneWidget,
    );
    await capture(tester, 'expansion-review');
    final before = app.workspace.content;
    await key(tester, LogicalKeyboardKey.tab);
    expect(find.text('请先保留或放弃扩展内容，再继续操作'), findsOneWidget);
    expect(app.workspace.content.nodes.length, before.nodes.length);
    await key(tester, LogicalKeyboardKey.space);
    expect(app.container.read(provider)!.selectedCount, 0);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.space);
    expect(app.container.read(provider)!.selectedCount, 2);
    await key(tester, LogicalKeyboardKey.f2);
    final field = find.descendant(of: find.byType(MapGhostNode), matching: find.byType(TextField));
    await tester.enterText(field, '每日闭卷自测');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(app.container.read(provider)!.drafts.last.title, '每日闭卷自测');
    final longTitle = List.filled(40, '闭卷自测').join();
    app.container.read(provider.notifier).edit('d2', longTitle);
    await tester.pumpAndSettle();
    expect(app.container.read(provider)!.drafts.last.title, longTitle);
    expect(tester.takeException(), isNull);
    app.container.read(provider.notifier).edit('d2', '每日闭卷自测');
    await tester.pumpAndSettle();
    await focusMap(tester);
    await key(tester, LogicalKeyboardKey.enter);
    expect(app.container.read(provider), isNull);
    expect(app.workspace.content.nodes.length, before.nodes.length + 2);
    expect(app.workspace.content.assistantReceipts.length, 1);
    await capture(tester, 'expansion-kept');
    await app.workspace.undo();
    await tester.pumpAndSettle();
    expect(app.workspace.content.nodes.length, before.nodes.length);
    await app.workspace.redo();
    await tester.pumpAndSettle();
    expect(app.workspace.content.nodes.length, before.nodes.length + 2);
  });
  testWidgets('stop ignores late drafts; retry excludes; continue and discard', (tester) async {
    final models = [ControlledExpander(), ControlledExpander(), ControlledExpander()];
    var index = 0;
    final app = await openAssistantApp(
      tester,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(() async => models[index++])],
    );
    final provider = expansionControllerProvider('demo-1'),
        controller = app.container.read(expansionControllerProvider('demo-1').notifier);
    await tester.runAsync(() async {
      final run = controller.start(
        controller.request(
          MindMap.defaultId,
          'c3',
          depth: 2,
          breadth: 3,
          direction: ExpansionDirection.why,
          grounded: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      models[0].output.add(const ExpansionDraft(id: 'd1', parentRef: 'c3', title: '原因'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      controller.stop();
      expect(app.container.read(provider)!.phase, ExpansionPhase.stopped);
      models[0].output.add(const ExpansionDraft(id: 'late', parentRef: 'c3', title: 'Late'));
      unawaited(models[0].output.close());
      await run;
      expect(app.container.read(provider)!.drafts.length, 1);
      final retry = controller.regenerate();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(models[1].contexts.single.excludedTitles, contains('原因'));
      models[1].output.add(const ExpansionDraft(id: 'd2', parentRef: 'c3', title: '新原因'));
      unawaited(models[1].output.close());
      await retry;
      final deeper = controller.continueFromDraft('d2');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(models[2].contexts.single.targets, {'T1': 'new:d2'});
      models[2].output.add(const ExpansionDraft(id: 'd3', parentRef: 'new:d2', title: '更深原因'));
      unawaited(models[2].output.close());
      await deeper;
      controller.toggle('d2', false);
      expect(app.container.read(provider)!.selectedCount, 0);
      expect(await controller.keep(), 0);
      controller.edit('d3', '修改原因');
      expect(app.container.read(provider)!.selectedCount, 2);
      controller.edit('d2', '');
      controller.discard();
      expect(app.container.read(provider), isNull);
      final remembered = controller.request(MindMap.defaultId, 'c3');
      expect(remembered.direction, ExpansionDirection.why);
      expect(remembered.breadth, 3);
      expect(remembered.grounded, isFalse);
    });
    await tester.pumpAndSettle();
  });
  testWidgets('network failure, retry, apply failure preserve review', (tester) async {
    final first = ControlledExpander(), second = ControlledExpander();
    var index = 0;
    final app = await openAssistantApp(
      tester,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(() async => index++ == 0 ? first : second)],
    );
    final provider = expansionControllerProvider('demo-1'),
        controller = app.container.read(expansionControllerProvider('demo-1').notifier);
    final run = controller.start(controller.request(MindMap.defaultId, 'c3'));
    await tester.pumpAndSettle();
    first.output.addError(const ResearchFailure(ResearchFailureKind.network));
    unawaited(first.output.close());
    await tester.pumpAndSettle();
    await run;
    await tester.pumpAndSettle();
    expect(app.container.read(provider)!.phase, ExpansionPhase.error);
    await capture(tester, 'expansion-network');
    final retry = controller.regenerate();
    await tester.pumpAndSettle();
    second.output.add(const ExpansionDraft(id: 'd1', parentRef: 'c3', title: '新思路'));
    unawaited(second.output.close());
    await tester.pumpAndSettle();
    await retry;
    app.executor.fail = true;
    expect(await controller.keep(), 0);
    expect(app.container.read(provider)!.isApplying, isFalse);
    controller.discard();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('unconfigured shortcut opens setup', (tester) async {
    final app = await openAssistantApp(tester, key: false);
    app.workspace.selectCard('c3');
    await focusMap(tester);
    await key(tester, LogicalKeyboardKey.tab, alt: true);
    expect(find.byKey(const ValueKey('assistant-quick-actions')), findsOneWidget);
    expect(find.byType(ExpansionSection), findsNothing);
    expect(app.container.read(expansionControllerProvider('demo-1')), isNull);
  });
  for (final (language, appearance) in [('zh', 'light'), ('zh', 'dark'), ('en', 'dark')]) {
    testWidgets('expansion options layout $language $appearance', (tester) async {
      final app = await openAssistantApp(
        tester,
        size: language == 'en' ? const Size(1100, 760) : const Size(1400, 1000),
        prefs: {'settings.language': language, 'settings.appearance': appearance, 'expansion.demo-1.depth': 2},
      );
      app.workspace.selectCard('c3');
      await focusMap(tester);
      await tester.tap(find.byKey(const ValueKey('node-bar-assistant')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-expand-ideas')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expansion-start')), findsOneWidget);
      // Real glyph extents are meaningful only when the evidence fonts are loaded;
      // the default widget-test Ahem font intentionally uses square glyphs.
      if (language == 'en' && Platform.environment['MM_SCREENSHOTS'] != null) {
        final label = find.text('Counterpoints');
        expect(tester.renderObject<RenderParagraph>(label).didExceedMaxLines, isFalse);
      }
      expect(tester.takeException(), isNull);
      await capture(
        tester,
        'expansion-options-$language-$appearance',
        clip: tester
            .getRect(find.byKey(const ValueKey('assistant-quick-actions')))
            .expandToInclude(tester.getRect(find.byKey(const ValueKey('expansion-settings'))))
            .inflate(8),
      );
      await tester.tap(find.byKey(const ValueKey('expansion-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-close')));
      await tester.pumpAndSettle();
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }
  testWidgets('side settings hover, keyboard dismissal and parent actions remain usable', (tester) async {
    final app = await openAssistantApp(tester);
    app.workspace.selectCard('c3');
    await focusMap(tester);
    await tester.tap(find.byKey(const ValueKey('node-bar-assistant')));
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionSection), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('quick-expand-ideas'))));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    final menu = tester.getRect(find.byKey(const ValueKey('assistant-quick-actions')));
    final settings = tester.getRect(find.byKey(const ValueKey('expansion-settings')));
    expect(settings.left - menu.right, closeTo(8, .01));
    expect(settings.top, menu.top);
    expect(settings.right, lessThanOrEqualTo(tester.view.physicalSize.width));
    await mouse.moveTo(Offset.zero);
    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey('expansion-settings')), matching: find.byType(TextField)),
      '补充一些具体原因',
    );
    await key(tester, LogicalKeyboardKey.arrowLeft, alt: true);
    expect(find.byType(ExpansionSection), findsOneWidget, reason: 'Option+Left keeps its native text editing meaning');
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.byType(ExpansionSection), findsNothing);
    expect(find.byKey(const ValueKey('assistant-quick-actions')), findsOneWidget);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(find.byType(ExpansionSection), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('expansion-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-expand-ideas')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-action-explain')));
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionSection), findsNothing);
    expect(find.byKey(const ValueKey('assistant-quick-actions')), findsOneWidget);
    expect(app.container.read(expansionControllerProvider('demo-1')), isNull);
    await tester.tap(find.byKey(const ValueKey('quick-close')));
    await tester.pumpAndSettle();
    await mouse.removePointer();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  testWidgets('narrow window replaces menu, preserves settings and restores parent on Back', (tester) async {
    tester.view.physicalSize = const Size(600, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await testOverrides(),
          assistantConfiguredProvider.overrideWith((ref) async => true),
          assistantDependenciesProvider.overrideWithValue(
            AssistantDependencies(
              studySetId: 'demo-1',
              model: unconfiguredAssistantModel,
              storage: MemoryConversationArchive(),
              runFactory: (_, _, _) async => throw UnimplementedError(),
              executor: RecordingExecutor(),
              notes: MemoryNoteSaver(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: MMTheme.dark(),
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: Text('popup-anchor')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final popup = showAssistantQuickActions(
      tester.element(find.text('popup-anchor')),
      studySetId: 'demo-1',
      passage: nodeContext(mapId: MindMap.defaultId, nodeId: 'c3', title: 'Topic'),
      insertionTarget: (mapId: MindMap.defaultId, parentId: 'c3'),
      origin: PanelOrigin.map,
      toolbar: const Rect.fromLTWH(530, 80, 40, 30),
      selection: const Rect.fromLTWH(530, 80, 40, 30),
      viewport: const Rect.fromLTWH(0, 0, 600, 760),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('quick-input')), '保留这段输入');
    await tester.tap(find.byKey(const ValueKey('quick-expand-ideas')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-close')).hitTestable(), findsNothing);
    expect(find.byKey(const ValueKey('expansion-back')).hitTestable(), findsOneWidget);
    final settings = tester.getRect(find.byKey(const ValueKey('expansion-settings')));
    expect(settings.left, greaterThanOrEqualTo(0));
    expect(settings.right, lessThanOrEqualTo(600));
    await capture(tester, 'expansion-options-narrow', clip: settings.inflate(6));
    await tester.tap(find.text('2 层'));
    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey('expansion-settings')), matching: find.byType(TextField)),
      '更具体一些',
    );
    tester.view.physicalSize = const Size(800, 760);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-close')).hitTestable(), findsOneWidget);
    expect(tester.widget<MMSegmentedControl<int>>(find.byKey(const ValueKey('expansion-depth'))).value, 2);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: find.byKey(const ValueKey('expansion-settings')), matching: find.byType(EditableText)),
          )
          .controller
          .text,
      '更具体一些',
    );
    tester.view.physicalSize = const Size(600, 760);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expansion-back')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('quick-input'))).controller!.text, '保留这段输入');
    await tester.tap(find.byKey(const ValueKey('quick-close')));
    await tester.pumpAndSettle();
    await popup;
    expect(tester.takeException(), isNull);
  });
  testWidgets('selected two levels survive model completion, preview, keep and undo', (tester) async {
    final client = ScriptClient([
      answer('{"ref":"a","parent":"T1","title":"主动回忆"}'),
      answer('{"ref":"b","parent":"a","title":"闭卷自测"}'),
    ]);
    final app = await openAssistantApp(
      tester,
      realWrites: true,
      overrides: [
        ideaExpanderFactoryProvider.overrideWithValue(
          () async => ModelIdeaExpander(AssistantConnection(client, Dio()), 'test'),
        ),
      ],
    );
    app.workspace.selectCard('c3');
    await focusMap(tester);
    await tester.tap(find.byKey(const ValueKey('node-bar-assistant')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-expand-ideas')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 层'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('expansion-start')));
      for (var i = 0; i < 100; i++) {
        if (app.container.read(expansionControllerProvider('demo-1'))?.phase != ExpansionPhase.generating) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('Expansion did not finish');
    });
    await tester.pumpAndSettle();
    final state = app.container.read(expansionControllerProvider('demo-1'))!;
    expect(state.phase, ExpansionPhase.review);
    expect(state.failure, isNull);
    expect(state.drafts, hasLength(2));
    expect(state.drafts.last.parentRef, 'new:${state.drafts.first.id}');
    expect(client.calls, 2);
    expect(find.byType(MapGhostNode), findsNWidgets(2));
    await capture(tester, 'expansion-two-level-preview');
    final before = app.workspace.content;
    final controller = app.container.read(expansionControllerProvider('demo-1').notifier);
    expect(await controller.keep(), 2);
    final parent = app.workspace.content.cards.singleWhere((c) => c.title == '主动回忆');
    final child = app.workspace.content.cards.singleWhere((c) => c.title == '闭卷自测');
    expect(app.workspace.content.node(child.id)!.parentId, parent.id);
    await app.workspace.undo();
    expect(app.workspace.content.cards.length, before.cards.length);
    await settleHud(tester);
  });
  testWidgets('unfinished depth is visible while partial drafts stay reviewable', (tester) async {
    final model = ControlledExpander();
    final app = await openAssistantApp(
      tester,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(() async => model)],
    );
    final controller = app.container.read(expansionControllerProvider('demo-1').notifier);
    final run = controller.start(controller.request(MindMap.defaultId, 'c3', depth: 2));
    await tester.pumpAndSettle();
    model.output.add(const ExpansionDraft(id: 'partial', parentRef: 'c3', title: '未完成的分支'));
    model.output.addError(const ResearchFailure(ResearchFailureKind.protocol, 'incompleteDepth'));
    unawaited(model.output.close());
    await tester.pumpAndSettle();
    await run;
    expect(find.text('部分分支未达到所选层级，可换一批重试'), findsOneWidget);
    expect(app.container.read(expansionControllerProvider('demo-1'))!.phase, ExpansionPhase.stopped);
    expect(find.byType(MapGhostNode), findsOneWidget);
    controller.discard();
    await tester.pumpAndSettle();
  });
  testWidgets('global duplicate filtering cannot mark an incomplete branch as complete', (tester) async {
    final model = ControlledExpander();
    final app = await openAssistantApp(
      tester,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(() async => model)],
    );
    final controller = app.container.read(expansionControllerProvider('demo-1').notifier);
    final run = controller.start(controller.request(MindMap.defaultId, 'c3', depth: 2));
    await tester.pumpAndSettle();
    model.output.add(const ExpansionDraft(id: 'parent', parentRef: 'c3', title: '新主题'));
    model.output.add(const ExpansionDraft(id: 'duplicate', parentRef: 'new:parent', title: '对策一：间隔重复'));
    unawaited(model.output.close());
    await tester.pumpAndSettle();
    await run;
    final state = app.container.read(expansionControllerProvider('demo-1'))!;
    expect(state.drafts, hasLength(1));
    expect(state.phase, ExpansionPhase.stopped);
    expect(state.failure?.code, 'incompleteDepth');
    controller.discard();
    await tester.pumpAndSettle();
  });
  testWidgets('options entry remembers settings and adjusted retry uses them', (tester) async {
    final first = ControlledExpander(), second = ControlledExpander();
    var call = 0;
    final app = await openAssistantApp(
      tester,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(() async => call++ == 0 ? first : second)],
    );
    app.workspace.selectCard('c3');
    await focusMap(tester);
    await tester.tap(find.byKey(const ValueKey('node-bar-assistant')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-expand-ideas')));
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionSection), findsOneWidget);
    final options = find.byType(ExpansionOptions);
    expect(find.descendant(of: options, matching: find.byType(MMSegmentedControl<int>)), findsNWidgets(2));
    expect(find.descendant(of: options, matching: find.byType(ChoiceChip)), findsNothing);
    expect(tester.getTopLeft(find.text('层级')).dx, tester.getTopLeft(find.text('数量')).dx);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('expansion-depth'))).dx,
      tester.getTopLeft(find.byKey(const ValueKey('expansion-amount'))).dx,
    );
    final chip = find.byKey(const ValueKey('expansion-direction-auto'));
    final colors = tester.element(chip).mmColors;
    BoxDecoration chipDecoration(Finder chip) =>
        tester.widget<Container>(find.descendant(of: chip, matching: find.byType(Container)).first).decoration!
            as BoxDecoration;
    expect(chipDecoration(chip).color, colors.research);
    expect(chipDecoration(chip).border, isNull);
    expect(tester.widget<Text>(find.descendant(of: chip, matching: find.byType(Text))).style!.color, colors.onResearch);
    final unselected = chipDecoration(find.byKey(const ValueKey('expansion-direction-example')));
    expect(unselected.border, Border.all(color: colors.line, width: .5));
    final sourceSwitch = find.byType(MMSwitch);
    expect(tester.widget<MMSwitch>(sourceSwitch).color, colors.research);
    expect(tester.getCenter(find.byType(MMTextField)).dy, lessThan(tester.getCenter(sourceSwitch).dy));
    expect(tester.getCenter(find.byKey(const ValueKey('expansion-start'))).dy, tester.getCenter(sourceSwitch).dy);
    final hintField = find.descendant(of: find.byType(MMTextField), matching: find.byType(TextField));
    expect(tester.widget<TextField>(hintField).maxLength, 200);
    await capture(tester, 'expansion-options');
    await tester.tap(find.byKey(const ValueKey('expansion-direction-example')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 层'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: find.byType(ExpansionSection), matching: find.byType(TextField)),
      '结合编程',
    );
    await tester.tap(find.byType(MMSwitch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expansion-start')));
    await tester.pumpAndSettle();
    expect(first.requests.single.depth, 2);
    expect(first.requests.single.breadth, 8);
    expect(first.requests.single.grounded, isFalse);
    expect(first.requests.single.hint, '结合编程');
    first.output.add(const ExpansionDraft(id: 'd1', parentRef: 'c3', title: '测试思路'));
    unawaited(first.output.close());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('调整'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('反方'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新生成'));
    await tester.pumpAndSettle();
    expect(second.requests.single.direction, ExpansionDirection.counter);
    second.output.add(const ExpansionDraft(id: 'd2', parentRef: 'c3', title: '反方思路'));
    unawaited(second.output.close());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('放弃'));
    await tester.pumpAndSettle();
    expect(app.container.read(expansionControllerProvider('demo-1')), isNull);
  });

  testWidgets('empty, partial failure, no-result stop and busy guard', (tester) async {
    final models = [ControlledExpander(), ControlledExpander(), ControlledExpander()];
    var call = 0;
    final app = await openAssistantApp(
      tester,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(() async => models[call++])],
    );
    final p = expansionControllerProvider('demo-1'),
        c = app.container.read(expansionControllerProvider('demo-1').notifier);
    c.stop();
    final empty = c.start(c.request(MindMap.defaultId, 'c3'));
    await tester.pumpAndSettle();
    await expectLater(c.start(c.request(MindMap.defaultId, 'c3')), throwsStateError);
    c.toggle('missing', true);
    c.edit('missing', 'text');
    unawaited(models[0].output.close());
    await tester.pumpAndSettle();
    await empty;
    await tester.pumpAndSettle();
    expect(app.container.read(p), isNull);
    expect(find.text('这里暂时没有值得补充的方向，换个方向试试'), findsOneWidget);
    final partial = c.start(c.request(MindMap.defaultId, 'c3'));
    await tester.pumpAndSettle();
    models[1].output.add(const ExpansionDraft(id: 'd1', parentRef: 'c3', title: '有效结果'));
    models[1].output.add(const ExpansionDraft(id: 'duplicate', parentRef: 'c3', title: '有效结果'));
    models[1].output.add(const ExpansionDraft(id: 'rejected', parentRef: 'new:duplicate', title: '不得留下'));
    models[1].output.addError(const ResearchFailure(ResearchFailureKind.network));
    unawaited(models[1].output.close());
    await tester.pumpAndSettle();
    await partial;
    expect(app.container.read(p)!.phase, ExpansionPhase.stopped);
    expect(app.container.read(p)!.drafts.length, 1);
    await capture(tester, 'expansion-stopped');
    final before = app.workspace.content;
    app.workspace.beginEditing('c3');
    expect(app.container.read(workspaceProvider('demo-1')).editingCardId, isNull);
    app.workspace.setMapView(MapViewMode.outline);
    expect(app.container.read(workspaceProvider('demo-1')).mapView, MapViewMode.map);
    await app.workspace.rename('c3', '不能修改');
    await app.workspace.undo();
    expect(app.workspace.content.card('c3')!.title, before.card('c3')!.title);
    c.discard();
    final stopped = c.start(c.request(MindMap.defaultId, 'c3'));
    await tester.pumpAndSettle();
    c.stop();
    unawaited(models[2].output.close());
    await tester.pumpAndSettle();
    await stopped;
    expect(app.container.read(p), isNull);
    expect(app.container.read(expansionBusyProvider), isFalse);
  });

  testWidgets('production factory validates credentials and owns its connection', (tester) async {
    final app = await openAssistantApp(tester);
    final model = await app.container.read(ideaExpanderFactoryProvider)();
    expect(model, isA<ModelIdeaExpander>());
    model.close();
    app.secrets.values.clear();
    await expectLater(app.container.read(ideaExpanderFactoryProvider)(), throwsA(isA<ResearchFailure>()));
  });
  testWidgets('local retry switches model; keep rejects concurrent submission', (tester) async {
    final first = ControlledExpander(), second = ControlledExpander();
    var call = 0;
    final app = await openAssistantApp(
      tester,
      realWrites: true,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(() async => call++ == 0 ? first : second)],
    );
    await tester.runAsync(
      () => app.container
          .read(assistantServicesProvider.notifier)
          .upsert(
            AssistantService(
              id: 'local',
              protocol: ServiceProtocol.ollama,
              name: 'Local',
              endpoint: 'http://localhost:11434',
              localEnabled: true,
              models: const [ServiceModel(id: 'local-model')],
            ),
          ),
    );
    final p = expansionControllerProvider('demo-1'),
        c = app.container.read(expansionControllerProvider('demo-1').notifier);
    final run = c.start(c.request(MindMap.defaultId, 'c3'));
    await tester.pumpAndSettle();
    first.output.addError(const ResearchFailure(ResearchFailureKind.network));
    unawaited(first.output.close());
    await tester.pumpAndSettle();
    await run;
    final local = find.text('改用本机模型');
    expect(local, findsOneWidget);
    await tester.tap(local);
    await pumpFor(tester);
    await tester.pumpAndSettle();
    expect(app.container.read(assistantServicesProvider).value!.configuration!.model, 'local-model');
    second.output.add(const ExpansionDraft(id: 'd1', parentRef: 'c3', title: '本机结果'));
    unawaited(second.output.close());
    await tester.pumpAndSettle();
    final keep = c.keep();
    c.discard();
    c.stop();
    expect(await c.keep(), 0);
    expect(await keep, 1);
    await tester.pumpAndSettle();
    expect(app.container.read(p), isNull);
    expect(app.workspace.content.assistantReceipts.length, 1);
  });

  testWidgets('preview animation stops on manual viewport and on discard', (tester) async {
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    final model = ControlledExpander();
    final app = await openAssistantApp(
      tester,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(() async => model)],
    );
    final c = app.container.read(expansionControllerProvider('demo-1').notifier);
    final run = c.start(c.request(MindMap.defaultId, 'c3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ExpansionWorking), findsWidgets);
    model.output.add(const ExpansionDraft(id: 'd1', parentRef: 'c3', title: '动画草稿'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(MapPane), const Offset(20, 10));
    await tester.pump(const Duration(milliseconds: 100));
    c.discard();
    unawaited(model.output.close());
    await tester.pumpAndSettle();
    await run;
    expect(tester.takeException(), isNull);
  });
  testWidgets('dark review uses research tokens and compact source page chip', (tester) async {
    final model = ControlledExpander();
    final app = await openAssistantApp(
      tester,
      prefs: {'settings.appearance': 'dark'},
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(() async => model)],
    );
    app.workspace.selectCard('c3');
    await focusMap(tester);
    final run = app.container
        .read(expansionControllerProvider('demo-1').notifier)
        .start(app.container.read(expansionControllerProvider('demo-1').notifier).request(MindMap.defaultId, 'c3'));
    await tester.pumpAndSettle();
    model.output.add(
      const ExpansionDraft(id: 'dark1', parentRef: 'c3', title: '主动回忆', tag: ExpansionDirection.action, page: 24),
    );
    model.output.add(const ExpansionDraft(id: 'dark2', parentRef: 'new:dark1', title: '闭卷自测'));
    unawaited(model.output.close());
    await tester.pumpAndSettle();
    await run;
    final ghost = find.byType(MapGhostNode).first;
    expect(Theme.of(tester.element(ghost)).brightness, Brightness.dark);
    expect(find.text('p.24'), findsOneWidget);
    final icon = tester.widget<Icon>(find.descendant(of: ghost, matching: find.byIcon(MMIcons.document)));
    expect(icon.size, 10);
    await capture(tester, 'expansion-review-dark');
    expect(tester.takeException(), isNull);
  });
  testWidgets('multi targets share review, at most three calls and one transaction', (tester) async {
    final models = BatchModels()..gate = Completer<void>();
    final app = await openAssistantApp(
      tester,
      realWrites: true,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(models.create)],
    );
    final ids = ['c3', 'c4', 'c6'];
    for (var i = 0; i < 3; i++) {
      await app.workspace.addTopic('并发分支$i');
      ids.add(app.container.read(workspaceProvider('demo-1')).selectedCardId!);
    }
    final c = app.container.read(expansionControllerProvider('demo-1').notifier);
    final before = app.workspace.content.nodes.length;
    final run = c.start(c.request(MindMap.defaultId, ids.first, targets: ids));
    await tester.pumpAndSettle();
    expect(models.active, 3);
    models.gate!.complete();
    await tester.pumpAndSettle();
    await run;
    expect(models.maximum, 3);
    expect(models.requests.length, 6);
    expect(models.closed, 6);
    await capture(tester, 'multi-review');
    expect(await c.keep(), 12);
    expect(app.workspace.content.nodes.length, before + 12);
    await app.workspace.undo();
    expect(app.workspace.content.nodes.length, before);
  });

  testWidgets('group preview moves existing nodes, deselection restores and keep undoes', (tester) async {
    final models = BatchModels();
    final app = await openAssistantApp(
      tester,
      realWrites: true,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(models.create)],
    );
    final p = expansionControllerProvider('demo-1'), c = app.container.read(p.notifier);
    final before = app.workspace.content;
    final run = c.start(
      c.request(
        MindMap.defaultId,
        'c3',
        targets: ['c3', 'c4'],
        scope: ExpansionScope.group,
        commonParentId: MindMap.defaultId,
      ),
    );
    await tester.pumpAndSettle();
    await run;
    expect(app.container.read(p)!.moves.keys, ['c3', 'c4']);
    expect(app.workspace.content, same(before));
    await capture(tester, 'group-preview');
    final draft = app.container.read(p)!.drafts.single;
    c.toggle(draft.id, false);
    await tester.pumpAndSettle();
    expect(app.container.read(p)!.moves, isEmpty);
    c.toggle(draft.id, true);
    await tester.pumpAndSettle();
    await c.keep();
    await tester.pumpAndSettle();
    expect(app.workspace.content.node('c3')!.parentId, app.workspace.content.node('c4')!.parentId);
    expect(app.workspace.content.node('c3')!.parentId, isNotNull);
    await app.workspace.undo();
    await tester.pumpAndSettle();
    expect(app.workspace.content.node('c3')!.parentId, isNull);
    expect(app.workspace.content.nodes.length, before.nodes.length);
    expect(tester.takeException(), isNull);
  });

  testWidgets('siblings validate common parent and use one model call', (tester) async {
    final models = BatchModels();
    final app = await openAssistantApp(
      tester,
      realWrites: true,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(models.create)],
    );
    final p = expansionControllerProvider('demo-1'), c = app.container.read(p.notifier);
    await tester.runAsync(
      () => c.start(
        c.request(
          MindMap.defaultId,
          'c3',
          targets: ['c3', 'c4'],
          scope: ExpansionScope.siblings,
          commonParentId: MindMap.defaultId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(models.requests.single.scope, ExpansionScope.siblings);
    expect(app.container.read(p)!.moves, isEmpty);
    expect(await c.keep(), 2);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => c.start(
        c.request(
          MindMap.defaultId,
          'c3',
          targets: ['c3', 'c6'],
          scope: ExpansionScope.group,
          commonParentId: MindMap.defaultId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(app.container.read(p)!.failure!.kind, ResearchFailureKind.invalidRequest);
    c.discard();
  });

  testWidgets('root shortcut plans, controls are bounded, new branches remain drafts', (tester) async {
    final models = BatchModels()
      ..items = const [
        ExpansionPlanItem(targetId: 'c3', add: 1, reason: 'thin'),
        ExpansionPlanItem(targetId: 'c4', add: 8, reason: 'empty'),
        ExpansionPlanItem(targetId: MindMap.defaultId, add: 3, reason: 'newBranch', title: '实践路径'),
      ];
    final app = await openAssistantApp(
      tester,
      realWrites: true,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(models.create)],
    );
    app.workspace.selectMapRoot();
    await focusMap(tester);
    await key(tester, LogicalKeyboardKey.tab, alt: true);
    await tester.pumpAndSettle();
    final p = expansionControllerProvider('demo-1'), c = app.container.read(p.notifier);
    expect(find.byType(ExpansionPlanSheet), findsOneWidget);
    expect(models.plans, 1);
    expect(models.planContext!.targets['T1'], MindMap.defaultId);
    expect(models.planContext!.details['T1']!.title, '认知科学入门');
    expect(models.planContext!.details.values.every((d) => d.pages.isEmpty), isTrue);
    expect(app.container.read(p)!.planItems.first.targetId, 'c4');
    await capture(tester, 'map-plan');
    await tester.tap(find.byKey(const ValueKey('plan-minus-0')));
    await tester.pumpAndSettle();
    expect(app.container.read(p)!.planItems.first.add, 7);
    await tester.tap(find.byKey(const ValueKey('plan-plus-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(app.container.read(p)!.disabledPlan, {1});
    c.updatePlan(0, add: 99);
    c.updatePlan(1, add: -9);
    c.updatePlan(-1, add: 2);
    final before = app.workspace.content.nodes.length;
    await tester.tap(find.text('开始扩展'));
    await tester.pumpAndSettle();
    expect(models.plans, 1);
    expect(models.requests.length, 2);
    expect(app.workspace.content.nodes.length, before);
    expect(app.container.read(p)!.drafts.length, 12);
    await capture(tester, 'map-review');
    final branch = app.container.read(p)!.drafts.firstWhere((d) => d.parentRef == MindMap.defaultId);
    c.toggle(branch.id, false);
    await tester.runAsync(() => c.regenerate());
    await tester.pumpAndSettle();
    // Regeneration restores the planned parent and excludes old children.
    expect(models.plans, 1);
    expect(app.container.read(p)!.drafts.firstWhere((d) => d.id == branch.id).kept, isTrue);
    await tester.runAsync(() => c.continueFromDraft(branch.id));
    await tester.pumpAndSettle();
    expect(models.requests.last.depth, 3);
    c.discard();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('whole map over fifty drafts keeps once, undoes and redoes once', (tester) async {
    final models = BatchModels();
    final app = await openAssistantApp(
      tester,
      realWrites: true,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(models.create)],
    );
    final ids = <String>[];
    for (var i = 0; i < 8; i++) {
      await app.workspace.addTopic('计划分支$i');
      ids.add(app.container.read(workspaceProvider('demo-1')).selectedCardId!);
    }
    models.items = [for (final id in ids) ExpansionPlanItem(targetId: id, add: 8, reason: 'empty')];
    final p = expansionControllerProvider('demo-1'), c = app.container.read(p.notifier);
    final before = app.workspace.content;
    await tester.runAsync(
      () => c.planMap(c.request(MindMap.defaultId, MindMap.defaultId, scope: ExpansionScope.map, breadth: 8)),
    );
    await tester.pumpAndSettle();
    expect(find.text('+64'), findsOneWidget);
    await tester.tap(find.text('开始扩展'));
    await tester.pumpAndSettle();
    expect(app.container.read(p)!.selectedCount, 64);
    await capture(tester, 'map-64-review');
    expect(await c.keep(), 64);
    await tester.pumpAndSettle();
    expect(app.workspace.content.nodes.length, before.nodes.length + 64);
    expect(app.workspace.content.assistantReceipts.length, 1);
    await app.workspace.undo();
    await tester.pumpAndSettle();
    expect(app.workspace.content.nodes.length, before.nodes.length);
    await app.workspace.redo();
    await tester.pumpAndSettle();
    expect(app.workspace.content.nodes.length, before.nodes.length + 64);
  });

  testWidgets('multi selection entry offers grouping and disables different parents', (tester) async {
    final models = BatchModels();
    final app = await openAssistantApp(
      tester,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(models.create)],
    );
    app.workspace.selectCards(['c3', 'c4']);
    await focusMap(tester);
    await tester.tap(find.byKey(const ValueKey('node-bar-assistant')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-expand-ideas')));
    await tester.pumpAndSettle();
    expect(find.text('分别扩展 2 个主题'), findsNWidgets(2));
    await capture(tester, 'multi-options');
    await tester.tap(find.text('归纳上级主题'));
    await tester.pumpAndSettle();
    final p = expansionControllerProvider('demo-1'), c = app.container.read(p.notifier);
    expect(app.container.read(p)!.request.scope, ExpansionScope.group);
    c.discard();
    await tester.pumpAndSettle();
    app.workspace.selectCards(['c3', 'c6']);
    await focusMap(tester);
    await tester.tap(find.byKey(const ValueKey('node-bar-assistant')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-expand-ideas')));
    await tester.pumpAndSettle();
    final group = tester.widget<MMButton>(find.widgetWithText(MMButton, '归纳上级主题'));
    expect(group.onPressed, isNull);
    expect(
      find.byTooltip(tester.element(find.byType(ExpansionSection)).l10n.mapEditDifferentParents),
      findsNWidgets(2),
    );
    await key(tester, LogicalKeyboardKey.escape);
  });

  testWidgets('plan cancellation, failure retry and partial batch failure release busy', (tester) async {
    final models = BatchModels()..planGate = Completer<void>();
    final app = await openAssistantApp(
      tester,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(models.create)],
    );
    final p = expansionControllerProvider('demo-1'), c = app.container.read(p.notifier);
    final request = c.request(MindMap.defaultId, MindMap.defaultId, scope: ExpansionScope.map, breadth: 8);
    final run = c.planMap(request);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(app.container.read(p)!.phase, ExpansionPhase.planning);
    await expectLater(c.planMap(request), throwsStateError);
    c.discard();
    models.planGate!.complete();
    await tester.pumpAndSettle();
    await run;
    expect(app.container.read(p), isNull);
    models.planGate = null;
    models.planFailure = const ResearchFailure(ResearchFailureKind.network);
    await tester.runAsync(() => c.planMap(request));
    await tester.pumpAndSettle();
    expect(app.container.read(p)!.phase, ExpansionPhase.error);
    models.planFailure = null;
    models.items = const [ExpansionPlanItem(targetId: 'c3', add: 2, reason: 'thin')];
    await tester.runAsync(() => c.regenerate());
    await tester.pumpAndSettle();
    c.updatePlan(0, enabled: false);
    await c.startPlan();
    expect(app.container.read(p)!.phase, ExpansionPhase.plan);
    c.updatePlan(0, enabled: true);
    models.failure = const ResearchFailure(ResearchFailureKind.protocol, 'noValidExpansion');
    await tester.runAsync(() => c.startPlan());
    await tester.pumpAndSettle();
    expect(app.container.read(p)!.phase, ExpansionPhase.stopped);
    expect(app.container.read(p)!.drafts.length, 2);
    expect(app.container.read(expansionBusyProvider), isFalse);
    c.discard();
    await tester.runAsync(() => c.planMap(request));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getBottomLeft(find.byType(MapPane)) + const Offset(30, -30));
    await tester.pumpAndSettle();
    expect(app.container.read(p), isNull);
  });
  testWidgets('root entry offers plan and branches only; multi main and siblings actions', (tester) async {
    final models = BatchModels();
    final app = await openAssistantApp(
      tester,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(models.create)],
    );
    final p = expansionControllerProvider('demo-1'), c = app.container.read(p.notifier);
    app.workspace.selectMapRoot();
    await focusMap(tester);
    await tester.tap(find.byKey(const ValueKey('node-bar-assistant')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-expand-ideas')));
    await tester.pumpAndSettle();
    expect(find.text('扩展整张脑图…'), findsNWidgets(2));
    await capture(tester, 'root-options');
    await tester.tap(find.byKey(const ValueKey('expansion-start')));
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionPlanSheet), findsOneWidget);
    expect(models.plans, 1);
    c.discard();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('node-bar-assistant')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-expand-ideas')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只加新分支'));
    await tester.pumpAndSettle();
    expect(models.plans, 1);
    expect(models.requests.single.targetIds, [MindMap.defaultId]);
    expect(models.requests.single.depth, 1);
    c.discard();
    await tester.pumpAndSettle();
    app.workspace.selectCards(['c3', 'c4']);
    await focusMap(tester);
    await tester.tap(find.byKey(const ValueKey('node-bar-assistant')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-expand-ideas')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expansion-start')));
    await tester.pumpAndSettle();
    expect(app.container.read(p)!.request.targetIds.toSet(), {'c3', 'c4'});
    c.discard();
    await tester.pumpAndSettle();
    app.workspace.selectCards(['c3', 'c4']);
    await focusMap(tester);
    await tester.tap(find.byKey(const ValueKey('node-bar-assistant')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-expand-ideas')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('补全同级'));
    await tester.pumpAndSettle();
    expect(app.container.read(p)!.request.scope, ExpansionScope.siblings);
    c.discard();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('context menu exposes grouping with reason and root expansion', (tester) async {
    final models = BatchModels();
    final app = await openAssistantApp(
      tester,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(models.create)],
    );
    final p = expansionControllerProvider('demo-1'), c = app.container.read(p.notifier);
    app.workspace.selectCards(['c3', 'c4']);
    await focusMap(tester);
    await tester.tap(find.text('遗忘的规律').last, buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('归纳上级主题'), findsOneWidget);
    await tester.tap(find.text('归纳上级主题'));
    await tester.pumpAndSettle();
    expect(app.container.read(p)!.request.scope, ExpansionScope.group);
    c.discard();
    await tester.pumpAndSettle();
    app.workspace.selectCards(['c3', 'c6']);
    await focusMap(tester);
    await tester.tap(find.text('遗忘的规律').last, buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    final reason = tester.element(find.byType(MapPane)).l10n.mapEditDifferentParents;
    expect(find.byTooltip(reason), findsNWidgets(2));
    await key(tester, LogicalKeyboardKey.escape);
    app.workspace.selectMapRoot();
    await focusMap(tester);
    await tester.tap(
      find.descendant(of: find.byType(MindMapCanvas), matching: find.text('认知科学入门')),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('扩展整张脑图…'));
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionPlanSheet), findsOneWidget);
    c.discard();
    await tester.pumpAndSettle();
  });

  test('map planning context stays structural with many targets and validates budget', () async {
    var content = demoContent();
    var i = 0;
    final editor = StudySetEditor(newId: () => 'plan-${i++}', now: () => testNow);
    for (var n = 0; n < 20; n++) {
      content = editor.addTopic(content, title: '分支$n').$1;
    }
    final reader = WorkspaceReader(
      content: () => content,
      contexts: const [],
      filePath: (d) => d.fileName,
      pageText: (_, _) async => throw StateError('Plan must not read pages'),
    );
    final builder = ExpansionContextBuilder(reader);
    final r = ExpansionRequest(
      studySetId: 'demo-1',
      mapId: MindMap.defaultId,
      targetIds: [MindMap.defaultId],
      scope: ExpansionScope.map,
      breadth: 8,
    );
    final context = await builder.build(content, r);
    expect(context.targets.length, greaterThan(20));
    expect(context.details.values.every((d) => d.pages.isEmpty), isTrue);
    await expectLater(builder.build(content, r, tokenBudget: 1), throwsA(isA<ResearchFailure>()));
    await expectLater(
      builder.build(content, ExpansionRequest(studySetId: 'demo-1', mapId: 'missing', targetIds: ['c3'])),
      throwsA(isA<ResearchFailure>()),
    );
  });
  testWidgets('stop cancels the three active calls and queued targets; restart ignores late completion', (
    tester,
  ) async {
    final gate = Completer<void>(), models = BatchModels();
    models.gate = gate;
    final app = await openAssistantApp(
      tester,
      overrides: [ideaExpanderFactoryProvider.overrideWithValue(models.create)],
    );
    final p = expansionControllerProvider('demo-1'), c = app.container.read(p.notifier);
    final ids = ['c3', 'c4', 'c6'];
    await app.workspace.addTopic('排队分支');
    ids.add(app.container.read(workspaceProvider('demo-1')).selectedCardId!);
    final first = c.start(c.request(MindMap.defaultId, ids.first, targets: ids));
    await tester.pumpAndSettle();
    expect(models.requests.length, 3);
    c.stop();
    expect(app.container.read(p), isNull);
    expect(app.container.read(expansionBusyProvider), isFalse);
    models.gate = null;
    await tester.runAsync(() => c.start(c.request(MindMap.defaultId, 'c3')));
    await tester.pumpAndSettle();
    final current = app.container.read(p)!;
    gate.complete();
    await tester.pumpAndSettle();
    await first;
    expect(app.container.read(p), same(current));
    expect(models.requests.length, 4);
    expect(models.active, 0);
    c.discard();
    await tester.pumpAndSettle();
  });
  test('group context distinguishes selected topics from siblings and reads only their sources', () async {
    var content = demoContent(), sequence = 0;
    final editor = StudySetEditor(newId: () => 'unselected-${sequence++}', now: () => testNow);
    final added = editor.addTopic(content, title: '未选主题');
    content = editor
        .createExcerpt(
          added.$1,
          documentId: 'c1',
          page: 99,
          rects: const [PageRect(10, 100, 20, 20)],
          quote: '不应纳入归纳的内容',
          colorIndex: 0,
          parentId: added.$2.id,
        )
        .$1;
    final reads = <int>[];
    final reader = WorkspaceReader(
      content: () => content,
      contexts: const [],
      filePath: (d) => d.fileName,
      pageText: (_, p) async {
        reads.add(p);
        return 'Source $p';
      },
    );
    for (final scope in [ExpansionScope.group, ExpansionScope.siblings]) {
      reads.clear();
      final context = await ExpansionContextBuilder(reader).build(
        content,
        ExpansionRequest(
          studySetId: 'demo-1',
          mapId: MindMap.defaultId,
          targetIds: ['c3', 'c4'],
          scope: scope,
          commonParentId: MindMap.defaultId,
        ),
      );
      expect(context.targets, {'T1': MindMap.defaultId});
      expect(context.details['T1']!.children, ['遗忘的规律', '对策一：间隔重复']);
      expect(context.details['T1']!.siblings, ['未选主题']);
      expect(reads, [23, 24, 25]);
    }
  });
  for (final parent in [null, 'c3']) {
    testWidgets('map popup derives expansion target from insertion parent $parent', (tester) async {
      await openAssistantApp(tester);
      final popup = showAssistantQuickActions(
        tester.element(find.byType(MapPane)),
        studySetId: 'demo-1',
        passage: nodeContext(mapId: MindMap.defaultId, nodeId: parent ?? '__root__', title: 'Topic'),
        insertionTarget: (mapId: MindMap.defaultId, parentId: parent),
        origin: PanelOrigin.map,
        toolbar: const Rect.fromLTWH(1000, 100, 40, 30),
        selection: const Rect.fromLTWH(1000, 100, 40, 30),
        viewport: const Rect.fromLTWH(0, 0, 1400, 900),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-expand-ideas')));
      await tester.pumpAndSettle();
      expect(tester.widget<ExpansionSection>(find.byType(ExpansionSection)).targetId, parent ?? MindMap.defaultId);
      await tester.tap(find.byKey(const ValueKey('quick-close')));
      await tester.pumpAndSettle();
      await popup;
    });
  }
}
