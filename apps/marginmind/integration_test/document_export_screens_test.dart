import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/document_import.dart';
import 'package:marginmind/features/workspace/reflow_document.dart';
import 'package:marginmind/features/workspace/widgets/document_export_sheet.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_book/mm_book.dart' as book;
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
// ignore: depend_on_referenced_packages
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_dart;
// ignore: depend_on_referenced_packages
import 'package:pdfrx/pdfrx.dart';

import '../test/helpers.dart';

/// Walks the export sheet in the real app on the running device, then checks
/// the files it writes: PDF annotations are read back through the device's own
/// PDFium, so this also proves the annotation API exists on that platform.
/// With CAPTURE_UI a host saves the window at each PHONE_SHOT marker; see
/// tool/capture_document_export.py.
const _capture = bool.fromEnvironment('CAPTURE_UI');
const _dark = bool.fromEnvironment('UI_DARK');
const _realSave = bool.fromEnvironment('UI_REAL_SAVE');
const _nativeMenu = bool.fromEnvironment('UI_NATIVE_MENU');

const _setId = 'demo-1';
final _date = DateTime.utc(2026, 11);

const _chapterOne = [
  '连续学习带来的流畅感是一种错觉。它让人觉得自己学会了，却没有让知识在第二天还能被调用。',
  '把同样的时间拆开，中间留出足够让人略微遗忘的空白，回想时的那一点吃力，会让记忆的痕迹更牢固。',
  '间隔多长并没有统一答案。一个实用的经验是：想在多久之后还记得，就把间隔设成那段时间的十分之一到五分之一。',
];

class _Repository extends InMemoryStudySetContentRepository {
  _Repository(super.initial, this.directory);
  final Directory directory;
  @override
  String resolveFile(String studySetId, String fileName) => '${directory.path}/$fileName';
}

/// One test-time source EPUB, written by the writer under test and read back by
/// the importer, so the import → annotate → export round trip is real.
Uint8List _sourceEpub() => book.BookEpubWriter(
  title: '刻意的间隔',
  identifier: 'urn:test:epub',
  chapters: [
    book.BookChapter('c', [
      book.BookBlock(id: 'h', kind: book.BlockKind.heading, start: 0, runs: const [book.InlineRun('为什么要隔开')]),
      for (final (i, text) in _chapterOne.indexed)
        book.BookBlock(
          id: 'p$i',
          kind: book.BlockKind.paragraph,
          start: 7 + _chapterOne.take(i).fold<int>(0, (n, t) => n + t.length + 1),
          runs: [book.InlineRun(text)],
        ),
    ]),
  ],
  toc: [book.BookTocEntry('t', '为什么要隔开', 'c', 0)],
  resources: const {},
).write();

