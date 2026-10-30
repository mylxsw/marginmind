import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/vocabulary/pdf_hints.dart';
import 'package:marginmind/features/vocabulary/vocabulary_hints.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

// Run: flutter build macos --release --target benchmark/vocabulary_hints.dart
// Uses the existing 300-page PDF fixture, with hints off as the control.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopWindow.initialize(
    title: 'GUL-597 Vocabulary benchmark',
    minimumSize: const Size(1000, 700),
    initialSize: const Size(1000, 700),
  );
  // Prevent macOS occlusion from suspending the benchmark's frame clock.
  // These settings belong only to this short-lived benchmark window.
  await windowManager.setAlwaysOnTop(true);
  await windowManager.setVisibleOnAllWorkspaces(true, visibleOnFullScreen: true);
  await MMPdfEngine.initialize();
  final data = await rootBundle.load('assets/sample/benchmark.pdf');
  final file = File('${Directory.systemTemp.path}/mm-pdf-benchmark.pdf');
  await file.writeAsBytes(data.buffer.asUint8List());
  // Keep the benchmark isolated from the user's persisted reading preferences.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({'vocabulary.hintMode': 'off'});
  final preferences = await SharedPreferences.getInstance();
  final now = DateTime.utc(2026);
  final terms = [
    'page',
    'line',
    'pdf',
    'rendering',
    'selection',
    'scrolling',
    'benchmark',
    for (var i = 0; i < 993; i++) 'unrelated$i',
  ];
  final vocabulary = InMemoryVocabularyRepository([
    for (final term in terms)
      VocabularyEntry(
        id: term,
        term: term,
        language: 'en',
        kind: VocabularyKind.word,
        createdAt: now,
        updatedAt: now,
        forms: [term],
        gloss: '释义',
      ),
  ]);
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        vocabularyRepositoryProvider.overrideWithValue(vocabulary),
      ],
      child: MaterialApp(
        theme: MMTheme.light(),
        home: Benchmark(path: file.path),
      ),
    ),
  );
}

class Benchmark extends ConsumerStatefulWidget {
  const Benchmark({super.key, required this.path});
  final String path;
  @override
  ConsumerState<Benchmark> createState() => _BenchmarkState();
}

class _BenchmarkState extends ConsumerState<Benchmark> {
  final controller = MMPdfViewController();
  final viewKey = GlobalKey();
  final paintKey = GlobalKey();
  final frames = <FrameTiming>[];
  final results = <String, Object>{};
  String phase = 'Loading';
  bool started = false;

  PdfViewerController get pdf {
    PdfViewerController? found;
    void visit(Element e) {
      if (e.widget case PdfViewer(:final controller)) found = controller;
      e.visitChildren(visit);
    }

    viewKey.currentContext!.visitChildElements(visit);
    return found!;
  }

  Future<void> run() async {
    if (started) return;
    started = true;
    try {
      await Future<void>.delayed(const Duration(seconds: 3));
      SchedulerBinding.instance.addTimingsCallback(frames.addAll);
      for (final mode in VocabularyHintMode.values) {
        await ref.read(vocabularyHintProvider.notifier).setMode(mode);
        for (final repeat in [false, true]) {
          for (final scenario in ['scroll', 'inertia']) {
            await pdf.goToPage(pageNumber: 1, duration: Duration.zero);
            await Future<void>.delayed(const Duration(seconds: 1));
            setState(() => phase = '${mode.name}-${repeat ? "repeat" : "first"}-$scenario');
            await Future<void>.delayed(const Duration(milliseconds: 200));
            frames.clear();
            final origin = pdf.centerPosition;
            final zoom = pdf.currentZoom;
            final watch = Stopwatch()..start();
            for (var i = 0; i < 360; i++) {
              final t = i / 359;
              switch (scenario) {
                case 'scroll':
                  pdf.value = pdf.calcMatrixFor(origin + Offset(0, t * 24000), zoom: zoom);
                case 'inertia':
                  pdf.value = pdf.calcMatrixFor(origin + Offset(0, 18000.0 * (1 - math.pow(1 - t, 3))), zoom: zoom);
              }
              SchedulerBinding.instance.scheduleFrame();
              await SchedulerBinding.instance.endOfFrame.timeout(const Duration(seconds: 5));
            }
            watch.stop();
            await Future<void>.delayed(const Duration(milliseconds: 500));
            Map<String, Object> summary(List<double> values) {
              values.sort();
              double percentile(double p) => values[(p * (values.length - 1)).ceil()];
              return {
                'p50_ms': percentile(.5),
                'p95_ms': percentile(.95),
                'p99_ms': percentile(.99),
                'over_16_67_percent': values.where((v) => v > 16.67).length * 100 / values.length,
              };
            }

            results[phase] = {
              'frames': frames.length,
              'duration_ms': watch.elapsedMilliseconds,
              'ui': summary(frames.map((f) => f.buildDuration.inMicroseconds / 1000).toList()),
              'raster': summary(frames.map((f) => f.rasterDuration.inMicroseconds / 1000).toList()),
              'total': summary(frames.map((f) => f.totalSpan.inMicroseconds / 1000).toList()),
              'rss_bytes': ProcessInfo.currentRss,
              'raw_us': [
                for (final f in frames)
                  [f.buildDuration.inMicroseconds, f.rasterDuration.inMicroseconds, f.totalSpan.inMicroseconds],
              ],
            };
          }
        }
      }
      SchedulerBinding.instance.removeTimingsCallback(frames.addAll);
      // stdout is collected by the runner, including on Release builds.
      // ignore: avoid_print
      print('VOCABULARY_BENCHMARK_JSON=${jsonEncode(results)}');
      exit(0);
    } catch (error, stack) {
      stderr.writeln('$error\n$stack');
      exit(1);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Vocabulary benchmark · $phase')),
    body: RepaintBoundary(
      key: paintKey,
      child: PdfVocabularyHints(
        studySetId: 'benchmark',
        documentId: 'benchmark',
        pdf: controller,
        builder: (hints, onTap, onViewport) => MMPdfView(
          key: viewKey,
          filePath: widget.path,
          controller: controller,
          highlights: hints,
          onViewportChanged: onViewport,
          onReady: (_) => run(),
        ),
      ),
    ),
  );
}
