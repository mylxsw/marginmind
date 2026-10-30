import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/expansion_context.dart';
import 'package:marginmind/features/assistant/expansion_controller.dart';
import 'package:marginmind/features/assistant/assistant_reader.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/assistant/widgets/expansion_widgets.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

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

Future<void> capture(WidgetTester tester, String name) async {
  final output = Platform.environment['MM_SCREENSHOTS'];
  if (output == null) return;
  Directory(output).createSync(recursive: true);
  final pane = tester.renderObject<RenderBox>(find.byType(MapPane));
  final image = await tester.runAsync(
    () => (tester.binding.renderViews.first.debugLayer! as OffsetLayer).toImage(
      pane.localToGlobal(Offset.zero) & pane.size,
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
    await capture(tester, 'expansion-review');
    final before = app.workspace.content;
    await key(tester, LogicalKeyboardKey.tab);
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
    expect(find.byType(ExpansionSection), findsOneWidget);
    await capture(tester, 'expansion-options');
    await tester.tap(find.widgetWithText(ChoiceChip, '例子'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 层'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: find.byType(ExpansionSection), matching: find.byType(TextField)),
      '结合编程',
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('扩展想法  ⌥⇥'));
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
}
