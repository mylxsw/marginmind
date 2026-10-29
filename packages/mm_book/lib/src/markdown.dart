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
    final attempted = <String>{};
    var total = bytes.length;
    var imageIndex = 0;
    for (final image in document.querySelectorAll('img')) {
      cancellation?.check();
      final src = image.attributes['src'] ?? '';
      final uri = Uri.tryParse(src);
      if (uri != null && (uri.hasScheme || uri.hasAuthority || src.startsWith('/'))) {
        continue; // Shared HTML parsing keeps blocked URL placeholders.
      }
      // Failed local images retain a placeholder without exposing their source path in IR.
      image.attributes['src'] = 'images/missing-${imageIndex++}';
      String path;
      try {
        path = _markdownImagePath(src);
      } on FormatException {
        diagnostics.add('Unsafe image path: $src');
        continue;
      }
      final extension = RegExp(r'\.([a-zA-Z0-9]{1,8})$').firstMatch(path)?.group(1)?.toLowerCase();
      final key = 'images/${sha256.convert(utf8.encode(path))}${extension == null ? '' : '.$extension'}';
      image.attributes['src'] = key;
      if (!attempted.add(path)) continue;
      Uint8List? data;
      try {
        // The caller binds this resolver to sourcePath's directory, whether absolute or relative.
        data = await resolver?.call(path);
      } catch (error) {
        cancellation?.check();
        if (error is BookParseException && error.kind == BookErrorKind.cancelled) rethrow;
        diagnostics.add('Could not read image: $path');
        continue;
      }
      cancellation?.check();
      if (data == null) {
        diagnostics.add('Missing image: $path');
        continue;
      }
      if (data.length > maxBytes - total) {
        diagnostics.add('Image exceeds resource limit: $path');
        continue;
      }
      total += data.length;
      resources[key] = Uint8List.fromList(data);
    }
    // Resolution has already produced package-root paths; main has no directory.
    final chapter = const EpubParser().parseHtml('main', document.outerHtml, diagnostics);
    final headings = chapter.blocks.where((b) => b.kind == BlockKind.heading).toList();
    final toc = [for (final b in headings) BookTocEntry(b.id, b.text, 'main', b.start)];
    return Book(headings.firstOrNull?.text ?? '', [chapter], resources, diagnostics, toc: toc);
  }
}

/// Resolver paths are relative to the Markdown file, not paths inside an EPUB.
/// Literal parent segments are allowed; encoded traversal/separators are rejected.
String _markdownImagePath(String source) {
  final raw = source.split(RegExp(r'[?#]')).first;
  if (raw.isEmpty || RegExp(r'%2f|%5c|%00', caseSensitive: false).hasMatch(raw)) {
    throw const FormatException('Unsafe image path');
  }
  String decoded;
  try {
    decoded = Uri.decodeComponent(raw);
  } on ArgumentError {
    throw const FormatException('Invalid image path encoding');
  }
  if (decoded.contains('\\') ||
      decoded.contains('\u0000') ||
      decoded.contains('\uFFFD') ||
      decoded.startsWith('/') ||
      RegExp(r'%[0-9a-f]{2}', caseSensitive: false).hasMatch(decoded)) {
    throw const FormatException('Unsafe image path');
  }
  final rawSegments = raw.split('/'), decodedSegments = decoded.split('/');
  for (var i = 0; i < decodedSegments.length; i++) {
    if ((decodedSegments[i] == '..' || decodedSegments[i] == '.') && rawSegments[i] != decodedSegments[i]) {
      throw const FormatException('Encoded image traversal');
    }
  }
  final uri = Uri.parse(decoded);
  if (uri.hasScheme || uri.hasAuthority) throw const FormatException('Unsafe image path');
  final path = Uri.decodeComponent(Uri(path: decoded).normalizePath().path);
  if (path.isEmpty || path.endsWith('/') || path == '.' || path == '..') {
    throw const FormatException('Image path has no filename');
  }
  return path;
}
