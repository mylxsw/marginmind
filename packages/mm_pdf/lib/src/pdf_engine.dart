import 'package:pdfrx/pdfrx.dart';

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:mm_core/mm_core.dart';

import 'open_document.dart';

/// Document-level operations that do not need a viewer.
abstract final class MMPdfEngine {
  static bool _initialized = false;

  /// Call once at startup, before any document API is used.
  static Future<void> initialize() async {
    if (_initialized) return;
    await pdfrxFlutterInitialize();
    _initialized = true;
  }

  /// Extract once per session and always release the PDFium document.
  static Future<List<TranslationParagraph>> translationParagraphs(String path, String documentId) async {
    final doc = await openDocument(path);
    try {
      final pages = <TranslationPage>[];
      for (final page in doc.pages) {
        final text = await page.loadText();
        if (text != null) {
          pages.add(
            TranslationPage(page.pageNumber, text.fullText, [
              for (final r in text.charRects) PageRect(r.left, r.top, r.right, r.bottom),
            ]),
          );
        }
      }
      return splitTranslationParagraphs(documentId, pages);
    } finally {
      await doc.dispose();
    }
  }

  /// Reads the page count (and title, if the file has one) of [path].
  /// Throws if the file is not a readable PDF.
  static Future<({int pageCount, String? title})> inspect(String path) async {
    final doc = await openDocument(path);
    try {
      return (pageCount: doc.pages.length, title: null);
    } finally {
      await doc.dispose();
    }
  }

  /// Inspect a browser print without publishing a temporary document path.
  static Future<({int pageCount, List<TranslationPage> pages, Uint8List? preview})> inspectData(Uint8List bytes) async {
    final doc = await PdfDocument.openData(bytes);
    try {
      final pages = <TranslationPage>[];
      for (final page in doc.pages) {
        final text = await page.loadText();
        if (text != null) {
          pages.add(
            TranslationPage(page.pageNumber, text.fullText, [
              for (final r in text.charRects) PageRect(r.left, r.top, r.right, r.bottom),
            ]),
          );
        }
      }
      final image = doc.pages.isEmpty
          ? null
          : await doc.pages.first.render(
              width: 400,
              height: (doc.pages.first.height * 400 / doc.pages.first.width).ceil(),
              fullWidth: 400,
              fullHeight: doc.pages.first.height * 400 / doc.pages.first.width,
            );
      Uint8List? preview;
      try {
        if (image != null) {
          preview = await image.createImage().then((image) async {
            try {
              return (await image.toByteData(format: ui.ImageByteFormat.png))?.buffer.asUint8List();
            } finally {
              image.dispose();
            }
          });
        }
      } finally {
        image?.dispose();
      }
      return (pageCount: doc.pages.length, pages: pages, preview: preview);
    } finally {
      await doc.dispose();
    }
  }

  /// The text of 1-based [page] of [path], or null when the file or page
  /// cannot be read.
  static Future<String?> pageText(String path, int page) async => (await pageContent(path, page))?.text;

  static Future<DocumentOutline> outline(String path, String documentId) async {
    final doc = await openDocument(path);
    try {
      List<PdfOutlineEntry> convert(List<PdfOutlineNode> nodes, String prefix) => [
        for (final (i, n) in nodes.indexed)
          PdfOutlineEntry(
            id: 'pdf-$prefix$i',
            title: n.title.trim(),
            page: n.dest?.pageNumber ?? 0,
            children: convert(n.children, '$prefix$i/'),
          ),
      ];
      return DocumentOutline(documentId: documentId, items: convert(await doc.loadOutline(), ''));
    } finally {
      await doc.dispose();
    }
  }

  /// Character geometry from the supplied original or recognized PDF.
  static Future<TranslationPage?> quotePage(String path, int page) async {
    final doc = await openDocument(path);
    try {
      if (page < 1 || page > doc.pages.length) return null;
      final text = await doc.pages[page - 1].loadText();
      if (text == null) return null;
      return TranslationPage(page, text.fullText, [
        for (final r in text.charRects) PageRect(r.left, r.top, r.right, r.bottom),
      ]);
    } finally {
      await doc.dispose();
    }
  }

  /// Like [pageText], with the page height in points.
  static Future<({String text, double height})?> pageContent(String path, int page) async {
    PdfDocument? doc;
    try {
      doc = await openDocument(path);
      if (page < 1 || page > doc.pages.length) return null;
      final pdfPage = doc.pages[page - 1];
      final text = (await pdfPage.loadText())?.fullText;
      return text == null ? null : (text: text, height: pdfPage.height);
    } catch (_) {
      return null;
    } finally {
      await doc?.dispose();
    }
  }
}
