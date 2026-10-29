import 'dart:convert';
import 'dart:typed_data';

import 'package:mm_book/mm_book.dart';

void main() {
  final chapter = const EpubParser().parseHtml(
    'probe',
    '<section style="padding:20px"><p>A<ruby>汉<rt>han</rt></ruby></p>'
        '<table><thead><tr><th>header</th></tr></thead><tbody><tr><td>body</td></tr></tbody></table>'
        '<img src="image.svg"></section>',
  );
  final book = Book(
    'probe',
    [chapter],
    {'image.svg': Uint8List.fromList(utf8.encode('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10"/>'))},
    [],
  );
  final json = book.toJson();
  final spine = (json['spine'] as List).single as Map;
  final nodes = (spine['structure'] as List).cast<Map>();
  final table = (spine['blocks'] as List).cast<Map>().firstWhere((b) => b['kind'] == 'table');
  final cell = ((table['rows'] as List).first as List).first as Map;
  final resource = (json['resources'] as List).single as Map;
  // ignore: avoid_print
  print(
    const JsonEncoder.withIndent('  ').convert({
      'baseline': '7aa0c27',
      'container_style_present': nodes.first.containsKey('style'),
      'table_header_identity_present': cell.containsKey('header') || cell.containsKey('isHeader'),
      'intrinsic_size_present': resource.containsKey('width') && resource.containsKey('height'),
      'ir': json,
    }),
  );
}
