import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'research.dart';

/// Basic note formatting (P2-C07): a Markdown subset of `**bold**`,
/// `*italic*`, `- ` bullets and `1. ` numbered items, one block per line.
///
/// One parser serves every place a note is shown — the map, review and
/// export — so they always agree. A [TextFormat.plain] note is never parsed:
/// its stars and dashes stay literal text. A plain note turns into Markdown
/// only when the user first formats it, and [escapeNoteMarkdown] keeps its
/// existing text literal then.

enum NoteBlockKind { paragraph, bullet, ordered }

/// A run of text with one style.
@immutable
class NoteSpan {
  const NoteSpan(this.text, {this.bold = false, this.italic = false});

  final String text;
  final bool bold;
  final bool italic;

  @override
  bool operator ==(Object other) =>
      other is NoteSpan && other.text == text && other.bold == bold && other.italic == italic;

  @override
  int get hashCode => Object.hash(text, bold, italic);

  @override
  String toString() => 'NoteSpan(${bold ? 'b ' : ''}${italic ? 'i ' : ''}"$text")';
}

/// One line of a note.
@immutable
class NoteBlock {
  const NoteBlock(this.kind, this.spans, {this.number = 0});

  final NoteBlockKind kind;

  /// The number written before an ordered item.
  final int number;
  final List<NoteSpan> spans;

  /// The line's text without markup.
  String get text => spans.map((s) => s.text).join();

  /// What is shown before the text: `• ` or `1. `.
  String get prefix => switch (kind) {
    NoteBlockKind.paragraph => '',
    NoteBlockKind.bullet => '• ',
    NoteBlockKind.ordered => '$number. ',
  };
}

/// A note as shown: its lines, each a paragraph or list item.
@immutable
class NoteDocument {
  const NoteDocument(this.blocks);

  /// Reads [text] stored as [format]. Plain text keeps every character.
  factory NoteDocument.parse(String text, TextFormat format) => NoteDocument([
    for (final line in text.split('\n'))
      if (format == TextFormat.plain)
        NoteBlock(NoteBlockKind.paragraph, [if (line.isNotEmpty) NoteSpan(line)])
      else
        _parseLine(line, 0).block,
  ]);

  final List<NoteBlock> blocks;

  /// The note as plain text: markup removed, list items with `•` / `1.`.
  /// Used where formatting cannot be shown (OPML, search, labels).
  String toPlainText() => blocks.map((b) => '${b.prefix}${b.text}').join('\n');

  /// Whether any line is a list item or any text is bold or italic.
  bool get hasFormatting =>
      blocks.any((b) => b.kind != NoteBlockKind.paragraph || b.spans.any((s) => s.bold || s.italic));
}

/// [text] as shown, without markup: what search, labels and OPML use.
String notePlainText(String text, TextFormat format) =>
    format == TextFormat.plain ? text : NoteDocument.parse(text, format).toPlainText();

/// A range of Markdown source with how the editor shows it: [marker] for
/// the markup itself (stars, list prefixes, escapes), else the text's style.
@immutable
class NoteSourceRun {
  const NoteSourceRun(this.start, this.end, {this.marker = false, this.bold = false, this.italic = false});

  final int start;
  final int end;
  final bool marker;
  final bool bold;
  final bool italic;

  @override
  bool operator ==(Object other) =>
      other is NoteSourceRun &&
      other.start == start &&
      other.end == end &&
      other.marker == marker &&
      other.bold == bold &&
      other.italic == italic;

  @override
  int get hashCode => Object.hash(start, end, marker, bold, italic);

  @override
  String toString() =>
      'NoteSourceRun($start, $end${marker ? ', marker' : ''}${bold ? ', b' : ''}${italic ? ', i' : ''})';
}

