part of '../mm_book.dart';

/// A highlight or underline to write into an exported book.
class BookExportMark {
  const BookExportMark(this.anchor, {required this.rgb, this.underline = false});
  final TextAnchor anchor;
  final int rgb;
  final bool underline;
}

/// A note attached to the end of [anchor] in an exported book.
class BookExportNote {
  const BookExportNote(this.anchor, this.text);
  final TextAnchor anchor;
  final String text;
}

/// Builds an EPUB 3 from the stored book model, so every reflowable source
/// (EPUB, MOBI, AZW3, web capture) exports the same way and canonical offsets
/// place marks exactly. Marks are `mark` elements and underlined spans; notes
/// are EPUB 3 footnotes, which readers show as pop-ups.
class BookEpubWriter {
  BookEpubWriter({
    required this.title,
    required this.identifier,
    required this.chapters,
    required this.toc,
    required this.resources,
    this.language = 'und',
    this.marks = const [],
    this.notes = const [],
    DateTime? modified,
  }) : modified = modified ?? DateTime.now();

  final String title, identifier, language;
  final List<BookChapter> chapters;
  final List<BookTocEntry> toc;

  /// Bytes and media type of the images chapters reference, by source path.
  final Map<String, ({Uint8List bytes, String mime})> resources;
  final List<BookExportMark> marks;
  final List<BookExportNote> notes;
  final DateTime modified;

  late final Map<String, int> _chapterIndex = {for (var i = 0; i < chapters.length; i++) chapters[i].id: i};
  late final Map<String, String> _images = {};
  late final Map<String, String> _targets = () {
    final targets = <String, String>{};
    for (var i = 0; i < chapters.length; i++) {
      for (final entry in chapters[i].elementOffsets.entries) {
        final block = _blockAt(chapters[i], entry.value);
        if (block != null) targets.putIfAbsent(entry.key, () => '${_chapterFile(i)}#${_blockId(block)}');
      }
    }
    return targets;
  }();
  var _noteNumber = 0;

