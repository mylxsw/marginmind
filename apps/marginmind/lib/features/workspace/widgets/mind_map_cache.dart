part of 'mind_map_canvas.dart';

/// Vertical space between sibling nodes; drops split it between them.
const _siblingGap = 14.0;

/// How much of a suspended card shows through: enough to read, clearly set
/// apart from the cards still in review.
const _suspendedOpacity = 0.45;

/// Widest summary label before it wraps.
const _summaryLabelWidth = 200.0;

/// Per-canvas cache. Immutable content makes unchanged UI rebuilds O(1).
/// Geometry is compared separately so metadata and equal-size text edits
/// can refresh node views without relaying out or repainting the edges.
class MindMapRenderCache {
  static const measurementCapacity = 2048;
  final _measurements = <(String, TextStyle, double), ({Size size, int lines})>{};
  StudySetContent? _content;
  String? _title;
  String? _mapId;
  AppLocalizations? _localizations;
  ThemeData? _theme;
  TextStyle _baseStyle = const TextStyle();
  TextScaler _textScaler = TextScaler.noScaling;
  Locale? _locale;
  TextDirection _direction = TextDirection.ltr;
  (String, String)? _draft;
  (String, String)? _markDraft;
  TreeLayoutResult? _layout;
  List<(String, String?, double, double)> _geometry = [];
  List<(String, String, String, String, double, double)> _summaryGeometry = [];

  /// Relations of the map, and the label shown for each summary and relation.
  List<MapRelation> _relations = const [];
  Map<String, String> _markLabels = const {};
  Map<String, _NodeSpec> _specs = {};
  Map<String, int> _collapsed = {};
  Set<String> _expandable = {};

  @visibleForTesting
  int measurementCount = 0;
  @visibleForTesting
  int layoutCount = 0;
  @visibleForTesting
  int get cachedMeasurementCount => _measurements.length;

  TreeLayoutResult update({
    required StudySetContent content,
    String mapId = MindMap.defaultId,
    required String rootTitle,
    required AppLocalizations localizations,
    required ThemeData theme,

    /// The ambient text style the node texts inherit (font family, letter
    /// spacing): measured with it so a measured title fits as rendered.
    TextStyle baseStyle = const TextStyle(),
    TextScaler textScaler = TextScaler.noScaling,
    Locale locale = const Locale('en'),
    TextDirection textDirection = TextDirection.ltr,

    /// The title being typed into a node (card id, text): measured in place
    /// of the stored title so the layout follows the text field.
    (String, String)? draft,

    /// Likewise for the label of a relation or summary (id, text).
    (String, String)? markDraft,
  }) {
    final environmentChanged =
        _theme != theme ||
        _baseStyle != baseStyle ||
        _textScaler != textScaler ||
        _locale != locale ||
        _direction != textDirection;
    if (!environmentChanged &&
        identical(_content, content) &&
        _title == rootTitle &&
        _mapId == mapId &&
        _draft == draft &&
        _markDraft == markDraft &&
        identical(_localizations, localizations)) {
      return _layout!;
    }
    if (environmentChanged) {
      _measurements.clear();
      _clipped.clear();
    }
    _theme = theme;
    _baseStyle = baseStyle;
    _textScaler = textScaler;
    _locale = locale;
    _direction = textDirection;
    _content = content;
    _title = rootTitle;
    _mapId = mapId;
    _draft = draft;
    _markDraft = markDraft;
    _localizations = localizations;

    // Index once: childrenOf/card/annotation each scan the content lists.
    final cards = {for (final card in content.cards) card.id: card};
    final annotations = {for (final a in content.annotations) a.id: a};
    final documents = {for (final d in content.documents) d.id: d};
    final children = <String?, List<MapNode>>{};
    for (final node in content.nodes) {
      if (node.mapId != mapId) continue;
      children.putIfAbsent(node.parentId, () => []).add(node);
    }
    for (final siblings in children.values) {
      siblings.sort((a, b) => a.order.compareTo(b.order));
    }
    _specs = {};
    _collapsed = {};
    _expandable = {};
    final geometry = <(String, String?, double, double)>[];
    LayoutNode build(String id, String? parentId, _NodeSpec spec, {bool collapsed = false}) {
      _specs[id] = spec;
      geometry.add((id, parentId, spec.size.width, spec.size.height));
      var descendants = children[id == rootNodeId ? null : id] ?? const <MapNode>[];
      if (id != rootNodeId && descendants.isNotEmpty) {
        _expandable.add(id);
        if (collapsed) {
          _collapsed[id] = descendants.length;
          descendants = const [];
        }
      }
      return LayoutNode(
        id: id,
        width: spec.size.width,
        height: spec.size.height,
        children: [
          for (final node in descendants)
            if (cards[node.cardId] case final card?)
              build(
                card.id,
                id,
                _NodeSpec.forCard(
                  draft?.$1 == card.id ? card.copyWith(title: draft!.$2) : card,
                  annotations[card.annotationId],
                  documents[annotations[card.annotationId]?.documentId],
                  localizations,
                  this,
                  editing: draft?.$1 == card.id,
                ),
                collapsed: node.collapsed,
              ),
        ],
      );
    }

    final tree = build(rootNodeId, null, _NodeSpec.root(rootTitle.isEmpty ? localizations.appName : rootTitle, this));
    String label(String id, String stored) => markDraft?.$1 == id ? markDraft!.$2 : stored;
    _relations = content.relationsOf(mapId);
    final mapSummaries = content.summariesOf(mapId);
    _markLabels = {
      for (final r in _relations) r.id: label(r.id, r.label),
      for (final (s, _) in mapSummaries) s.id: label(s.id, s.label),
    };
    final summaries = [
      for (final (s, _) in mapSummaries)
        if (_summaryLabelSize(_markLabels[s.id]!, editing: markDraft?.$1 == s.id) case final size)
          LayoutSummary(
            id: s.id,
            parentId: s.parentId ?? rootNodeId,
            fromId: s.fromId,
            toId: s.toId,
            width: size.width,
            height: size.height,
          ),
    ];
    final summaryGeometry = [for (final s in summaries) (s.id, s.parentId, s.fromId, s.toId, s.width, s.height)];
    if (_layout == null || !listEquals(_geometry, geometry) || !listEquals(_summaryGeometry, summaryGeometry)) {
      _layout = const TreeLayout(
        levelGap: 56,
        siblingGap: _siblingGap,
        padding: 72,
        summaryGap: MMSpacing.m,
        bracketWidth: MMSpacing.m,
        labelGap: MMSpacing.s,
        balanced: true,
      ).layout(tree, summaries: summaries);
      layoutCount++;
      _geometry = geometry;
      _summaryGeometry = summaryGeometry;
    }
    return _layout!;
  }