/// How the editor styles Markdown [source]: consecutive runs covering every
/// character except the line breaks.
List<NoteSourceRun> noteSourceRuns(String source) {
  final runs = <NoteSourceRun>[];
  var offset = 0;
  for (final line in source.split('\n')) {
    runs.addAll(_parseLine(line, offset).runs);
    offset += line.length + 1;
  }
  return runs;
}

final _bullet = RegExp(r'^- ');
final _ordered = RegExp(r'^(\d{1,9})\. ');

/// Characters a backslash makes literal.
const _escapable = {r'\', '*', '-', '.'};

({NoteBlock block, List<NoteSourceRun> runs}) _parseLine(String line, int offset) {
  var kind = NoteBlockKind.paragraph;
  var number = 0;
  var start = 0;
  if (_bullet.hasMatch(line)) {
    kind = NoteBlockKind.bullet;
    start = 2;
  } else if (_ordered.firstMatch(line) case final m?) {
    kind = NoteBlockKind.ordered;
    number = int.parse(m.group(1)!);
    start = m.end;
  }
  final runs = <NoteSourceRun>[if (start > 0) NoteSourceRun(offset, offset + start, marker: true)];
  final spans = _parseInline(line, start, offset, runs);
  return (block: NoteBlock(kind, spans, number: number), runs: runs);
}

/// A star run (1–3 stars) that may open or close bold and / or italic.
class _Delimiter {
  _Delimiter(this.index, this.length);
  final int index;
  final int length;
  bool boldMatched = false;
  bool italicMatched = false;
  bool get hasBold => length >= 2;
  bool get hasItalic => length.isOdd;
}

List<NoteSpan> _parseInline(String line, int from, int offset, List<NoteSourceRun> runs) {
  // First pass: find star runs and escapes.
  final delimiters = <int, _Delimiter>{};
  final escapes = <int>{};
  for (var i = from; i < line.length; i++) {
    final ch = line[i];
    if (ch == r'\' && i + 1 < line.length && _escapable.contains(line[i + 1])) {
      escapes.add(i);
      i++;
    } else if (ch == '*') {
      var j = i;
      while (j < line.length && line[j] == '*') {
        j++;
      }
      if (j - i <= 3) delimiters[i] = _Delimiter(i, j - i);
      i = j - 1;
    }
  }
  // Pair them per style: an opener is followed by text, a closer follows it.
  bool spaceAt(int i) => i < from || i >= line.length || line[i].trim().isEmpty;
  void pair(bool Function(_Delimiter) has, void Function(_Delimiter) mark) {
    _Delimiter? open;
    for (final d in delimiters.values) {
      if (!has(d)) continue;
      final canClose = !spaceAt(d.index - 1);
      final canOpen = !spaceAt(d.index + d.length);
      if (open != null && canClose) {
        mark(open);
        mark(d);
        open = null;
      } else if (canOpen) {
        open = d;
      }
    }
  }

  pair((d) => d.hasBold, (d) => d.boldMatched = true);
  pair((d) => d.hasItalic, (d) => d.italicMatched = true);

  // Second pass: emit spans and source runs.
  final spans = <NoteSpan>[];
  final text = StringBuffer();
  var bold = false, italic = false;
  var runStart = from;
  void flushSpan() {
    if (text.isEmpty) return;
    final s = text.toString();
    if (spans.isNotEmpty && spans.last.bold == bold && spans.last.italic == italic) {
      spans[spans.length - 1] = NoteSpan(spans.last.text + s, bold: bold, italic: italic);
    } else {
      spans.add(NoteSpan(s, bold: bold, italic: italic));
    }
    text.clear();
  }

  void textRun(int end) {
    if (end > runStart) runs.add(NoteSourceRun(offset + runStart, offset + end, bold: bold, italic: italic));
    runStart = end;
  }

  void markerRun(int end) {
    runs.add(NoteSourceRun(offset + runStart, offset + end, marker: true));
    runStart = end;
  }

  var i = from;
  while (i < line.length) {
    if (escapes.contains(i)) {
      textRun(i);
      markerRun(i + 1);
      text.write(line[i + 1]);
      i += 2;
      continue;
    }
    final d = delimiters[i];
    if (d == null) {
      text.write(line[i]);
      i++;
      continue;
    }
    final markers = (d.boldMatched ? 2 : 0) + (d.italicMatched ? 1 : 0);
    final literal = d.length - markers;
    // Unmatched stars stay text, in the style around them.
    if (literal > 0) text.write('*' * literal);
    i += literal;
    textRun(i);
    if (markers == 0) continue;
    flushSpan();
    i += markers;
    markerRun(i);
    if (d.boldMatched) bold = !bold;
    if (d.italicMatched) italic = !italic;
  }
  textRun(line.length);
  flushSpan();
  return spans;
}

/// [plain] as Markdown that reads back as the same text: stars and
/// backslashes before them are escaped, as are lines that would start a
/// list. [offsets] maps a position in [plain] to the same place in [text].
({String text, int Function(int) offsets}) escapeNoteMarkdown(String plain) {
  final out = StringBuffer();
  final inserted = <int>[];
  var lineStart = true;
  for (var i = 0; i < plain.length; i++) {
    final ch = plain[i];
    if (lineStart) {
      lineStart = false;
      if (_bullet.hasMatch(plain.substring(i, i + 2 > plain.length ? plain.length : i + 2))) {
        inserted.add(i);
        out.write(r'\');
      } else if (_ordered.matchAsPrefix(plain, i) case final m?) {
        final dot = i + m.group(1)!.length;
        out.write(plain.substring(i, dot));
        inserted.add(dot);
        out.write(r'\.');
        i = dot;
        continue;
      }
    }
    if (ch == '*' || (ch == r'\' && i + 1 < plain.length && _escapable.contains(plain[i + 1]))) {
      inserted.add(i);
      out.write(r'\');
    }
    out.write(ch);
    if (ch == '\n') lineStart = true;
  }
  return (text: out.toString(), offsets: (o) => o + inserted.where((i) => i < o).length);
}

/// A note's text and selection while it is being edited.
@immutable
class NoteEditValue {
  const NoteEditValue(this.text, this.start, this.end, this.format);

  NoteEditValue.collapsed(this.text, int offset, this.format) : start = offset, end = offset;

  final String text;
  final int start;
  final int end;
  final TextFormat format;

  @override
  bool operator ==(Object other) =>
      other is NoteEditValue &&
      other.text == text &&
      other.start == start &&
      other.end == end &&
      other.format == format;

  @override
  int get hashCode => Object.hash(text, start, end, format);

  @override
  String toString() => 'NoteEditValue("$text", $start, $end, ${format.name})';
}

/// The formatting commands of the note editor, as pure text edits.
abstract final class NoteFormatting {
  /// The value as Markdown: a plain note is escaped so it reads the same.
  static NoteEditValue ensureMarkdown(NoteEditValue v) {
    if (v.format == TextFormat.markdown) return v;
    final escaped = escapeNoteMarkdown(v.text);
    return NoteEditValue(escaped.text, escaped.offsets(v.start), escaped.offsets(v.end), TextFormat.markdown);
  }

  static NoteEditValue toggleBold(NoteEditValue v) => _toggleInline(ensureMarkdown(v), 2);

  static NoteEditValue toggleItalic(NoteEditValue v) => _toggleInline(ensureMarkdown(v), 1);

  static NoteEditValue toggleBullets(NoteEditValue v) => _toggleList(ensureMarkdown(v), ordered: false);

  static NoteEditValue toggleNumbers(NoteEditValue v) => _toggleList(ensureMarkdown(v), ordered: true);

  /// `- ` or `1. ` just typed at the start of a line of a plain note: the
  /// note becomes Markdown with that line a list item. Null otherwise.
  static NoteEditValue? autoList(NoteEditValue before, NoteEditValue after) {
    if (after.format != TextFormat.plain || after.start != after.end) return null;
    final p = after.start;
    if (after.text.length != before.text.length + 1 || p < 1 || after.text[p - 1] != ' ') return null;
    if (after.text.substring(0, p - 1) + after.text.substring(p) != before.text) return null;
    final ls = _lineStart(after.text, p);
    final prefix = after.text.substring(ls, p);
    final bullet = prefix == '- ';
    final ordered = _ordered.firstMatch(prefix)?.end == prefix.length;
    if (!bullet && !ordered) return null;
    final escaped = escapeNoteMarkdown(after.text);
    // Undo the escape of this one prefix: it is the list being started.
    final slash = escaped.offsets(ls) + (bullet ? 0 : prefix.length - 2);
    final text = escaped.text.substring(0, slash) + escaped.text.substring(slash + 1);
    return NoteEditValue.collapsed(text, escaped.offsets(p) - 1, TextFormat.markdown);
  }

  /// A line break typed in a list item of a Markdown note continues the
  /// list; typed in an empty item it ends the list instead. Null when
  /// [after] is not [before] with one line break typed.
  static NoteEditValue? continueList(NoteEditValue before, NoteEditValue after) {
    if (after.format != TextFormat.markdown || before.start != before.end || after.start != after.end) return null;
    final p = before.start;
    if (after.start != p + 1 || after.text != '${before.text.substring(0, p)}\n${before.text.substring(p)}') {
      return null;
    }
    final ls = _lineStart(before.text, p);
    final line = before.text.substring(ls, _lineEnd(before.text, p));
    final String prefix;
    final String next;
    if (_bullet.hasMatch(line)) {
      prefix = '- ';
      next = '- ';
    } else if (_ordered.firstMatch(line) case final m?) {
      prefix = m.group(0)!;
      next = '${int.parse(m.group(1)!) + 1}. ';
    } else {
      return null;
    }
    if (p < ls + prefix.length) return null;
    if (line.length == prefix.length) {
      // An empty item: leave the list.
      final text = before.text.substring(0, ls) + before.text.substring(ls + prefix.length);
      return NoteEditValue.collapsed(text, ls, TextFormat.markdown);
    }
    final text = '${before.text.substring(0, p)}\n$next${before.text.substring(p)}';
    return NoteEditValue.collapsed(text, p + 1 + next.length, TextFormat.markdown);
  }

  static int _lineStart(String text, int offset) => offset == 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;

  static int _lineEnd(String text, int offset) {
    final i = text.indexOf('\n', offset);
    return i < 0 ? text.length : i;
  }

  static int _prefixLength(String line) => _bullet.hasMatch(line) ? 2 : (_ordered.firstMatch(line)?.end ?? 0);

  /// Whether the character at [i] is escaped by a backslash.
  static bool _escaped(String text, int i) {
    var n = 0;
    while (i - n - 1 >= 0 && text[i - n - 1] == r'\') {
      n++;
    }
    return n.isOdd;
  }

  /// Markup stars right before [i]; an escaped star is text.
  static int _starsBefore(String text, int i) {
    var n = 0;
    while (i - n - 1 >= 0 && text[i - n - 1] == '*' && !_escaped(text, i - n - 1)) {
      n++;
    }
    return n;
  }

  /// Markup stars from [i] on; an escaped star is text.
  static int _starsAfter(String text, int i) {
    var n = 0;
    while (i + n < text.length && text[i + n] == '*' && !_escaped(text, i + n)) {
      n++;
    }
    return n;
  }

  /// Whether stars of [before] / [after] count carry the style of [width]
  /// (2 = bold, 1 = italic).
  static bool _carries(int stars, int width) => stars <= 3 && (width == 2 ? stars >= 2 : stars.isOdd);

  static NoteEditValue _toggleInline(NoteEditValue v, int width) {
    final text = v.text;
    final marker = '*' * width;
    if (v.start == v.end) {
      final p = v.start;
      // An empty pair from the last toggle is taken away again.
      if (p >= width &&
          text.length >= p + width &&
          text.substring(p - width, p + width) == marker * 2 &&
          _starsBefore(text, p) == width &&
          _starsAfter(text, p) == width) {
        return NoteEditValue.collapsed(
          text.substring(0, p - width) + text.substring(p + width),
          p - width,
          TextFormat.markdown,
        );
      }
      return NoteEditValue.collapsed(
        text.substring(0, p) + marker * 2 + text.substring(p),
        p + width,
        TextFormat.markdown,
      );
    }
    // Each selected line on its own: inline styles do not cross lines. List
    // prefixes and surrounding spaces stay outside the markers.
    final segments = <(int, int)>[];
    var ls = _lineStart(text, v.start);
    while (ls <= v.end && ls <= text.length) {
      final le = _lineEnd(text, ls);
      var s = ls + _prefixLength(text.substring(ls, le));
      var e = le;
      if (v.start > s) s = v.start;
      if (v.end < e) e = v.end;
      while (s < e && text[s].trim().isEmpty) {
        s++;
      }
      while (e > s && text[e - 1].trim().isEmpty) {
        e--;
      }
      if (e > s) segments.add((s, e));
      if (le >= text.length) break;
      ls = le + 1;
    }
    // Each segment's text without the stars around it, and how many stars
    // sit on each side (selected or not).
    final cores = <(int, int, int, int)>[];
    for (final (s, e) in segments) {
      final outerStart = s - _starsBefore(text, s);
      final outerEnd = e + _starsAfter(text, e);
      final coreStart = math.min(outerStart + _starsAfter(text, outerStart), outerEnd);
      final coreEnd = math.max(outerEnd - _starsBefore(text, outerEnd), coreStart);
      if (coreEnd > coreStart) cores.add((coreStart, coreEnd, coreStart - outerStart, outerEnd - coreEnd));
    }
    if (cores.isEmpty) return v;
    final unwrap = cores.every((c) => _carries(c.$3, width) && _carries(c.$4, width));
    final out = StringBuffer();
    var at = 0;
    int? start;
    var end = 0;
    for (final (s, e, _, _) in cores) {
      out.write(text.substring(at, unwrap ? s - width : s));
      if (!unwrap) out.write(marker);
      start ??= out.length;
      out.write(text.substring(s, e));
      end = out.length;
      if (!unwrap) out.write(marker);
      at = unwrap ? e + width : e;
    }
    out.write(text.substring(at));
    return NoteEditValue(out.toString(), start!, end, TextFormat.markdown);
  }

  static NoteEditValue _toggleList(NoteEditValue v, {required bool ordered}) {
    final text = v.text;
    final first = _lineStart(text, v.start);
    // A selection ending at the very start of a line leaves that line alone.
    final lastOffset = v.end > v.start && v.end > 0 && text[v.end - 1] == '\n' ? v.end - 1 : v.end;
    final last = _lineEnd(text, lastOffset);
    final lines = text.substring(first, last).split('\n');
    final all = lines.every((l) => ordered ? _ordered.hasMatch(l) : _bullet.hasMatch(l));
    final next = <String>[];
    var number = 1;
    for (final line in lines) {
      final body = line.substring(_prefixLength(line));
      next.add(all ? body : '${ordered ? '${number++}. ' : '- '}$body');
    }
    final replaced = next.join('\n');
    final result = text.substring(0, first) + replaced + text.substring(last);
    if (v.start == v.end) {
      // The caret keeps its place in the line's text.
      final oldPrefix = _prefixLength(lines.first);
      final newPrefix = _prefixLength(next.first);
      final column = (v.start - first - oldPrefix).clamp(0, lines.first.length - oldPrefix);
      return NoteEditValue.collapsed(result, first + newPrefix + column, TextFormat.markdown);
    }
    return NoteEditValue(result, first + _prefixLength(next.first), first + replaced.length, TextFormat.markdown);
  }
}
