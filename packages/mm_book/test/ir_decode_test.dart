import 'dart:convert';
import 'dart:typed_data';

import 'package:mm_book/mm_book.dart';
import 'package:test/test.dart';

void main() {
  test('stored IR recovers all readable blocks without changing canonical text', () async {
    final b = await const BookParser().parse(
      SourceBytes(
        'notes.md',
        Uint8List.fromList(
          utf8.encode('''# Title

A **bold** word and [link](https://example.com).

- one
- two

> Quote

|A|B|
|-|-|
|x|y|

```dart
final x = 1;
```
'''),
        ),
      ),
    );
    final raw = ((b.toJson()['spine'] as List).single as Map).cast<String, Object?>();
    final restored = BookChapter.fromJson(raw);
    expect(restored.canonicalText, b.chapters.single.canonicalText);
    expect(restored.blocks.map((b) => b.kind), b.chapters.single.blocks.map((b) => b.kind));
    expect(restored.anchor(0, restored.canonicalText.length).quote, restored.canonicalText);
    expect(() => BookChapter.fromJson({...raw, 'canonicalText': 'changed'}), throwsFormatException);
    final blocks = (raw['blocks'] as List).map((e) => Map<String, Object?>.from(e as Map)).toList();
    blocks.first['start'] = 1;
    expect(() => BookChapter.fromJson({...raw, 'blocks': blocks}), throwsFormatException);
    blocks.first['start'] = 0;
    blocks.first['end'] = 99;
    expect(() => BookChapter.fromJson({...raw, 'blocks': blocks}), throwsFormatException);
  });
}
