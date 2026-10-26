// Reproducible macOS map workload. Run with --profile or --release; no user files.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

const runLabel = String.fromEnvironment('RUN_LABEL', defaultValue: 'local');
const mode = bool.fromEnvironment('dart.vm.product') ? 'Release' : 'Profile';

StudySetContent fixture(int count) {
  final now = DateTime(2026);
  return StudySetContent(
    cards: [
      for (var i = 0; i < count - 1; i++) Card(id: 'c$i', kind: CardKind.topic, title: 'Node $i 中文', createdAt: now),
    ],
    nodes: [
      for (var i = 0; i < count - 1; i++)
        MapNode(cardId: 'c$i', parentId: i < 6 ? null : 'c${(i - 6) ~/ 6}', order: i.toDouble()),
    ],
    relations: [for (var i = 1; i < 6; i++) MapRelation(id: 'r$i', fromId: 'c0', toId: 'c$i', label: 'Link $i')],
  );
}

class DelayedRepository extends InMemoryStudySetContentRepository {
  DelayedRepository() : super({'bench': fixture(50)});
  final events = StreamController<StudySetContent>.broadcast();
  final pending = <StudySetContent>[];
  bool delayed = false;
  @override
  Stream<StudySetContent> watch(String id) async* {
    yield await load(id);
    yield* events.stream;
  }

  @override
  Future<StudySetContent> update(String id, StudySetContent Function(StudySetContent) change) async {
    final next = await super.update(id, change);
    if (delayed) {
      pending.add(next);
    } else {
      events.add(next);
    }
    return next;
  }
}

final repo = DelayedRepository();
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopWindow.initialize(title: 'GUL497 $runLabel $mode', minimumSize: const Size(1280, 820));
  // Keep the diagnostic workload isolated from user preferences.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        contentRepositoryProvider.overrideWithValue(repo),
        studySetRepositoryProvider.overrideWithValue(InMemoryStudySetRepository()),
      ],
      child: MaterialApp(
        theme: MMTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Workload(),
      ),
    ),
  );
}

class Workload extends ConsumerStatefulWidget {
  const Workload({super.key});
  @override
  ConsumerState<Workload> createState() => _WorkloadState();
}

