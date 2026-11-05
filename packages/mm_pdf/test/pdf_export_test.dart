import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_dart;
import 'package:pdfrx/pdfrx.dart';

/// A three-page PDF with one text line, built by hand so tests need no fixture.
Uint8List samplePdf({int pages = 3}) {
  final out = BytesBuilder();
  final offsets = <int>[];
  void obj(String body) {
    offsets.add(out.length);
    out.add(latin1.encode('${offsets.length} 0 obj\n$body\nendobj\n'));
  }

  out.add(latin1.encode('%PDF-1.7\n'));
  obj('<< /Type /Catalog /Pages 2 0 R >>');
  final kids = [for (var i = 0; i < pages; i++) '${4 + i * 2} 0 R'].join(' ');
  obj('<< /Type /Pages /Kids [$kids] /Count $pages >>');
  obj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  for (var i = 0; i < pages; i++) {
    obj(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 600] /Contents ${5 + i * 2} 0 R '
      '/Resources << /Font << /F1 3 0 R >> >> >>',
    );
    final stream = 'BT /F1 14 Tf 40 500 Td (Page ${i + 1} of the sample document) Tj ET';
    obj('<< /Length ${stream.length} >>\nstream\n$stream\nendstream');
  }
  final xref = out.length;
  final table = StringBuffer('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    table.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  table.write('trailer << /Size ${offsets.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  out.add(latin1.encode(table.toString()));
  return out.toBytes();
}

const colors = MMPdfExportColors(mark: _rgb, note: _rgb, ink: _rgb);
int _rgb(int index) => index == 1 ? 0x34C759 : 0xFFCC00;

Document _doc() => Document(
  id: 'd',
  title: 'Sample',
  fileName: 'documents/a.pdf',
  sourceFileName: 'documents/a.pdf',
  pageCount: 3,
  importedAt: DateTime(2026),
);

Annotation _mark(
  String id,
  int page, {
  AnnotationKind kind = AnnotationKind.highlight,
  AnnotationLineStyle line = AnnotationLineStyle.solid,
  int color = 0,
  String quote = 'q',
  PageRect rect = const PageRect(40, 515, 200, 498),
}) => Annotation(
  id: id,
  documentId: 'd',
  pages: [
    AnnotationPage(page: page, rects: [rect]),
  ],
  quote: quote,
  colorIndex: color,
  createdAt: DateTime(2026),
  kind: kind,
  lineStyle: line,
);

StudySetContent _content() => StudySetContent(
  documents: [_doc()],
  annotations: [
    _mark('h', 1),
    _mark('h2', 2, color: 1),
    _mark(
      'u',
      2,
      kind: AnnotationKind.underline,
      line: AnnotationLineStyle.wavy,
      rect: const PageRect(40, 485, 200, 470),
    ),
    _mark('v', 2, kind: AnnotationKind.underline, rect: const PageRect(40, 465, 200, 450)),
    _mark('r', 3, quote: ''),
  ],
  marginNotes: [
    MarginNote(
      id: 'n',
      documentId: 'd',
      page: 1,
      lineY: 500,
      text: '批注 with 中文',
      colorIndex: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ],
  inkStrokes: [
    InkStroke(
      id: 'i',
      documentId: 'd',
      page: 1,
      tool: InkTool.pen,
      colorIndex: 1,
      width: 2,
      points: const [InkPoint(30, 100), InkPoint(90, 140), InkPoint(120, 90)],
    ),
    InkStroke(
      id: 'e',
      documentId: 'd',
      page: 2,
      tool: InkTool.ellipse,
      colorIndex: 1,
      width: 2,
      ellipse: const PageRect(30, 200, 120, 100),
    ),
    InkStroke(
      id: 'a',
      documentId: 'd',
      page: 2,
      tool: InkTool.arrow,
      colorIndex: 1,
      width: 2,
      points: const [InkPoint(30, 300), InkPoint(120, 340)],
    ),
  ],
);

/// Annotation subtypes per page of [bytes], read back through PDFium.
Future<Map<int, List<int>>> subtypes(Uint8List bytes) async {
  final document = await PdfDocument.openData(bytes);
  try {
    return await document.useNativeDocumentHandle((handle) {
      final api = pdfium_dart.getPdfium(modulePath: Pdfrx.pdfiumModulePath);
      final native = pdfium_dart.FPDF_DOCUMENT.fromAddress(handle);
      final result = <int, List<int>>{};
      for (var i = 0; i < api.FPDF_GetPageCount(native); i++) {
        final page = api.FPDF_LoadPage(native, i);
        result[i + 1] = [
          for (var a = 0; a < api.FPDFPage_GetAnnotCount(page); a++)
            () {
              final annot = api.FPDFPage_GetAnnot(page, a);
              final type = api.FPDFAnnot_GetSubtype(annot);
              api.FPDFPage_CloseAnnot(annot);
              return type;
            }(),
        ];
        api.FPDF_ClosePage(page);
      }
      return result;
    });
  } finally {
    await document.dispose();
  }
}

String noteText(pdfium_dart.PDFium api, pdfium_dart.FPDF_ANNOTATION annot) => using((arena) {
  final key = 'Contents'.toNativeUtf8(allocator: arena).cast<Char>();
  final size = api.FPDFAnnot_GetStringValue(annot, key, nullptr, 0);
  final buffer = arena<Uint16>(size ~/ 2);
  api.FPDFAnnot_GetStringValue(annot, key, buffer.cast(), size);
  return String.fromCharCodes(buffer.asTypedList(size ~/ 2 - 1));
});

/// `flutter test` does not bundle PDFium: use PDFIUM_PATH or the library the
/// workspace's native-asset build hook downloaded.
String? _pdfiumLibrary() {
  final configured = Platform.environment['PDFIUM_PATH'];
  if (configured != null) return configured;
  final hooks = Directory('../../.dart_tool/hooks_runner/shared/pdfium_dart/build');
  if (!hooks.existsSync()) return null;
  return hooks
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => RegExp(r'pdfium\.(so|dylib|dll)$').hasMatch(f.path))
      .firstOrNull
      ?.absolute
      .path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = _pdfiumLibrary();
  if (library == null) {
    test('PDF export needs PDFium', () {}, skip: 'Set PDFIUM_PATH to run the PDF export tests');
    return;
  }
  Pdfrx.pdfiumModulePath = library;
  final source = samplePdf();

  setUpAll(() async {
    final cache = await Directory.systemTemp.createTemp('pdf_export_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => cache.path,
    );
    await MMPdfEngine.initialize();
  });

  Future<Uint8List> export(DocumentExportOptions options, {bool Function()? cancelled}) =>
      MMPdfExport.write(source, DocumentExportPlan.build(_content(), _doc(), options), colors, cancelled: cancelled);

  test('writes every mark as a standard annotation another reader can list', () async {
    final out = await export(const DocumentExportOptions());
    final found = await subtypes(out);
    expect(
      found[1],
      unorderedEquals([pdfium_dart.FPDF_ANNOT_HIGHLIGHT, pdfium_dart.FPDF_ANNOT_TEXT, pdfium_dart.FPDF_ANNOT_INK]),
    );
    expect(
      found[2],
      unorderedEquals([
        pdfium_dart.FPDF_ANNOT_HIGHLIGHT,
        pdfium_dart.FPDF_ANNOT_UNDERLINE,
        pdfium_dart.FPDF_ANNOT_UNDERLINE,
        pdfium_dart.FPDF_ANNOT_INK,
        pdfium_dart.FPDF_ANNOT_INK,
      ]),
    );
    expect(found[3], [pdfium_dart.FPDF_ANNOT_SQUARE]);
    if (Platform.environment['PDF_EXPORT_SAMPLE'] case final path?) await File(path).writeAsBytes(out);
  });

  test('keeps note text, including non-Latin characters', () async {
    final out = await export(const DocumentExportOptions(highlights: false, underlines: false, ink: false));
    final document = await PdfDocument.openData(out);
    try {
      final text = await document.useNativeDocumentHandle((handle) {
        final api = pdfium_dart.getPdfium(modulePath: Pdfrx.pdfiumModulePath);
        final page = api.FPDF_LoadPage(pdfium_dart.FPDF_DOCUMENT.fromAddress(handle), 0);
        final annot = api.FPDFPage_GetAnnot(page, 0);
        final value = noteText(api, annot);
        api.FPDFPage_CloseAnnot(annot);
        api.FPDF_ClosePage(page);
        return value;
      });
      expect(text, '批注 with 中文');
    } finally {
      await document.dispose();
    }
  });

  test('places annotations relative to a page box that does not start at the origin', () async {
    final shifted = Uint8List.fromList(
      latin1.encode(latin1.decode(samplePdf()).replaceAll('/MediaBox [0 0 400 600]', '/MediaBox [10 20 410 620]')),
    );
    final out = await MMPdfExport.write(
      shifted,
      DocumentExportPlan.build(
        _content(),
        _doc(),
        const DocumentExportOptions(underlines: false, notes: false, ink: false),
      ),
      colors,
    );
    final document = await PdfDocument.openData(out);
    try {
      final rect = await document.useNativeDocumentHandle((handle) {
        final api = pdfium_dart.getPdfium(modulePath: Pdfrx.pdfiumModulePath);
        final page = api.FPDF_LoadPage(pdfium_dart.FPDF_DOCUMENT.fromAddress(handle), 0);
        final annot = api.FPDFPage_GetAnnot(page, 0);
        final value = using((arena) {
          final r = arena<pdfium_dart.FS_RECTF>();
          api.FPDFAnnot_GetRect(annot, r);
          return (r.ref.left, r.ref.bottom);
        });
        api.FPDFPage_CloseAnnot(annot);
        api.FPDF_ClosePage(page);
        return value;
      });
      expect(rect.$1, closeTo(50, .01));
      expect(rect.$2, closeTo(518, .01));
    } finally {
      await document.dispose();
    }
  });

  test('an untouched copy is the source itself', () async {
    final out = await export(DocumentExportOptions.preset(DocumentExportPreset.clean));
    expect(identical(out, source), isTrue);
  });

  test('a page range keeps only those pages, and only their marks', () async {
    final out = await export(const DocumentExportOptions(pages: {2}));
    final found = await subtypes(out);
    expect(found.keys, [1]);
    expect(found[1], hasLength(5));
  });

  test('a clean page range writes no annotations', () async {
    final out = await export(DocumentExportOptions.preset(DocumentExportPreset.clean).copyWith(pages: () => {1, 3}));
    final found = await subtypes(out);
    expect(found, {1: <int>[], 2: <int>[]});
  });

  test('never changes the source bytes', () async {
    final before = Uint8List.fromList(source);
    await export(const DocumentExportOptions());
    expect(source, before);
  });

  test('cancelling stops the write', () async {
    expect(() => export(const DocumentExportOptions(), cancelled: () => true), throwsA(isA<MMPdfExportCancelled>()));
  });

  test('reports the permissions of an open PDF', () async {
    expect(MMPdfExport.canWriteMarks, isTrue);
    expect(await MMPdfExport.allowsMarks(source), isTrue);
  });
}
