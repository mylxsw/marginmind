import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import '../assistant_controller.dart';

/// A block of an answer: the Markdown the assistant writes (paragraphs,
/// lists, small headings, conclusion boxes).
sealed class AnswerBlock {
  const AnswerBlock(this.text);
  final String text;
}

class ParagraphBlock extends AnswerBlock {
  const ParagraphBlock(super.text);
}

class HeadingBlock extends AnswerBlock {
  const HeadingBlock(super.text);
}

class ListItemBlock extends AnswerBlock {
  const ListItemBlock(super.text, {this.marker = '•'});
  final String marker;
}

/// A `>` quote: the verdict of a check, shown boxed.
class ConclusionBlock extends AnswerBlock {
  const ConclusionBlock(super.text);
}

final _heading = RegExp(r'^#{1,6}\s+(.*)$');
final _bullet = RegExp(r'^\s*[-*+]\s+(.*)$');
final _numbered = RegExp(r'^\s*(\d+)[.)]\s+(.*)$');
final _quote = RegExp(r'^>\s?(.*)$');

/// Splits [text] into blocks. Anything else is a paragraph; lines of one
/// paragraph keep their breaks.
List<AnswerBlock> parseAnswer(String text) {
  final blocks = <AnswerBlock>[];
  final paragraph = <String>[];
  final quote = <String>[];
  void flush() {
    if (paragraph.isNotEmpty) blocks.add(ParagraphBlock(paragraph.join('\n')));
    if (quote.isNotEmpty) blocks.add(ConclusionBlock(quote.join('\n')));
    paragraph.clear();
    quote.clear();
  }

  for (final line in text.split('\n')) {
    if (line.trim().isEmpty) {
      flush();
    } else if (_quote.firstMatch(line) case final m?) {
      if (paragraph.isNotEmpty) flush();
      quote.add(m[1]!);
    } else if (_heading.firstMatch(line) case final m?) {
      flush();
      blocks.add(HeadingBlock(m[1]!));
    } else if (_bullet.firstMatch(line) case final m?) {
      flush();
      blocks.add(ListItemBlock(m[1]!));
    } else if (_numbered.firstMatch(line) case final m?) {
      flush();
      blocks.add(ListItemBlock(m[2]!, marker: '${m[1]}.'));
    } else {
      if (quote.isNotEmpty) flush();
      paragraph.add(line);
    }
  }
  flush();
  return blocks;
}

/// A piece of inline text.
sealed class Inline {
  const Inline();
}

class TextRun extends Inline {
  const TextRun(this.text, {this.bold = false, this.italic = false, this.url});
  final String text;
  final bool bold, italic;
  final Uri? url;
}

/// A citation the answer may show: [label] is "p.42" or "1".
class CitationRun extends Inline {
  const CitationRun(this.citation, this.label);
  final Citation citation;
  final String label;
}

final _inline = RegExp(
  r'\*\*(.+?)\*\*|(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?!\w)|\[([^\]\n]+)\]\(([^)\s]+)\)|\[(page|source):(\d+)\]',
);

/// Numbers external sources 1, 2… by their first citation in [text].
Map<String, int> sourceNumbers(String text, List<Citation> citations) {
  final byMarker = {for (final c in citations) c.marker: c};
  final numbers = <String, int>{};
  for (final m in RegExp(r'\[source:\d+\]').allMatches(text)) {
    final c = byMarker[m[0]];
    if (c != null && c.external) numbers.putIfAbsent(c.sourceId!, () => numbers.length + 1);
  }
  return numbers;
}

/// Inline runs of [text]. Citation markers that are not in [citations] are
/// dropped without a trace.
List<Inline> parseInline(String text, List<Citation> citations, Map<String, int> numbers) {
  final byMarker = {for (final c in citations) c.marker: c};
  final out = <Inline>[];
  var at = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > at) out.add(TextRun(text.substring(at, m.start)));
    at = m.end;
    if (m[1] != null) {
      out.add(TextRun(m[1]!, bold: true));
    } else if (m[2] != null) {
      out.add(TextRun(m[2]!, italic: true));
    } else if (m[3] != null) {
      final url = Uri.tryParse(m[4]!);
      out.add(TextRun(m[3]!, url: url != null && (url.scheme == 'https' || url.scheme == 'http') ? url : null));
    } else {
      final c = byMarker[m[0]];
      if (c == null) continue;
      if (c.external) {
        out.add(CitationRun(c, '${numbers[c.sourceId] ?? '?'}'));
      } else if (c.page != null) {
        out.add(CitationRun(c, 'p.${c.page}'));
      }
    }
  }
  if (at < text.length) out.add(TextRun(text.substring(at)));
  return out;
}

/// The Markdown an answer is copied as: page markers become "p.N", source
/// markers footnotes listed at the end.
String copyableAnswer(String text, List<Citation> citations) {
  final numbers = sourceNumbers(text, citations);
  final byMarker = {for (final c in citations) c.marker: c};
  final body = text.replaceAllMapped(RegExp(r'\[(page|source):(\d+)\]'), (m) {
    final c = byMarker[m[0]];
    if (c == null) return '';
    return c.external ? '[^${numbers[c.sourceId]}]' : '(p.${c.page})';
  });
  final notes = [
    for (final e in numbers.entries)
      if (citations.firstWhere((c) => c.sourceId == e.key).url case final url) '[^${e.value}]: ${url ?? e.key}',
  ];
  return notes.isEmpty ? body : '$body\n\n${notes.join('\n')}';
}

