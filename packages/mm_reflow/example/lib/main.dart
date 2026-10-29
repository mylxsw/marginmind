import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_reflow/mm_reflow.dart';

import 'l10n/probe_localizations.dart';

void main() => runApp(
  MaterialApp(
    theme: MMTheme.light(),
    localizationsDelegates: ProbeLocalizations.localizationsDelegates,
    supportedLocales: ProbeLocalizations.supportedLocales,
    home: const Probe(),
  ),
);

// Scientific parameters, not product UI presets. Reproduction commands can override them.
const sampleIds = ['7337', '33283', '28885'];
const onlyBook = String.fromEnvironment('BOOK');
const autoBenchmark = bool.fromEnvironment('BENCHMARK');
const repeats = int.fromEnvironment('REPEATS', defaultValue: 30);

class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  Book? book;
  ChapterLayout? layout;
  final engine = ReflowEngine();
  String revision = '';
  Map<String, MMBookImage> images = {};
  int chapter = 0, page = 0, bookIndex = 0;
  double size = 16;
  bool scroll = false, busy = false;
  String? failure;
  TextAnchor? selection;
  final frames = <Map<String, int>>[];
  bool collectFrames = false;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(onTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await loadBook(0);
      if (autoBenchmark && mounted) await benchmark();
    });
  }

  void onTimings(List<ui.FrameTiming> timings) {
    if (!collectFrames) return;
    frames.addAll(
      timings.map(
        (f) => {
          'build_us': f.buildDuration.inMicroseconds,
          'raster_us': f.rasterDuration.inMicroseconds,
        },
      ),
    );
  }

  void emit(Map<String, Object?> value) {
    // JSONL is the harness protocol; no source text or credentials are logged.
    // ignore: avoid_print
    print('REFLOW ${jsonEncode(value)}');
  }

  Future<Map<String, MMBookImage>> decode(Book b, BookChapter c) async {
    final result = <String, MMBookImage>{};
    for (final path
        in c.blocks
            .expand(
              (b) => [
                b.resource,
                ...b.runs.map((r) => r.resource),
                ...b.rows.expand(
                  (row) =>
                      row.expand((cell) => cell.runs.map((r) => r.resource)),
                ),
              ],
            )
            .whereType<String>()
            .toSet()) {
      final bytes = b.resources[path];
      if (bytes == null) {
        emit({'kind': 'missing_image', 'path': path});
        continue;
      }
      try {
        result[path] = await MMBookImage.decode(
          bytes,
          svgImage: path.toLowerCase().endsWith('.svg'),
        );
      } catch (_) {
        emit({'kind': 'unsupported_image', 'path': path});
      }
    }
    return result;
  }

  Future<void> loadBook(int index) async {
    try {
      final bytes = await rootBundle.load('assets/${sampleIds[index]}.epub');
      book = const EpubParser().parse(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      revision = book!.revision;
      bookIndex = index;
      await loadChapter(0);
    } catch (error, stack) {
      emit({'kind': 'error', 'error': '$error', 'stack': '$stack'});
      if (mounted) setState(() => failure = '$error');
    }
  }

  Future<void> loadChapter(int index) async {
    final request = ++generation;
    final decoded = await decode(book!, book!.chapters[index]);
    if (!mounted || request != generation) {
      for (final i in decoded.values) {
        i.dispose();
      }
      return;
    }
    final oldLayout = layout;
    final oldImages = images;
    late ChapterLayout next;
    try {
      next = await engine.layout(
        book!.chapters[index],
        LayoutSpec(width: 360, fontSize: size),
        request,
        revision: revision,
        resources: LayoutResources(images: decoded),
      );
    } on LayoutCancelled {
      for (final image in decoded.values) {
        image.dispose();
      }
      return;
    } catch (_) {
      for (final image in decoded.values) {
        image.dispose();
      }
      rethrow;
    }
    if (!mounted || request != generation) {
      next.dispose();
      engine.evictChapter(next.chapter.id);
      for (final image in decoded.values) {
        image.dispose();
      }
      return;
    }
    images = decoded;
    chapter = index;
    page = 0;
    selection = null;
    setState(() => layout = next);
    oldLayout?.dispose();
    engine
        .clear(); // Release borrowed old image handles before their owner does.
    for (final i in oldImages.values) {
      i.dispose();
    }
  }

  Future<void> relayout({double width = 360}) async {
    final request = ++generation;
    final oldOffset =
        selection?.start ??
        (layout == null
            ? 0
            : layout!.hitTest(Offset(0, layout!.pages[page].top)).start);
    try {
      final next = await engine.layout(
        book!.chapters[chapter],
        LayoutSpec(width: width, fontSize: size),
        request,
        revision: revision,
        resources: LayoutResources(images: images),
        visibleOffset: oldOffset,
      );
      if (!mounted || request != generation) {
        next.dispose();
        return;
      }
      final previous = layout;
      layout = next;
      page = next.pageForOffset(oldOffset);
      setState(() {});
      previous?.dispose();
    } on LayoutCancelled {
      /* A newer settings request owns the surface. */
    }
  }

  Future<void> benchmark({
    int iterations = repeats,
    int pageChanges = 200,
    int memoryRounds = 5,
    int switchesPerRound = 10,
    Duration settleDelay = const Duration(seconds: 2),
    List<int> bookIndices = const [0, 1, 2],
  }) async {
    if (busy) return;
    setState(() => busy = true);
    emit({
      'kind': 'environment',
      'profile': kProfileMode,
      'release': kReleaseMode,
      'platform': defaultTargetPlatform.name,
      'pixel_ratio': View.of(context).devicePixelRatio,
      'refresh_hz': View.of(context).display.refreshRate,
      'repeats': iterations,
    });
    final measureEngine = ReflowEngine(maxChapters: 0);
    try {
      for (final bi in bookIndices) {
        if (onlyBook.isNotEmpty && sampleIds[bi] != onlyBook) continue;
        await loadBook(bi);
        if (failure != null) throw StateError(failure!);
        final b = book!;
        emit({
          'kind': 'book',
          'id': sampleIds[bi],
          'chapters': b.chapters.length,
          'diagnostics': b.diagnostics.take(2).toList(),
          'diagnostic_count': b.diagnostics.length,
        });
        for (var ci = 0; ci < b.chapters.length; ci++) {
          MMBookImage.clearSvgCache();
          final decodeWatch = Stopwatch()..start();
          await loadChapter(ci);
          emit({
            'kind': 'decode',
            'chapter': ci,
            'state': 'cold',
            'us': decodeWatch.elapsedMicroseconds,
            'images': images.length,
          });
          decodeWatch.reset();
          await loadChapter(ci);
          emit({
            'kind': 'decode',
            'chapter': ci,
            'state': 'hot',
            'us': decodeWatch.elapsedMicroseconds,
            'images': images.length,
          });
          final c = b.chapters[ci];
          for (final width in [320.0, 768.0, 1200.0]) {
            for (var iteration = -2; iteration < iterations; iteration++) {
              for (final fontSize in [16.0, 22.0]) {
                final watch = Stopwatch()..start();
                final measured = await measureEngine.layout(
                  c,
                  LayoutSpec(width: width, fontSize: fontSize),
                  0,
                  revision: revision,
                  resources: LayoutResources(images: images),
                );
                watch.stop();
                final anchor = c.anchor(
                  0,
                  math.min(c.canonicalText.length, 32),
                );
                final boxes = measured.boxes(anchor);
                final matches =
                    c.resolves(anchor) &&
                    (anchor.quote.isEmpty || boxes.isNotEmpty);
                if (iteration >= 0) {
                  emit({
                    'kind': 'layout',
                    'book': sampleIds[bi],
                    'chapter': ci,
                    'utf16': c.canonicalText.length,
                    'blocks': c.blocks.length,
                    'images': images.length,
                    'tables': c.blocks
                        .where((b) => b.kind == BlockKind.table)
                        .length,
                    'width': width,
                    'font': fontSize,
                    'iteration': iteration,
                    'us': watch.elapsedMicroseconds,
                    'work_us': measured.workTime.inMicroseconds,
                    'max_batch_us': measured.maxBatchTime.inMicroseconds,
                    'pages': measured.pages.length,
                    'anchor_ok': matches,
                  });
                }
                measured.dispose();
              }
              // Deliberate scheduling boundary outside measured layout time.
              await Future<void>.delayed(Duration.zero);
            }
          }
        }
        // Measure actual rendered page changes, independent of layout loops.
        final illustrated = b.chapters
            .asMap()
            .entries
            .where(
              (e) => e.value.blocks.any(
                (block) =>
                    block.runs.any((r) => r.resource != null) ||
                    block.rows.any(
                      (row) => row.any(
                        (cell) => cell.runs.any((r) => r.resource != null),
                      ),
                    ),
              ),
            )
            .map((e) => e.key)
            .toList();
        if (illustrated.isEmpty) illustrated.add(0);
        for (final state in ['cold', 'hot']) {
          frames.clear();
          collectFrames = true;
          for (var i = 0; i < pageChanges; i++) {
            if (i % 20 == 0) {
              if (state == 'cold') MMBookImage.clearSvgCache();
              await loadChapter(illustrated[(i ~/ 20) % illustrated.length]);
            }
            setState(() => page = (i % 20) % layout!.pages.length);
            await WidgetsBinding.instance.endOfFrame;
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
          collectFrames = false;
          for (final f in frames) {
            emit({
              'kind': 'frame',
              'book': sampleIds[bi],
              'state': state,
              ...f,
            });
          }
        }
        // Ten switches per round, identical chapter sequence, fixed end chapter.
        // PSS snapshots are collected by the host on each settled round event.
        for (var round = 0; round <= memoryRounds; round++) {
          if (round > 0) {
            for (var i = 0; i < switchesPerRound; i++) {
              await loadChapter(illustrated[i % illustrated.length]);
              await WidgetsBinding.instance.endOfFrame;
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
          } else {
            await loadChapter(
              illustrated[(switchesPerRound - 1) % illustrated.length],
            );
          }
          await Future<void>.delayed(settleDelay);
          emit({
            'kind': 'memory_round',
            'round': round,
            'switches': round * switchesPerRound,
          });
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        emit({'kind': 'book_done', 'book': sampleIds[bi]});
      }
      for (final scenario in [
        'long-chapter',
        'single-paragraph',
        'huge-image',
      ]) {
        final html = switch (scenario) {
          'long-chapter' => '<p>${'中文 mixed text ' * 20}</p>' * 500,
          'single-paragraph' => '<p>${'中文 mixed text ' * 3000}</p>',
          _ => '<img src="huge">',
        };
        final stress = const EpubParser().parseHtml(scenario, html);
        final resources = LayoutResources(
          intrinsicSizes: {'huge': const Size(100000, 100000)},
        );
        for (var i = -2; i < iterations; i++) {
          for (final font in [16.0, 22.0]) {
            final timer = Stopwatch()..start();
            final measured = await measureEngine.layout(
              stress,
              LayoutSpec(width: 320, fontSize: font),
              0,
              revision: 'synthetic-v1',
              resources: resources,
            );
            if (i >= 0) {
              emit({
                'kind': 'stress_layout',
                'scenario': scenario,
                'iteration': i,
                'font': font,
                'utf16': stress.canonicalText.length,
                'us': timer.elapsedMicroseconds,
                'work_us': measured.workTime.inMicroseconds,
                'max_batch_us': measured.maxBatchTime.inMicroseconds,
              });
            }
            measured.dispose();
          }
        }
      }
      emit({'kind': 'done'});
    } catch (error, stack) {
      emit({'kind': 'error', 'error': '$error', 'stack': '$stack'});
    }
    measureEngine.dispose();
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ProbeLocalizations.of(context)!;
    final l = layout;
    return Scaffold(
      appBar: AppBar(title: Text(book?.title ?? strings.loading)),
      body: SafeArea(
        child: Column(
          children: [
            Wrap(
              children: [
                for (var i = 0; i < sampleIds.length; i++)
                  TextButton(
                    onPressed: busy ? null : () => loadBook(i),
                    child: Text(sampleIds[i]),
                  ),
                IconButton(
                  tooltip: strings.chapter,
                  onPressed: busy || book == null
                      ? null
                      : () =>
                            loadChapter((chapter + 1) % book!.chapters.length),
                  icon: const Icon(Icons.menu_book),
                ),
                IconButton(
                  tooltip: strings.previous,
                  onPressed: busy || l == null
                      ? null
                      : () => setState(() => page = math.max(0, page - 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: strings.next,
                  onPressed: busy || l == null
                      ? null
                      : () => setState(
                          () => page = math.min(l.pages.length - 1, page + 1),
                        ),
                  icon: const Icon(Icons.chevron_right),
                ),
                IconButton(
                  tooltip: strings.fontSize,
                  onPressed: busy || l == null
                      ? null
                      : () {
                          size = size == 16 ? 22 : 16;
                          relayout();
                        },
                  icon: const Icon(Icons.text_fields),
                ),
                IconButton(
                  tooltip: strings.scroll,
                  onPressed: busy
                      ? null
                      : () => setState(() => scroll = !scroll),
                  icon: const Icon(Icons.swap_vert),
                ),
                IconButton(
                  tooltip: strings.benchmark,
                  onPressed: busy ? null : benchmark,
                  icon: const Icon(Icons.speed),
                ),
              ],
            ),
            if (failure != null) Text(strings.failed),
            if (l != null)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: ReflowSurface(
                      layout: l,
                      page: scroll ? null : page,
                      highlight: selection,
                      onSelection: (anchor) =>
                          setState(() => selection = anchor),
                    ),
                  ),
                ),
              ),
            if (l != null)
              Text(
                '${chapter + 1}/${book!.chapters.length} · ${page + 1}/${l.pages.length}',
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeTimingsCallback(onTimings);
    layout?.dispose();
    engine.dispose();
    for (final image in images.values) {
      image.dispose();
    }
    super.dispose();
  }
}