  Uint8List write() {
    final archive = Archive();
    void add(String name, List<int> bytes, {bool store = false}) {
      final file = ArchiveFile.bytes(name, bytes);
      if (store) file.compression = CompressionType.none;
      archive.addFile(file);
    }

    void text(String name, String body) => add(name, utf8.encode(body));
    // OCF requires an uncompressed `mimetype` as the first archive entry.
    add('mimetype', ascii.encode('application/epub+zip'), store: true);
    text(
      'META-INF/container.xml',
      '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
          '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>'
          '</container>',
    );
    for (var i = 0; i < chapters.length; i++) {
      text('OEBPS/${_chapterFile(i)}', _chapterXhtml(i));
    }
    text('OEBPS/style.css', _stylesheet);
    text('OEBPS/nav.xhtml', _nav());
    text('OEBPS/content.opf', _opf());
    for (final entry in _images.entries) {
      add('OEBPS/${entry.value}', resources[entry.key]!.bytes);
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String _chapterFile(int index) => 'chapter$index.xhtml';
  static String _blockId(BookBlock block) => 'b${block.start}';

  BookBlock? _blockAt(BookChapter chapter, int offset) {
    BookBlock? last;
    for (final block in chapter.blocks) {
      if (block.start > offset) break;
      last = block;
    }
    return last;
  }

  String _opf() {
    final items = [
      '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
      '<item id="css" href="style.css" media-type="text/css"/>',
      for (var i = 0; i < chapters.length; i++)
        '<item id="c$i" href="${_chapterFile(i)}" media-type="application/xhtml+xml"/>',
      for (final (i, entry) in _images.entries.indexed)
        '<item id="r$i" href="${_attr(entry.value)}" media-type="${_attr(resources[entry.key]!.mime)}"/>',
    ];
    final stamp = '${modified.toUtc().toIso8601String().split('.').first}Z';
    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="id">${_text(identifier)}</dc:identifier>'
        '<dc:title>${_text(title)}</dc:title>'
        '<dc:language>${_text(language)}</dc:language>'
        '<meta property="dcterms:modified">$stamp</meta>'
        '</metadata>'
        '<manifest>${items.join()}</manifest>'
        '<spine>${[for (var i = 0; i < chapters.length; i++) '<itemref idref="c$i"/>'].join()}</spine>'
        '</package>';
  }

  String _nav() {
    String link(BookTocEntry entry) {
      final index = _chapterIndex[entry.chapterId];
      if (index == null) return '<span>${_text(entry.title)}</span>';
      final block = _blockAt(chapters[index], entry.offset);
      final target = '${_chapterFile(index)}${block == null ? '' : '#${_blockId(block)}'}';
      return '<a href="${_attr(target)}">${_text(entry.title)}</a>';
    }

    String list(List<BookTocEntry> entries) =>
        '<ol>${[for (final entry in entries) '<li>${link(entry)}${entry.children.isEmpty ? '' : list(entry.children)}</li>'].join()}</ol>';

    // nav must hold at least one entry: fall back to one link per chapter.
    final body = toc.isNotEmpty
        ? list(toc)
        : '<ol>${[for (var i = 0; i < chapters.length; i++) '<li><a href="${_chapterFile(i)}">${_text(title)} ${i + 1}</a></li>'].join()}</ol>';
    return _page(title, '<nav epub:type="toc" id="toc"><h1>${_text(title)}</h1>$body</nav>');
  }

  String _page(String heading, String body) =>
      '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
      '<head><meta charset="utf-8"/><title>${_text(heading)}</title>'
      '<link rel="stylesheet" type="text/css" href="style.css"/></head><body>$body</body></html>';

  String _chapterXhtml(int index) {
    final chapter = chapters[index];
    final chapterMarks = marks.where((m) => m.anchor.chapterId == chapter.id).toList();
    final chapterNotes = <int, List<(int, String)>>{};
    for (final note in notes.where((n) => n.anchor.chapterId == chapter.id)) {
      (chapterNotes[note.anchor.end] ??= []).add((++_noteNumber, note.text));
    }
    final out = StringBuffer();
    String? openList;
    void closeList() {
      if (openList != null) out.write('</$openList>');
      openList = null;
    }

    final inline = _InlineWriter(this, chapterMarks, chapterNotes);
    for (final block in chapter.blocks) {
      final style = _styleAttr(block.style);
      final id = 'id="${_blockId(block)}"';
      if (block.kind == BlockKind.list) {
        final tag = block.ordered ? 'ol' : 'ul';
        if (openList != tag) {
          closeList();
          final start = block.ordered && block.listStart != 1 ? ' start="${block.listStart}"' : '';
          out.write('<$tag$start>');
          openList = tag;
        }
        out.write('<li $id$style>${inline.runs(block.runs, block.start)}</li>');
        continue;
      }
      closeList();
      switch (block.kind) {
        case BlockKind.heading:
          final level = block.level.clamp(1, 6);
          out.write('<h$level $id$style>${inline.runs(block.runs, block.start)}</h$level>');
        case BlockKind.quote:
          out.write('<blockquote $id$style><p>${inline.runs(block.runs, block.start)}</p></blockquote>');
        case BlockKind.code:
          out.write('<pre $id$style><code>${inline.runs(block.runs, block.start)}</code></pre>');
        case BlockKind.image:
          out.write('<figure $id$style>${inline.runs(block.runs, block.start)}</figure>');
        case BlockKind.rule:
          out.write('<hr $id/>');
        case BlockKind.table:
          out.write('<table $id$style>${inline.table(block)}</table>');
        case BlockKind.footnote:
          out.write('<p class="footnote" $id$style>${inline.runs(block.runs, block.start)}</p>');
        case BlockKind.paragraph:
        case BlockKind.list:
          out.write('<p $id$style>${inline.runs(block.runs, block.start)}</p>');
      }
    }
    closeList();
    for (final entry in chapterNotes.values.expand((v) => v).toList()..sort((a, b) => a.$1.compareTo(b.$1))) {
      out.write('<aside epub:type="footnote" id="mm-note-${entry.$1}"><p>${_multiline(entry.$2)}</p></aside>');
    }
    return _page(title, out.toString());
  }

  /// The package file of a chapter image; missing resources stay out of the book.
  String? imageFile(String? source) {
    if (source == null) return null;
    final resource = resources[source];
    if (resource == null) return null;
    return _images.putIfAbsent(source, () {
      final extension = switch (resource.mime) {
        'image/png' => 'png',
        'image/jpeg' => 'jpg',
        'image/gif' => 'gif',
        'image/webp' => 'webp',
        'image/svg+xml' => 'svg',
        _ => 'bin',
      };
      return 'images/${_images.length}.$extension';
    });
  }

  /// An http(s)/mailto link, or the chapter holding an internal fragment.
  String? linkTarget(String? link) {
    if (link == null) return null;
    final uri = Uri.tryParse(link);
    if (uri == null) return null;
    if (uri.hasScheme) return const {'http', 'https', 'mailto'}.contains(uri.scheme) ? link : null;
    return uri.fragment.isEmpty ? null : _targets[uri.fragment];
  }

  static const _stylesheet = '''
@namespace epub "http://www.idpf.org/2007/ops";
body { line-height: 1.6; }
img { max-width: 100%; height: auto; }
figure { margin: 1em 0; text-align: center; }
table { border-collapse: collapse; }
td, th { border: 1px solid #999; padding: .25em .5em; }
blockquote { margin-left: 1em; padding-left: 1em; border-left: 3px solid #ccc; }
pre { white-space: pre-wrap; }
.footnote { font-size: .9em; }
a.mm-noteref { font-size: .75em; vertical-align: super; line-height: 0; text-decoration: none; }
aside[epub|type~="footnote"] { display: none; }
''';
}

/// Writes runs in canonical-offset order, splitting them at mark boundaries.
class _InlineWriter {
  _InlineWriter(this.book, this.marks, this.notes);
  final BookEpubWriter book;
  final List<BookExportMark> marks;
  final Map<int, List<(int, String)>> notes;

  String runs(List<InlineRun> runs, int base) {
    final out = StringBuffer();
    var offset = base;
    for (final run in runs) {
      out.write(_run(run, offset));
      offset += run.text.length;
    }
    return out.toString();
  }

  /// Cell text repeats inside the table block's runs, so cells locate themselves there.
  String table(BookBlock block) {
    final out = StringBuffer();
    var cursor = 0;
    for (final row in block.rows) {
      out.write('<tr>');
      for (final cell in row) {
        final found = cell.text.isEmpty ? -1 : block.text.indexOf(cell.text, cursor);
        final start = found < 0 ? -1 : block.start + found;
        if (found >= 0) cursor = found + cell.text.length;
        final tag = cell.header ? 'th' : 'td';
        final span =
            '${cell.rowSpan > 1 ? ' rowspan="${cell.rowSpan}"' : ''}${cell.colSpan > 1 ? ' colspan="${cell.colSpan}"' : ''}';
        out.write('<$tag$span>${start < 0 ? _plain(cell.runs) : runs(cell.runs, start)}</$tag>');
      }
      out.write('</tr>');
    }
    return out.toString();
  }

  String _plain(List<InlineRun> runs) => runs.map((r) => _text(r.text)).join();

  String _run(InlineRun run, int start) {
    final image = book.imageFile(run.resource);
    if (run.resource != null || run.text == '￼') {
      if (image == null) return '';
      final size = _styleAttr({'width': ?run.width, 'height': ?run.height});
      return '<img src="${_attr(image)}" alt=""$size/>';
    }
    final end = start + run.text.length;
    // Split at every mark edge and note position inside this run.
    final cuts = <int>{start, end};
    for (final mark in marks) {
      if (mark.anchor.start > start && mark.anchor.start < end) cuts.add(mark.anchor.start);
      if (mark.anchor.end > start && mark.anchor.end < end) cuts.add(mark.anchor.end);
    }
    for (final position in notes.keys) {
      if (position > start && position < end) cuts.add(position);
    }
    final points = cuts.toList()..sort();
    final body = StringBuffer();
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i], b = points[i + 1];
      var part = _multiline(run.text.substring(a - start, b - start));
      for (final mark in marks.where((m) => m.anchor.start <= a && m.anchor.end >= b)) {
        final color = '#${mark.rgb.toRadixString(16).padLeft(6, '0')}';
        part = mark.underline
            ? '<span style="text-decoration: underline; text-decoration-color: $color">$part</span>'
            : '<mark style="background-color: ${color}66; color: inherit">$part</mark>';
      }
      body.write(part);
      body.write(_noteRefs(b));
    }
    if (run.text.isEmpty) body.write(_noteRefs(start));
    var html = body.toString();
    if (run.code) html = '<code>$html</code>';
    if (run.emphasis) html = '<em>$html</em>';
    if (run.strong) html = '<strong>$html</strong>';
    final style = _styleAttr(run.style);
    if (style.isNotEmpty) html = '<span$style>$html</span>';
    if (run.ruby != null) html = '<ruby>$html<rt>${_text(run.ruby!)}</rt></ruby>';
    final target = book.linkTarget(run.link ?? run.footnoteRef);
    if (target != null) html = '<a href="${_attr(target)}">$html</a>';
    return html;
  }

