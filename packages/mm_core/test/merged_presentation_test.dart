import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  test('merged text exports every segment and source; recolor covers all source segments', () {
    var seq = 0;
    final editor = StudySetEditor(newId: () => 'x${++seq}', now: () => DateTime(2026));
    final (one, first) = editor.addDocument(StudySetContent.empty, title: 'Book A', fileName: 'a.pdf', pageCount: 10);
    final (two, second) = editor.addDocument(one, title: 'Book B', fileName: 'b.pdf', pageCount: 10);
    final (three, a) = editor.createExcerpt(
      two,
      documentId: first.id,
      page: 2,
      rects: const [],
      quote: 'First paragraph',
      colorIndex: 0,
    );
    final (four, b) = editor.createExcerpt(
      three,
      documentId: second.id,
      page: 8,
      rects: const [],
      quote: 'Second paragraph & <details>',
      colorIndex: 1,
    );
    final merged = editor.mergeCards(four, [b.id, a.id]);
    final exporter = MapExporter(merged.content, rootTitle: 'Root');
    expect(
      exporter.markdown(),
      contains('“First paragraph” *(Book A, p. 2)*\n  “Second paragraph & <details>” *(Book B, p. 8)*'),
    );
    final opml = exporter.opml();
    expect(opml, contains('Second paragraph &amp; &lt;details&gt;'));
    expect(opml, contains('Book A, p. 2'));
    expect(opml, contains('Book B, p. 8'));
    expect(buildReviewFace(merged.value!, merged.content).back.quote, 'First paragraph\nSecond paragraph & <details>');
    final colored = editor.recolorMany(merged.content, [a.id], 4);
    expect(colored.annotations.map((a) => a.colorIndex), [4, 4]);
    expect(merged.content.annotations.map((a) => a.colorIndex), [0, 1]);
    expect(identical(editor.recolorMany(colored, [a.id], 4), colored), isTrue);
  });
}
