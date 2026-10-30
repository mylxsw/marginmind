import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pdf/mm_pdf.dart';

void main() {
  const lines = [('newer', Rect.fromLTWH(10, 40, 80, 20)), ('older', Rect.fromLTWH(10, 10, 80, 20))];
  test('touch tolerance picks the nearest line and exact hits win', () {
    expect(hitAnnotation(const Offset(50, 35), lines), isNull);
    expect(hitAnnotation(const Offset(50, 32), lines, tolerance: 12), 'older');
    expect(hitAnnotation(const Offset(50, 38), lines, tolerance: 12), 'newer');
    expect(hitAnnotation(const Offset(50, 29), lines, tolerance: 12), 'older');
    expect(hitAnnotation(const Offset(104, 20), lines, tolerance: 12), isNull);
    expect(hitAnnotation(const Offset(50, 35), lines, tolerance: 12), 'newer');
  });
  test('overlaps prefer first mark, not the union between separate lines', () {
    expect(
      hitAnnotation(const Offset(20, 20), [
        ('newer', const Rect.fromLTWH(10, 10, 20, 20)),
        ('older', const Rect.fromLTWH(10, 10, 80, 20)),
      ], tolerance: 12),
      'newer',
    );
    expect(
      hitAnnotation(const Offset(50, 100), [
        ('mark', const Rect.fromLTWH(10, 10, 80, 20)),
        ('mark', const Rect.fromLTWH(10, 180, 80, 20)),
      ], tolerance: 12),
      isNull,
    );
  });
}
