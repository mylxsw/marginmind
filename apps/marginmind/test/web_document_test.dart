import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/web_document.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_platform/mm_platform.dart';

final now = DateTime.utc(2026, 10, 29);
BrowserDocumentCapture capture(String html, {int version = 0, Uint8List? pdf}) => BrowserDocumentCapture(
  url: Uri.parse('https://example.com/article'),
  title: 'Article',
  capturedAt: now.add(Duration(seconds: version)),
  html: html,
  snapshot: '<p>snapshot $version</p>',
  resources: {},
  pdf: pdf,
);

void main() {
  test('all three formats preserve origin and publish immutable complete packages', () async {
    final converter = WebDocumentConverter(
      inspectPdf: (_) async => (pageCount: 2, pages: <TranslationPage>[], preview: null),
    );
    final store = InMemoryStudySetContentRepository();
    for (final mode in WebCaptureMode.values) {
      final result = await converter.prepare(
        capture('<h1>Title</h1><p>Body 🌍</p>', pdf: Uint8List.fromList(ascii.encode('%PDF-test'))),
        id: mode.name,
        title: 'My title',
        mode: mode,
      );
      final document = result.package.document;
      expect(document.origin!.mode, mode);
      expect(document.origin!.url, 'https://example.com/article');
      expect(document.origin!.capturedAt, now);
      expect(result.package.files, contains(document.origin!.snapshotFile));
      final snapshotMetadata = jsonDecode(
        utf8.decode(
          result.package.files[document.origin!.snapshotFile!.replaceFirst('snapshot.html', 'resources.json')]!,
        ),
      ) as Map;
      expect(snapshotMetadata['url'], document.origin!.url);
      expect(snapshotMetadata['capturedAt'], now.toIso8601String());
      expect(snapshotMetadata['mode'], mode.name);
      expect(snapshotMetadata['sourceFile'], document.sourceFileName);
      expect(snapshotMetadata['snapshotSha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(document.pageCount, mode == WebCaptureMode.original ? 2 : 0);
      expect(document.contentManifest, mode == WebCaptureMode.original ? isNull : isNotNull);
      expect(document.layout, mode == WebCaptureMode.original ? DocumentLayout.fixed : DocumentLayout.reflow);
      if (mode == WebCaptureMode.markdown) {
        expect(utf8.decode(result.package.files[document.sourceFileName]!), contains('# Title'));
      }
      await store.importDocumentPackage('set', result.package);
      expect((await store.load('set')).document(mode.name)!.title, 'My title');
    }
  });
  test('recapture aligns annotations against the latest content and keeps unresolved marks', () async {
    const converter = WebDocumentConverter();
    final first = await converter.prepare(
      capture('<p>before target after</p>'),
      id: 'web',
      title: 'Title',
      mode: WebCaptureMode.readable,
    );
    final previous = first.package.document.copyWith(
      readingPosition: TextReadingPosition(revision: first.package.document.revision!, chapterId: 'main', offset: 7),
    );
    final store = InMemoryStudySetContentRepository();
    await store.importDocumentPackage('set', first.package);
    Annotation mark(String id, String quote) => Annotation(
      id: id,
      documentId: 'web',
      textAnchors: [TextAnchor('main', 7, 7 + quote.length, quote, revision: previous.revision!)],
      quote: quote,
      colorIndex: 2,
      createdAt: now,
    );
    await store.update(
      'set',
      (c) => c.copyWith(
        annotations: [mark('a', 'target'), mark('b', 'removed')],
        noteAttachments: [
          NoteAttachment(
            id: 'attachment',
            noteId: 'n',
            target: TextTarget(documentId: 'web', textAnchors: mark('a', 'target').textAnchors),
          ),
        ],
        marginNotes: [
          MarginNote(
            id: 'margin',
            documentId: 'web',
            anchor: AnnotationAnchor(textAnchors: mark('a', 'target').textAnchors, quote: 'target'),
            text: 'note',
            colorIndex: 0,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        inkStrokes: [
          InkStroke(
            id: 'ink',
            documentId: 'web',
            textAnchor: ParagraphInkAnchor(
              anchor: mark('a', 'target').textAnchors.single,
              blockId: 'old-block',
              capturedWidth: 400,
              originX: 0,
              originY: 0,
            ),
            tool: InkTool.pen,
            colorIndex: 0,
            width: 2,
          ),
        ],
        bookmarks: [
          Bookmark(
            id: 'bookmark',
            documentId: 'web',
            position: TextReadingPosition(revision: previous.revision!, chapterId: 'main', offset: 7),
            createdAt: now,
          ),
        ],
      ),
    );
    final next = await converter.prepare(
      capture('<p>new before target after</p>', version: 1),
      id: 'web',
      title: 'Title',
      mode: WebCaptureMode.readable,
      previous: previous,
      oldChapters: {'main': 'before target after'},
    );
    // This edit lands after preparation and must be included by reconciliation.
    await store.update('set', (c) => c.copyWith(annotations: [...c.annotations, mark('late', 'target')]));
    final result = await store.importDocumentPackage('set', next.package);
    expect(result.annotation('a')!.textAnchors.single.start, 11);
    expect(result.annotation('late')!.textAnchors.single.revision, next.package.document.revision);
    expect(result.annotation('a')!.needsReview, isFalse);
    expect(result.annotation('b')!.needsReview, isTrue);
    expect(result.annotation('b')!.textAnchors.single.revision, previous.revision);
    expect((result.bookmarks.single.position as TextReadingPosition).offset, 11);
    expect((result.document('web')!.readingPosition as TextReadingPosition).offset, 11);
    expect((result.noteAttachments.single.target as TextTarget).textAnchors.single.start, 11);
    expect(result.marginNotes.single.anchor!.textAnchors.single.revision, next.package.document.revision);
    expect(result.inkStrokes.single.textAnchor!.blockId, isNot('old-block'));
    expect(next.package.document.importedAt, previous.importedAt);
    expect(store.documentFiles, contains(('set', previous.origin!.snapshotFile!)));
    await expectLater(store.importDocumentPackage('set', next.package), throwsStateError);
    expect(Annotation.fromJson(result.annotation('b')!.copyWith(colorIndex: 3).toJson()).needsReview, isTrue);
  });
  test('image resources are packaged for both reading and offline snapshots', () async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jVYsAAAAASUVORK5CYII=',
    );
    final captured = BrowserDocumentCapture(
      url: Uri.parse('https://example.com/'),
      title: 'Image',
      capturedAt: now,
      html: '<p>text</p><img src="resources/image-1.png">',
      snapshot: '<img src="resources/image-1.png">',
      resources: {'resources/image-1.png': png},
    );
    final prepared = await const WebDocumentConverter().prepare(
      captured,
      id: 'image',
      title: 'Image',
      mode: WebCaptureMode.readable,
    );
    final files = prepared.package.files;
    final manifest = jsonDecode(utf8.decode(files[prepared.package.document.contentManifest]!)) as Map;
    final resource = (manifest['resources'] as List).single as Map;
    expect(files[resource['path']], png);
    expect(resource['sourcePath'], 'resources/image-1.png');
    expect(prepared.package.document.revision, prepared.book.revision);
    expect(
      files[prepared.package.document.origin!.snapshotFile!.replaceFirst('snapshot.html', 'resources/image-1.png')],
      png,
    );
    expect(captured.resources['resources/image-1.png']!.asUnmodifiableView(), png);
  });
  test(
    'unchanged canonical content retains its IR revision but captures and concurrency guards are distinct',
    () async {
      const converter = WebDocumentConverter();
      final store = InMemoryStudySetContentRepository();
      final first = await converter.prepare(
        capture('<p>unchanged</p>'),
        id: 'same',
        title: 'Custom title',
        mode: WebCaptureMode.readable,
      );
      await store.importDocumentPackage('set', first.package);
      final second = await converter.prepare(
        capture('<p>unchanged</p>', version: 1),
        id: 'same',
        title: 'Renamed',
        mode: WebCaptureMode.readable,
        previous: first.package.document,
      );
      expect(second.package.document.revision, first.package.document.revision);
      expect(second.package.document.origin!.snapshotFile, isNot(first.package.document.origin!.snapshotFile));
      await store.importDocumentPackage('set', second.package);
      await expectLater(store.importDocumentPackage('set', second.package), throwsStateError);
      expect((await store.load('set')).document('same')!.title, 'Renamed');
    },
  );
  test('PDF quote relocation is unique, handles pages and preserves missing quotes', () async {
    final pages = [
      TranslationPage(1, 'alpha', [for (var i = 0; i < 5; i++) PageRect(i.toDouble(), 20, i + 1, 10)]),
      TranslationPage(2, 'beta', [for (var i = 0; i < 4; i++) PageRect(i.toDouble(), 20, i + 1, 10)]),
    ];
    expect(alignPdfQuote('ha\nbe', pages)!.map((p) => p.page), [1, 2]);
    expect(alignPdfQuote('', pages), isNull);
    expect(alignPdfQuote('missing', pages), isNull);
    expect(alignPdfQuote('a', pages), isNull);
    expect(alignPdfQuote('alpha', [TranslationPage(1, 'alpha', [])]), isNull);
    expect(alignPdfQuote('alpha', [TranslationPage(1, 'alpha', List.filled(5, const PageRect(0, 0, 0, 0)))]), isNull);
    final converter = WebDocumentConverter(inspectPdf: (_) async => (pageCount: 2, pages: pages, preview: null));
    final prepared = await converter.prepare(
      capture('<p>alpha beta</p>', pdf: Uint8List.fromList([1])),
      id: 'web',
      title: 'PDF',
      mode: WebCaptureMode.original,
    );
    final content = StudySetContent(
      documents: [prepared.package.document],
      annotations: [
        for (final quote in ['alpha', 'missing'])
          Annotation(
            id: quote,
            documentId: 'web',
            page: 1,
            rects: [const PageRect(0, 100, 10, 90)],
            quote: quote,
            colorIndex: 0,
            createdAt: now,
          ),
      ],
    );
    final aligned = reconcileWebContent(content, prepared.package.document, prepared.book.chapters, {}, pages);
    expect(aligned.annotation('alpha')!.needsReview, isFalse);
    expect(aligned.annotation('alpha')!.rects.first.top, 20);
    expect(aligned.annotation('missing')!.needsReview, isTrue);
    expect(aligned.annotation('missing')!.rects.first.top, 100);
    await expectLater(
      converter.prepare(capture('<p>a</p>'), id: 'web', title: '', mode: WebCaptureMode.readable),
      throwsFormatException,
    );
    await expectLater(
      converter.prepare(capture('<p>a</p>'), id: 'web', title: 'PDF', mode: WebCaptureMode.original),
      throwsFormatException,
    );
  });
}
