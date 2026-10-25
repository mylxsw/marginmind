import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
    PdfrxEntryFunctions.instance = _Engine();
  });

  testWidgets('commits viewport bounds, cancels stale selection and reports scrolling', (tester) async {
    final controller = MMPdfViewController();
    MMPdfSelection? committed;
    var viewportChanges = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(
          filePath: 'selection-test.pdf',
          controller: controller,
          onSelectionCommitted: (s) => committed = s,
          onViewportChanged: () => viewportChanges++,
        ),
      ),
    );
    for (var i = 0; i < 100 && !controller.isReady; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(controller.isReady, isTrue);
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    final pdf = viewer.controller!;
    final page = pdf.document.pages.first;
    final text = (await tester.runAsync(page.loadStructuredText))!;
    await tester.runAsync(
      () => pdf.textSelectionDelegate.setTextSelectionPointRange(
        PdfTextSelectionRange.fromPoints(PdfTextSelectionPoint(text, 0), PdfTextSelectionPoint(text, 8)),
      ),
    );
    final listener = tester
        .widgetList<Listener>(find.descendant(of: find.byType(MMPdfView), matching: find.byType(Listener)))
        .firstWhere((w) => w.onPointerUp != null);
    listener.onPointerUp!(const PointerUpEvent());
    await tester.pump(const Duration(milliseconds: 130));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(committed, isNotNull);
    expect(committed!.viewportRect!.width, greaterThan(0));
    final firstRect = pdf.calcRectForRectInsidePage(pageNumber: 1, rect: text.charRects.first);
    expect(committed!.viewportRect!.contains(pdf.documentToLocal(firstRect.center)), isTrue);
    committed = null;
    listener.onPointerUp!(const PointerUpEvent());
    pdf.value = pdf.value.clone()..translateByDouble(0, -20, 0, 1);
    await tester.pump(const Duration(milliseconds: 130));
    expect(committed, isNull);
    listener.onPointerUp!(const PointerUpEvent());
    await controller.clearSelection();
    await tester.pump(const Duration(milliseconds: 130));
    expect(committed, isNull);
    final before = viewportChanges;
    final navigation = controller.goToPage(2);
    await tester.pumpAndSettle();
    await navigation;
    expect(viewportChanges, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.isReady, isFalse);
  });
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
  late List<PdfPage> pages = [_Page(this, 1), _Page(this, 2)];
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
    if (invocation.memberName == #render) return Future<PdfImage?>.value(null);
    return super.noSuchMethod(invocation);
  }
}

class _Token implements PdfPageRenderCancellationToken {
  @override
  bool isCanceled = false;
  @override
  void cancel() => isCanceled = true;
}
