import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'package:pdfrx/pdfrx.dart';

Future<PdfDocument> openDocument(String path) async {
  final response = await web.window.fetch(path.toJS).toDart;
  if (!response.ok) throw StateError('Cannot open PDF');
  final data = (await response.arrayBuffer().toDart).toDart.asUint8List();
  return PdfDocument.openData(data, sourceName: path);
}
