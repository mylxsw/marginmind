import 'package:pdfrx/pdfrx.dart';

Future<PdfDocument> openDocument(String path) => PdfDocument.openFile(path);
