import 'dart:convert';
import 'dart:io';

import 'package:mm_book/mm_book.dart';

import '../test/fixtures.dart';

void main() {
  final book = const EpubParser().parse(contractEpub());
  File('test/fixtures/book-v1.json')
      .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(book.toJson())}\n');
}
