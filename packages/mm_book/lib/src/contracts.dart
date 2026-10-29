part of '../mm_book.dart';

enum BookErrorKind { drm, damaged, unsupported, cancelled, limitExceeded }

/// Typed failures remain FormatExceptions for existing import callers.
class BookParseException extends FormatException {
  const BookParseException(this.kind, String message) : super(message);
  final BookErrorKind kind;
}

class BookCancellationToken {
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  void check() {
    if (_cancelled) throw const BookParseException(BookErrorKind.cancelled, 'Import cancelled');
  }
}

/// Markdown paths are relative to the source file directory and may contain `../`.
/// Callers bind resolution to that directory and enforce their import sandbox.
/// Stored resource keys are independent safe package paths, never filesystem URLs.
/// No parser performs network access or writes files; persistence is mm_data's transaction.
typedef ResourceResolver = Future<Uint8List?> Function(String path);

/// Source container tree; leaves reference the flat block list used by layout.
class BookFontFace {
  const BookFontFace(this.family, this.resource, this.weight, this.style);
  final String family, resource, weight, style;
  Map<String, String> toJson() => {'family': family, 'resource': resource, 'weight': weight, 'style': style};
}

class BookNode {
  BookNode(this.path, this.tag, this.blockId, List<BookNode> children, {Map<String, String> style = const {}})
    : children = List.unmodifiable(children),
      style = Map.unmodifiable(style);
  final String path, tag;
  final String? blockId;
  final List<BookNode> children;

  /// Cascaded properties, with lengths retained in CSS units for layout.
  final Map<String, String> style;
  Map<String, Object?> toJson() => {
    'path': path,
    'tag': tag,
    if (blockId != null) 'blockId': blockId,
    'style': style,
    'children': children.map((c) => c.toJson()).toList(),
  };
}

class BookTocEntry {
  BookTocEntry(this.id, this.title, this.chapterId, this.offset, [List<BookTocEntry> children = const []])
    : children = List.unmodifiable(children);
  final String id, title, chapterId;
  final int offset;
  final List<BookTocEntry> children;
  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'chapterId': chapterId,
    'offset': offset,
    'children': children.map((e) => e.toJson()).toList(),
  };
}

T _guard<T>(T Function() action) {
  try {
    return action();
  } on BookParseException {
    rethrow;
  } on FormatException catch (e) {
    throw BookParseException(BookErrorKind.damaged, e.message);
  } on RangeError {
    throw const BookParseException(BookErrorKind.damaged, 'Truncated book data');
  } on XmlException {
    throw const BookParseException(BookErrorKind.damaged, 'Invalid XML');
  }
}

Never _damaged(String message) => throw BookParseException(BookErrorKind.damaged, message);
Never _unsupported(String message) => throw BookParseException(BookErrorKind.unsupported, message);
Never _limit() => throw const BookParseException(BookErrorKind.limitExceeded, 'Book exceeds parsing limits');

Map<String, Object?> _chapterJson(BookChapter c) => {
  'id': c.id,
  'sourceHref': c.id,
  'canonicalText': c.canonicalText,
  'sourceMap': c.sourceMap,
  'elementOffsets': c.elementOffsets,
  'structure': c.structure.map((n) => n.toJson()).toList(),
  'fonts': c.fonts.map((f) => f.toJson()).toList(),
  if (c.viewportWidth != null) 'viewportWidth': c.viewportWidth,
  if (c.viewportHeight != null) 'viewportHeight': c.viewportHeight,
  'blocks': [
    for (final b in c.blocks)
      {
        'id': b.id,
        'kind': b.kind.name,
        'start': b.start,
        'end': b.end,
        'level': b.level,
        'style': b.style,
        'sourcePath': b.sourcePath,
        'ordered': b.ordered,
        'listStart': b.listStart,
        if (b.resource != null) 'resource': b.resource,
        'runs': b.runs.map(_runJson).toList(),
        'rows': b.rows
            .map(
              (r) => r
                  .map(
                    (c) => {
                      'rowSpan': c.rowSpan,
                      'colSpan': c.colSpan,
                      'header': c.header,
                      'runs': c.runs.map(_runJson).toList(),
                    },
                  )
                  .toList(),
            )
            .toList(),
      },
  ],
};
Map<String, Object?> _runJson(InlineRun r) => {
  'text': r.text,
  'strong': r.strong,
  'emphasis': r.emphasis,
  'code': r.code,
  'style': r.style,
  if (r.ruby != null) 'ruby': r.ruby,
  if (r.footnoteRef != null) 'footnoteRef': r.footnoteRef,
  if (r.remoteUrl != null) 'remoteUrl': r.remoteUrl,
  if (r.link != null) 'link': r.link,
  if (r.resource != null) 'resource': r.resource,
  if (r.width != null) 'width': r.width,
  if (r.height != null) 'height': r.height,
};

String _mime(Uint8List b, String path) {
  bool starts(List<int> v) => b.length >= v.length && List.generate(v.length, (i) => b[i] == v[i]).every((v) => v);
  if (starts([0x89, 0x50, 0x4e, 0x47])) return 'image/png';
  if (starts([0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (starts(ascii.encode('GIF8'))) return 'image/gif';
  if (b.length >= 12 && starts(ascii.encode('RIFF')) && latin1.decode(b.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  if (path.toLowerCase().endsWith('.svg') || latin1.decode(b.take(512).toList()).contains('<svg')) {
    try {
      if (XmlDocument.parse(utf8.decode(b)).rootElement.name.local == 'svg') return 'image/svg+xml';
    } on FormatException {
      /* invalid XML is not an SVG resource */
    } on XmlException {
      /* invalid XML is not an SVG resource */
    }
  }
  if (starts(ascii.encode('wOFF'))) return 'font/woff';
  if (starts(ascii.encode('wOF2'))) return 'font/woff2';
  if (starts([0, 1, 0, 0]) || starts(ascii.encode('OTTO'))) return 'font/otf';
  final ext = path.split('.').last.toLowerCase();
  return switch (ext) {
    'svg' => 'application/octet-stream',
    'css' => 'text/css',
    'html' || 'xhtml' => 'application/xhtml+xml',
    'xml' || 'opf' || 'ncx' => 'application/xml',
    _ => 'application/octet-stream',
  };
}
