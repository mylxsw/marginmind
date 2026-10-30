part of '../mm_reflow.dart';

double? _length(String? value, double font, double width, {double? root}) {
  final match = RegExp(r'^(-?[0-9]*\.?[0-9]+)(px|em|rem|ex|%)?$').firstMatch(value?.trim() ?? '');
  if (match == null) return null;
  final n = double.tryParse(match[1]!);
  if (n == null || !n.isFinite) return null;
  return n *
      switch (match[2]) {
        'em' => font,
        'rem' => root ?? font,
        'ex' => font * .5,
        '%' => width / 100,
        _ => 1.0,
      };
}

EdgeInsets _edges(Map<String, String> style, String key, double font, double width) {
  final parts = (style[key] ?? '').split(RegExp(r'\s+'));
  final values = parts.map((p) => _length(p, font, width) ?? 0).toList();
  double at(int i) => values[i < values.length ? i : 0];
  final defaults = [at(0), at(1), values.length > 2 ? at(2) : at(0), values.length > 3 ? at(3) : at(1)];
  final sides = ['top', 'right', 'bottom', 'left'];
  final resolved = [
    for (var i = 0; i < 4; i++) math.max(0.0, _length(style['$key-${sides[i]}'], font, width) ?? defaults[i]),
  ];
  return EdgeInsets.fromLTRB(resolved[3], resolved[0], resolved[1], resolved[2]);
}

class _Unit {
  _Unit(
    this.top,
    this.bottom, {
    this.before = false,
    this.after = false,
    this.header = const [],
    this.headerHeight = 0,
  });
  final double top, bottom, headerHeight;
  final bool before, after;
  final List<LayoutPiece> header;
}

class _BlockLayout {
  _BlockLayout(this.block, this.x, this.width, this.before, this.after);
  final BookBlock block;
  final double x, width, before, after;
  final pieces = <LayoutPiece>[];
  final units = <_Unit>[];
  double height = 0;
}

class _Cell {
  _Cell(this.cell, this.row, this.column, this.endRow, this.offset);
  final BookCell cell;
  final int row, column, endRow, offset;
  late LayoutPiece piece;
}

/// Measures leaf blocks independently (visible leaf first), then places them in
/// canonical order. Every yielded step is an interruption/scheduling boundary.
class _Typesetter {
  _Typesetter(this.chapter, this.spec, this.resources, {this.visibleOffset = 0}) {
    void walk(BookNode node, List<BookNode> parents) {
      if (node.blockId != null) {
        ancestors[node.blockId!] = parents;
        for (final parent in parents) {
          firstChild.putIfAbsent(parent.path, () => node.blockId!);
          lastChild[parent.path] = node.blockId!;
        }
      }
      for (final child in node.children) {
        walk(child, [...parents, node]);
      }
    }

    for (final root in chapter.structure) {
      walk(root, []);
    }
  }
  final BookChapter chapter;
  final LayoutSpec spec;
  final LayoutResources resources;
  final int visibleOffset;
  final ancestors = <String, List<BookNode>>{};
  final firstChild = <String, String>{}, lastChild = <String, String>{};
  final measured = <String, _BlockLayout>{};
  final owned = <TextPainter>[];
  final links = <LayoutLink>[];
  // Link-heavy chapters must not rescan the whole source prefix for every
  // anchor. Index once, preserving mm_book's expand-to-grapheme contract even
  // when markup divides a combining sequence or emoji between inline runs.
  late final List<int> _boundaries = () {
    var offset = 0;
    return [0, for (final cluster in chapter.canonicalText.characters) offset += cluster.length];
  }();

  TextAnchor _linkAnchor(int start, int end) {
    int lowerBound(int offset) {
      var lo = 0, hi = _boundaries.length;
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if (_boundaries[mid] < offset) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo;
    }

    final index = lowerBound(start);
    final firstIndex = _boundaries[index] == start ? index : index - 1;
    final lastIndex = lowerBound(end);
    final first = _boundaries[firstIndex], last = _boundaries[lastIndex];
    return TextAnchor(
      chapter.id,
      first,
      last,
      chapter.canonicalText.substring(first, last),
      prefix: chapter.canonicalText.substring(_boundaries[math.max(0, firstIndex - 32)], first),
      suffix: chapter.canonicalText.substring(last, _boundaries[math.min(_boundaries.length - 1, lastIndex + 32)]),
    );
  }

