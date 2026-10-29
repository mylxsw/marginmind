// Run from apps/marginmind:
// flutter run -d macos -t ../../packages/mm_pdf/example/reading_probe.dart \
//   --dart-define=PROBE_PDF=/absolute/path/to/document.pdf
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MMPdfEngine.initialize();
  const path = String.fromEnvironment('PROBE_PDF');
  final PdfDocument document;
  if (const bool.fromEnvironment('PROBE_SELF_CHECK')) {
    final data = await rootBundle.load('assets/sample/sample.pdf');
    document = await PdfDocument.openData(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  } else {
    document = await PdfDocument.openFile(path);
  }
  final text = await document.pages.first.loadText();
  if (const bool.fromEnvironment('PROBE_SELF_CHECK')) {
    final page = document.pages.first;
    final image = await page.render(
      x: 24,
      y: 36,
      width: (page.width - 72).round(),
      height: (page.height - 56).round(),
      fullWidth: page.width,
      fullHeight: page.height,
    );
    if (image == null || text == null || text.fullText.isEmpty) throw StateError('Native PDFium probe failed');
    debugPrint(
      'NATIVE_PROBE_OK pages=${document.pages.length} cropped=${image.width}x${image.height} chars=${text.fullText.length}',
    );
    image.dispose();
    await document.dispose();
    exit(0);
  }
  runApp(
    MaterialApp(
      home: ReadingProbe(path: path, document: document, text: text),
    ),
  );
}

/// Deliberately separate from production UI: proves a cropped page renderer
/// with original-coordinate selection/ink, a viewport margin, and real PdfViews.
class ReadingProbe extends StatefulWidget {
  const ReadingProbe({super.key, required this.path, required this.document, this.text});
  final String path;
  final PdfDocument document;
  final PdfPageRawText? text;
  @override
  State<ReadingProbe> createState() => _ReadingProbeState();
}

class _ReadingProbeState extends State<ReadingProbe> {
  final controllers = [MMPdfViewController(), MMPdfViewController()];
  final sync = ReadingSync();
  bool cropped = true, ink = false;
  double scale = .65;
  final marks = <Offset>[];
  final selected = <PageRect>[];
  Offset? start;
  final _pending = <int>{};
  @override
  void dispose() {
    sync.dispose();
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void changed(int side) {
    if (!_pending.add(side)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending.remove(side);
      if (!mounted || !controllers.every((c) => c.isReady)) return;
      final position = controllers[side].readingPosition;
      if (position == null) return;
      final mapping = ReadingAlignment(
        leftHeights: controllers[0].pageHeights,
        rightHeights: controllers[1].pageHeights,
      );
      final target = mapping.map(position, reverse: side == 1);
      final current = controllers[1 - side].readingPosition!;
      final heights = controllers[1 - side].pageHeights;
      if ((ReadingAlignment.scalar(target, heights) - ReadingAlignment.scalar(current, heights)).abs() < .001) return;
      unawaited(
        sync.drive(side, () => controllers[1 - side].jumpToReadingPosition(mapping.map(position, reverse: side == 1))),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Reading probe · pdfrx 2.10.1'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Crop + margin'),
            Tab(text: 'Two PdfViews'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          cropPage(),
          Row(
            children: [
              for (var side = 0; side < 2; side++)
                Expanded(
                  child: Listener(
                    onPointerDown: (_) => sync.userInput(side),
                    onPointerSignal: (_) => sync.userInput(side),
                    child: MMPdfView(
                      filePath: widget.path,
                      controller: controllers[side],
                      onViewportChanged: () => changed(side),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  Widget cropPage() {
    final page = widget.document.pages.first;
    final geometry = PageViewportTransform(
      pageSize: Size(page.width, page.height),
      crop: cropped ? CropInsets(left: 24, top: 36, right: 48, bottom: 20) : CropInsets(),
      scale: scale,
    );
    final size = geometry.visibleSize;
    return Column(
      children: [
        Wrap(
          children: [
            TextButton(onPressed: () => setState(() => cropped = !cropped), child: Text(cropped ? 'Uncrop' : 'Crop')),
            TextButton(onPressed: () => setState(() => ink = !ink), child: Text(ink ? 'Ink' : 'Select')),
            TextButton(onPressed: () => setState(() => scale = scale == .65 ? 1 : .65), child: const Text('Zoom')),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: size.width + 220,
                height: size.height + 80,
                // The margin is a sibling in the viewport, never a page overlay.
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      width: size.width,
                      height: size.height,
                      child: GestureDetector(
                        key: const ValueKey('crop-surface'),
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) => setState(() {
                          start = geometry.toPdf(d.localPosition);
                          if (ink) marks.add(start!);
                        }),
                        onPanUpdate: (d) => setState(() {
                          final point = geometry.toPdf(d.localPosition);
                          if (ink) {
                            marks.add(point);
                            return;
                          }
                          final area = Rect.fromPoints(start!, point);
                          selected.clear();
                          for (final r in widget.text?.charRects ?? <PdfRect>[]) {
                            if (Rect.fromLTRB(r.left, r.bottom, r.right, r.top).overlaps(area)) {
                              selected.add(PageRect(r.left, r.top, r.right, r.bottom));
                            }
                          }
                        }),
                        child: ClipRect(
                          child: Stack(
                            children: [
                              Positioned(
                                left: -geometry.crop.left * scale,
                                top: -geometry.crop.top * scale,
                                width: page.width * scale,
                                height: page.height * scale,
                                child: PdfPageView(
                                  document: widget.document,
                                  pageNumber: 1,
                                  decoration: const BoxDecoration(color: Colors.white),
                                ),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(painter: ProbeMarks(geometry, List.of(selected), List.of(marks))),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: size.width + 12,
                      top: 80,
                      width: 196,
                      child: const TextField(
                        key: ValueKey('margin-card'),
                        maxLines: null,
                        decoration: InputDecoration(filled: true, hintText: 'Margin note'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ProbeMarks extends CustomPainter {
  ProbeMarks(this.geometry, this.selected, this.ink);
  final PageViewportTransform geometry;
  final List<PageRect> selected;
  final List<Offset> ink;
  @override
  void paint(Canvas canvas, Size size) {
    final highlight = Paint()..color = const Color(0x66FFCC00);
    for (final rect in selected) {
      canvas.drawRect(geometry.rect(rect), highlight);
    }
    final pen = Paint()
      ..color = Colors.red
      ..strokeWidth = 2;
    for (var i = 1; i < ink.length; i++) {
      canvas.drawLine(geometry.toViewport(ink[i - 1]), geometry.toViewport(ink[i]), pen);
    }
  }

  @override
  bool shouldRepaint(covariant ProbeMarks oldDelegate) => true;
}
