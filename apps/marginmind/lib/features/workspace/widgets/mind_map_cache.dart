part of 'mind_map_canvas.dart';

/// Vertical space between sibling nodes; drops split it between them.
const _siblingGap = 14.0;

/// Per-canvas cache. Immutable content makes unchanged UI rebuilds O(1).
/// Geometry is compared separately so metadata and equal-size text edits
/// can refresh node views without relaying out or repainting the edges.
class MindMapRenderCache {
  static const measurementCapacity = 2048;
  final _measurements = <(String, TextStyle, double), ({Size size, int lines})>{};
  StudySetContent? _content;
  String? _title;
  AppLocalizations? _localizations;
  ThemeData? _theme;
  TextScaler _textScaler = TextScaler.noScaling;
  Locale? _locale;
  TextDirection _direction = TextDirection.ltr;
  (String, String)? _draft;
  TreeLayoutResult? _layout;
  List<(String, String?, double, double)> _geometry = [];
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
    required String rootTitle,
    required AppLocalizations localizations,
    required ThemeData theme,
    TextScaler textScaler = TextScaler.noScaling,
    Locale locale = const Locale('en'),
    TextDirection textDirection = TextDirection.ltr,

    /// The title being typed into a node (card id, text): measured in place
    /// of the stored title so the layout follows the text field.
    (String, String)? draft,
  }) {
    final environmentChanged =
        _theme != theme || _textScaler != textScaler || _locale != locale || _direction != textDirection;
    if (!environmentChanged &&
        identical(_content, content) &&
        _title == rootTitle &&
        _draft == draft &&
        identical(_localizations, localizations)) {
      return _layout!;
    }
    if (environmentChanged) _measurements.clear();
    _theme = theme;
    _textScaler = textScaler;
    _locale = locale;
    _direction = textDirection;
    _content = content;
    _title = rootTitle;
    _draft = draft;
    _localizations = localizations;

    // Index once: childrenOf/card/annotation each scan the content lists.
    final cards = {for (final card in content.cards) card.id: card};
    final annotations = {for (final a in content.annotations) a.id: a};
    final documents = {for (final d in content.documents) d.id: d};
    final children = <String?, List<MapNode>>{};
    for (final node in content.nodes) {
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
                ),
                collapsed: node.collapsed,
              ),
        ],
      );
    }

    final tree = build(rootNodeId, null, _NodeSpec.root(rootTitle.isEmpty ? localizations.appName : rootTitle, this));
    if (_layout == null || !listEquals(_geometry, geometry)) {
      _layout = const TreeLayout(levelGap: 56, siblingGap: _siblingGap, padding: 72).layout(tree);
      layoutCount++;
      _geometry = geometry;
    }
    return _layout!;
  }

  ({Size size, int lines}) _measure(String text, TextStyle style, double width) {
    final key = (text, style, width);
    final cached = _measurements.remove(key);
    if (cached != null) {
      _measurements[key] = cached;
      return cached;
    }
    final painter = TextPainter(
      text: TextSpan(text: text.isEmpty ? ' ' : text, style: style),
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
}

enum _Kind { root, topic, excerpt, note }

/// What a node shows, and its measured size (layout needs sizes up front).
class _NodeSpec {
  _NodeSpec._(this.kind, this.title, this.quote, this.meta, this.color, this.size);

  final _Kind kind;
  final String title;
  final String? quote;
  final String? meta;
  final MMAnnotationColor? color;
  final Size size;

  static const excerptWidth = 240.0;
  static const _excerptTextWidth = excerptWidth - 12 - 38 - 16;

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

  factory _NodeSpec.forCard(Card card, Annotation? a, Document? doc, AppLocalizations l, MindMapRenderCache cache) {
    switch (card.kind) {
      case CardKind.topic:
        final s = cache._measure(card.title, MMTypography.headline, 220 - 28).size;
        return _NodeSpec._(_Kind.topic, card.title, null, null, null, Size(s.width + 32, s.height + 18));
      case CardKind.note:
        final s = cache._measure(card.title, MMTypography.body.copyWith(height: 19 / 13), 230 - 44).size;
        return _NodeSpec._(_Kind.note, card.title, null, null, null, Size(s.width + 48, s.height + 16));
      case CardKind.image:
      case CardKind.excerpt:
        final quote = a?.quote ?? '';
        final lines = math.min(4, cache._measure(quote, MMTypography.readingExcerpt, _excerptTextWidth).lines);
        final height =
            11 +
            cache._textScaler.scale(17) +
            6 +
            (lines * cache._textScaler.scale(20) + 12) +
            6 +
            cache._textScaler.scale(14) +
            11 +
            2;
        return _NodeSpec._(
          _Kind.excerpt,
          card.title.isEmpty ? l.untitledExcerpt : card.title,
          quote,
          doc == null ? null : '${doc.title} · ${l.pageNumber(a!.page)}',
          MMAnnotationColor.fromIndex(a?.colorIndex ?? 0),
          Size(excerptWidth, height.toDouble()),
        );
    }
  }
}
