import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Results are file metadata only; PDF text and pixels never cross the channel.
class PdfOcrDocument {
  const PdfOcrDocument({required this.path, required this.pageCount, required this.textPages, this.hasCopy = false});
  factory PdfOcrDocument.fromMap(Map<Object?, Object?> value) => PdfOcrDocument(
    path: value['path'] as String,
    pageCount: value['pageCount'] as int,
    textPages: Set.unmodifiable((value['textPages'] as List).cast<int>()),
    hasCopy: value['hasCopy'] as bool,
  );
  final String path;
  final int pageCount;
  final Set<int> textPages;
  final bool hasCopy;
}

enum PdfOcrLanguage {
  chineseEnglish(['zh-Hans', 'en-US']),
  chinese(['zh-Hans']),
  english(['en-US']);

  const PdfOcrLanguage(this.codes);
  final List<String> codes;
}

abstract class PdfOcrService {
  bool get supported;
  Future<PdfOcrDocument> inspect(String source);
  Future<({PdfOcrDocument document, bool cancelled})> recognize(
    String source, {
    required String id,
    required int first,
    required int last,
    required PdfOcrLanguage language,
    required void Function(int done, int total) onProgress,
  });
  Future<void> cancel(String id);
}

class VisionPdfOcr implements PdfOcrService {
  VisionPdfOcr({this.channel = const MethodChannel('marginmind/pdf_ocr')}) {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'progress') return;
      final args = (call.arguments as Map).cast<String, Object?>();
      _progress[args['id']]?.call(args['done'] as int, args['total'] as int);
    });
  }
  final MethodChannel channel;
  final _progress = <String, void Function(int, int)>{};

  @override
  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  @override
  Future<PdfOcrDocument> inspect(String source) async =>
      PdfOcrDocument.fromMap((await channel.invokeMapMethod('inspect', {'source': source}))!);

  @override
  Future<({PdfOcrDocument document, bool cancelled})> recognize(
    String source, {
    required String id,
    required int first,
    required int last,
    required PdfOcrLanguage language,
    required void Function(int done, int total) onProgress,
  }) async {
    if (first < 1 || last < first || id.isEmpty || _progress.containsKey(id)) {
      throw ArgumentError('Invalid OCR request');
    }
    _progress[id] = onProgress;
    try {
      final value = (await channel.invokeMapMethod('recognize', {
        'source': source,
        'id': id,
        'first': first,
        'last': last,
        'languages': language.codes,
      }))!;
      return (document: PdfOcrDocument.fromMap(value), cancelled: value['cancelled'] as bool);
    } finally {
      _progress.remove(id);
    }
  }

  @override
  Future<void> cancel(String id) => channel.invokeMethod('cancel', {'id': id});
}
