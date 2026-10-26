import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pdf/src/preview_cache.dart';

void main() {
  test('buckets, shares requests and returns immutable bytes', () async {
    var calls = 0;
    final cache = MMPdfPreviewCache(
      render: (page, width) async {
        calls++;
        expect(page, 1);
        expect(width, 192);
        return Uint8List.fromList([1, 2]);
      },
    );
    final a = cache.get(1);
    final b = cache.get(1, pixelWidth: 180);
    expect(identical(a, b), isTrue);
    final bytes = await a;
    expect(await cache.get(1), same(bytes));
    expect(calls, 1);
    expect(() => bytes![0] = 4, throwsUnsupportedError);
    expect(cache.cachedBytes, 2);
  });
  test('LRU eviction respects byte budget, hits refresh recency', () async {
    final calls = <int>[];
    final cache = MMPdfPreviewCache(
      maxBytes: 4,
      render: (page, width) async {
        calls.add(page);
        return Uint8List(2);
      },
    );
    await cache.get(1);
    await cache.get(2);
    await cache.get(1);
    await cache.get(3);
    await cache.get(1);
    await cache.get(2);
    expect(calls, [1, 2, 3, 2]);
    expect(cache.cachedBytes, 4);
    expect(cache.entryCount, 2);
  });
  test('clear discards active result and skips old queued requests', () async {
    final active = Completer<Uint8List?>();
    final calls = <int>[];
    final cache = MMPdfPreviewCache(
      render: (page, width) {
        calls.add(page);
        return page == 1 ? active.future : Future.value(Uint8List(1));
      },
    );
    final first = cache.get(1);
    final queued = cache.get(2);
    await Future<void>.delayed(Duration.zero);
    cache.clear();
    final fresh = cache.get(3);
    active.complete(Uint8List(1));
    expect(await first, isNull);
    expect(await queued, isNull);
    expect(await fresh, isNotNull);
    expect(calls, [1, 3]);
    expect(cache.entryCount, 1);
    cache.clear();
    expect(cache.cachedBytes, 0);
  });
  test('errors, null and oversized results do not poison queue or cache', () async {
    final cache = MMPdfPreviewCache(
      maxBytes: 1,
      render: (page, width) async {
        if (page == 1) throw StateError('render failed');
        if (page == 2) return null;
        return Uint8List(2);
      },
    );
    await expectLater(cache.get(1), throwsStateError);
    expect(await cache.get(2), isNull);
    expect(await cache.get(3), hasLength(2));
    expect(cache.entryCount, 0);
    await expectLater(cache.get(1), throwsStateError);
  });
  test('validates bounds', () {
    Future<Uint8List?> render(int p, int w) async => null;
    expect(() => MMPdfPreviewCache(render: render, maxBytes: 0), throwsArgumentError);
    final cache = MMPdfPreviewCache(render: render);
    expect(() => cache.get(0), throwsRangeError);
    expect(() => cache.get(1, pixelWidth: 0), throwsRangeError);
    expect(() => cache.get(1, pixelWidth: 1025), throwsRangeError);
  });
}
