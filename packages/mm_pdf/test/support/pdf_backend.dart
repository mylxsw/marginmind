import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

void installTestPdfBackend({int pageCount = 3, List<double>? pageWidths}) {
  assert(pageWidths == null || pageWidths.length == pageCount);
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  PdfrxEntryFunctions.instance = _Engine(pageCount, pageWidths);
}

// Deterministic backend: exercise the actual viewer and selection delegate
// without requiring a native PDFium asset in flutter test or CI.
class _Engine implements PdfrxEntryFunctions {
  _Engine(this.pageCount, this.pageWidths);
  final int pageCount;
  final List<double>? pageWidths;
  @override
  Future<void> init() async {}
  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async => _Document(pageCount, pageWidths);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Document extends PdfDocument {
  _Document(this.pageCount, this.pageWidths) : super(sourceName: 'selection-test.pdf');
  final int pageCount;
  final List<double>? pageWidths;
  @override
  late List<PdfPage> pages = List.generate(pageCount, (index) => _Page(this, index + 1, pageWidths?[index] ?? 600));
  @override
  bool get isEncrypted => false;
  @override
  PdfPermissions? get permissions => null;
  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();
  @override
  Future<void> dispose() async {}
  @override
  Future<void> loadPagesProgressively<T>({
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
    int? startPageNumber,
  }) async {}
  @override
  bool isIdenticalDocumentHandle(Object? other) => identical(this, other);
  @override
  Future<List<PdfOutlineNode>> loadOutline() async => TestPdfOutline.nodes;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Page implements PdfPage {
  _Page(this.document, this.pageNumber, this.width);
  @override
  final PdfDocument document;
  @override
  final int pageNumber;
  @override
  bool get isLoaded => true;
  @override
  final double width;
  @override
  double get height => 800;
  @override
  PdfPageRotation get rotation => PdfPageRotation.none;
  @override
  PdfPageRenderCancellationToken createCancellationToken() => _Token();
  @override
  Future<PdfPageRawText?> loadText() async =>
      TestPdfText.pages[pageNumber] ??
      PdfPageRawText('Selected passage', List.generate(16, (i) => PdfRect(30 + i * 10, 700, 40 + i * 10, 680)));
  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #render) return TestPdfRender._render(invocation.namedArguments);
    return super.noSuchMethod(invocation);
  }
}

abstract final class TestPdfText {
  static Map<int, PdfPageRawText> pages = {};
}

/// The table of contents the test backend's document reports.
abstract final class TestPdfOutline {
  static List<PdfOutlineNode> nodes = [];
}

/// Page rendering in the test backend: empty for the viewer's tiles, real
/// (blank) pixels for area captures when [produceImages] is set.
abstract final class TestPdfRender {
  static bool produceImages = false;
  static final requestedFullSizes = <(double?, double?)>[];

  /// Arguments of each produced render.
  static final renders = <Map<String, Object?>>[];

  static Future<PdfImage?> _render(Map<Symbol, dynamic> args) {
    requestedFullSizes.add((args[#fullWidth] as double?, args[#fullHeight] as double?));
    if (!produceImages) return Future.value(null);
    final width = args[#width] as int;
    final height = args[#height] as int;
    renders.add({
      'x': args[#x],
      'y': args[#y],
      'width': width,
      'height': height,
      if (renders.isEmpty && args[#fullWidth] == 1200.0) 'fullWidth': args[#fullWidth],
    });
    return Future.value(PdfImage.createFromBgraData(Uint8List(width * height * 4), width: width, height: height));
  }
}

class _Token implements PdfPageRenderCancellationToken {
  @override
  bool isCanceled = false;
  @override
  void cancel() => isCanceled = true;
}
