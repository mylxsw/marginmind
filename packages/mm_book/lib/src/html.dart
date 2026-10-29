part of '../mm_book.dart';

Iterable<Map<String, Object>> _sourceEntries(List<InlineRun> runs, int offset) sync* {
  for (final r in runs) {
    if (r.sourcePath != null) {
      yield {
        'path': r.sourcePath!,
        'sourceStart': r.sourceStart,
        'sourceEnd': r.sourceEnd,
        'start': offset,
        'end': offset + r.text.length,
      };
    }
    offset += r.text.length;
  }
}

BookChapter _htmlChapter(String id, String source, List<String> diagnostics) {
  final document = html.parse(source);
  final css = _Css(document, id, diagnostics);
  final styles = <dom.Element, Map<String, String>>{};
  final paths = <dom.Node, String>{};
  final targets = <String, int>{};
  final blocks = <BookBlock>[];
  var offset = 0;
  void index(dom.Node node, String path, Map<String, String> parent, int depth) {
    if (depth > 256) _limit();
    paths[node] = path;
    var style = parent;
    if (node is dom.Element) {
      style = css.compute(node, parent, diagnostics);
      styles[node] = style;
    }
    for (var i = 0; i < node.nodes.length; i++) {
      index(node.nodes[i], '$path/$i', style, depth + 1);
    }
  }

  index(document.documentElement!, '0', {}, 0);
  bool hidden(dom.Element e) =>
      const {
        'script',
        'style',
        'head',
        'noscript',
        'rt',
        'input',
        'button',
        'select',
        'textarea',
      }.contains(e.localName) ||
      e.attributes.containsKey('hidden') ||
      styles[e]?['display'] == 'none';
  void mark(dom.Element e, int at) {
    if (e.id.isNotEmpty) targets.putIfAbsent(e.id, () => at);
    if (e.attributes['name'] case final String name) {
      targets.putIfAbsent(name, () => at);
    }
  }

  List<InlineRun> inline(dom.Node root, {bool preserve = false, int? start, Iterable<dom.Node>? content}) {
    final runs = <InlineRun>[];
    var whitespace = true;
    var length = 0;
    void add(
      String text,
      dom.Node node,
      Map<String, String> style,
      bool strong,
      bool emphasis,
      bool code,
      String? link, {
      String? resource,
      String? ruby,
      String? footnote,
      String? remoteUrl,
      int sourceStart = 0,
      int? sourceEnd,
    }) {
      if (text.isEmpty) return;
      runs.add(
        InlineRun(
          text,
          strong: strong,
          emphasis: emphasis,
          code: code,
          link: link,
          resource: resource,
          style: style,
          sourcePath: paths[node],
          sourceStart: sourceStart,
          sourceEnd: sourceEnd ?? (node is dom.Text ? node.text.length : 0),
          width: style['width'] ?? (node is dom.Element ? node.attributes['width'] : null),
          height: style['height'] ?? (node is dom.Element ? node.attributes['height'] : null),
          ruby: ruby,
          footnoteRef: footnote,
          remoteUrl: remoteUrl,
        ),
      );
      length += text.length;
      whitespace = text.endsWith(' ') || text.endsWith('\n');
    }

    void walk(dom.Node node, Map<String, String> style, bool strong, bool emphasis, bool code, String? link) {
      if (node is dom.Text) {
        var text = node.text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
        final pre = preserve || const {'pre', 'pre-wrap', 'break-spaces'}.contains(style['white-space']);
        if (!pre) {
          text = text.replaceAll(RegExp(r'[ \t\n\f]+'), ' ');
          if (whitespace && text.startsWith(' ')) text = text.substring(1);
        }
        add(text, node, style, strong, emphasis, code, link);
        return;
      }
      if (node is! dom.Element || hidden(node)) return;
      style = styles[node] ?? style;
      mark(node, (start ?? offset) + length);
      final tag = node.localName;
      strong =
          strong ||
          const {'b', 'strong'}.contains(tag) ||
          const {'bold', '700', '800', '900'}.contains(style['font-weight']);
      emphasis = emphasis || const {'i', 'em'}.contains(tag) || style['font-style'] == 'italic';
      code = code || tag == 'code';
      if (tag == 'a') {
        final href = node.attributes['href'];
        final uri = href == null ? null : Uri.tryParse(href);
        link = uri != null && (!uri.hasScheme || const {'http', 'https', 'mailto'}.contains(uri.scheme)) ? href : null;
      }
      if (tag == 'img' || tag == 'image') {
        final src = node.attributes['src'] ?? node.attributes['href'] ?? node.attributes['xlink:href'];
        if (src != null) {
          try {
            add('\uFFFC', node, style, strong, emphasis, code, link, resource: _resolve(id, src));
          } on FormatException {
            diagnostics.add('Blocked image URL: $src');
            final uri = Uri.tryParse(src);
            add(
              '\uFFFC',
              node,
              style,
              strong,
              emphasis,
              code,
              link,
              remoteUrl: uri != null && const {'http', 'https'}.contains(uri.scheme) ? src : null,
            );
          }
        }
        return;
      }
      if (tag == 'br') {
        add('\n', node, style, strong, emphasis, code, link);
        return;
      }
      if (tag == 'ruby') {
        String readable(dom.Node child) {
          if (child is dom.Text) return child.text;
          if (child is dom.Element && (hidden(child) || child.localName == 'rp')) return '';
          return child.nodes.map(readable).join();
        }

        var base = node.nodes.map(readable).join();
        if (!preserve && !const {'pre', 'pre-wrap'}.contains(style['white-space'])) {
          base = base.replaceAll(RegExp(r'[ \t\r\n\f]+'), ' ');
          if (whitespace && base.startsWith(' ')) base = base.substring(1);
        }
        final annotation = node.querySelectorAll('rt').map((n) => n.nodes.map(readable).join()).join(' ');
        add(base, node, style, strong, emphasis, code, link, ruby: annotation);
        return;
      }
      if ((node.attributes['epub:type'] ?? '').split(' ').contains('noteref')) {
        add(node.text, node, style, strong, emphasis, code, link, footnote: node.attributes['href']);
        return;
      }
      for (final child in node.nodes) {
        walk(child, style, strong, emphasis, code, link);
      }
    }

    if (content == null) {
      walk(root, root is dom.Element ? styles[root] ?? {} : {}, false, false, preserve, null);
    } else {
      for (final node in content) {
        walk(node, root is dom.Element ? styles[root] ?? {} : {}, false, false, preserve, null);
      }
    }
    if (!preserve && runs.isNotEmpty) {
      final last = runs.last;
      if (last.text.endsWith(' ') && !const {'pre', 'pre-wrap', 'break-spaces'}.contains(last.style['white-space'])) {
        runs[runs.length - 1] = InlineRun(
          last.text.replaceFirst(RegExp(r' +$'), ''),
          strong: last.strong,
          emphasis: last.emphasis,
          code: last.code,
          link: last.link,
          resource: last.resource,
          width: last.width,
          height: last.height,
          style: last.style,
          sourcePath: last.sourcePath,
          sourceStart: last.sourceStart,
          sourceEnd: last.sourceEnd,
          ruby: last.ruby,
          footnoteRef: last.footnoteRef,
          remoteUrl: last.remoteUrl,
        );
      }
    }
    return runs;
  }

  void add(
    dom.Node node,
    BlockKind kind,
    List<InlineRun> runs, {
    List<List<BookCell>> rows = const [],
    String? sourcePath,
  }) {
    if (runs.every((r) => r.text.isEmpty) && kind != BlockKind.rule) return;
    final element = node is dom.Element ? node : null;
    final tag = element?.localName ?? '';
    final parent = element?.parent;
    final block = BookBlock(
      id: '$id#${sourcePath ?? paths[node]}',
      sourcePath: sourcePath ?? paths[node] ?? '',
      kind: kind,
      start: offset,
      runs: runs,
      rows: rows,
      level: RegExp(r'^h[1-6]$').hasMatch(tag) ? int.parse(tag.substring(1)) : 1,
      style: element == null ? {} : styles[element] ?? {},
      resource: kind == BlockKind.image ? runs.firstOrNull?.resource : null,
      ordered: parent?.localName == 'ol',
      listStart: int.tryParse(parent?.attributes['start'] ?? '') ?? 1,
    );
    blocks.add(block);
    offset = block.end + 1;
  }

  void visit(dom.Node node) {
    if (node is dom.Text) {
      if (node.text.trim().isNotEmpty) add(node, BlockKind.paragraph, inline(node));
      return;
    }
    if (node is! dom.Element || hidden(node)) return;
    mark(node, offset);
    final tag = node.localName;
    if (tag == 'table') {
      final rows = <List<BookCell>>[];
      var cellOffset = offset;
      for (final row in node.querySelectorAll('tr')) {
        final cells = <BookCell>[];
        for (final cell in row.children.where((c) => c.localName == 'td' || c.localName == 'th')) {
          final runs = inline(cell, start: cellOffset);
          final c = BookCell(
            runs,
            rowSpan: (int.tryParse(cell.attributes['rowspan'] ?? '') ?? 1).clamp(1, 1000),
            colSpan: (int.tryParse(cell.attributes['colspan'] ?? '') ?? 1).clamp(1, 1000),
          );
          cells.add(c);
          cellOffset += c.length + 1;
        }
        if (cells.isNotEmpty) rows.add(cells);
      }
      final runs = <InlineRun>[];
      for (var r = 0; r < rows.length; r++) {
        if (r > 0) runs.add(const InlineRun('\n'));
        for (var c = 0; c < rows[r].length; c++) {
          if (c > 0) runs.add(const InlineRun('\t'));
          runs.addAll(rows[r][c].runs);
        }
      }
      add(node, BlockKind.table, runs, rows: rows);
      return;
    }
    if (tag == 'hr') {
      add(node, BlockKind.rule, []);
      return;
    }
    final kind = switch (tag) {
      'p' => BlockKind.paragraph,
      'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6' => BlockKind.heading,
      'li' => BlockKind.list,
      'blockquote' => BlockKind.quote,
      'pre' => BlockKind.code,
      'img' || 'image' => BlockKind.image,
      _ => null,
    };
    final footnote = (node.attributes['epub:type'] ?? '').split(' ').any((v) => v == 'footnote' || v == 'endnote');
    // Nested block containers are visited separately, never flattened into one run.
    final nested = node.children.any(
      (c) => const {'p', 'ul', 'ol', 'blockquote', 'pre', 'table', 'div'}.contains(c.localName),
    );
    if ((kind != null || footnote) && !nested) {
      add(node, footnote ? BlockKind.footnote : kind!, inline(node, preserve: kind == BlockKind.code));
    } else {
      final pending = <dom.Node>[];
      void flush() {
        if (pending.isEmpty) return;
        add(
          node,
          footnote ? BlockKind.footnote : kind ?? BlockKind.paragraph,
          inline(node, content: pending),
          sourcePath: paths[pending.first],
        );
        pending.clear();
      }

      for (final child in node.nodes) {
        if (child is dom.Element &&
            const {
              'p',
              'div',
              'section',
              'article',
              'main',
              'header',
              'footer',
              'aside',
              'figure',
              'figcaption',
              'h1',
              'h2',
              'h3',
              'h4',
              'h5',
              'h6',
              'ul',
              'ol',
              'li',
              'blockquote',
              'pre',
              'table',
              'hr',
              'img',
              'image',
              'svg',
            }.contains(child.localName)) {
          flush();
          visit(child);
        } else {
          pending.add(child);
        }
      }
      flush();
    }
  }

  visit(document.body!);
  double? width, height;
  for (final meta in document.querySelectorAll('meta[name="viewport"]')) {
    final content = meta.attributes['content'] ?? '';
    width = double.tryParse(RegExp(r'width\s*=\s*([\d.]+)').firstMatch(content)?.group(1) ?? '');
    height = double.tryParse(RegExp(r'height\s*=\s*([\d.]+)').firstMatch(content)?.group(1) ?? '');
  }
  final blockByPath = {for (final b in blocks) b.sourcePath: b.id};
  BookNode? structure(dom.Node node) {
    final path = paths[node] ?? '';
    final children = <BookNode>[
      for (final c in node.nodes)
        if (structure(c) case final BookNode n) n,
    ];
    final block = blockByPath[path];
    if (block == null && children.isEmpty) return null;
    return BookNode(path, node is dom.Element ? node.localName ?? '' : '#text', block, block == null ? children : []);
  }

  final roots = <BookNode>[
    for (final n in document.body!.nodes)
      if (structure(n) case final BookNode s) s,
  ];
  final textLength = blocks.isEmpty ? 0 : blocks.last.end;
  return BookChapter(
    id,
    blocks,
    elementOffsets: Map.unmodifiable(targets.map((k, v) => MapEntry(k, v.clamp(0, textLength)))),
    structure: List.unmodifiable(roots),
    fonts: List.unmodifiable(css.fonts),
    viewportWidth: width,
    viewportHeight: height,
  );
}
