import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_reflow/mm_reflow.dart';

const parser = EpubParser();
const spec = LayoutSpec(width: 240, pageHeight: 120);
BookChapter chapter(String id) =>
    parser.parseHtml(id, '<p>中文 é 👩‍👩‍👧‍👦 mixed text ${'word ' * 100}</p><p>end</p>');
void paint(ChapterLayout l, {int? page, Offset scroll = Offset.zero}) {
  final recorder = ui.PictureRecorder();
  l.paint(
    Canvas(recorder),
    page: page,
    localScroll: scroll,
    highlight: l.chapter.anchor(0, l.chapter.canonicalText.length),
  );
  recorder.endRecording().dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('complete specification keys distinguish all geometry and font inputs', () {
    const same = LayoutSpec(width: 240, pageHeight: 120);
    expect(same, spec);
    expect(same.hashCode, spec.hashCode);
    final variants = [
      const LayoutSpec(width: 241, pageHeight: 120),
      const LayoutSpec(width: 240, pageHeight: 121),
      const LayoutSpec(width: 240, fontSize: 22),
      const LayoutSpec(width: 240, lineHeight: 2),
      const LayoutSpec(width: 240, padding: EdgeInsets.all(8)),
      const LayoutSpec(width: 240, fontFamily: 'serif'),
      const LayoutSpec(width: 240, fontDigest: 'loaded'),
      const LayoutSpec(width: 240, locale: Locale('zh')),
      const LayoutSpec(width: 240, direction: TextDirection.rtl),
      const LayoutSpec(width: 240, textScale: 2),
      const LayoutSpec(width: 240, readerStyle: MMReaderStyle.dark),
      const LayoutSpec(width: 240, engineVersion: 2),
    ];
    expect(variants.every((v) => v != spec), isTrue);
    for (final invalid in [
      const LayoutSpec(width: double.nan),
      const LayoutSpec(width: 20, padding: EdgeInsets.all(10)),
      const LayoutSpec(width: 20, padding: EdgeInsets.all(-1)),
      const LayoutSpec(width: 20, textScale: 0),
    ]) {
      expect(invalid.validate, throwsArgumentError);
    }
    expect(() => ReflowEngine(maxBytes: -1), throwsArgumentError);
  });

  test('LRU enforces entries and bytes without disposing an active lease', () async {
    final engine = ReflowEngine(maxChapters: 2);
    final c = chapter('a');
    final first = await engine.layout(c, spec, 1, revision: 'r');
    final again = await engine.layout(c, spec, 2, revision: 'r');
    expect(identical(first.pieces.first.painter, again.pieces.first.painter), isTrue);
    expect(again.generation, 2);
    first.dispose();
    first.dispose();
    expect(() => first.hitTest(Offset.zero), throwsStateError);
    final second = await engine.layout(chapter('b'), spec, 2, revision: 'r');
    final third = await engine.layout(chapter('c'), spec, 2, revision: 'r');
    expect(engine.cachedLayouts, 2);
    expect(engine.cachedBytes, lessThanOrEqualTo(engine.maxBytes));
    paint(again);
    expect(again.hitTest(Offset.zero).start, 0);
    engine.evictChapter('b');
    expect(engine.cachedLayouts, 1);
    engine.clear();
    expect(engine.cachedBytes, 0);
    paint(second);
    again.dispose();
    second.dispose();
    third.dispose();
    engine.dispose();
    await expectLater(engine.layout(c, spec, 3, revision: 'r'), throwsA(isA<LayoutCancelled>()));
    final tiny = ReflowEngine(maxBytes: 1);
    final tooLarge = await tiny.layout(c, spec, 1, revision: 'r');
    expect(tiny.cachedLayouts, 0);
    tooLarge.dispose();
    tiny.dispose();
  });

  test('cache access refreshes LRU and 200 chapter changes stay within byte budget', () async {
    final samples = [for (var i = 0; i < 5; i++) chapter('ch-$i')];
    final probe = ChapterLayout.layout(samples.first, spec);
    final entryBytes = probe.estimatedBytes;
    probe.dispose();
    final engine = ReflowEngine(maxChapters: 3, maxBytes: entryBytes * 2 + 1);
    final a = await engine.layout(samples[0], spec, 1, revision: 'r');
    final b = await engine.layout(samples[1], spec, 1, revision: 'r');
    final refreshed = await engine.layout(samples[0], spec, 1, revision: 'r');
    refreshed.dispose();
    final c = await engine.layout(samples[2], spec, 1, revision: 'r');
    final stillA = await engine.layout(samples[0], spec, 1, revision: 'r');
    expect(identical(a.pieces.first.painter, stillA.pieces.first.painter), isTrue);
    final replacedB = await engine.layout(samples[1], spec, 1, revision: 'r');
    expect(identical(b.pieces.first.painter, replacedB.pieces.first.painter), isFalse);
    for (final lease in [a, b, c, stillA, replacedB]) {
      lease.dispose();
    }
    for (var turn = 0; turn < 200; turn++) {
      final layout = await engine.layout(samples[turn % samples.length], spec, 1, revision: 'r');
      expect(engine.cachedBytes, lessThanOrEqualTo(entryBytes * 2 + 1));
      expect(engine.cachedLayouts, lessThanOrEqualTo(2));
      layout.dispose();
    }
    engine.dispose();
    expect(engine.cachedBytes, 0);
  });

  test('revision, metadata and spec invalidate cached geometry', () async {
    final engine = ReflowEngine();
    final c = chapter('a');
    final leases = <ChapterLayout>[];
    for (final (revision, resources, layoutSpec) in [
      ('a', LayoutResources(), spec),
      ('b', LayoutResources(), spec),
      ('b', LayoutResources(revision: 'images-ready'), spec),
      ('b', LayoutResources(intrinsicSizes: {'x': const Size(20, 30)}), spec),
      ('b', LayoutResources(headerRows: {'t': 1}), spec),
      (
        'b',
        LayoutResources(
          containerStyles: {
            'p': {'padding': '2em'},
          },
        ),
        spec,
      ),
      ('b', LayoutResources(), const LayoutSpec(width: 320)),
    ]) {
      leases.add(await engine.layout(c, layoutSpec, 1, revision: revision, resources: resources));
    }
    for (var i = 1; i < leases.length; i++) {
      expect(identical(leases[i - 1].pieces.first.painter, leases[i].pieces.first.painter), isFalse);
    }
    expect(engine.cachedLayouts, lessThanOrEqualTo(3));
    for (final l in leases) {
      l.dispose();
    }
    engine.dispose();
  });

  test('yield boundaries discard cancelled and out-of-order results', () async {
    final gates = <Completer<void>>[];
    final engine = ReflowEngine(
      batchBudget: Duration.zero,
      yieldWork: () {
        final gate = Completer<void>();
        gates.add(gate);
        return gate.future;
      },
    );
    final c = chapter('c');
    final old = engine.layout(c, spec, 1, revision: 'r');
    final oldCheck = expectLater(old, throwsA(isA<LayoutCancelled>()));
    expect(gates.length, 1);
    engine.invalidate();
    gates.first.complete();
    await oldCheck;
    expect(engine.cachedLayouts, 0);
    final newer = engine.layout(c, spec, 3, revision: 'r');
    gates.last.complete();
    await Future<void>.delayed(Duration.zero);
    gates.last.complete();
    final result = await newer;
    expect(result.generation, 3);
    expect(result.workTime.inMicroseconds, greaterThan(0));
    expect(result.maxBatchTime.inMicroseconds, greaterThan(0));
    result.dispose();
    engine.dispose();
  });

  test('controller rejects stale callbacks and restores a source bookmark', () async {
    final selected = <List<TextAnchor>>[];
    final controller = ReflowController(onSelectionChanged: selected.add);
    final c = chapter('c');
    final first = (await controller.layout(c, spec, revision: 'r'))!;
    final anchor = c.anchor(40, 50);
    final top = first.reveal(c.anchor(40, 40))!.rect.top;
    final generation = first.generation;
    expect(controller.selectionChanged([anchor], generation: generation), isTrue);
    expect(selected.single.single.quote, anchor.quote);
    expect(controller.selectionChanged([const TextAnchor('c', 0, 1, 'bad')], generation: generation), isFalse);
    final pending = controller.layout(c, const LayoutSpec(width: 300, fontSize: 22), revision: 'r', viewportTop: top);
    expect(controller.hitTest(Offset.zero, generation: generation), isNull);
    expect(controller.boxes(anchor), isEmpty);
    expect(controller.reveal(anchor), isNull);
    expect(controller.selectionChanged([anchor], generation: generation), isFalse);
    expect(await controller.imagesReady(LayoutResources(), controller.generation), isFalse);
    final next = (await pending)!;
    expect(first.isDisposed, isTrue);
    expect(controller.boxes(anchor).every((b) => b.generation == next.generation), isTrue);
    expect(controller.restoredTop, greaterThan(0));
    expect(controller.reveal(anchor), isNotNull);
    expect(controller.hitTest(Offset.zero, generation: next.generation), isNotNull);
    expect(controller.selection.single.quote, anchor.quote);
    expect(
      await controller.imagesReady(
        LayoutResources(revision: 'ready'),
        next.generation,
        viewportTop: controller.restoredTop,
      ),
      isTrue,
    );
    expect(await controller.imagesReady(LayoutResources(), next.generation), isFalse);
    expect(await controller.imagesReady(LayoutResources(), generation), isFalse);
    await controller.layout(c, spec, revision: 'r', position: c.anchor(0, 0));
    expect(controller.restoredTop, 0);
    controller.dispose();
    controller.dispose();
    await expectLater(controller.layout(c, spec, revision: 'r'), throwsStateError);
  });

  test('controller cancellation, disposal and unresolvable bookmark are safe', () async {
    final gates = <Completer<void>>[];
    final controller = ReflowController(
      engine: ReflowEngine(
        batchBudget: Duration.zero,
        yieldWork: () {
          final gate = Completer<void>();
          gates.add(gate);
          return gate.future;
        },
      ),
    );
    final pending = controller.layout(chapter('c'), spec, revision: 'r');
    controller.dispose();
    gates.single.complete();
    expect(await pending, isNull);
    final normal = ReflowController();
    final l = (await normal.layout(chapter('a'), spec, revision: 'r', position: const TextAnchor('other', 0, 0, '')))!;
    expect(normal.restoredTop, 0);
    expect(l.reveal(const TextAnchor('a', 0, 1, 'bad')), isNull);
    normal.dispose();
  });

  test('image pixel admission and changed image handles cannot reuse painters', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 10, 10), Paint());
    final picture = recorder.endRecording();
    final a = MMBookImage.raster(await picture.toImage(10, 10));
    final b = MMBookImage.raster(await picture.toImage(10, 10));
    picture.dispose();
    final c = parser.parseHtml('c', '<p>A<img src="x">B</p>');
    final engine = ReflowEngine(maxImagePixels: 100);
    await expectLater(
      engine.layout(
        c,
        spec,
        1,
        revision: 'r',
        resources: LayoutResources(images: {'x': a, 'y': b}),
      ),
      throwsA(
        isA<ImageBudgetExceeded>()
            .having((e) => e.decodedPixels, 'decodedPixels', 200)
            .having((e) => e.budget, 'budget', 100)
            .having((e) => e.toString(), 'description', contains('200')),
      ),
    );
    expect(engine.cachedLayouts, 0);
    final fallback = await engine.layout(
      c,
      spec,
      1,
      revision: 'r',
      resources: LayoutResources(intrinsicSizes: {'x': a.size}),
    );
    expect(fallback.pieces.single.artwork.single.image, isNull);
    expect(fallback.boxes(c.anchor(0, c.canonicalText.length)), isNotEmpty);
    paint(fallback);
    fallback.dispose();
    final first = await engine.layout(
      c,
      spec,
      1,
      revision: 'r',
      resources: LayoutResources(images: {'x': a}),
    );
    final second = await engine.layout(
      c,
      spec,
      1,
      revision: 'r',
      resources: LayoutResources(images: {'x': b}),
    );
    expect(identical(first.pieces.first.painter, second.pieces.first.painter), isFalse);
    engine.dispose();
    paint(first);
    paint(second);
    first.dispose();
    second.dispose();
    a.dispose();
    b.dispose();
  });
}
