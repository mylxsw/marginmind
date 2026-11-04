import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/reflow_document.dart';
import 'package:mm_book/mm_book.dart';

import 'helpers.dart' show demoContent;

ReflowDocument document(Book book) => ReflowDocument(
  demoContent().documents.first.copyWith(title: book.title),
  book.chapters,
  book.toc,
  {},
  (_) async => [],
);

void main() {
  test('old flat Markdown indexes recover nested headings without changing targets', () {
    final chapter = const EpubParser().parseHtml(
      'main',
      '<h1>Document</h1><h2>Chapter</h2><h3>Detail</h3><h2>Next</h2>',
    );
    final headings = chapter.blocks.where((block) => block.kind == BlockKind.heading).toList();
    final entries = [for (final block in headings) BookTocEntry(block.id, block.text, 'main', block.start)];
    final book = document(Book('Document', [chapter], {}, [], toc: entries));
    final rows = book.navigationOutline;
    expect(rows.map((row) => row.depth), [0, 1, 0]);
    expect(rows.map((row) => row.entry), entries.skip(1));
    expect(book.outline, entries);
  });

  test('explicit EPUB hierarchy is preserved even when source heading levels differ', () {
    final chapter = const EpubParser().parseHtml('main', '<h1>Document</h1><h1>Chapter</h1>');
    final child = BookTocEntry('child', 'Chapter', 'main', 9);
    final root = BookTocEntry('root', 'Document', 'main', 0, [child]);
    final rows = document(Book('Document', [chapter], {}, [], toc: [root])).navigationOutline;
    expect(rows.map((row) => row.depth), [0]);
    expect(rows.last.entry, same(child));
  });

  test('a document heading alone leaves an empty chapter list', () {
    final chapter = const EpubParser().parseHtml('main', '<h1>Document</h1><p>Text.</p>');
    final root = BookTocEntry('root', 'Document', 'main', 0);
    final book = document(Book('Document', [chapter], {}, [], toc: [root]));
    expect(book.navigationOutline, isEmpty);
    expect(book.outline, [root]);
  });

  test('promoting document children leaves peer chapters at their own level', () {
    final chapter = const EpubParser().parseHtml('main', '<h1>Document</h1><h2>Child</h2><h1>Peer</h1>');
    final child = BookTocEntry('child', 'Child', 'main', 9);
    final peer = BookTocEntry('peer', 'Peer', 'main', 15);
    final root = BookTocEntry('root', 'Document', 'main', 0, [child]);
    final book = document(Book('Document', [chapter], {}, [], toc: [root, peer]));
    expect(book.navigationOutline.map((row) => row.depth), [0, 0]);
    expect(book.navigationOutline.map((row) => row.entry), [child, peer]);
  });
}