/// While an answer streams, a marker may be cut in two: hide the open
/// bracket until it closes.
String visibleWhileStreaming(String text) => text.replaceFirst(RegExp(r'\[[a-z]*:?\d*$'), '');

/// The answer's body. [onPage] jumps to a page in the source; [onSource]
/// opens an external source.
class AnswerBody extends StatelessWidget {
  const AnswerBody({
    super.key,
    required this.text,
    required this.citations,
    required this.onCitation,
    this.onLink,
    this.tooltipFor,
    this.cursor = false,
  });

  final String text;
  final List<Citation> citations;
  final ValueChanged<Citation> onCitation;
  final ValueChanged<Uri>? onLink;
  final String Function(Citation citation)? tooltipFor;

  /// Shows the blinking cursor after the last block (still being written).
  final bool cursor;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final shown = cursor ? visibleWhileStreaming(text) : text;
    final numbers = sourceNumbers(shown, citations);
    final blocks = parseAnswer(shown);
    // Merged onto the inherited style: rich text keeps the system family.
    final base = DefaultTextStyle.of(context).style;
    final body = base.merge(t.body.copyWith(height: 22 / 13, color: c.label));
    InlineSpan spans(String value, TextStyle style, {bool last = false}) => TextSpan(
      style: style,
      children: [
        for (final run in parseInline(value, citations, numbers))
          switch (run) {
            TextRun(:final text, :final url?) => WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: MMInteractive(
                onTap: onLink == null ? null : () => onLink!(url),
                tooltip: url.toString(),
                semanticLabel: text,
                canRequestFocus: false,
                cursor: SystemMouseCursors.click,
                builder: (context, s) => Text(
                  text,
                  style: style.copyWith(color: c.accent, decoration: s.hovered ? TextDecoration.underline : null),
                ),
              ),
            ),
            TextRun(:final text, :final bold, :final italic) => TextSpan(
              text: text,
              style: TextStyle(fontWeight: bold ? FontWeight.w600 : null, fontStyle: italic ? FontStyle.italic : null),
            ),
            CitationRun(:final citation, :final label) => WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: CitationChip(
                  label: label,
                  external: citation.external,
                  tooltip: tooltipFor?.call(citation) ?? label,
                  onPressed: () => onCitation(citation),
                ),
              ),
            ),
          },
        if (last && cursor) const WidgetSpan(alignment: PlaceholderAlignment.middle, child: StreamingCursor()),
      ],
    );

    if (blocks.isEmpty) {
      return cursor ? const Align(alignment: Alignment.centerLeft, child: StreamingCursor()) : const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, block) in blocks.indexed)
          Padding(
            padding: EdgeInsets.only(
              top: block is HeadingBlock ? (i == 0 ? 0 : 10) : 0,
              bottom: switch (block) {
                HeadingBlock() => MMSpacing.xs,
                ListItemBlock() => MMSpacing.xxs,
                _ => MMSpacing.s,
              },
            ),
            child: switch (block) {
              HeadingBlock() => Text.rich(
                spans(
                  block.text,
                  base.merge(t.callout.copyWith(fontWeight: FontWeight.w600, color: c.secondaryLabel)),
                  last: i == blocks.length - 1,
                ),
              ),
              ListItemBlock(:final marker) => Padding(
                padding: const EdgeInsets.only(left: MMSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 16,
                      child: Text(marker, style: body.copyWith(color: c.secondaryLabel)),
                    ),
                    Expanded(child: Text.rich(spans(block.text, body, last: i == blocks.length - 1))),
                  ],
                ),
              ),
              ConclusionBlock() => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: MMSpacing.s),
                decoration: BoxDecoration(
                  color: c.positive.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text.rich(spans(block.text, body, last: i == blocks.length - 1)),
              ),
              ParagraphBlock() => Text.rich(spans(block.text, body, last: i == blocks.length - 1)),
            },
          ),
      ],
    );
  }
}

/// `p.N` (local, accent) or `n` (external source) inline in an answer.
class CitationChip extends StatelessWidget {
  const CitationChip({
    super.key,
    required this.label,
    required this.external,
    required this.tooltip,
    required this.onPressed,
  });

  final String label;
  final bool external;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MMInteractive(
      onTap: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      canRequestFocus: false,
      builder: (context, s) {
        final (Color bg, Color fg) = external
            ? (s.hovered ? c.research : c.fill, s.hovered ? c.onAccent : c.secondaryLabel)
            : (s.hovered ? c.accent : c.accentTint, s.hovered ? c.onAccent : c.accent);
        return AnimatedContainer(
          duration: MMMotion.quick,
          curve: MMMotion.quickCurve,
          height: 15,
          constraints: const BoxConstraints(minWidth: 16),
          padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xs),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: context.mmText.footnote.copyWith(fontSize: 10, fontWeight: FontWeight.w600, color: fg, height: 1),
            ),
          ),
        );
      },
    );
  }
}

/// The cursor at the end of an answer being written: blinks once a second,
/// stays still when motion is reduced.
class StreamingCursor extends StatefulWidget {
  const StreamingCursor({super.key});

  @override
  State<StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<StreamingCursor> with SingleTickerProviderStateMixin {
  late final _blink = AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MMAppearance.reduceMotionOf(context)) {
      _blink.stop();
      _blink.value = 0;
    } else if (!_blink.isAnimating) {
      _blink.repeat();
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      key: const ValueKey('assistant-cursor'),
      width: 7,
      height: 14,
      margin: const EdgeInsets.only(left: 2),
      color: context.mmColors.research,
    );
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, child) => Opacity(opacity: _blink.value < .5 ? 1 : 0, child: child),
      child: bar,
    );
  }
}
