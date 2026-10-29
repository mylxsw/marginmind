import 'dart:convert';
import 'dart:io';

import 'package:mm_book/mm_book.dart';

Future<void> main(List<String> paths) async {
  for (final path in paths) {
    final book = await const BookParser().parse(SourceBytes(path.split('/').last, await File(path).readAsBytes()));
    stdout.writeln(
      jsonEncode({
        'path': path,
        'title': book.title,
        'chapters': book.chapters.length,
        'utf16': book.chapters.fold(0, (n, c) => n + c.canonicalText.length),
        'resources': book.resources.length,
        'toc': book.toc.length,
        'revision': book.revision,
        'diagnostics': book.diagnostics.take(20).toList(),
      }),
    );
  }
}
