import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

void main() {
  test('crop keeps original selection and ink coordinates through resize and zoom', () {
    for (final scale in [.5, 1.0, 2.0]) {
      final transform = PageViewportTransform(
        pageSize: const Size(600, 800),
        crop: CropInsets(left: 20, top: 30, right: 40, bottom: 50),
        scale: scale,
        origin: const Offset(10, 12),
      );
      const original = Offset(80, 700);
      expect(transform.toPdf(transform.toViewport(original)), original);
      expect(transform.visibleSize, Size(540 * scale, 720 * scale));
      expect(transform.rect(const PageRect(80, 700, 180, 680)).size, Size(100 * scale, 20 * scale));
    }
    expect(
      () => PageViewportTransform(pageSize: const Size(600, 800), crop: CropInsets(), scale: 0),
      throwsArgumentError,
    );
  });
  test('alignment maps in both directions, including single pages and different heights', () {
    final mapping = ReadingAlignment(
      leftHeights: [800, 600],
      rightHeights: [900, 700, 500],
      points: [AlignPoint(left: PdfReadingPosition(page: 1, y: 400), right: PdfReadingPosition(page: 2, y: 350))],
    );
    for (final value in [0.0, .2, .5, 1.0, 1.8, 2.0]) {
      final p = ReadingAlignment.position(value, mapping.leftHeights);
      final back = mapping.map(mapping.map(p), reverse: true);
      expect(ReadingAlignment.scalar(back, mapping.leftHeights), closeTo(value, 1e-9));
    }
    expect(ReadingAlignment(leftHeights: [800], rightHeights: [600]).map(PdfReadingPosition(page: 1, y: 400)).y, 300);
    final point = AlignPoint(left: PdfReadingPosition(page: 1, y: 400), right: PdfReadingPosition(page: 1, y: 300));
    expect(
      () => ReadingAlignment(leftHeights: [800], rightHeights: [600], points: [point, point]),
      throwsArgumentError,
    );
    expect(() => ReadingAlignment(leftHeights: [], rightHeights: [600]), throwsArgumentError);
    expect(() => ReadingAlignment.scalar(PdfReadingPosition(page: 1, y: 900), [800]), throwsArgumentError);
  });
  test('asynchronous echo, user takeover, disabled and disposed sync', () async {
    final sync = ReadingSync();
    final pending = Completer<void>();
    var count = 0;
    final drive = sync.drive(0, () async {
      count++;
      await pending.future;
    });
    await sync.drive(1, () async {
      count++;
    });
    expect(count, 1);
    sync.userInput(1);
    await sync.drive(1, () async {
      count++;
    });
    pending.complete();
    await drive;
    expect(count, 2);
    sync.enabled = false;
    await sync.drive(0, () async {
      count++;
    });
    sync.enabled = true;
    sync.dispose();
    await sync.drive(0, () async {
      count++;
    });
    expect(count, 2);
  });
}
