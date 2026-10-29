part of '../mm_book.dart';

class MarkdownBookParser {
  const MarkdownBookParser({this.maxBytes = 64 * 1024 * 1024});
  final int maxBytes;

  Future<Book> parse(
    Uint8List bytes, {
    String sourcePath = 'document.md',
    ResourceResolver? resolver,
    BookCancellationToken? cancellation,
  }) async {
    cancellation?.check();
    if (bytes.length > maxBytes) _limit();
    final source = _guard(() => utf8.decode(bytes));
    final rendered = md.markdownToHtml(source, extensionSet: md.ExtensionSet.gitHubWeb);
    final document = html.parse(rendered);
    final slugs = <String, int>{};
    for (final heading in document.querySelectorAll('h1,h2,h3,h4,h5,h6')) {
      final slug = heading.text
          .toLowerCase()
          .replaceAll(RegExp(r'[^\p{L}\p{N} _-]', unicode: true), '')
          .replaceAll(' ', '-');
      final number = slugs.update(slug, (n) => n + 1, ifAbsent: () => 0);
      heading.id = number == 0 ? slug : '$slug-$number';
    }
    final resources = <String, Uint8List>{};
    final diagnostics = <String>[];
    var total = bytes.length;
    for (final image in document.querySelectorAll('img')) {
      cancellation?.check();
      final src = image.attributes['src'] ?? '';
      final uri = Uri.tryParse(src);
      if (uri == null || uri.hasScheme || src.startsWith('//') || src.startsWith('/')) {
        continue;
      }
      final path = _guard(() => _resolve(sourcePath, src));
      image.attributes['src'] = path;
      if (resources.containsKey(path)) continue;
      final data = await resolver?.call(path);
      cancellation?.check();
      if (data == null) {
        diagnostics.add('Missing image: $path');
        continue;
      }
      total += data.length;
      if (total > maxBytes) _limit();
      resources[path] = Uint8List.fromList(data);
    }
    // Resolution has already produced package-root paths; main has no directory.
    final chapter = const EpubParser().parseHtml('main', document.outerHtml, diagnostics);
    final headings = chapter.blocks.where((b) => b.kind == BlockKind.heading).toList();
    final toc = [for (final b in headings) BookTocEntry(b.id, b.text, 'main', b.start)];
    return Book(headings.firstOrNull?.text ?? '', [chapter], resources, diagnostics, toc: toc);
  }
}
