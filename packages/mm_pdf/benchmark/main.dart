// Run with the app's macOS host; see docs/pdf-performance.md.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopWindow.initialize(
    title: 'GUL-495 PDF benchmark',
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
  runApp(MaterialApp(home: Benchmark(path: file.path)));
}

class Benchmark extends StatefulWidget {
  const Benchmark({super.key, required this.path});
  final String path;
  @override
  State<Benchmark> createState() => _BenchmarkState();
}

class _BenchmarkState extends State<Benchmark> {
  final controller = MMPdfViewController();
  final viewKey = GlobalKey();
  final paintKey = GlobalKey();
  final frames = <FrameTiming>[];
  final results = <String, Object>{};
  String phase = 'Loading';
  bool started = false;
  final highlights = [
    for (var page = 1; page <= 300; page++)
      for (var line = 0; line < 20; line++)
        MMPdfHighlight(
          id: '$page-$line',
          page: page,
          rects: [PageRect(40, 800 - line * 16.0, 400, 788 - line * 16.0)],
          color: const Color(0x55FFFF00),
        ),
  ];

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
      for (final warm in [false, true]) {
        for (final scenario in ['scroll', 'jump', 'inertia', 'zoom']) {
          await pdf.goToPage(pageNumber: 1, duration: Duration.zero);
          await Future<void>.delayed(const Duration(seconds: 1));
          setState(() => phase = '${warm ? "warm" : "cold"}-$scenario');
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
              case 'jump':
                if (i % 30 == 0) {
                  await pdf.goToPage(pageNumber: 1 + (i ~/ 30) * 24, duration: Duration.zero);
                }
              case 'inertia':
                pdf.value = pdf.calcMatrixFor(origin + Offset(0, 18000.0 * (1 - math.pow(1 - t, 3))), zoom: zoom);
              case 'zoom':
                pdf.value = pdf.calcMatrixFor(origin, zoom: zoom * (1.5 - 0.5 * math.cos(t * math.pi * 4)));
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
      SchedulerBinding.instance.removeTimingsCallback(frames.addAll);
      final appearance = <Map<String, Object>>[];
      // Actual visible ink, not render request duration or FrameTiming. The
      // readback overhead is included, making this an observable upper bound.
      for (final page in [299, 279, 259, 239, 219, 199, 179, 159, 139, 119]) {
        final watch = Stopwatch()..start();
        await pdf.goToPage(pageNumber: page, duration: Duration.zero);
        var ink = 0;
        do {
          SchedulerBinding.instance.scheduleFrame();
          await SchedulerBinding.instance.endOfFrame;
          final boundary = paintKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = (await image.toByteData())!.buffer.asUint8List();
          ink = 0;
          for (var y = image.height ~/ 5; y < image.height * 4 ~/ 5; y++) {
            for (var x = image.width * 3 ~/ 10; x < image.width * 7 ~/ 10; x++) {
              final offset = (y * image.width + x) * 4;
              if (data[offset] < 100 && data[offset + 1] < 100 && data[offset + 2] < 100) ink++;
            }
          }
          image.dispose();
        } while (ink < 100 && watch.elapsedMilliseconds < 5000);
        if (ink < 100) throw StateError('Page $page did not display ink in 5 seconds');
        appearance.add({'page': page, 'first_ink_ms': watch.elapsedMicroseconds / 1000, 'ink_pixels': ink});
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      results['appearance'] = {'method': 'jump to first visible ink, includes GPU readback', 'samples': appearance};
      // stdout is collected by the runner, including on Release builds.
      // ignore: avoid_print
      print('PDF_BENCHMARK_JSON=${jsonEncode(results)}');
      exit(0);
    } catch (error, stack) {
      stderr.writeln('$error\n$stack');
      exit(1);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('PDF benchmark · $phase')),
    body: RepaintBoundary(
      key: paintKey,
      child: MMPdfView(
        key: viewKey,
        filePath: widget.path,
        controller: controller,
        highlights: highlights,
        onReady: (_) => run(),
      ),
    ),
  );
}
