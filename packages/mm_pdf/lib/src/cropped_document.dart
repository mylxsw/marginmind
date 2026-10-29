import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:mm_core/mm_core.dart';
import 'package:pdfrx/pdfrx.dart';

import 'reading_geometry.dart';

/// Display-only document: PDFium renders source tiles from the original page.
/// pdfrx still owns virtualization, the 100 MiB cache and real text selection.
/// This document must never be assembled or used as the source for OCR/export.
class CroppedDocument extends PdfDocument {
  CroppedDocument(this.original, DocumentCrop crop) : super(sourceName: original.sourceName) {
    _pages = List.unmodifiable([
      for (final page in original.pages) CroppedPage(this, page, crop.forPage(page.pageNumber)),
    ]);
  }
  final PdfDocument original;
  late final List<PdfPage> _pages;
  @override
  List<PdfPage> get pages => _pages;
  @override
  set pages(List<PdfPage> value) => throw UnsupportedError('Display-only document');
  @override
  PdfPermissions? get permissions => original.permissions;
  @override
  bool get isEncrypted => original.isEncrypted;
  @override
  Stream<PdfDocumentEvent> get events => original.events;
  @override
  Future<void> dispose() => original.dispose();
  @override
  bool isIdenticalDocumentHandle(Object? other) => identical(this, other);
  @override
  Future<void> loadPagesProgressively<T>({
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
    int? startPageNumber,
  }) => original.loadPagesProgressively(
    onPageLoadProgress: onPageLoadProgress,
    data: data,
    loadUnitDuration: loadUnitDuration,
    startPageNumber: startPageNumber,
  );
  @override
  Future<List<PdfOutlineNode>> loadOutline() async => [for (final node in await original.loadOutline()) _outline(node)];
  PdfOutlineNode _outline(PdfOutlineNode n) => PdfOutlineNode(
    title: n.title,
    dest: destination(n.dest),
    children: [for (final child in n.children) _outline(child)],
  );

  PdfDest? destination(PdfDest? dest) {
    if (dest == null || dest.pageNumber < 1 || dest.pageNumber > pages.length || dest.params == null) return dest;
    final crop = (pages[dest.pageNumber - 1] as CroppedPage).crop;
    final p = List<double?>.of(dest.params!);
    void x(int i) {
      if (p.length > i && p[i] != null) p[i] = p[i]! - crop.left;
    }

    void y(int i) {
      if (p.length > i && p[i] != null) p[i] = p[i]! - crop.bottom;
    }

    switch (dest.command) {
      case PdfDestCommand.xyz:
        x(0);
        y(1);
      case PdfDestCommand.fitH:
      case PdfDestCommand.fitBH:
        y(0);
      case PdfDestCommand.fitV:
      case PdfDestCommand.fitBV:
        x(0);
      case PdfDestCommand.fitR:
        x(0);
        y(1);
        x(2);
        y(3);
      default:
        break;
    }
    return PdfDest(dest.pageNumber, dest.command, p);
  }

  @override
  Future<bool> assemble() => throw UnsupportedError('Display-only document');
  @override
  Future<Uint8List> encodePdf({bool incremental = false, bool removeSecurity = false}) =>
      throw UnsupportedError('Use original document for export');
  @override
  Future<T> useNativeDocumentHandle<T>(FutureOr<T> Function(int) task) => original.useNativeDocumentHandle(task);
  @override
  Future<void> reloadPages({List<int>? pageNumbersToReload}) => throw UnsupportedError('Reopen display document');
}

class CroppedPage implements PdfPage {
  CroppedPage(this.document, this.basePage, this.crop) {
    crop.validateSize(basePage.width, basePage.height);
  }
  @override
  final CroppedDocument document;
  final PdfPage basePage;
  final CropInsets crop;
  PageViewportTransform transform({double scale = 1, Offset origin = Offset.zero}) =>
      PageViewportTransform(pageSize: Size(basePage.width, basePage.height), crop: crop, scale: scale, origin: origin);
  PdfRect toOriginal(PdfRect r) =>
      PdfRect(r.left + crop.left, r.top + crop.bottom, r.right + crop.left, r.bottom + crop.bottom);
  PdfRect fromOriginal(PdfRect r) =>
      PdfRect(r.left - crop.left, r.top - crop.bottom, r.right - crop.left, r.bottom - crop.bottom);
  @override
  int get pageNumber => basePage.pageNumber;
  @override
  double get width => basePage.width - crop.left - crop.right;
  @override
  double get height => basePage.height - crop.top - crop.bottom;
  @override
  PdfPageRotation get rotation => PdfPageRotation.none;
  @override
  bool get isLoaded => basePage.isLoaded;
  @override
  PdfPageRenderCancellationToken createCancellationToken() => basePage.createCancellationToken();
  @override
  Future<PdfPageRawText?> loadText() async {
    // PDFium's raw boxes use the rotated page coordinates. Translate every
    // character, including hidden ones, to preserve text and search ordering.
    final text = await basePage.loadText();
    return text == null ? null : PdfPageRawText(text.fullText, [for (final r in text.charRects) fromOriginal(r)]);
  }

  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) async => [
    for (final link in await basePage.loadLinks(compact: compact, enableAutoLinkDetection: enableAutoLinkDetection))
      PdfLink(
        [for (final r in link.rects) fromOriginal(r)],
        url: link.url,
        dest: document.destination(link.dest),
        annotation: link.annotation,
      ),
  ];
  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
    PdfPageRenderPriority? priority,
  }) {
    final sx = (fullWidth ?? this.width) / this.width;
    final sy = (fullHeight ?? this.height) / this.height;
    return basePage.render(
      x: x + (crop.left * sx).round(),
      y: y + (crop.top * sy).round(),
      width: width ?? (this.width * sx).round(),
      height: height ?? (this.height * sy).round(),
      fullWidth: basePage.width * sx,
      fullHeight: basePage.height * sy,
      backgroundColor: backgroundColor,
      annotationRenderingMode: annotationRenderingMode,
      flags: flags,
      cancellationToken: cancellationToken,
      priority: priority,
    );
  }
}