Future<Map<int, List<int>>> _annotations(Uint8List bytes) async {
  final document = await PdfDocument.openData(bytes);
  try {
    return await document.useNativeDocumentHandle((handle) {
      final api = pdfium_dart.getPdfium(modulePath: Pdfrx.pdfiumModulePath);
      final native = pdfium_dart.FPDF_DOCUMENT.fromAddress(handle);
      return {
        for (var i = 0; i < api.FPDF_GetPageCount(native); i++)
          i + 1: () {
            final page = api.FPDF_LoadPage(native, i);
            final types = [
              for (var a = 0; a < api.FPDFPage_GetAnnotCount(page); a++)
                () {
                  final annot = api.FPDFPage_GetAnnot(page, a);
                  final type = api.FPDFAnnot_GetSubtype(annot);
                  api.FPDFPage_CloseAnnot(annot);
                  return type;
                }(),
            ];
            api.FPDF_ClosePage(page);
            return types;
          }(),
      };
    });
  } finally {
    await document.dispose();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('every export screen and the files it writes', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    await DesktopWindow.initialize(title: 'Foliarc', minimumSize: MMSizes.windowMinSize);

    final directory = (await tester.runAsync(() => Directory.systemTemp.createTemp('document-export')))!;
    final repository = _Repository({_setId: StudySetContent.empty}, directory);
    final sample = await rootBundle.load('assets/sample/sample.pdf');
    final pdf = sample.buffer.asUint8List(sample.offsetInBytes, sample.lengthInBytes);

    // Real text positions, so marks in the exported file land on real lines.
    final lines = (await tester.runAsync(() async {
      await MMPdfEngine.initialize();
      final document = await PdfDocument.openData(pdf);
      try {
        final text = await document.pages.first.loadText();
        final rects = <PageRect>[];
        final chars = text!.charRects;
        for (var i = 0, start = 0; i < chars.length && rects.length < 6; i++) {
          final last = i + 1 == chars.length || (chars[i + 1].top - chars[i].top).abs() > 4;
          if (!last || i - start < 8) {
            if (last) start = i + 1;
            continue;
          }
          rects.add(PageRect(chars[start].left, chars[start].top, chars[i].right, chars[start].bottom));
          start = i + 1;
        }
        return (rects: rects, pages: document.pages.length);
      } finally {
        await document.dispose();
      }
    }))!;
    expect(lines.rects.length, greaterThanOrEqualTo(4));

    Future<void> importFile(String id, String name, Uint8List bytes) async {
      final file = File('${directory.path}/$name');
      await file.writeAsBytes(bytes);
      final package = await const DocumentImporter().prepare((path: file.path, name: name), id: id, now: _date);
      await repository.importDocumentPackage(_setId, package);
      for (final entry in package.files.entries) {
        final target = File('${directory.path}/${entry.key}');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(entry.value);
      }
    }

    await tester.runAsync(() async {
      await importFile('pdf', '记忆的形状.pdf', pdf);
      await importFile('blank', '附录.pdf', pdf);
      await importFile('epub', '刻意的间隔.epub', _sourceEpub());
      await importFile(
        'md',
        '读书会提纲.md',
        Uint8List.fromList(utf8.encode('# 读书会提纲\n\n遗忘曲线最陡的部分在学习后的**头一个小时**。\n\n- 重读带来熟悉感，复述才暴露漏洞。\n')),
      );
      final imported = await repository.load(_setId);
      final stored = {
        for (final id in ['epub', 'md']) id: await ReflowDocument.load(repository, _setId, imported.document(id)!),
      };
      await repository.update(_setId, (content) {
        final epub = content.document('epub')!;
        final md = content.document('md')!;
        TextAnchor anchorIn(Document document, String quote) {
          final chapter = stored[document.id]!.chapters.firstWhere((c) => c.canonicalText.contains(quote));
          final start = chapter.canonicalText.indexOf(quote);
          return chapter.anchor(start, start + quote.length, revision: document.revision!);
        }

        Annotation pageMark(String id, int line, int color, {AnnotationKind kind = AnnotationKind.highlight}) =>
            Annotation(
              id: id,
              documentId: 'pdf',
              pages: [
                AnnotationPage(page: 1, rects: [lines.rects[line]]),
              ],
              quote: 'quote $id',
              colorIndex: color,
              createdAt: _date,
              kind: kind,
            );
        Annotation textMark(
          Document document,
          String id,
          String quote,
          int color, {
          AnnotationKind kind = AnnotationKind.highlight,
        }) => Annotation(
          id: id,
          documentId: document.id,
          textAnchors: [anchorIn(document, quote)],
          quote: quote,
          colorIndex: color,
          createdAt: _date,
          kind: kind,
        );
        MarginNote textNote(Document document, String id, String quote, String text) => MarginNote(
          id: id,
          documentId: document.id,
          anchor: AnnotationAnchor(textAnchors: [anchorIn(document, quote)], quote: quote),
          text: text,
          colorIndex: 0,
          createdAt: _date,
          updatedAt: _date,
        );
        return content.copyWith(
          annotations: [
            pageMark('p1', 0, 0),
            pageMark('p2', 1, 1),
            pageMark('p3', 2, 3),
            pageMark('p4', 3, 2, kind: AnnotationKind.underline),
            textMark(epub, 'e1', '流畅感是一种错觉', 0),
            textMark(epub, 'e2', '回想时的那一点吃力', 2, kind: AnnotationKind.underline),
            textMark(md, 'm1', '头一个小时', 0),
            textMark(md, 'm2', '复述才暴露漏洞', 2, kind: AnnotationKind.underline),
          ],
          marginNotes: [
            MarginNote(
              id: 'pn',
              documentId: 'pdf',
              page: 1,
              anchor: AnnotationAnchor(
                pages: [
                  AnnotationPage(page: 1, rects: [lines.rects[1]]),
                ],
                quote: 'quote',
              ),
              text: '回忆本身就是一次编辑。',
              colorIndex: 0,
              createdAt: _date,
              updatedAt: _date,
            ),
            textNote(epub, 'en', '流畅感是一种错觉', '≈ 熟悉感不等于掌握。'),
            textNote(md, 'mn', '头一个小时', '讨论：为什么下课后马上回顾最有效？'),
          ],
          inkStrokes: [
            InkStroke(
              id: 'pi',
              documentId: 'pdf',
              page: 1,
              tool: InkTool.ellipse,
              colorIndex: 0,
              width: 2,
              ellipse: PageRect(
                lines.rects[2].left,
                lines.rects[2].top + 4,
                lines.rects[2].left + 80,
                lines.rects[2].bottom - 4,
              ),
            ),
          ],
        );
      });
    });
    final sets = [StudySet(id: _setId, title: '学习科学', colorIndex: 0, lastOpenedAt: _date, createdAt: _date)];
    await tester.pumpWidget(
      ProviderScope(
        overrides: await testOverrides(
          prefs: {'settings.language': 'zh', 'settings.appearance': _dark ? 'dark' : 'light'},
          renderPdf: true,
          sets: sets,
          content: repository,
        ),
        child: const MarginMindApp(),
      ),
    );

    Future<void> idle([int steps = 10]) async {
      for (var i = 0; i < steps; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
    }

    final marker = File('${Directory.systemTemp.path}/document-export-shot');
    final errors = <String>[];
    Future<void> shot(String name) async {
      await idle(8);
      Object? error;
      while ((error = tester.takeException()) != null) {
        errors.add('$name: $error');
        // ignore: avoid_print
        print('SCREEN_ERROR:$name:$error');
      }
      if (!_capture) return;
      await tester.runAsync(() async {
        await marker.writeAsString(name);
        // ignore: avoid_print
        print('PHONE_SHOT:$name:${marker.path}');
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (await marker.readAsString() != 'captured:$name') {
          if (DateTime.now().isAfter(deadline)) throw TimeoutException('Host did not capture $name');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await idle(2);
      await tester.tap(finder, warnIfMissed: false);
      await idle(5);
    }

    Finder key(String value) => find.byKey(ValueKey(value));
    final container = ProviderScope.containerOf(tester.element(find.byType(MarginMindApp)));
    container.read(navigationProvider.notifier).openStudySet(_setId);
    await idle(20);
    final workspace = container.read(workspaceProvider(_setId).notifier);

    final written = <String, Uint8List>{};
    DocumentExportSheet.debugSave = (name, bytes) async {
      written[name] = bytes;
      return true;
    };
    addTearDown(() => DocumentExportSheet.debugSave = null);

    Future<void> openSheet(String document) async {
      await tester.runAsync(() async {});
      workspace.openDocument(document);
      await idle(12);
      final context = tester.element(find.byType(Navigator).first);
      unawaited(showDocumentExportSheet(context, _setId, document));
      await idle(8);
    }

    Future<void> closeSheet() async {
      await tap(key('document-export-cancel'));
      await idle(4);
    }

    /// Exports and waits for the sheet to close; PDFium and the isolate run for real.
    Future<void> run(Finder finder) async {
      await tap(finder);
      for (var i = 0; i < 100 && find.byType(DocumentExportSheet).evaluate().isNotEmpty; i++) {
        await idle(2);
      }
      expect(find.byType(DocumentExportSheet), findsNothing);
    }

    // Entry point: the menu on the reader, on every form factor.
    workspace.openDocument('pdf');
    await idle(20);
    if (_nativeMenu) {
      // The iPhone's menu is a native sheet: the host taps its row through XCTest.
      await MMNativePresentation.initialize();
      await tap(key('phone-workspace-more'));
      await idle(10);
      await shot('12-native-more');
      for (var i = 0; i < 900 && find.byType(DocumentExportSheet).evaluate().isEmpty; i++) {
        await idle(1);
      }
      expect(find.byType(DocumentExportSheet), findsOneWidget);
      await shot('13-native-export-sheet');
      return;
    }
    if (key('phone-workspace-more').evaluate().isNotEmpty) {
      await tap(key('phone-workspace-more'));
      await idle(4);
      await shot('01-entry');
      await tap(key('phone-row-export-copy'));
    } else {
      await tap(key('reader-more').first);
      await idle(4);
      await shot('01-entry');
      await tap(key('reader-export-copy'));
    }
    await idle(8);
    expect(find.byType(DocumentExportSheet), findsOneWidget);
    await shot('02-pdf-choices');

    // Options replace the choices rather than stacking under them.
    await tap(key('document-export-more'));
    await shot('03-pdf-options');
    await tap(key('document-export-color-1'));
    await tap(find.text('指定页'));
    await tester.enterText(
      find.descendant(of: key('document-export-pages'), matching: find.byType(EditableText)),
      '99999',
    );
    await shot('04-pdf-invalid-pages');
    await tester.enterText(find.descendant(of: key('document-export-pages'), matching: find.byType(EditableText)), '1');
    await idle(3);
    FocusManager.instance.primaryFocus?.unfocus();
    await shot('05-pdf-options-filled');
    await run(key('document-export-save'));
    final filtered = await tester.runAsync(() => _annotations(written.values.last));
    expect(filtered!.keys, [1]);
    // Green is filtered out: two highlights, one underline, one note, one stroke.
    expect(filtered[1], hasLength(5));
    await shot('06-hud');
    written.clear();

    // The one-tap route writes everything on every page.
    await openSheet('pdf');
    await run(key('document-export-everything'));
    final name = written.keys.single;
    expect(name, '记忆的形状（标注版）.pdf');
    final everything = (await tester.runAsync(() => _annotations(written[name]!)))!;
    expect(everything.keys, hasLength(lines.pages));
    expect(everything[1], hasLength(6));
    await tester.runAsync(() => File('${directory.path}/exported.pdf').writeAsBytes(written[name]!));
    // ignore: avoid_print
    print('EXPORTED_PDF:${directory.path}/exported.pdf');
    written.clear();

    await openSheet('pdf');
    await run(key('document-export-marks'));
    final marksOnly = (await tester.runAsync(() => _annotations(written.values.single)))!;
    expect(marksOnly[1], hasLength(4));
    expect(marksOnly[1], everyElement(isNot(pdfium_dart.FPDF_ANNOT_INK)));
    written.clear();

    await openSheet('pdf');
    await run(key('document-export-clean'));
    expect(written.keys.single, '记忆的形状（副本）.pdf');
    expect(written.values.single, pdf);
    written.clear();

    await openSheet('blank');
    await shot('07-no-annotations');
    await closeSheet();

    await openSheet('epub');
    await shot('08-epub-choices');
    await tap(key('document-export-more'));
    await shot('09-epub-options');
    await tap(key('document-export-more'));
    await run(key('document-export-everything'));
    expect(written.keys.single, '刻意的间隔（标注版）.epub');
    final epubFiles = ZipDecoder().decodeBytes(written.values.single).files;
    expect(epubFiles.first.name, 'mimetype');
    final xhtml = utf8.decode(epubFiles.firstWhere((f) => f.name.endsWith('chapter0.xhtml')).content);
    expect(xhtml, contains('流畅感是一种错觉</mark>'));
    expect(xhtml, contains('回想时的那一点吃力</span>'));
    expect(xhtml, contains('≈ 熟悉感不等于掌握。'));
    expect(book.EpubParser().parse(written.values.single).chapters.single.canonicalText, contains('连续学习'));
    await tester.runAsync(() => File('${directory.path}/exported.epub').writeAsBytes(written.values.single));
    written.clear();

    await openSheet('md');
    await shot('10-markdown-choices');
    await run(key('document-export-everything'));
    expect(written.keys.single, '读书会提纲（标注版）.md');
    final markdown = utf8.decode(written.values.single);
    expect(markdown, contains('<mark>头一个小时</mark>[^1]**'));
    expect(markdown, contains('<u>复述才暴露漏洞</u>'));
    expect(markdown, contains('[^1]: 讨论'));
    written.clear();

    // The platform's own save panel or share sheet, with the real file name.
    if (_realSave) {
      DocumentExportSheet.debugSave = null;
      await openSheet('pdf');
      await tester.tap(key('document-export-everything'), warnIfMissed: false);
      await idle(30);
      await shot('11-system-save');
    }
    expect(errors, isEmpty);
  });
}