  Duration workTime = Duration.zero, maxBatchTime = Duration.zero;
  bool get fixed => (chapter.viewportWidth ?? 0) > 0 && (chapter.viewportHeight ?? 0) > 0;
  double get contentWidth => fixed ? chapter.viewportWidth! : spec.contentWidth;
  double get contentHeight => fixed ? chapter.viewportHeight! : spec.contentHeight;
  double get font => fixed ? 16 : spec.fontSize * spec.textScale;

  Iterable<void> steps() sync* {
    // Shape the requested leaf before its neighbours. Placement still follows
    // source order, so canonical offsets never depend on scheduling priority.
    final blocks = chapter.blocks.toList();
    final focus = blocks.indexWhere((b) => b.end >= visibleOffset);
    final order = <BookBlock>[];
    if (focus >= 0) order.add(blocks[focus]);
    for (var distance = 1; order.length < blocks.length && focus >= 0; distance++) {
      if (focus + distance < blocks.length) order.add(blocks[focus + distance]);
      if (focus - distance >= 0) order.add(blocks[focus - distance]);
    }
    if (focus < 0) order.addAll(blocks);
    for (final block in order) {
      final watch = Stopwatch()..start();
      final margin = _edges(block.style, 'margin', font, contentWidth);
      final padding = _edges(block.style, 'padding', font, contentWidth);
      var x = (fixed ? 0 : spec.padding.left) + margin.left + padding.left;
      var width = contentWidth - margin.horizontal - padding.horizontal;
      var before = margin.top + padding.top;
      var after = margin.bottom + padding.bottom + font * .5;
      final parents = ancestors[block.id] ?? [];
      for (final parent in parents) {
        if (parent.tag == 'ul' || parent.tag == 'ol' || parent.tag == 'blockquote') {
          x += font;
          width -= font;
        }
        final style = resources.containerStyles[parent.path] ?? const <String, String>{};
        final m = _edges(style, 'margin', font, contentWidth);
        final p = _edges(style, 'padding', font, contentWidth);
        x += m.left + p.left;
        width -= m.horizontal + p.horizontal;
        if (firstChild[parent.path] == block.id) before += m.top + p.top;
        if (lastChild[parent.path] == block.id) after += m.bottom + p.bottom;
      }
      if (parents.isEmpty && (block.kind == BlockKind.list || block.kind == BlockKind.quote)) {
        x += font;
        width -= font;
      }
      final containingWidth = math.max(1.0, width);
      width = math.max(1.0, math.min(width, _length(block.style['width'], font, containingWidth) ?? width));
      width = math.max(1.0, math.min(width, _length(block.style['max-width'], font, containingWidth) ?? width));
      final measuredBlock = _BlockLayout(block, x, width, before, after);
      measured[block.id] = measuredBlock;
      workTime += watch.elapsed;
      if (block.kind == BlockKind.table && block.rows.isNotEmpty) {
        yield* _table(measuredBlock);
      } else {
        final timer = Stopwatch()..start();
        _leaf(measuredBlock);
        workTime += timer.elapsed;
        maxBatchTime = Duration(microseconds: math.max(maxBatchTime.inMicroseconds, timer.elapsedMicroseconds));
        yield null;
      }
    }
  }

  double _fontSize(Map<String, String> style, {double fallback = 1}) {
    final raw = style['font-size'];
    if (fixed) return math.max(1, _length(raw, font, font) ?? font * fallback);
    // Absolute publisher body sizes yield to reader settings; relative emphasis
    // remains proportional. The parser currently preserves CSS length strings.
    if (raw != null && RegExp(r'(em|rem|%)$').hasMatch(raw)) {
      return math.max(1, _length(raw, font, font) ?? font);
    }
    return font * fallback;
  }

  String? _fontFamily(String? css) {
    final family = css?.split(',').first.replaceAll(RegExp("['\"]"), '').trim();
    return resources.fontFamilies[family] ?? family ?? MMTypography.readingBody.fontFamily;
  }

