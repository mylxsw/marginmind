import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

final time = DateTime.utc(2026);
MarginNote note(String id, double y, {DateTime? createdAt, AnnotationAnchor? anchor}) => MarginNote(
  id: id,
  documentId: 'd',
  page: 1,
  lineY: anchor == null ? y : null,
  anchor: anchor,
  text: id,
  colorIndex: 0,
  createdAt: createdAt ?? time,
  updatedAt: time,
);
void main() {
  final transform = PageViewportTransform(
    pageSize: const Size(600, 800),
    crop: CropInsets(top: 20),
    scale: .8,
    origin: const Offset(10, 16),
  );
  test('78% boundary includes column and layout margins', () {
    expect(marginFits(648.96, 600), true);
    expect(marginFits(648.95, 600), false);
    expect(marginFits(500, 400), true);
    expect(marginFits(double.infinity, 600), false);
    expect(marginFits(500, 0), false);
  });
  test('stable anchor/time/id order, 8pt gaps, and page-bottom overflow', () {
    final layout = layoutMarginNotes(
      [
        note('z', 100),
        note('b', 100),
        note('a', 100),
        note('old', 100, createdAt: time.subtract(const Duration(days: 1))),
      ],
      transform: transform,
      height: (_) => 60,
    );
    expect(layout.map((p) => p.note.id), ['old', 'a', 'b', 'z']);
    expect(layout.first.anchorY, closeTo(560, .01));
    for (var i = 1; i < layout.length; i++) {
      expect(layout[i].top - layout[i - 1].top, closeTo(66.4, .01));
    }
    expect(layout.last.top + layout.last.height, greaterThan(transform.visibleSize.height + transform.origin.dy));
    expect(layoutMarginNotes([], transform: transform, height: (_) => 10), isEmpty);
  });
  test('text anchors share transform and marker groups preserve notes', () {
    final anchored = note(
      'quote',
      0,
      anchor: AnnotationAnchor(
        pages: [
          const AnnotationPage(page: 1, rects: [PageRect(20, 780, 100, 760)]),
        ],
        quote: 'text',
      ),
    );
    expect(marginAnchorY(anchored, transform), 16);
    final layout = layoutMarginNotes([anchored], transform: transform, height: (_) => 20);
    expect(layout.single.top, closeTo(19.2, .01));
    final groups = groupMarginMarkers([note('c', 600), note('b', 770), anchored], transform);
    expect(groups.map((g) => g.length), [2, 1]);
    expect(groupMarginMarkers([], transform), isEmpty);
  });
}