  /// Each note's reference is written once, after the text it annotates.
  String _noteRefs(int position) {
    final pending = notes[position];
    if (pending == null || !_written.add(position)) return '';
    return pending.map((n) => '<a class="mm-noteref" epub:type="noteref" href="#mm-note-${n.$1}">${n.$1}</a>').join();
  }

  final _written = <int>{};
}

String _multiline(String text) => _text(text).replaceAll('\n', '<br/>');

/// XML 1.0 forbids most control characters, which source books can contain.
String _text(String text) => text
    .replaceAll(RegExp('[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F￾￿￼]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _attr(String text) => _text(text).replaceAll('"', '&quot;');

/// Source CSS survives as inline style, minus anything that could load a resource.
String _styleAttr(Map<String, String> style) {
  final safe = [
    for (final e in style.entries)
      if (RegExp(r'^[a-z-]+$').hasMatch(e.key) &&
          !RegExp(r'url\(|expression|javascript:|@', caseSensitive: false).hasMatch(e.value))
        '${e.key}: ${e.value}',
  ];
  return safe.isEmpty ? '' : ' style="${_attr(safe.join('; '))}"';
}

/// Writes marks back into Markdown source, keeping the author's formatting.
/// Stored offsets address rendered text, so each quote is located in the source
/// by tolerating inline syntax, preferring the match nearest its stored place.
class BookMarkdownAnnotator {
  BookMarkdownAnnotator(this.source, {required this.canonicalLength});
  final String source;
  final int canonicalLength;

  String write({
    List<BookExportMark> marks = const [],
    List<BookExportNote> notes = const [],
    String? unplacedHeading,
  }) {
    final insertions = <int, List<_Insertion>>{};
    final taken = <(int, int)>[];
    void insert(int at, String text, {required int order}) => (insertions[at] ??= []).add(_Insertion(text, order));

    bool free(int a, int b) => taken.every((t) => b <= t.$1 || a >= t.$2);
    for (final mark in marks) {
      for (final (a, b) in _locate(mark.anchor)) {
        if (!free(a, b)) continue;
        taken.add((a, b));
        insert(a, mark.underline ? '<u>' : '<mark>', order: 1);
        insert(b, mark.underline ? '</u>' : '</mark>', order: 0);
      }
    }
    final definitions = StringBuffer();
    final sorted = [...notes]..sort((x, y) => x.anchor.end.compareTo(y.anchor.end));
    var number = 0;
    final unplaced = <String>[];
    for (final note in sorted) {
      number++;
      final found = _locate(note.anchor);
      if (found.isEmpty) {
        unplaced.add('> ${note.anchor.quote.replaceAll('\n', ' ')}[^$number]');
      } else {
        // After a closing tag at the same position, so the reference stays outside the mark.
        insert(found.last.$2, '[^$number]', order: 2);
      }
      definitions.write('\n[^$number]: ${note.text.replaceAll('\n', '\n    ')}\n');
    }
    final out = StringBuffer();
    final points = insertions.keys.toList()..sort();
    var cursor = 0;
    for (final point in points) {
      out.write(source.substring(cursor, point));
      for (final item in insertions[point]!..sort((a, b) => a.order.compareTo(b.order))) {
        out.write(item.text);
      }
      cursor = point;
    }
    out.write(source.substring(cursor));
    if (unplaced.isNotEmpty) {
      out.write('\n\n');
      if (unplacedHeading != null) out.write('## $unplacedHeading\n\n');
      out.write(unplaced.join('\n\n'));
      out.write('\n');
    }
    if (definitions.isNotEmpty) {
      out.write('\n');
      out.write(definitions);
    }
    return out.toString();
  }

  /// Source ranges of a quote, one per rendered line it spans; empty when any
  /// line cannot be found, so a mark is never written partly in the wrong place.
  List<(int, int)> _locate(TextAnchor anchor) {
    final ranges = <(int, int)>[];
    var from = 0;
    final position = canonicalLength == 0 ? 0.0 : anchor.start / canonicalLength;
    for (final line in anchor.quote.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty)) {
      final pattern = RegExp(
        line
            .split(RegExp(r'\s+'))
            .map((word) => word.split('').map(RegExp.escape).join(r'[*_`~\\]*'))
            .join(r'[*_`~\\]*\s+[*_`~\\]*'),
      );
      final matches = pattern.allMatches(source, from).toList();
      if (matches.isEmpty) return const [];
      final best = matches.reduce((a, b) {
        double distance(Match m) => (m.start / math.max(1, source.length) - position).abs();
        return distance(b) < distance(a) ? b : a;
      });
      ranges.add((best.start, best.end));
      from = best.end;
    }
    return ranges;
  }
}

class _Insertion {
  const _Insertion(this.text, this.order);
  final String text;
  final int order;
}
