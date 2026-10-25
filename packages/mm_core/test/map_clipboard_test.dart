import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  var serial = 0;
  final editor = StudySetEditor(newId: () => 'n${serial++}', now: () => DateTime(2026));
  test('tabs, spaces, blank lines and list markers normalize and round trip', () {
    for (final text in ['A\n\tB\n\t\tC\nD', 'A\n  B\n    C\nD', '\n- A\n\n  • B\n    1. C\n+ D\n']) {
      final entries = MapClipboard.fromText(text);
      expect(entries.map((e) => (e.depth, e.title)), [(0, 'A'), (1, 'B'), (2, 'C'), (0, 'D')]);
      final roundtrip = MapClipboard.fromText(MapClipboard.toText(entries));
      expect(roundtrip.map((e) => (e.depth, e.title)), entries.map((e) => (e.depth, e.title)));
    }
    expect(MapClipboard.fromText('   A\n\tB\n\t  C\n   D').map((e) => e.depth), [0, 1, 2, 0]);
    expect(MapClipboard.fromText('\n  \n'), isEmpty);
    expect(MapClipboard.fromText('A\n- \n  B').map((e) => (e.depth, e.title)), [(0, 'A'), (1, 'B')]);
  });
  test('Notes bullets preserve whitespace after the marker and round trip', () {
    for (final text in [
      '* Alpha\n* \tBeta\n* \t\tGamma\n* Delta',
      '* Alpha\n    * Beta\n        * Gamma\n* Delta',
      '* Alpha\n*   Beta\n*     Gamma\n* Delta',
      '1. Alpha\n2. \tBeta\n3. \t\tGamma\n4. Delta',
    ]) {
      final entries = MapClipboard.fromText(text);
      expect(entries.map((e) => (e.depth, e.title)), [(0, 'Alpha'), (1, 'Beta'), (2, 'Gamma'), (0, 'Delta')]);
      expect(
        MapClipboard.fromText(MapClipboard.toText(entries)).map((e) => (e.depth, e.title)),
        entries.map((e) => (e.depth, e.title)),
      );
    }
  });
  test('cut reuses an unattached highlight; copying keeps independent highlights', () {
    final (c1, doc) = editor.addDocument(StudySetContent.empty, title: 'PDF', fileName: 'a.pdf', pageCount: 2);
    final (original, excerpt) = editor.createExcerpt(
      c1,
      documentId: doc.id,
      page: 1,
      rects: const [PageRect(0, 2, 2, 0)],
      quote: 'Quote',
      colorIndex: 2,
    );
    final entries = MapClipboard.decode(MapClipboard.encode(MapClipboard.copy(original, [excerpt.id])))!;
    expect(entries.single.annotation!.id, excerpt.annotationId);
    final cut = editor.removeMany(original, [excerpt.id]);
    final (restored, roots) = editor.paste(cut, entries);
    expect(restored.annotations, hasLength(1));
    expect(restored.cards, hasLength(1));
    expect(restored.card(roots.single)!.annotationId, excerpt.annotationId);
    expect(restored.cardForAnnotation(excerpt.annotationId!)!.id, roots.single);
    // A duplicated clipboard entry must not bind two cards to the same highlight.
    final (repeated, _) = editor.paste(cut, [...entries, ...entries]);
    expect(repeated.annotations, hasLength(2));
    expect(repeated.cards.map((c) => c.annotationId).toSet(), hasLength(2));
    final (copied, copiedRoots) = editor.paste(original, entries);
    expect(copied.annotations, hasLength(2));
    final copyId = copiedRoots.single;
    final copyAnnotationId = copied.card(copyId)!.annotationId!;
    expect(copyAnnotationId, isNot(excerpt.annotationId));
    final recolored = editor.recolorMany(copied, [copyId], 3);
    expect(recolored.annotation(excerpt.annotationId!)!.colorIndex, 2);
    expect(recolored.annotation(copyAnnotationId)!.colorIndex, 3);
    final deleted = editor.deleteAnnotation(recolored, copyAnnotationId);
    expect(deleted.annotations.single.id, excerpt.annotationId);
    expect(deleted.card(excerpt.id), isNotNull);
    expect(deleted.card(copyId), isNull);
    // A missing original highlight still gets a fresh, valid highlight.
    final (missing, _) = editor.paste(c1, entries);
    expect(missing.annotations, hasLength(1));
    expect(missing.annotations.single.id, isNot(excerpt.annotationId));
  });
  test('forest copy deduplicates selected descendants and includes folded children', () {
    final (c1, a) = editor.addTopic(StudySetContent.empty, title: 'A');
    final (c2, b) = editor.addTopic(c1, title: 'B', parentId: a.id);
    final (c3, d) = editor.addTopic(c2, title: 'D');
    final folded = editor.setCollapsed(c3, a.id, collapsed: true);
    final entries = MapClipboard.copy(folded, [d.id, b.id, a.id]);
    expect(entries.map((e) => (e.depth, e.title)), [(0, 'A'), (1, 'B'), (0, 'D')]);
    expect(entries.first.collapsed, isTrue);
    final decoded = MapClipboard.decode(MapClipboard.encode(entries))!;
    final (pasted, roots) = editor.paste(folded, decoded);
    expect(roots, hasLength(2));
    expect(pasted.childrenOf(roots.first), hasLength(1));
    expect(pasted.node(roots.first)!.collapsed, isTrue);
    expect(MapClipboard.copy(pasted, roots).map((e) => e.title), ['A', 'B', 'D']);
  });
  test('internal excerpts and multiline notes survive; foreign excerpts become notes', () {
    final (c1, doc) = editor.addDocument(StudySetContent.empty, title: 'PDF', fileName: 'a.pdf', pageCount: 2);
    final (c2, excerpt) = editor.createExcerpt(
      c1,
      documentId: doc.id,
      page: 1,
      rects: const [PageRect(0, 2, 2, 0)],
      quote: 'Quote',
      colorIndex: 2,
    );
    final (c3, note) = editor.addNote(c2, text: 'Line 1\nLine 2', parentId: excerpt.id);
    final entries = MapClipboard.decode(MapClipboard.encode(MapClipboard.copy(c3, [excerpt.id, note.id])))!;
    final (pasted, roots) = editor.paste(c3, entries, parentId: excerpt.id);
    final newCard = pasted.card(roots.single)!;
    expect(newCard.kind, CardKind.excerpt);
    expect(newCard.annotationId, isNot(excerpt.annotationId));
    expect(pasted.annotation(newCard.annotationId!)!.quote, 'Quote');
    expect(pasted.annotation(newCard.annotationId!)!.colorIndex, 2);
    expect(pasted.card(pasted.childrenOf(newCard.id).single.cardId)!.title, 'Line 1\nLine 2');
    final (foreign, ids) = editor.paste(StudySetContent.empty, entries);
    expect(foreign.card(ids.single)!.kind, CardKind.note);
    expect(foreign.card(ids.single)!.title, contains('Quote'));
    expect(MapClipboard.toText([entries.first]), contains('Quote'));
    expect(MapClipboard.toText([entries.last]), '\tLine 1 Line 2');
  });
  test('rejects malformed payloads, depth jumps and unknown targets without partial writes', () {
    for (final data in [
      'garbage',
      '{}',
      '[]',
      jsonEncode({'format': MapClipboard.format, 'version': 2}),
      jsonEncode({
        'format': MapClipboard.format,
        'version': 1,
        'nodes': [
          {'depth': 2},
        ],
      }),
    ]) {
      expect(MapClipboard.decode(data), isNull);
    }
    final entries = MapClipboard.fromText('A');
    expect(editor.paste(StudySetContent.empty, entries, parentId: 'missing').$1, same(StudySetContent.empty));
    expect(editor.paste(StudySetContent.empty, []).$1, same(StudySetContent.empty));
    expect(() => editor.paste(StudySetContent.empty, [const OutlineEntry(1, 'Bad')]), throwsFormatException);
    expect(() => MapClipboard.fromText(List.filled(10001, 'A').join('\n')), throwsFormatException);
  });
}