  /// A summary label's box; an empty one takes no room unless it is being
  /// typed into. Like a topic, the box leaves a little room past the measured
  /// text: rendered glyphs can come out a fraction wider, and a box without
  /// slack wraps the last character onto a hidden second line.
  Size _summaryLabelSize(String text, {required bool editing}) {
    if (text.isEmpty && !editing) return Size.zero;
    final s = _measure(text, MMTypography.headline, _summaryLabelWidth).size;
    return Size(
      math.max(s.width, editing ? MMSpacing.xxxl : 0) + MMSpacing.xs + MMSpacing.m * 2,
      s.height + MMSpacing.s * 2,
    );
  }

  ({Size size, int lines}) _measure(String text, TextStyle style, double width) {
    final key = (text, style, width);
    final cached = _measurements.remove(key);
    if (cached != null) {
      _measurements[key] = cached;
      return cached;
    }
    final painter = TextPainter(
      text: TextSpan(text: text.isEmpty ? ' ' : text, style: _baseStyle.merge(style)),
      textDirection: _direction,
      textScaler: _textScaler,
      locale: _locale,
    )..layout(maxWidth: width);
    final result = (
      size: Size(painter.width.ceilToDouble(), painter.height.ceilToDouble()),
      lines: math.max(1, painter.computeLineMetrics().length),
    );
    painter.dispose();
    measurementCount++;
    if (_measurements.length == measurementCapacity) _measurements.remove(_measurements.keys.first);
    _measurements[key] = result;
    return result;
  }

  final _clipped = <(String, TextStyle, double, int), String>{};

  /// [text] as shown in at most [maxLines] lines of [width]: cut at the end
  /// of the last line with an ellipsis when it is longer. The renderer's own
  /// ellipsis is not reliable with fallback fonts (the excerpt serif), so the
  /// shown text carries it.
  String _clip(String text, TextStyle style, double width, int maxLines) {
    if (_measure(text, style, width).lines <= maxLines) return text;
    final key = (text, style, width, maxLines);
    final cached = _clipped.remove(key);
    if (cached != null) return _clipped[key] = cached;
    final painter = TextPainter(
      text: TextSpan(text: text, style: _baseStyle.merge(style)),
      textDirection: _direction,
      textScaler: _textScaler,
      locale: _locale,
    )..layout(maxWidth: width);
    final last = painter.computeLineMetrics()[maxLines - 1];
    var end = painter.getPositionForOffset(Offset(0, last.baseline + last.descent + 1)).offset;
    painter.dispose();
    measurementCount++;
    var clipped = text;
    while (end > 0) {
      clipped = '${text.substring(0, end).trimRight()}…';
      if (_measure(clipped, style, width).lines <= maxLines) break;
      end--;
      // Never split a surrogate pair.
      if (end > 0 && (text.codeUnitAt(end) & 0xFC00) == 0xDC00) end--;
    }
    if (_clipped.length == measurementCapacity) _clipped.remove(_clipped.keys.first);
    return _clipped[key] = clipped;
  }
}

