import 'package:meta/meta.dart';

enum DocumentFormat {
  pdf,
  epub,
  mobi,
  azw3,
  markdown,
  web,
  unknown;

  static DocumentFormat fromFileName(String name) => switch (name.split('.').last.toLowerCase()) {
    'pdf' => pdf,
    'epub' => epub,
    'mobi' || 'azw' => mobi,
    'azw3' => azw3,
    'md' || 'markdown' => markdown,
    _ => unknown,
  };
  static const extensions = ['pdf', 'epub', 'mobi', 'azw3', 'azw', 'md', 'markdown'];
}

enum DocumentLayout { fixed, reflow }

@immutable
class DocumentOrigin {
  DocumentOrigin({required this.url, required this.capturedAt, this.snapshotFile}) {
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw ArgumentError('Invalid document origin');
    }
  }
  final String url;
  final DateTime capturedAt;
  final String? snapshotFile;
  Map<String, Object?> toJson() => {
    'url': url,
    'capturedAt': capturedAt.toIso8601String(),
    if (snapshotFile != null) 'snapshotFile': snapshotFile,
  };
  factory DocumentOrigin.fromJson(Map<String, Object?> j) => DocumentOrigin(
    url: j['url'] as String,
    capturedAt: DateTime.parse(j['capturedAt'] as String),
    snapshotFile: j['snapshotFile'] as String?,
  );
}

@immutable
class DocumentContentFeatures {
  const DocumentContentFeatures({this.text = true, this.outline = true});
  final bool text, outline;
  Map<String, Object?> toJson() => {'text': text, 'outline': outline};
  factory DocumentContentFeatures.fromJson(Map<String, Object?> j) =>
      DocumentContentFeatures(text: j['text'] as bool? ?? true, outline: j['outline'] as bool? ?? true);
}

@immutable
class DocumentRuntime {
  const DocumentRuntime({this.ocr = false, this.browser = false});
  final bool ocr, browser;
}

/// UI and commands consume these flags; format decisions belong here.
@immutable
class DocumentCapabilities {
  const DocumentCapabilities._({
    required this.selectText,
    required this.annotate,
    required this.excerpt,
    required this.marginNotes,
    required this.parallel,
    required this.translate,
    required this.ink,
    required this.capture,
    required this.search,
    required this.outline,
    required this.bookmarks,
    required this.readingSettings,
    required this.crop,
    required this.ocr,
    required this.thumbnails,
    required this.recapture,
    required this.zoom,
  });
  final bool selectText,
      annotate,
      excerpt,
      marginNotes,
      parallel,
      translate,
      ink,
      capture,
      search,
      outline,
      bookmarks,
      readingSettings,
      crop,
      ocr,
      thumbnails,
      recapture,
      zoom;
  factory DocumentCapabilities.resolve({
    required DocumentFormat format,
    required DocumentLayout layout,
    DocumentContentFeatures contentFeatures = const DocumentContentFeatures(),
    DocumentRuntime runtime = const DocumentRuntime(),
  }) {
    final known = format != DocumentFormat.unknown;
    final pdf =
        known && layout == DocumentLayout.fixed && (format == DocumentFormat.pdf || format == DocumentFormat.web);
    final text = known && contentFeatures.text;
    return DocumentCapabilities._(
      selectText: text,
      annotate: text,
      excerpt: text,
      marginNotes: known,
      parallel: known,
      translate: text,
      ink: known,
      capture: known,
      search: text,
      outline: known && contentFeatures.outline,
      bookmarks: known,
      readingSettings: known && layout == DocumentLayout.reflow,
      crop: pdf,
      ocr: pdf && runtime.ocr,
      thumbnails: known && layout == DocumentLayout.fixed,
      recapture: format == DocumentFormat.web && runtime.browser,
      zoom: known && layout == DocumentLayout.fixed,
    );
  }
}
