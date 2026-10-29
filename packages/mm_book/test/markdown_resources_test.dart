import 'dart:convert';
import 'dart:typed_data';

import 'package:mm_book/mm_book.dart';
import 'package:test/test.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));
final png = Uint8List.fromList([137, 80, 78, 71]);

void checkResourceKeys(Book book) {
  expect(book.resources, isNotEmpty);
  for (final key in book.resources.keys) {
    expect(key, matches(r'^images/[a-f0-9]{64}\.png$'));
    expect(key.startsWith('/'), isFalse);
    expect(key.split('/'), isNot(contains('..')));
  }
  final refs = book.chapters.single.blocks.expand((b) => b.runs).map((r) => r.resource).whereType<String>().toSet();
  expect(refs, containsAll(book.resources.keys));
}

void main() {
  for (final name in ['notes/a.md', 'a.md', '/Users/me/notes/a.md', r'C:\notes\a.md']) {
    test('image resolver is relative to Markdown directory for $name', () async {
      final seen = <String>[];
      final book = await const BookParser().parse(
        SourceBytes(name, bytes('# Title\n\n![alt](img/a.png)')),
        resolver: (path) async {
          seen.add(path);
          return png;
        },
      );
      expect(seen, ['img/a.png']);
      expect(book.resources.values.single, png);
      expect(book.diagnostics, isEmpty);
      checkResourceKeys(book);
    });
  }

  test('parent image paths resolve against the selected file and aliases import once', () async {
    for (final name in ['a.md', 'notes/a.md', '/Users/me/notes/a.md']) {
      final file = Uri.file('/import/').resolve(name);
      final expected = file.resolve('../a.png').path;
      final seen = <String>[];
      final book = await const BookParser().parse(
        SourceBytes(name, bytes('![a](../a.png) ![alias](img/../../a.png)')),
        resolver: (path) async {
          seen.add(path);
          // The caller, not the EPUB resolver, interprets the image against the source directory.
          expect(file.resolve(path).path, expected);
          return png;
        },
      );
      expect(seen, ['../a.png']);
      expect(book.resources, hasLength(1));
      expect(book.diagnostics, isEmpty);
      checkResourceKeys(book);
      final refs = book.chapters.single.blocks.expand((b) => b.runs).where((r) => r.resource != null);
      expect(refs, hasLength(2));
      expect(refs.first.resource, refs.last.resource);
    }
  });

  test('unsafe image paths are skipped without failing the document or calling resolver', () async {
    for (final path in [
      r'img\a.png',
      'img/\u0000a.png',
      '%2e%2e/a.png',
      'img/%2E%2e/a.png',
      'img/%252e%252e/a.png',
      'img%2fa.png',
      'img/%5ca.png',
      'img/%00a.png',
      'img/%ZZ.png',
      'img/%FF.png',
      '',
    ]) {
      final seen = <String>[];
      final book = await const BookParser().parse(
        SourceBytes('/Users/me/notes/a.md', bytes('<p>Before</p><img src="$path"><img src="good.png"><p>After</p>')),
        resolver: (relative) async {
          seen.add(relative);
          return png;
        },
      );
      expect(seen, ['good.png'], reason: path);
      expect(book.resources, hasLength(1));
      expect(book.diagnostics.single, startsWith('Unsafe image path:'), reason: path);
      expect(book.chapters.single.canonicalText, allOf(contains('Before'), contains('After')));
      checkResourceKeys(book);
    }
  });

  test('missing images and resolver failures preserve text and other imported images', () async {
    final seen = <String>[];
    final book = await const MarkdownBookParser().parse(
      bytes('Before ![a](missing.png) ![b](denied.png) ![c](broken.png) ![d](good.png) After'),
      resolver: (path) async {
        seen.add(path);
        if (path == 'denied.png') throw Exception('private filesystem details');
        if (path == 'broken.png') throw StateError('read failed');
        return path == 'good.png' ? png : null;
      },
    );
    expect(seen, ['missing.png', 'denied.png', 'broken.png', 'good.png']);
    expect(book.resources, hasLength(1));
    expect(book.diagnostics, [
      'Missing image: missing.png',
      'Could not read image: denied.png',
      'Could not read image: broken.png',
    ]);
    expect(book.chapters.single.canonicalText, 'Before \uFFFC \uFFFC \uFFFC \uFFFC After');
    checkResourceKeys(book);
  });

  test('encoded filename spaces normalize and oversized images are optional failures', () async {
    final source = bytes('![big](big.png) ![small](img/a%20b.png)');
    final seen = <String>[];
    final book = await MarkdownBookParser(maxBytes: source.length + 4).parse(
      source,
      resolver: (path) async {
        seen.add(path);
        return path == 'big.png' ? Uint8List(5) : png;
      },
    );
    expect(seen, ['big.png', 'img/a b.png']);
    expect(book.diagnostics.single, 'Image exceeds resource limit: big.png');
    expect(book.resources, hasLength(1));
    checkResourceKeys(book);
  });

  test('cancellation remains fatal when a resolver read throws', () async {
    final token = BookCancellationToken();
    await expectLater(
      const MarkdownBookParser().parse(
        bytes('![a](a.png)'),
        cancellation: token,
        resolver: (_) async {
          token.cancel();
          throw Exception('read interrupted');
        },
      ),
      throwsA(isA<BookParseException>().having((e) => e.kind, 'kind', BookErrorKind.cancelled)),
    );
    await expectLater(
      const MarkdownBookParser().parse(
        bytes('![a](a.png)'),
        resolver: (_) async {
          throw const BookParseException(BookErrorKind.cancelled, 'caller cancelled');
        },
      ),
      throwsA(isA<BookParseException>().having((e) => e.kind, 'kind', BookErrorKind.cancelled)),
    );
  });
}
