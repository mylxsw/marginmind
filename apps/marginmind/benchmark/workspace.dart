// Full application benchmark entry. Only input comes from native desktop events.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  stdout.writeln('BOOT bindings');
  await DesktopWindow.initialize(
    title: 'GUL-495 Workspace',
    minimumSize: const Size(1200, 800),
    initialSize: const Size(1600, 1000),
  );
  stdout.writeln('BOOT window');
  await windowManager.setAlwaysOnTop(true);
  await windowManager.setVisibleOnAllWorkspaces(true);
  await windowManager.maximize();
  stdout.writeln('BOOT engine');
  await MMPdfEngine.initialize();
  final directory = await Directory.systemTemp.createTemp('gul495-workspace-');
  final store = FileLibraryStore(directory);
  final set = await store.create(const NewStudySet(title: 'GUL-495 • 300 nodes • 120 raster pages', colorIndex: 0));
  final data = await rootBundle.load('assets/sample/workspace-images.pdf');
  final source = File('${directory.path}/images.pdf');
  await source.writeAsBytes(data.buffer.asUint8List());
  final fileName = await store.importFile(set.id, source.path);
  var counter = 0;
  final editor = StudySetEditor(newId: () => 'fixture-${++counter}', now: () => DateTime(2026, 10, 26));
  var content = editor
      .addDocument(StudySetContent.empty, title: 'Raster images — 1800×2400', fileName: fileName, pageCount: 120)
      .$1;
  for (var group = 0; group < 10; group++) {
    final root = editor.addTopic(content, title: 'Chapter $group');
    content = root.$1;
    for (var node = 0; node < 29; node++) {
      content = editor.addTopic(content, title: 'Evidence $group.$node', parentId: root.$2.id).$1;
    }
  }
  await store.update(set.id, (_) => content);
  stdout.writeln('BOOT seeded');
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      studySetRepositoryProvider.overrideWithValue(store),
      contentRepositoryProvider.overrideWithValue(store),
    ],
  );
  stdout.writeln('BOOT provider');
  stdout.writeln('BOOT loaded');
  container.read(navigationProvider.notifier).openStudySet(set.id);
  final frames = <FrameTiming>[];
  final events = <Map<String, num>>[];
  final clock = Stopwatch();
  var recording = false;
  WidgetsBinding.instance.addTimingsCallback((batch) {
    if (recording) frames.addAll(batch);
  });
  Future<void> finish() async {
    recording = false;
    final result = {
      'label': const String.fromEnvironment('BENCH_LABEL'),
      'finalPage': container.read(workspaceProvider(set.id).notifier).activePage,
      'nodes': 300,
      'pages': 120,
      'dpr': WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio,
      'rss': ProcessInfo.currentRss,
      'events': events,
      'frames_us': [
        for (final f in frames)
          [f.buildDuration.inMicroseconds, f.rasterDuration.inMicroseconds, f.totalSpan.inMicroseconds],
      ],
    };
    stdout.writeln('WORKSPACE_TIMINGS_JSON=${jsonEncode(result)}');
    await stdout.flush();
    await Future<void>.delayed(const Duration(seconds: 2));
    exit(0);
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: Listener(
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent) return;
          if (!recording && events.isEmpty) {
            recording = true;
            clock.start();
            Timer(const Duration(seconds: 32), finish);
          }
          events.add({'ms': clock.elapsedMilliseconds, 'dy': event.scrollDelta.dy});
        },
        child: const MarginMindApp(),
      ),
    ),
  );
  Timer(const Duration(seconds: 8), () => stdout.writeln('WORKSPACE_READY'));
}
