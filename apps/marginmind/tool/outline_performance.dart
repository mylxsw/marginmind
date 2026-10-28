// Native, in-memory workload: flutter run -d macos --profile
// -t tool/outline_performance.dart --dart-define=RUN_LABEL=before
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

const label = String.fromEnvironment('RUN_LABEL', defaultValue: 'local');
final now = DateTime(2026);
StudySetContent fixture(int count) => StudySetContent(
  cards: [for (var i = 0; i < count; i++) Card(id: 'c$i', kind: CardKind.topic, title: 'Node $i 中文', createdAt: now)],
  nodes: [
    for (var i = 0; i < count; i++)
      MapNode(cardId: 'c$i', parentId: i < 6 ? null : 'c${(i - 6) ~/ 6}', order: i.toDouble()),
  ],
);
final repo = InMemoryStudySetContentRepository({'bench': fixture(50)});
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  final frames = <FrameTiming>[];
  final report = <String, Object>{};
  bool recording = false;
  String phase = 'warmup';
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(record);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(
        run().catchError((Object error, StackTrace stack) {
          stderr.writeln('$error\n$stack');
          exit(1);
        }),
      ),
    );
  }

  void record(List<FrameTiming> values) {
    if (recording) frames.addAll(values);
  }

  Future<void> pause([int ms = 500]) => Future<void>.delayed(Duration(milliseconds: ms));
  Offset pointFor(String title) {
    Offset? point;
    void visit(Element e) {
      if (e.widget is Text && (e.widget as Text).data == title) {
        final box = e.findRenderObject()! as RenderBox;
        point = box.localToGlobal(box.size.center(Offset.zero));
      }
      e.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return point!;
  }

  Future<void> run() async {
    await pause(2500);
    final controller = ref.read(workspaceProvider('bench').notifier);
    controller.setMapView(MapViewMode.outline);
    for (final count in [50, 500, 2000]) {
      setState(() => phase = '$count setup');
      await repo.update('bench', (_) => fixture(count));
      controller.selectCard(null);
      await pause(1000);
      final points = [pointFor('Node 0 中文'), pointFor('Node 6 中文')];
      for (final input in ['selection', 'mouse']) {
        setState(() => phase = '$count $input');
        await pause();
        frames.clear();
        final latency = <int>[];
        recording = true;
        for (var i = 0; i < 30; i++) {
          final id = i.isEven ? 'c0' : 'c6';
          final timer = Stopwatch()..start();
          if (input == 'mouse') {
            final point = points[i % 2];
            GestureBinding.instance.handlePointerEvent(
              PointerDownEvent(
                pointer: i + 1,
                position: point,
                kind: PointerDeviceKind.mouse,
                buttons: kPrimaryMouseButton,
              ),
            );
            await pause(8);
            GestureBinding.instance.handlePointerEvent(
              PointerUpEvent(pointer: i + 1, position: point, kind: PointerDeviceKind.mouse),
            );
          } else {
            controller.selectCard(id);
          }
          while (ref.read(workspaceProvider('bench')).selectedCardId != id) {
            if (timer.elapsedMilliseconds > 2000) throw StateError('Selection timed out');
            await pause(1);
          }
          await WidgetsBinding.instance.endOfFrame;
          latency.add(timer.elapsedMicroseconds);
          await pause(350);
        }
        await pause();
        recording = false;
        double p95(List<int> data) {
          data.sort();
          return data[(data.length * .95).ceil() - 1] / 1000;
        }

        report['$count/$input'] = {
          'frames': frames.length,
          'selection_to_frame_p95_ms': p95(latency),
          'build_p95_ms': p95(frames.map((f) => f.buildDuration.inMicroseconds).toList()),
          'raster_p95_ms': p95(frames.map((f) => f.rasterDuration.inMicroseconds).toList()),
          'over_16_67_ms': frames
              .where((f) => f.buildDuration.inMicroseconds > 16667 || f.rasterDuration.inMicroseconds > 16667)
              .length,
        };
        stdout.writeln('SCENARIO $label ${jsonEncode({'$count/$input': report['$count/$input']})}');
      }
    }
    SchedulerBinding.instance.removeTimingsCallback(record);
    stdout.writeln('RESULT ${jsonEncode({'label': label, 'scenarios': report})}');
    exit(0);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Padding(padding: const EdgeInsets.only(top: 40), child: Text('Outline $label $phase')),
        const Expanded(child: MapPane(studySetId: 'bench')),
      ],
    ),
  );
}
