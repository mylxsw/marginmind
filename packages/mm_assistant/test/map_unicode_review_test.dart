import 'dart:convert';

import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'map_generation_test.dart' as fixtures;

void main() {
  test('page chunks preserve Unicode after actual UTF-8 transport encoding', () async {
    final sent = <String>[];
    var call = 0;
    final generator = ModelMapGenerator.runtime((system, payload, cancel, validate) async {
      sent.addAll((payload['pages'] as Map).values.cast<String>());
      return '${jsonEncode({'k': 'point', 'id': 'p', 'parent': 'ROOT', 'title': 'Part ${call++}', 'doc': 'D1', 'page': 1})}\n${jsonEncode({'coverage': payload['requiredCoverage']})}';
    });
    final text = '${'x' * 9999}😀${'y' * 21000}';
    try {
      await generator
          .readChapter(
            MapChapterInput(
              chapterId: 'unicode',
              documentAlias: 'D1',
              context: fixtures.context(MapLinePhase.chapter),
              textByPage: {1: text},
            ),
            CancellationToken(),
          )
          .toList();
      expect(
        sent.map((s) => utf8.decode(utf8.encode(s))).join(),
        text,
        reason: 'A chunk boundary must not split a UTF-16 surrogate pair.',
      );
    } finally {
      await generator.close();
    }
  });
  test('pages and annotations preserve supplementary characters, slice quotes and the chunk limit', () async {
    final text = '${'x' * 9999}😀${'y' * 9997}𠮷${'z' * 21000}';
    final pages = <String>[], annotations = <String>[];
    var calls = 0;
    final generator = ModelMapGenerator.runtime((system, payload, cancel, validate) async {
      final page = (payload['pages'] as Map).values.cast<String>().toList();
      final marks = (payload['annotations'] as Map).values.cast<String>().toList();
      pages.addAll(page);
      annotations.addAll(marks);
      expect([...page, ...marks].every((s) => s.length <= 10000), isTrue);
      expect(jsonEncode(payload).length, lessThanOrEqualTo(mapStageInputCharacters));
      final point = {
        'k': 'point',
        'id': 'p',
        'parent': 'ROOT',
        'title': 'Part ${calls++}',
        if (page.isNotEmpty) 'doc': 'D1',
        if (page.isNotEmpty) 'page': 1,
        if (page.isNotEmpty) 'quote': page.single,
        if (marks.isNotEmpty) 'marks': ['A1'],
      };
      final result = '${jsonEncode(point)}\n${jsonEncode({'coverage': payload['requiredCoverage']})}';
      expect(validate(result).complete, isTrue);
      return result;
    });
    try {
      final points = await generator
          .readChapter(
            MapChapterInput(
              chapterId: 'both',
              documentAlias: 'D1',
              context: fixtures.context(MapLinePhase.chapter),
              textByPage: {1: text},
              annotations: {'A1': text},
              extractQuotes: true,
            ),
            CancellationToken(),
          )
          .toList();
      expect(pages.map((s) => utf8.decode(utf8.encode(s))).join(), text);
      expect(annotations.map((s) => utf8.decode(utf8.encode(s))).join(), text);
      expect(points.take(pages.length).map((p) => p.quote), pages);
      expect(points.take(pages.length).every((p) => p.source?.page == 1), isTrue);
      expect(points.skip(pages.length).every((p) => p.source == null && p.marks.single == 'private-mark'), isTrue);
    } finally {
      await generator.close();
    }
  });
}
