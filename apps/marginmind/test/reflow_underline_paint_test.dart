import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/reflow_reader.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_reflow/mm_reflow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reader paints a level, unbroken underline across mixed text runs', () async {
    final chapter = const EpubParser().parseHtml('mixed', '<p>中文<span style="font-size:0.75em"> Agent </span>内容</p>');
    final layout = ChapterLayout.layout(chapter, const LayoutSpec(width: 400));
    final anchor = chapter.anchor(0, chapter.canonicalText.length, revision: 'web-revision');
    final annotation = Annotation(
      id: 'line',
      documentId: 'web',
      textAnchors: [anchor],
      quote: anchor.quote,
      colorIndex: 0,
      createdAt: DateTime(2026),
      kind: AnnotationKind.underline,
    );
    for (final page in <int?>[null, 0]) {
      final recorder = ui.PictureRecorder();
      ReflowReaderPainter(
        layout,
        page,
        [annotation],
        {
          'line': [anchor],
        },
        [],
        null,
        null,
        null,
      ).paint(Canvas(recorder), const Size(400, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(400, 100);
      final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
      final textBoxes = layout.boxes(anchor, page: page);
      final left = textBoxes.first.rect.left.ceil() + 1;
      final right = textBoxes.last.rect.right.floor() - 1;
      List<int>? lineRows;
      for (var x = left; x < right; x++) {
        final rows = <int>[];
        for (var y = 0; y < image.height; y++) {
          final offset = (y * image.width + x) * 4;
          // Only the yellow annotation; the text is neutral.
          if (pixels.getUint8(offset) > 240 &&
              pixels.getUint8(offset + 1) > 150 &&
              pixels.getUint8(offset + 2) < 30 &&
              pixels.getUint8(offset + 3) > 30) {
            rows.add(y);
          }
        }
        expect(rows, isNotEmpty, reason: 'Underline has a gap at column $x');
        lineRows ??= rows;
        expect(rows, lineRows, reason: 'Underline changes height at column $x');
      }
      image.dispose();
      picture.dispose();
    }
    layout.dispose();
  });
}
