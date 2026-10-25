import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

void installTestPdfBackend() {
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  PdfrxEntryFunctions.instance = _Engine();
}

// Deterministic backend: exercise the actual viewer and selection delegate
// without requiring a native PDFium asset in flutter test or CI.
class _Engine implements PdfrxEntryFunctions {
  @override
  Future<void> init() async {}
  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async => _Document();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Document extends PdfDocument {
  _Document() : super(sourceName: 'selection-test.pdf');
  @override
  late List<PdfPage> pages = [_Page(this, 1), _Page(this, 2), _Page(this, 3)];
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
  Future<List<PdfOutlineNode>> loadOutline() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Page implements PdfPage {
  _Page(this.document, this.pageNumber);
  @override
  final PdfDocument document;
  @override
  final int pageNumber;
  @override
  bool get isLoaded => true;
  @override
  double get width => 600;
  @override
  double get height => 800;
  @override
  PdfPageRotation get rotation => PdfPageRotation.none;
  @override
  PdfPageRenderCancellationToken createCancellationToken() => _Token();
  @override
  Future<PdfPageRawText?> loadText() async =>
      PdfPageRawText('Selected passage', List.generate(16, (i) => PdfRect(30 + i * 10, 700, 40 + i * 10, 680)));
  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #render) return TestPdfRender._render(invocation.namedArguments);
    return super.noSuchMethod(invocation);
  }
}

/// Page rendering in the test backend: empty for the viewer's tiles, real
/// (blank) pixels for area captures when [produceImages] is set.
abstract final class TestPdfRender {
  static bool produceImages = false;

  /// Arguments of each produced render.
  static final renders = <Map<String, Object?>>[];

  static Future<PdfImage?> _render(Map<Symbol, dynamic> args) {
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
