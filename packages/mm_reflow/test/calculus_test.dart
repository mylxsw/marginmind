import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_reflow/mm_reflow.dart';

void main() {
  testWidgets('real Calculus inline and table SVGs keep source order after reflow', (tester) async {
    final root = Directory('test/fixtures/calculus');
    final chapter = const EpubParser().parseHtml('excerpt.html', File('${root.path}/excerpt.html').readAsStringSync());
    expect(chapter.blocks.length, 2);
    expect(chapter.blocks.first.text, startsWith('(1) \uFFFC which merely'));
    expect(chapter.blocks.last.rows.length, 4);
    expect(chapter.blocks.last.rows[1].map((c) => c.text), ['\uFFFC', '\uFFFC']);
    final images = <String, MMBookImage>{};
    await tester.runAsync(() async {
      for (final file in root.listSync().whereType<File>().where((f) => f.path.endsWith('.svg'))) {
        images[file.uri.pathSegments.last] = await MMBookImage.decode(file.readAsBytesSync(), svgImage: true);
      }
    });
    expect(images.length, 8);
    final anchor = chapter.anchor(0, chapter.canonicalText.length);
    final snapshot = anchor.toJson();
    for (final font in [16.0, 22.0]) {
      final layout = ChapterLayout.layout(chapter, LayoutSpec(width: 360, fontSize: font), images: images);
      expect(layout.pieces.first.artwork.single.rect.width, closeTo(1.176 * font * .5, .01));
      expect(layout.pieces.expand((p) => p.artwork).length, 8);
      expect(layout.pieces.skip(1).expand((p) => p.artwork).length, 7);
      final imageOffset = chapter.canonicalText.indexOf('\uFFFC');
      final box = layout.boxes(chapter.anchor(imageOffset, imageOffset + 1)).single;
      expect(layout.hitTest(box.center), inInclusiveRange(imageOffset, imageOffset + 1));
      expect(chapter.resolves(anchor), isTrue);
      expect(anchor.toJson(), snapshot);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: const ValueKey('excerpt'),
              child: ColoredBox(
                color: const Color(0xffffffff),
                child: SizedBox(
                  width: 360,
                  height: 300,
                  child: ReflowSurface(layout: layout, page: 0, onSelection: (_) {}),
                ),
              ),
            ),
          ),
        ),
      );
      await expectLater(
        find.byKey(const ValueKey('excerpt')),
        matchesGoldenFile('goldens/calculus-${font.toInt()}.png'),
      );
      await tester.pumpWidget(const SizedBox());
      layout.dispose();
    }
    for (final image in images.values) {
      image.dispose();
    }
  });

  test('missing artwork and dimensions are bounded without moving offsets', () {
    final c = const EpubParser().parseHtml(
      'c',
      '<p>A<img src="x" width="200%" height="2em">B<img src="y" width="invalid"><img src="z" height="40px"><img src="q" width="0"></p>',
    );
    final l = ChapterLayout.layout(c, const LayoutSpec(width: 100, pageHeight: 80));
    expect(l.pieces.single.artwork.length, 4);
    expect(l.pieces.single.artwork.every((a) => a.rect.width <= 100 && a.rect.height <= 80), isTrue);
    final rec = ui.PictureRecorder();
    l.paint(Canvas(rec));
    rec.endRecording().dispose();
    l.dispose();
  });
}
