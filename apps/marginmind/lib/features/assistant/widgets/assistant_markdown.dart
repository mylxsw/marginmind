import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:mm_design/mm_design.dart';

import '../assistant_controller.dart';

/// `[page:N]` / `[source:N]`: a citation chip, never a link.
class _CitationSyntax extends md.InlineSyntax {
  _CitationSyntax() : super(r'\[(?:page|source):\d+\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('cite')..attributes['marker'] = match[0]!);
    return true;
  }
}

/// `**…**` that CommonMark leaves open in Chinese: a closing `**` after
/// full-width punctuation and before a character (`**一句话：**这句…`) is not
/// right-flanking. Only spans that end in such punctuation are taken here;
/// everything else follows the standard rules.
class _CjkStrongSyntax extends md.InlineSyntax {
  _CjkStrongSyntax() : super(r'\*\*(?=\S)([^*\n]*?[\u3000-\u303f\uff01-\uff60])\*\*', startCharacter: 0x2a);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element('strong', md.InlineParser(match[1]!, parser.document).parse()));
    return true;
  }
}

/// GitHub-flavored Markdown (tables, strikethrough) plus citations. HTML in
/// an answer stays text.
md.Document _document() => md.Document(
  extensionSet: md.ExtensionSet.gitHubFlavored,
  inlineSyntaxes: [_CitationSyntax(), _CjkStrongSyntax()],
  encodeHtml: false,
  withDefaultBlockSyntaxes: true,
);

/// The blocks of [text].
List<md.Node> parseMarkdown(String text) => _document().parse(text);

/// Inline content of [text] only (bold, links, citations): how a block that
/// is still being written is shown.
List<md.Node> parseMarkdownInline(String text) => _document().parseInline(text);

/// Splits an answer being written into finished blocks and the open one:
/// the cut is the last blank line outside a code fence.
(String done, String open) splitStreaming(String text) {
  var cut = 0, fence = false, at = 0;
  for (final line in text.split('\n')) {
    final start = at;
    at += line.length + 1;
    if (line.trimLeft().startsWith('```')) {
      fence = !fence;
      if (fence) cut = start; // An open fence is not finished yet.
      continue;
    }
    if (!fence && line.trim().isEmpty && at <= text.length) cut = at;
  }
  if (fence) return (text.substring(0, cut), text.substring(cut));
  return (text.substring(0, cut.clamp(0, text.length)), text.substring(cut.clamp(0, text.length)));
}

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

/// Whether a check's verdict is qualified (“partly reliable”): its box is
/// then the caution color.
bool qualifiedVerdict(String text) =>
    RegExp(r'部分|不可靠|存疑|有误|partly|partially|unreliable|uncertain|mislead', caseSensitive: false).hasMatch(text);

/// The answer's body: Markdown laid out like a reading answer (headings,
/// lists, quotes of the source in the reading face, tables, rules), with
/// citation chips. While [cursor] is on, finished blocks are laid out and
/// the one being written shows its inline text.
class AnswerBody extends StatefulWidget {
  const AnswerBody({
    super.key,
    required this.text,
    required this.citations,
    required this.onCitation,
    this.onLink,
    this.tooltipFor,
    this.cursor = false,
    this.conclusion = false,
  });

  final String text;
  final List<Citation> citations;
  final ValueChanged<Citation> onCitation;
  final ValueChanged<Uri>? onLink;
  final String Function(Citation citation)? tooltipFor;

  /// Shows the blinking cursor after the text (still being written).
  final bool cursor;

  /// The first paragraph is a check's verdict: shown boxed.
  final bool conclusion;

  @override
  State<AnswerBody> createState() => _AnswerBodyState();
}

class _AnswerBodyState extends State<AnswerBody> {
  String? _parsed;
  List<md.Node> _blocks = const [];

