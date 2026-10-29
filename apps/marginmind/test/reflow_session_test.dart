import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/reflow_document.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_reflow/mm_reflow.dart';

import 'reflow_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const parser = EpubParser();
  const spec = LayoutSpec(width: 300, pageHeight: 240, padding: EdgeInsets.all(16));
  Future<ReflowDocument> fixture({bool image = false}) async {
    final repo = InMemoryStudySetContentRepository();
    final a = parser.parseHtml('a', '<h1>First</h1><p>${'anchors remain stable. ' * 40}</p>');
    final b = parser.parseHtml(
      'b',
      '<h1>Second</h1><p>UPPER lower 😀 combining é.</p>${image ? '<img src="art.svg">' : ''}',
    );
    final doc = await storeBook(
      repo,
      book: Book(
        'A book',
        [a, b],
        image
            ? {
                'art.svg': Uint8List.fromList(
                  utf8.encode(
                    '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect width="20" height="20"/></svg>',
                  ),
                ),
              }
            : {},
        [],
        toc: [BookTocEntry('a', 'First', 'a', 0), BookTocEntry('b', 'Second', 'b', 0)],
      ),
    );
    return ReflowDocument.load(repo, 'demo-1', doc);
  }

  test('manifest, canonical search offsets, progress and quote resolution', () async {
    final b = await fixture(image: true);
    expect(b.chapters.length, 2);
    expect(b.outline.length, 2);
    expect(b.title(b.end), 'Second');
    expect(b.progress(b.start), 0);
    expect(b.progress(b.end), 1);
    expect(b.atProgress(1).toJson(), b.end.toJson());
    expect(b.atProgress(-10).offset, 0);
    expect(b.search('upper').single.quote, 'UPPER');
    expect(b.search(''), isEmpty);
    final a = b.chapters.first.anchor(0, 5, revision: b.revision);
    expect(b.resolve(a), same(a));
    expect(b.resolve(const TextAnchor('absent', 0, 1, 'x', revision: 'old')), isNull);
    final relocated = b.resolve(const TextAnchor('b', 0, 5, 'UPPER', revision: 'old'));
    expect(relocated!.quote, 'UPPER');
    expect(relocated.revision, b.revision);
    expect(b.resolve(const TextAnchor('renamed', 0, 5, 'UPPER', revision: 'old'))!.chapterId, 'b');
    expect(
      b.resolve(const TextAnchor('a', 0, 7, 'anchors', revision: 'old')),
      isNull,
      reason: 'Repeated quote is unresolved',
    );
    expect(b.resolve(const TextAnchor('b', 0, 5, 'UPPER', prefix: 'wrong', revision: 'old')), isNull);
    expect(b.resolve(const TextAnchor('b', 0, 0, '', revision: 'old')), isNull);
    expect(b.resolve(TextAnchor('b', 0, 5, 'WRONG', revision: b.revision)), isNull);
    final unicode = b.chapters.last;
    final emoji = unicode.canonicalText.indexOf('😀');
    final half = unicode.canonicalText.substring(emoji, emoji + 1);
    expect(b.resolve(TextAnchor('b', emoji, emoji + 1, half, revision: b.revision)), isNull);
    expect(b.resolve(TextAnchor('b', emoji, emoji + 1, half, revision: 'old')), isNull);
    final combining = unicode.canonicalText.indexOf('é');
    expect(b.resolve(TextAnchor('b', combining, combining + 1, 'e', revision: b.revision)), isNull);
    expect(await b.resource('art.svg'), isNotEmpty);
    await expectLater(b.resource('../missing'), throwsFormatException);
  });
  test('navigation, resize, chapter boundaries, search and saved position', () async {
    final b = await fixture(image: true);
    final saved = <TextReadingPosition>[];
    final s = ReflowSession(() async => b, onPosition: saved.add);
    addTearDown(s.dispose);
    await s.configure(spec);
    expect(s.ready, isTrue);
    expect(s.position!.offset, 0);
    final old = s.layout!;
    await s.turn(1);
    expect(s.page, 1);
    expect(saved, isNotEmpty);
    final position = s.position!.toJson();
    await s.configure(const LayoutSpec(width: 400, pageHeight: 240, fontSize: 22));
    expect(old.isDisposed, isTrue);
    expect(s.position!.toJson(), position);
    await s.jump(b.start);
    await s.back();
    expect(s.position!.toJson(), position);
    expect(await s.jump(TextReadingPosition(revision: 'wrong', chapterId: 'a', offset: 0)), isFalse);
    expect(await s.jump(b.position('missing', 0)), isFalse);
    expect(await s.jump(b.position('a', 99999)), isFalse);
    await s.jump(b.position('a', b.chapters.first.canonicalText.length));
    await s.turn(1);
    expect(s.position!.chapterId, 'b');
    await s.turn(-1);
    expect(s.position!.chapterId, 'a');
    await s.search('upper');
    expect(s.matches.single.quote, 'UPPER');
    expect(s.position!.chapterId, 'b');
    await s.stepMatch(-1);
    expect(s.currentMatch!.quote, 'UPPER');
    await s.search('absent');
    expect(s.matchIndex, -1);
    await s.stepMatch(1);
    await s.search('');
    expect(s.currentMatch, isNull);
    s.scrolled(20);
    s.observe(b.start, 0);
    expect(saved.last.toJson(), b.start.toJson());
    await s.jump(b.start);
    await s.turn(-1);
    expect(s.position!.offset, 0);
    await s.jump(b.end);
    await s.turn(1);
    expect(s.position!.chapterId, 'b');
    expect(s.error, isNull);
  });
  test('search waits for loading and latest query wins', () async {
    final delayed = Completer<ReflowDocument>();
    final session = ReflowSession(() => delayed.future, onPosition: (_) {});
    addTearDown(session.dispose);
    final first = session.search('upper');
    final second = session.search('lower');
    delayed.complete(await fixture());
    await Future.wait([first, second]);
    expect(session.query, 'lower');
    expect(session.matches.single.quote, 'lower');
    final gone = ReflowSession(() async => await fixture(), onPosition: (_) {});
    final pending = gone.search('upper');
    gone.dispose();
    await pending;
  });
  test('late initialization and concurrent layout are safe on disposal', () async {
    final b = await fixture();
    final delayed = Completer<ReflowDocument>();
    final s = ReflowSession(() => delayed.future, onPosition: (_) {});
    final pending = s.configure(spec);
    s.dispose();
    delayed.complete(b);
    await pending;
    final active = ReflowSession(() async => b, onPosition: (_) {});
    addTearDown(active.dispose);
    final first = active.configure(spec);
    final second = active.configure(const LayoutSpec(width: 450, pageHeight: 200, fontSize: 22));
    await Future.wait([first, second]);
    expect(active.layout!.spec.fontSize, 22);
    expect(active.ready, isTrue);
    final turning = ReflowSession(() async => b, onPosition: (_) {});
    await turning.configure(spec);
    final turn = turning.turn(1);
    turning.dispose();
    await turn;
    final broken = ReflowSession(() async => throw const FormatException('broken'), onPosition: (_) {});
    await broken.configure(spec);
    expect(broken.error, isA<FormatException>());
    broken.dispose();
  });
  test('rejects corrupt IR, future versions and resource traversal before layout', () async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(repo);
    await expectLater(
      ReflowDocument.load(repo, 'demo-1', doc.copyWith(contentManifest: 'manifest.json')),
      throwsFormatException,
    );
    final key = ('demo-1', doc.contentManifest!);
    final original = repo.documentFiles[key]!;
    final manifest = (jsonDecode(utf8.decode(original)) as Map).cast<String, Object?>();
    repo.documentFiles[key] = utf8.encode(jsonEncode({...manifest, 'version': 99}));
    await expectLater(ReflowDocument.load(repo, 'demo-1', doc), throwsFormatException);
    final spine = (manifest['spine'] as List).first as Map;
    repo.documentFiles[key] = utf8.encode(
      jsonEncode({
        ...manifest,
        'spine': [
          {...spine, 'path': 'books/other/chapter.json'},
        ],
      }),
    );
    await expectLater(ReflowDocument.load(repo, 'demo-1', doc), throwsFormatException);
    repo.documentFiles[key] = original;
    repo.documentFiles[('demo-1', spine['path'] as String)] = utf8.encode('{}');
    await expectLater(ReflowDocument.load(repo, 'demo-1', doc), throwsFormatException);
  });
}