  LayoutPiece _text(
    BookBlock block,
    List<InlineRun> runs,
    int start,
    double width, {
    double x = 0,
    double y = 0,
    bool nowrap = false,
    bool decorative = false,
    String? decoration,
    double scale = 1,
  }) {
    final children = <InlineSpan>[];
    final dimensions = <PlaceholderDimensions>[];
    final images = <MMBookImage?>[];
    final sourceOffsets = <int>[start];
    var offset = start;
    void append(String text, TextStyle style, {bool anchored = true}) {
      children.add(TextSpan(text: text, style: style));
      for (var i = 0; i < text.length; i++) {
        sourceOffsets.add(anchored ? ++offset : offset);
      }
    }

    final baseSize = _fontSize(block.style, fallback: block.kind == BlockKind.heading ? 1.5 : 1) * scale;
    final indent = _length(block.style['text-indent'], baseSize, width) ?? 0;
    if (indent > 0 && !nowrap && !decorative) {
      dimensions.add(
        PlaceholderDimensions(size: Size(math.min(indent, width - 1), 0), alignment: PlaceholderAlignment.middle),
      );
      images.add(null);
      children.add(const WidgetSpan(child: SizedBox()));
      sourceOffsets.add(start);
    }
    if (decoration != null) append(decoration, const TextStyle(), anchored: false);
    for (final run in runs) {
      final runStart = offset;
      final size = _fontSize(run.style, fallback: baseSize / font) * (run.style['font-size'] == null ? 1 : scale);
      final decorations = <TextDecoration>[];
      final textDecoration = run.style['text-decoration'] ?? block.style['text-decoration'] ?? '';
      if (run.link != null || textDecoration.contains('underline')) decorations.add(TextDecoration.underline);
      if (textDecoration.contains('line-through')) decorations.add(TextDecoration.lineThrough);
      final weight = run.style['font-weight'] ?? block.style['font-weight'];
      final style = TextStyle(
        fontSize: size,
        fontWeight: run.strong || block.kind == BlockKind.heading || weight == 'bold'
            ? FontWeight.bold
            : FontWeight.values[((int.tryParse(weight ?? '') ?? 400) ~/ 100 - 1).clamp(0, 8)],
        fontStyle: run.emphasis || (run.style['font-style'] ?? block.style['font-style']) == 'italic'
            ? FontStyle.italic
            : FontStyle.normal,
        fontFamily: run.code || block.kind == BlockKind.code
            ? MMTypography.mono.fontFamily
            : spec.fontFamily ?? _fontFamily(run.style['font-family'] ?? block.style['font-family']),
        fontFamilyFallback: spec.fontFamily == MMReaderTypography.sans
            ? MMTypography.body.fontFamilyFallback
            : MMTypography.readingBody.fontFamilyFallback,
        decoration: TextDecoration.combine(decorations),
      );
      if (run.resource != null || run.remoteUrl != null) {
        final image = resources.images[run.resource];
        final natural = _natural(run.resource, fallback: Size(size, size));
        final target = _imageSize(run.width, run.height, natural, width, size);
        dimensions.add(PlaceholderDimensions(size: target, alignment: PlaceholderAlignment.middle));
        images.add(image);
        children.add(const WidgetSpan(alignment: PlaceholderAlignment.middle, child: SizedBox()));
        offset += run.text.length;
        sourceOffsets.add(offset);
      } else {
        append(run.text, style);
        if (run.ruby case final String ruby when ruby.isNotEmpty) {
          append('($ruby)', style.copyWith(fontSize: size * .65), anchored: false);
        }
      }
      final target = run.footnoteRef ?? run.link;
      if (target != null && !decorative) {
        links.add(LayoutLink(_linkAnchor(runStart, offset), target, footnote: run.footnoteRef != null));
      }
    }
    final painter = TextPainter(
      text: TextSpan(
        style: TextStyle(
          fontSize: baseSize,
          height: spec.lineHeight,
          color: spec.readerStyle.inkColor,
          fontFamily: spec.fontFamily,
        ),
        children: children,
      ),
      textDirection: spec.direction,
      locale: spec.locale,
      textAlign: switch (block.style['text-align']) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        'justify' => TextAlign.justify,
        _ => TextAlign.start,
      },
    );
    owned.add(painter);
    painter.setPlaceholderDimensions(dimensions);
    painter.layout(maxWidth: nowrap ? double.infinity : width);
    final piece = LayoutPiece(
      block,
      painter,
      Rect.fromLTWH(x, y, painter.width, painter.height),
      start,
      offset,
      sourceOffsets: sourceOffsets,
      decorative: decorative,
      viewport: Rect.fromLTWH(x, y, width, painter.height),
      contentWidth: math.max(width, painter.width),
    );
    final boxes = painter.inlinePlaceholderBoxes ?? [];
    for (var i = 0; i < boxes.length; i++) {
      if (boxes[i].toRect().height > 0) piece.artwork.add(InlineArtwork(images[i], boxes[i].toRect()));
    }
    return piece;
  }

  Size _natural(String? path, {Size fallback = const Size(3, 2)}) {
    final size = resources.intrinsicSizes[path] ?? resources.images[path]?.size ?? fallback;
    return size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0 ? size : fallback;
  }

  Size _imageSize(String? rawWidth, String? rawHeight, Size natural, double width, double font) {
    var w = _length(rawWidth, font, width), h = _length(rawHeight, font, width);
    if (w != null && w <= 0) w = null;
    if (h != null && h <= 0) h = null;
    w ??= h == null ? natural.width : h * natural.width / natural.height;
    h ??= w * natural.height / natural.width;
    final ratio = math.min(1.0, math.min(width / w, contentHeight / h));
    return Size(w * ratio, h * ratio);
  }

  void _leaf(_BlockLayout result) {
    final block = result.block;
    if (block.kind == BlockKind.image) {
      final natural = _natural(block.resource, fallback: Size(result.width, result.width / 1.5));
      final run = block.runs.firstOrNull;
      final size = _imageSize(
        block.style['width'] ?? run?.width,
        block.style['height'] ?? run?.height,
        natural,
        result.width,
        font,
      );
      result.pieces.add(
        LayoutPiece(block, null, Offset.zero & size, block.start, block.end, image: resources.images[block.resource]),
      );
      result.height = size.height;
    } else if (block.kind == BlockKind.rule) {
      result.pieces.add(
        LayoutPiece(block, null, Rect.fromLTWH(0, 0, result.width, 1), block.start, block.end, decorative: true),
      );
      result.height = 1;
    } else {
      final nowrap = block.kind == BlockKind.code || const {'pre', 'nowrap'}.contains(block.style['white-space']);
      final piece = _text(block, block.runs, block.start, result.width, nowrap: nowrap);
      result.pieces.add(piece);
      final lines = piece.painter!.computeLineMetrics();
      var top = 0.0;
      for (var i = 0; i < lines.length; i++) {
        // Shared line boundary; glyph baselines and selection boxes stay intact.
        final bottom = i + 1 == lines.length ? piece.painter!.height : lines[i + 1].baseline - lines[i + 1].ascent;
        result.units.add(_Unit(top, bottom));
        top = bottom;
      }
      result.height = piece.rect.height;
      if (block.kind == BlockKind.list) {
        final parent = (ancestors[block.id] ?? []).where((p) => p.tag == 'ol' || p.tag == 'ul').lastOrNull;
        final preceding = chapter.blocks
            .takeWhile((b) => b.id != block.id)
            .where(
              (b) =>
                  b.kind == BlockKind.list &&
                  ((ancestors[b.id] ?? []).where((p) => p.tag == 'ol' || p.tag == 'ul').lastOrNull?.path ==
                      parent?.path),
            )
            .length;
        final marker = block.ordered || parent?.tag == 'ol' ? '${block.listStart + preceding}.' : '•';
        final decoration = _text(block, const [], block.start, font * 3, decorative: true, decoration: marker);
        result.pieces.add(_move(decoration, Offset(-decoration.rect.width - font * .25, 0)));
      }
    }
    if (result.units.isEmpty || block.style['break-inside'] == 'avoid') {
      result.units
        ..clear()
        ..add(_Unit(0, result.height));
    }
  }

  Iterable<void> _table(_BlockLayout result) sync* {
    final block = result.block;
    final cells = <_Cell>[];
    // Store active spans as column intervals, not one entry for every covered
    // grid slot: a large rowspan/colspan must not allocate their product.
    final occupied = <({int start, int end, int untilRow})>[];
    var offset = block.start, columns = 0;
    for (var r = 0; r < block.rows.length; r++) {
      occupied.removeWhere((span) => span.untilRow <= r);
      var column = 0;
      for (final cell in block.rows[r]) {
        while (true) {
          final conflict = occupied
              .where((span) => column < span.end && column + cell.colSpan > span.start)
              .firstOrNull;
          if (conflict == null) break;
          column = conflict.end;
        }
        final endRow = math.min(block.rows.length, r + math.max(1, cell.rowSpan)).toInt();
        cells.add(_Cell(cell, r, column, endRow, offset));
        if (endRow > r + 1) occupied.add((start: column, end: column + cell.colSpan, untilRow: endRow));
        column += cell.colSpan;
        columns = math.max(columns, column);
        offset += cell.length + 1;
      }
    }
    if (columns == 0) return;
    final cellWidth = math.max(result.width / columns, font * 3);
    final heights = List.filled(block.rows.length, 0.0);
    for (final cell in cells) {
      final watch = Stopwatch()..start();
      cell.piece = _text(block, cell.cell.runs, cell.offset, cellWidth * cell.cell.colSpan - 8);
      if (cell.endRow == cell.row + 1) heights[cell.row] = math.max(heights[cell.row], cell.piece.rect.height + 8);
      workTime += watch.elapsed;
      maxBatchTime = Duration(microseconds: math.max(maxBatchTime.inMicroseconds, watch.elapsedMicroseconds));
      yield null;
    }
    for (final cell in cells.where((c) => c.endRow > c.row + 1)) {
      final actual = heights.sublist(cell.row, cell.endRow).fold(0.0, (a, b) => a + b);
      final extra = math.max(0.0, cell.piece.rect.height + 8 - actual) / (cell.endRow - cell.row);
      for (var row = cell.row; row < cell.endRow; row++) {
        heights[row] += extra;
      }
    }
    final tops = <double>[0];
    for (final h in heights) {
      tops.add(tops.last + h);
    }
    for (final cell in cells) {
      result.pieces.add(_move(cell.piece, Offset(cell.column * cellWidth + 4, tops[cell.row] + 4)));
    }
    final headerCount = (resources.headerRows[block.id] ?? 0).clamp(0, block.rows.length);
    // A header spanning into the body cannot be repeated independently.
    final safeHeader = cells.every((c) => c.row >= headerCount || c.endRow <= headerCount);
    final header = safeHeader
        ? [
            for (var i = 0; i < cells.length; i++)
              if (cells[i].row < headerCount) result.pieces[i],
          ]
        : <LayoutPiece>[];
    var start = 0;
    while (start < block.rows.length) {
      var end = start + 1;
      for (var r = start; r < end; r++) {
        for (final cell in cells.where((c) => c.row == r)) {
          end = math.max(end, cell.endRow);
        }
      }
      result.units.add(
        _Unit(
          tops[start],
          tops[end],
          header: start >= headerCount ? header : [],
          headerHeight: safeHeader ? tops[headerCount] : 0,
        ),
      );
      start = end;
    }
    result.height = tops.last;
  }

  LayoutPiece _move(LayoutPiece p, Offset offset, {double scale = 1}) {
    final result = LayoutPiece(
      p.block,
      p.painter,
      _scaleRect(p.rect, scale).shift(offset),
      p.textStart,
      p.textEnd,
      image: p.image,
      viewport: p.viewport == null ? null : _scaleRect(p.viewport!, scale).shift(offset),
      contentWidth: p.contentWidth * scale,
      scale: p.scale * scale,
      decorative: p.decorative,
      sourceOffsets: p.sourceOffsets,
    );
    result.artwork.addAll(p.artwork);
    return result;
  }

  _Geometry finish() {
    final watch = Stopwatch()..start();
    links.sort((a, b) => a.anchor.start.compareTo(b.anchor.start));
    final pieces = <LayoutPiece>[];
    final units = <_Unit>[];
    var y = fixed ? 0.0 : spec.padding.top;
    final fixedWidth = chapter.viewportWidth, fixedHeight = chapter.viewportHeight;
    final scale = fixed ? math.min(spec.contentWidth / fixedWidth!, spec.contentHeight / fixedHeight!) : 1.0;
    for (final block in chapter.blocks) {
      final measuredBlock = measured[block.id]!;
      y += measuredBlock.before;
      var origin = fixed
          ? Offset(spec.padding.left + measuredBlock.x * scale, spec.padding.top + y * scale)
          : Offset(measuredBlock.x, y);
      if (fixed && const {'absolute', 'fixed'}.contains(block.style['position'])) {
        final right = _length(block.style['right'], font, fixedWidth!);
        final bottom = _length(block.style['bottom'], font, fixedHeight!);
        final left =
            _length(block.style['left'], font, fixedWidth) ??
            (right == null ? measuredBlock.x : fixedWidth - right - measuredBlock.width);
        final top =
            _length(block.style['top'], font, fixedHeight) ??
            (bottom == null ? y : fixedHeight - bottom - measuredBlock.height);
        origin = Offset(spec.padding.left + left * scale, spec.padding.top + top * scale);
      }
      final translated = {for (final p in measuredBlock.pieces) p: _move(p, origin, scale: scale)};
      pieces.addAll(translated.values);
      final breaks = measuredBlock.units;
      for (var i = 0; i < breaks.length; i++) {
        final u = breaks[i];
        units.add(
          _Unit(
            y + u.top,
            y + u.bottom,
            before: i == 0 && const {'page', 'always', 'left', 'right'}.contains(block.style['break-before']),
            after:
                i == breaks.length - 1 &&
                const {'page', 'always', 'left', 'right'}.contains(block.style['break-after']),
            header: u.header.map((p) => translated[p]!).toList(),
            headerHeight: u.headerHeight,
          ),
        );
      }
      y += measuredBlock.height + measuredBlock.after;
    }
    if (fixed) {
      final height = fixedHeight! * scale;
      workTime += watch.elapsed;
      return _Geometry(
        List.unmodifiable(pieces),
        [PageSlice(spec.padding.top, spec.padding.top + height)],
        height + spec.padding.vertical,
        List.unmodifiable(links),
        workTime,
        maxBatchTime,
      );
    }
    final pages = <PageSlice>[];
    var top = spec.padding.top, bottom = top, headerHeight = 0.0;
    var header = <LayoutPiece>[];
    void flush() {
      if (bottom <= top) return;
      pages.add(
        PageSlice(
          top,
          bottom,
          header: List.unmodifiable(header),
          headerHeight: headerHeight,
          scrollExtent: math.max(0, bottom - top + headerHeight - spec.contentHeight),
        ),
      );
      top = bottom;
      header = [];
      headerHeight = 0;
    }

    for (final unit in units) {
      if (unit.before || unit.bottom - top + headerHeight > spec.contentHeight) {
        flush();
        // Blank block margins are not carried onto the next page.
        top = unit.top;
        bottom = top;
        if (unit.header.isNotEmpty && unit.headerHeight < spec.contentHeight * .5) {
          header = unit.header;
          headerHeight = unit.headerHeight;
        }
      }
      bottom = unit.bottom;
      if (unit.after) flush();
    }
    if (bottom > top && y - top + headerHeight <= spec.contentHeight) bottom = y;
    flush();
    if (pages.isEmpty) pages.add(PageSlice(spec.padding.top, spec.padding.top));
    workTime += watch.elapsed;
    maxBatchTime = Duration(microseconds: math.max(maxBatchTime.inMicroseconds, watch.elapsedMicroseconds));
    return _Geometry(
      List.unmodifiable(pieces),
      List.unmodifiable(pages),
      y + spec.padding.bottom,
      List.unmodifiable(links),
      workTime,
      maxBatchTime,
    );
  }

  void dispose() {
    for (final painter in owned) {
      painter.dispose();
    }
  }
}