  /// Finished blocks are parsed once; streaming only re-reads the open one.
  List<md.Node> _blocksOf(String text) {
    if (text != _parsed) {
      _parsed = text;
      _blocks = text.trim().isEmpty ? const [] : parseMarkdown(text);
    }
    return _blocks;
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.cursor ? visibleWhileStreaming(widget.text) : widget.text;
    final (done, open) = widget.cursor ? splitStreaming(shown) : (shown, '');
    final numbers = sourceNumbers(shown, widget.citations);
    final renderer = _Renderer(context, widget, numbers);
    final blocks = _blocksOf(done);
    final children = renderer.blocks(blocks, conclusion: widget.conclusion);
    if (widget.cursor) {
      children.add(
        Text.rich(
          TextSpan(
            style: renderer.body,
            children: [
              if (open.trim().isNotEmpty) renderer.inline(parseMarkdownInline(open.trim()), renderer.body),
              const WidgetSpan(alignment: PlaceholderAlignment.middle, child: StreamingCursor()),
            ],
          ),
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// Lays out Markdown nodes with the panel's tokens.
class _Renderer {
  _Renderer(this.context, this.widget, this.numbers)
    : c = context.mmColors,
      t = context.mmText,
      base = DefaultTextStyle.of(context).style {
    // Merged onto the inherited style: rich text keeps the system family.
    body = base.merge(t.body.copyWith(height: 1.75, color: c.label));
  }

  final BuildContext context;
  final AnswerBody widget;
  final Map<String, int> numbers;
  final MMColors c;
  final MMTextStyles t;
  final TextStyle base;
  late final TextStyle body;
  late final byMarker = {for (final x in widget.citations) x.marker: x};

  TextStyle get heading => base.merge(t.body.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.label));
  TextStyle get quote => base.merge(t.readingExcerpt.copyWith(fontSize: 12.5, color: c.excerptText));

  List<Widget> blocks(List<md.Node> nodes, {bool conclusion = false, TextStyle? style}) {
    final out = <Widget>[];
    var verdict = conclusion;
    for (final (i, node) in nodes.indexed) {
      final first = i == 0;
      final last = i == nodes.length - 1;
      if (node is! md.Element) {
        out.add(_paragraph([node], style ?? body, last: last));
        continue;
      }
      if (verdict && node.tag == 'p') {
        verdict = false;
        out.add(_verdict(node, last: last));
        continue;
      }
      out.add(block(node, first: first, last: last, style: style));
    }
    return out;
  }

  Widget _paragraph(List<md.Node> nodes, TextStyle style, {required bool last}) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 10),
    child: Text.rich(inline(nodes, style)),
  );

  Widget _verdict(md.Element p, {required bool last}) {
    final tint = qualifiedVerdict(p.textContent) ? c.caution : c.positive;
    return Container(
      key: const ValueKey('answer-verdict'),
      margin: EdgeInsets.only(bottom: last ? 0 : 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: MMSpacing.s),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: tint == c.caution ? .12 : .10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text.rich(inline(p.children ?? const [], body)),
    );
  }

  Widget block(md.Element e, {required bool first, required bool last, TextStyle? style}) {
    final text = style ?? body;
    switch (e.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        return Padding(
          padding: EdgeInsets.only(top: first ? 0 : 16, bottom: 6),
          child: Semantics(header: true, child: Text.rich(inline(e.children ?? const [], heading))),
        );
      case 'ul' || 'ol':
        return Padding(
          padding: EdgeInsets.only(bottom: last ? 0 : 10),
          child: _list(e, text, depth: 0),
        );
      case 'blockquote':
        return Container(
          margin: EdgeInsets.only(bottom: last ? 0 : 10),
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: c.separator, width: 2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: blocks(e.children ?? const [], style: quote),
          ),
        );
      case 'table':
        return Padding(
          padding: EdgeInsets.only(bottom: last ? 0 : 10),
          child: _table(e),
        );
      case 'hr':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: MMSpacing.m),
          child: Container(height: 1, color: c.separator),
        );
      case 'pre':
        return Container(
          margin: EdgeInsets.only(bottom: last ? 0 : 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: MMSpacing.s),
          decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(8)),
          child: Text(e.textContent.trimRight(), style: t.mono.copyWith(color: c.label)),
        );
      default: // p, and anything without its own layout
        return _paragraph(e.children ?? const [], text, last: last);
    }
  }

  Widget _list(md.Element list, TextStyle style, {required int depth}) {
    final ordered = list.tag == 'ol';
    final start = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    final items = (list.children ?? const []).whereType<md.Element>().where((e) => e.tag == 'li').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, item) in items.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : MMSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    ordered ? '${start + i}.' : (depth == 0 ? '•' : '◦'),
                    style: style.copyWith(color: c.secondaryLabel),
                  ),
                ),
                Expanded(child: _item(item, style, depth: depth)),
              ],
            ),
          ),
      ],
    );
  }

  /// A list item: its text, then nested lists (up to two levels shown as
  /// such) or paragraphs of a loose list.
  Widget _item(md.Element item, TextStyle style, {required int depth}) {
    final parts = <Widget>[];
    final run = <md.Node>[];
    void flush() {
      if (run.isEmpty) return;
      parts.add(Text.rich(inline(List.of(run), style)));
      run.clear();
    }

    for (final child in item.children ?? const <md.Node>[]) {
      if (child is md.Element && (child.tag == 'ul' || child.tag == 'ol')) {
        flush();
        parts.add(
          Padding(
            padding: const EdgeInsets.only(top: MMSpacing.xs),
            child: _list(child, style, depth: depth + 1),
          ),
        );
      } else if (child is md.Element && child.tag == 'p') {
        flush();
        run.addAll(child.children ?? const []);
        flush();
      } else {
        run.add(child);
      }
    }
    flush();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: parts);
  }

  Widget _table(md.Element table) {
    final rows = <(bool, List<md.Element>)>[];
    void collect(md.Element e) {
      for (final child in (e.children ?? const <md.Node>[]).whereType<md.Element>()) {
        if (child.tag == 'tr') {
          final cells = (child.children ?? const <md.Node>[]).whereType<md.Element>().toList();
          rows.add((cells.any((x) => x.tag == 'th'), cells));
        } else {
          collect(child);
        }
      }
    }

    collect(table);
    if (rows.isEmpty) return const SizedBox.shrink();
    final columns = rows.map((r) => r.$2.length).reduce((a, b) => a > b ? a : b);
    final cell = base.merge(t.footnote.copyWith(fontSize: 12, height: 1.5, color: c.label));
    final head = cell.copyWith(fontWeight: FontWeight.w600, color: c.secondaryLabel);
    return Table(
      key: const ValueKey('answer-table'),
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      border: TableBorder(horizontalInside: BorderSide(color: c.separator)),
      children: [
        for (final (header, cells) in rows)
          TableRow(
            children: [
              for (var i = 0; i < columns; i++)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 6, 10, 6),
                  child: i < cells.length
                      ? Text.rich(inline(cells[i].children ?? const [], header ? head : cell))
                      : const SizedBox.shrink(),
                ),
            ],
          ),
      ],
    );
  }

  InlineSpan inline(List<md.Node> nodes, TextStyle style) =>
      TextSpan(style: style, children: [for (final n in nodes) _span(n, style)]);

  InlineSpan _span(md.Node node, TextStyle style) {
    if (node is md.Text) return TextSpan(text: node.text);
    if (node is! md.Element) return TextSpan(text: node.textContent);
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'strong':
        return inline(children, style.copyWith(fontWeight: FontWeight.w600));
      case 'em':
        return inline(children, style.copyWith(fontStyle: FontStyle.italic));
      case 'del':
        return inline(children, style.copyWith(decoration: TextDecoration.lineThrough));
      case 'code':
        return TextSpan(
          text: node.textContent,
          style: t.mono.copyWith(color: c.label, backgroundColor: c.quaternaryFill),
        );
      case 'br':
        return const TextSpan(text: '\n');
      case 'a':
        final url = Uri.tryParse(node.attributes['href'] ?? '');
        if (url == null || (url.scheme != 'https' && url.scheme != 'http')) return inline(children, style);
        final label = node.textContent;
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: MMInteractive(
            onTap: widget.onLink == null ? null : () => widget.onLink!(url),
            tooltip: url.toString(),
            semanticLabel: label,
            canRequestFocus: false,
            cursor: SystemMouseCursors.click,
            builder: (context, s) => Text(
              label,
              style: style.copyWith(color: c.accent, decoration: s.hovered ? TextDecoration.underline : null),
            ),
          ),
        );
      case 'cite':
        // Markers not registered for this answer are dropped without a trace.
        final citation = byMarker[node.attributes['marker']];
        final String? label = citation == null
            ? null
            : citation.external
            ? '${numbers[citation.sourceId] ?? '?'}'
            : (citation.page == null ? null : 'p.${citation.page}');
        if (citation == null || label == null) return const TextSpan(text: '');
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: CitationChip(
              label: label,
              external: citation.external,
              tooltip: widget.tooltipFor?.call(citation) ?? label,
              onPressed: () => widget.onCitation(citation),
            ),
          ),
        );
      default:
        return inline(children, style);
    }
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