enum _Kind { root, topic, excerpt, note, image }

/// What a node shows, and its measured size (layout needs sizes up front).
class _NodeSpec {
  _NodeSpec._(
    this.kind,
    this.title,
    this.quote,
    this.meta,
    this.color,
    this.size, {
    this.image,
    this.imageHeight = 0,
    String? label,
    this.suspended = false,
  }) : label = label ?? title;

  final _Kind kind;

  /// Shown title; empty for an excerpt or image without one (no title row).
  final String title;

  /// What the node is called in its title editor and in the excerpt-target
  /// mark (the node itself is named by its content).
  final String label;

  /// The quote as shown: at most [maxQuoteLines] lines, ending with an
  /// ellipsis when cut. The source ([meta]) is shown on hover or selection.
  final String? quote;
  final String? meta;
  final MMAnnotationColor? color;
  final Size size;

  /// Image cards: package file name and the picture's height, from the
  /// area's aspect ratio (layout needs it before the file is decoded).
  final String? image;
  final double imageHeight;

  /// Kept out of review: drawn faded.
  final bool suspended;

  static const excerptWidth = 240.0;
  static const maxQuoteLines = 4;
  static const _excerptTextWidth = excerptWidth - 12 - 38 - 16;
  static const imageWidth = excerptWidth - 12 - 38;

  factory _NodeSpec.root(String title, MindMapRenderCache cache) {
    final w = cache._measure(title, MMTypography.title3, 360).size.width;
    return _NodeSpec._(
      _Kind.root,
      title,
      null,
      null,
      null,
      Size(w + 40, math.max(42, cache._textScaler.scale(20) + 22)),
    );
  }

  factory _NodeSpec.forCard(
    Card card,
    Annotation? a,
    Document? doc,
    AppLocalizations l,
    MindMapRenderCache cache, {
    bool editing = false,
  }) {
    // Excerpts and images show a title row only when they have a title (or
    // one is being typed).
    final titled = card.title.isNotEmpty || editing;
    final titleRow = titled ? cache._textScaler.scale(17) + 6 : 0;
    final source = doc == null ? null : '${doc.title} · ${l.pageNumber(a!.page)}';
    switch (card.kind) {
      case CardKind.topic:
        final s = cache._measure(card.title, MMTypography.headline, 220 - 28).size;
        return _NodeSpec._(
          _Kind.topic,
          card.title,
          null,
          null,
          null,
          Size(s.width + 32, s.height + 18),
          suspended: card.suspended,
        );
      case CardKind.research:
      case CardKind.note:
        final s = cache._measure(card.title, MMTypography.body.copyWith(height: 19 / 13), 230 - 44).size;
        return _NodeSpec._(
          _Kind.note,
          card.title,
          null,
          null,
          null,
          Size(s.width + 48, s.height + 16),
          suspended: card.suspended,
        );
      case CardKind.image:
        final r = a?.rects.firstOrNull;
        final aspect = r == null || r.right <= r.left ? 0.6 : (r.top - r.bottom).abs() / (r.right - r.left);
        final imageHeight = (imageWidth * aspect).clamp(36.0, 200.0).roundToDouble();
        final height = 11 + titleRow + imageHeight + 11 + 2;
        return _NodeSpec._(
          _Kind.image,
          card.title,
          null,
          source,
          MMAnnotationColor.fromIndex(a?.colorIndex ?? 0),
          Size(excerptWidth, height.toDouble()),
          image: card.imageFileName,
          imageHeight: imageHeight,
          label: card.title.isEmpty ? l.imageExcerpt : card.title,
          suspended: card.suspended,
        );
      case CardKind.excerpt:
        final quote = cache._clip(a?.quote ?? '', MMTypography.readingExcerpt, _excerptTextWidth, maxQuoteLines);
        final lines = cache._measure(quote, MMTypography.readingExcerpt, _excerptTextWidth).lines;
        final height = 11 + titleRow + (lines * cache._textScaler.scale(20) + 12) + 11 + 2;
        return _NodeSpec._(
          _Kind.excerpt,
          card.title,
          quote,
          source,
          MMAnnotationColor.fromIndex(a?.colorIndex ?? 0),
          Size(excerptWidth, height.toDouble()),
          label: card.title.isEmpty ? (quote.isEmpty ? l.untitledExcerpt : quote) : card.title,
          suspended: card.suspended,
        );
    }
  }
}
