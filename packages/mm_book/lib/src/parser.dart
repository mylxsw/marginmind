part of '../mm_book.dart';

class SourceBytes {
  SourceBytes(this.name, Uint8List bytes) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final String name;
  final Uint8List bytes;
}

/// One portable entry point. Run in a worker for large inputs; no platform APIs.
class BookParser {
  const BookParser({this.maxBytes = 64 * 1024 * 1024, this.maxEntries = 10000});
  final int maxBytes, maxEntries;
  Future<Book> parse(SourceBytes source, {ResourceResolver? resolver, BookCancellationToken? cancellation}) async {
    cancellation?.check();
    final ext = source.name.split('.').last.toLowerCase();
    final Book book;
    switch (ext) {
      case 'epub':
        book = EpubParser(maxBytes: maxBytes, maxEntries: maxEntries).parse(source.bytes);
      case 'mobi' || 'azw' || 'azw3' || 'azw4':
        book = MobiParser(maxBytes: maxBytes, maxRecords: maxEntries).parse(source.bytes);
      case 'md' || 'markdown':
        book = await MarkdownBookParser(maxBytes: maxBytes)
            .parse(source.bytes, sourcePath: source.name, resolver: resolver, cancellation: cancellation);
      case 'kfx':
        return _unsupported('KFX is not supported');
      default:
        return _unsupported('Unsupported book format: $ext');
    }
    cancellation?.check();
    return book;
  }
}