class _WorkloadState extends ConsumerState<Workload> {
  String phase = 'warmup';
  final samples = <String, List<FrameTiming>>{};
  int count = 50;
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(record);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(() async {
        try {
          await run();
        } catch (error, stack) {
          stderr.writeln('$error\n$stack');
          exit(1);
        }
      }()),
    );
  }

  void record(List<FrameTiming> frames) => samples.putIfAbsent('$count/$phase', () => []).addAll(frames);
  T widgetOf<T extends Widget>() {
    T? found;
    void visit(Element e) {
      if (e.widget is T) found ??= e.widget as T;
      e.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found!;
  }

  Future<void> pause([int ms = 300]) => Future<void>.delayed(Duration(milliseconds: ms));
  Future<void> scenario(String name, FutureOr<void> Function(int) step, {int frames = 90}) async {
    setState(() => phase = name);
    developer.Timeline.startSync('GUL-497 $count/$name');
    developer.Timeline.finishSync();
    stdout.writeln('SCENARIO $runLabel $mode $count/$name');
    for (var i = 0; i < frames; i++) {
      await step(i);
      await pause(16);
    }
    await pause(500); // Drain the engine's batched timing reports.
  }

  Future<void> run() async {
    await pause(4000);
    final c = ref.read(workspaceProvider('bench').notifier);
    for (final n in [50, 500]) {
      count = n;
      phase = 'setup';
      await repo.update('bench', (_) => fixture(n));
      await pause(700);
      final canvas = widgetOf<MindMapCanvas>();
      final transform = canvas.transformation;
      final base = transform.value.clone();
      await scenario('pan', (i) {
        transform.value = base.clone()..translateByDouble(math.sin(i / 12) * 120, math.cos(i / 12) * 80, 0, 1);
      });
      await scenario('zoom', (i) {
        final s = 1 + math.sin(i / 15) * .25;
        transform.value = base.clone()..scaleByDouble(s, s, 1, 1);
      });
      transform.value = base;
      if (!mounted) return;
      final box = context.findRenderObject()! as RenderBox;
      final point = box.localToGlobal(Offset(box.size.width - 100, box.size.height - 120));
      GestureBinding.instance.handlePointerEvent(
        PointerDownEvent(pointer: 9, position: point, kind: PointerDeviceKind.mouse, buttons: 1),
      );
      var last = point;
      await scenario('mouse-box-select', (i) {
        final next = point + Offset(-i.toDouble(), -i / 3);
        GestureBinding.instance.handlePointerEvent(
          PointerMoveEvent(pointer: 9, position: next, delta: next - last, kind: PointerDeviceKind.mouse, buttons: 1),
        );
        last = next;
      });
      GestureBinding.instance.handlePointerEvent(
        PointerUpEvent(pointer: 9, position: last, kind: PointerDeviceKind.mouse),
      );
      await scenario('mouse-wheel-zoom', (i) {
        GestureBinding.instance.handlePointerEvent(
          PointerScrollEvent(
            position: point,
            kind: PointerDeviceKind.mouse,
            scrollDelta: Offset(0, math.sin(i / 12) * 4),
          ),
        );
      });
      GestureBinding.instance.handlePointerEvent(PointerPanZoomStartEvent(pointer: 10, position: point));
      await scenario('trackpad-pan-zoom', (i) {
        GestureBinding.instance.handlePointerEvent(
          PointerPanZoomUpdateEvent(
            pointer: 10,
            position: point,
            pan: Offset(-i.toDouble(), -i / 3),
            panDelta: const Offset(-1, -1 / 3),
            scale: 1 + i / 180,
          ),
        );
      });
      GestureBinding.instance.handlePointerEvent(PointerPanZoomEndEvent(pointer: 10, position: point));
      transform.value = base;
      c.beginEditing('c0');
      await WidgetsBinding.instance.endOfFrame.timeout(const Duration(seconds: 5));
      await pause();
      await scenario('typing', (i) {
        if (i % 3 == 0) widgetOf<MMInlineTextField>().controller.text = 'Continuous input 中文 ${'x' * (i % 35)}';
      });
      await c.finishEditing('Final title');
      await scenario('selection', (i) {
        if (i % 3 == 0) c.selectCard('c${i % 6}');
      });
      await scenario('multi-select', (i) {
        if (i % 3 == 0) c.toggleCardSelection('c${i % 6}');
      });
      await scenario('collapse', (i) async {
        if (i % 15 == 0) await c.toggleCollapsed('c0');
      });
      await scenario('add-delete', (i) async {
        if (i % 15 == 0) {
          final card = await c.addTopic('New $i');
          await c.removeCards([card.id]);
        }
      });
      // Exercise the actual pointer route and Draggable, not only a move command.
      c.selectCard('c0');
      await pause();
      RenderBox? node;
      void find(Element e) {
        if (e.widget.key == const ValueKey('c0') && e.renderObject is RenderBox) node = e.renderObject as RenderBox;
        e.visitChildren(find);
      }

      if (!mounted) return;
      context.visitChildElements(find);
      if (node != null) {
        final origin = node!.localToGlobal(node!.size.center(Offset.zero));
        GestureBinding.instance.handlePointerEvent(
          PointerDownEvent(pointer: 7, position: origin, kind: PointerDeviceKind.mouse, buttons: 1),
        );
        var previous = origin;
        await scenario('drag', (i) {
          final pos = origin + Offset(50 + i.toDouble(), 40 * math.sin(i / 10));
          GestureBinding.instance.handlePointerEvent(
            PointerMoveEvent(
              pointer: 7,
              position: pos,
              delta: pos - previous,
              kind: PointerDeviceKind.mouse,
              buttons: 1,
            ),
          );
          previous = pos;
        });
        GestureBinding.instance.handlePointerEvent(
          PointerUpEvent(pointer: 7, position: previous, kind: PointerDeviceKind.mouse),
        );
      }
      repo.delayed = true;
      await c.rename('c0', 'OLD pending title');
      await c.rename('c0', 'FINAL saved title');
      await scenario('delayed-stream', (i) {
        if (i == 25) repo.events.add(repo.pending.removeAt(0));
        if (i == 65) repo.events.add(repo.pending.removeAt(0));
      });
      repo.delayed = false;
      await pause();
    }
    SchedulerBinding.instance.removeTimingsCallback(record);
    final report = <String, Object>{};
    for (final entry in samples.entries) {
      double p95(List<int> values) {
        values.sort();
        return values[(values.length * .95).ceil() - 1] / 1000;
      }

      report[entry.key] = {
        'frames': entry.value.length,
        'build_p95_ms': p95(entry.value.map((f) => f.buildDuration.inMicroseconds).toList()),
        'raster_p95_ms': p95(entry.value.map((f) => f.rasterDuration.inMicroseconds).toList()),
        'over_16_67_ms': entry.value
            .where((f) => f.buildDuration.inMicroseconds > 16667 || f.rasterDuration.inMicroseconds > 16667)
            .length,
      };
    }
    stdout.writeln('RESULT ${jsonEncode({'label': runLabel, 'mode': mode, 'scenarios': report})}');
    setState(() => phase = 'DONE');
    await pause(20000);
    exit(0);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Text('GUL-497 | $runLabel | $mode | $count nodes | $phase'),
        ),
        const Expanded(child: MapPane(studySetId: 'bench')),
      ],
    ),
  );
}
