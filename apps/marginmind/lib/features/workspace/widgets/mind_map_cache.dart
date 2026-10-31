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
///
/// Measurements are keyed by text, style and the width the text wraps in
/// (which follows the card's width, P2-C06), plus how a note is drawn;
/// clipped previews also by their line count, which follows the map's
/// density. A card resized or a density switched so only ever measures the
/// texts whose key changed, and switching back reads the old results.
class MindMapRenderCache {
  static const measurementCapacity = 2048;
  final _measurements = <_MeasureKey, ({Size size, int lines})>{};
  List<ExpansionDraft> _expansionDrafts = const [];
  Map<String, String> _expansionMoves = const {};
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
  TextFormat? _draftFormat;
  (String, double)? _widthDraft;
  (String, String)? _markDraft;
  Set<String> _expanded = const {};
  Set<String> _expandedNotes = const {};
  String? _focusedNoteId;
  bool _touchControls = false;
  Map<String, String> _noteOwners = const {};
  MapStructure? _structure;
  TreeLayoutResult? _layout;
  List<(String, String?, double, double)> _geometry = [];
  List<(String, String, String, String, double, double)> _summaryGeometry = [];

  /// Relations of the map, and the label shown for each summary and relation.
  List<MapRelation> _relations = const [];
  Map<String, String> _markLabels = const {};

  /// A node of each summary's range, by summary id: the summary takes its
  /// branch's color.
  Map<String, String> _summaryBranches = const {};
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
    List<ExpansionDraft> expansionDrafts = const [],
    Map<String, String> expansionMoves = const {},
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

    /// The format of [draft] when it differs from the card's (a note
    /// formatted while it is edited).
    TextFormat? draftFormat,

    /// A card being resized (card id, width): measured at that width in
    /// place of the stored one.
    (String, double)? widthDraft,

    /// Likewise for the label of a relation or summary (id, text).
    (String, String)? markDraft,

    /// Cards shown with their whole text: part of the key, since it changes
    /// what is measured and so every size and the layout.
    Set<String> expanded = const {},
    Set<String> expandedNotes = const {},
    String? focusedNoteId,
    bool touchControls = false,

    /// The structure to lay out in place of the map's own (a preview).
    MapStructure? structure,
  }) {
    structure ??= content.map(mapId)?.structure ?? MapStructure.mind;
    final environmentChanged =
        _theme != theme ||
        _baseStyle != baseStyle ||
        _textScaler != textScaler ||
        _locale != locale ||
        _direction != textDirection;
    if (!environmentChanged &&
        listEquals(_expansionDrafts, expansionDrafts) &&
        mapEquals(_expansionMoves, expansionMoves) &&
        identical(_content, content) &&
        _title == rootTitle &&
        _mapId == mapId &&
        _draft == draft &&
        _draftFormat == draftFormat &&
        _widthDraft == widthDraft &&
        _markDraft == markDraft &&
        setEquals(_expanded, expanded) &&
        setEquals(_expandedNotes, expandedNotes) &&
        _focusedNoteId == focusedNoteId &&
        _touchControls == touchControls &&
        _structure == structure &&
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
    _expansionDrafts = expansionDrafts;
    _expansionMoves = expansionMoves;
    _content = content;
    _title = rootTitle;
    _mapId = mapId;
    _draft = draft;
    _draftFormat = draftFormat;
    _widthDraft = widthDraft;
    _markDraft = markDraft;
    _expanded = Set.of(expanded);
    _expandedNotes = Set.of(expandedNotes);
    _focusedNoteId = focusedNoteId;
    _touchControls = touchControls;
    _localizations = localizations;
    final structureChanged = _structure != structure;
    _structure = structure;

    // Index once: childrenOf/card/annotation each scan the content lists.
    final cards = {for (final card in content.cards) card.id: card};
    final annotations = {for (final a in content.annotations) a.id: a};
    final documents = {for (final d in content.documents) d.id: d};
    final compact = (content.map(mapId)?.density ?? MapDensity.full) != MapDensity.full;
    final notes = {for (final n in content.researchNotes) n.id: n};
    final evidence = {for (final e in content.evidence) e.id: e};
    int sourceCount(ResearchNote note) =>
        {for (final ref in note.citations) ?evidence[ref.evidenceId]?.sourceId}.length;
    final attachments = MapNoteAttachments(content, mapId: mapId);
    _noteOwners = attachments.owners;
    final children = <String?, List<MapNode>>{};
    for (final node in attachments.nodes) {
      if (node.mapId != mapId) continue;
      children.putIfAbsent(expansionMoves[node.cardId]?.substring(4) ?? node.parentId, () => []).add(node);
    }
    for (final siblings in children.values) {
      siblings.sort((a, b) => a.order.compareTo(b.order));
    }
    _specs = {};
    _collapsed = {};
    _expandable = {};
    final geometry = <(String, String?, double, double)>[];
    late LayoutNode Function(MapNode node, String parentId) existing;
    LayoutNode ghost(ExpansionDraft d, String parentId) {
      final spec = _NodeSpec._(
        _Kind.topic,
        d.title,
        null,
        null,
        null,
        Size(
          d.id == '__expansion_placeholder__' ? 120 : 164,
          d.id == '__expansion_placeholder__' ? 30 : (d.tag != ExpansionDirection.auto || d.page != null ? 54 : 36),
        ),
      );
      _specs[d.id] = spec;
      geometry.add((d.id, parentId, spec.size.width, spec.size.height));
      return LayoutNode(
        id: d.id,
        width: spec.size.width,
        height: spec.size.height,
        children: [
          for (final node in children[d.id] ?? <MapNode>[])
            if (cards.containsKey(node.cardId)) existing(node, d.id),
          for (final child in expansionDrafts.where((c) => c.parentRef == 'new:${d.id}')) ghost(child, d.id),
        ],
      );
    }

    LayoutNode build(String id, String? parentId, _NodeSpec spec, {bool collapsed = false}) {
      final attached = attachments.notes[id];
      if (attached != null && attached.isNotEmpty) {
        spec.attachedNotes = [
          for (final note in attached)
            draft?.$1 == note.id ? note.copyWith(title: draft!.$2, textFormat: draftFormat) : note,
        ];
        spec.notesExpanded =
            expandedNotes.contains(id) ||
            attachments.owners[draft?.$1] == id ||
            attachments.owners[focusedNoteId] == id;
        // Topics and standalone notes need room for the footer; resizable
        // excerpt/image/research cards keep the user's chosen width.
        final width = spec.kind == _Kind.topic || spec.kind == _Kind.note
            ? math.max(_NodeSpec.excerptWidth, spec.size.width)
            : spec.size.width;
        var height = noteHeaderHeight;
        if (spec.notesExpanded) {
          for (final note in spec.attachedNotes) {
            final editing = draft?.$1 == note.id;
            final body = _measure(
              note.title,
              _NodeSpec.noteStyle,
              width - MMSpacing.m * 2 - (editing ? 0 : noteActionsWidth),
              note: note.textFormat,
              source: editing,
            ).size.height;
            // Match the existing card slack for fractional CJK font metrics.
            height += math.max(body, noteRowMinHeight) + MMSpacing.s * 2 + MMSpacing.xxs;
          }
        }
        spec.notesHeight = height;
        spec.size = Size(width, spec.size.height + height);
      }
      if (spec.source case final source?) {
        spec.sourceDocumentTitle = content.document(source.documentId)?.title;
        final sources = content.map(mapId)?.generation?.sources ?? <MapSource>[];
        final index = sources.indexWhere((s) => s.documentId == source.documentId);
        spec.sourceDocumentIndex = sources.length > 1 && index >= 0 ? index : null;
      }
      _specs[id] = spec;
      geometry.add((id, parentId, spec.size.width, spec.size.height));
      var descendants = children[id == rootNodeId ? null : id] ?? const <MapNode>[];
      if (id != rootNodeId && descendants.isNotEmpty) {
        _expandable.add(id);
        if (collapsed && expansionDrafts.isEmpty) {
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
            if (cards.containsKey(node.cardId)) existing(node, id),
          for (final d in expansionDrafts.where((d) => (d.parentRef == id || id == rootNodeId && d.parentRef == mapId)))
            ghost(d, id),
        ],
      );
    }

    existing = (node, parentId) {
      final card = cards[node.cardId]!;
      return build(
        card.id,
        parentId,
        _NodeSpec.forCard(
          draft?.$1 == card.id ? card.copyWith(title: draft!.$2, textFormat: draftFormat) : card,
          annotations[card.annotationId],
          documents[annotations[card.annotationId]?.documentId],
          localizations,
          this,
          editing: draft?.$1 == card.id,
          expanded: expanded.contains(card.id),
          width: widthDraft?.$1 == card.id ? widthDraft!.$2 : node.width,
          compact: compact,
          note: notes[card.researchNoteId],
          sourceCount: notes[card.researchNoteId] == null ? 0 : sourceCount(notes[card.researchNoteId]!),
        ),
        collapsed: node.collapsed,
      );
    };
    final tree = build(rootNodeId, null, _NodeSpec.root(rootTitle.isEmpty ? localizations.appName : rootTitle, this));
    String label(String id, String stored) => markDraft?.$1 == id ? markDraft!.$2 : stored;
    _relations = content.relationsOf(mapId);
    final mapSummaries = content.summariesOf(mapId);
    _markLabels = {
      for (final r in _relations) r.id: label(r.id, r.label),
      for (final (s, _) in mapSummaries) s.id: draft != null && draft.$1 == s.cardId ? draft.$2 : label(s.id, s.label),
    };
    _summaryBranches = {for (final (s, _) in mapSummaries) s.id: s.fromId};
    final summaries = [
      for (final (s, _) in mapSummaries)
        if (_summaryLabelSize(
              _markLabels[s.id]!,
              editing: markDraft?.$1 == s.id || (draft != null && draft.$1 == s.cardId),
            )
            case final size)
          LayoutSummary(
            id: s.id,
            parentId: s.parentId ?? rootNodeId,
            fromId: s.fromId,
            toId: s.toId,
            width: size.width,
            height: size.height,
            node: s.cardId == null
                ? null
                : build(
                    s.cardId!,
                    s.parentId ?? rootNodeId,
                    _NodeSpec._(_Kind.topic, _markLabels[s.id]!, null, null, null, size),
                  ),
          ),
    ];
    final summaryGeometry = [for (final s in summaries) (s.id, s.parentId, s.fromId, s.toId, s.width, s.height)];
    if (_layout == null ||
        structureChanged ||
        !listEquals(_geometry, geometry) ||
        !listEquals(_summaryGeometry, summaryGeometry)) {
      _layout = TreeLayout(
        levelGap: 56,
        siblingGap: _siblingGap,
        padding: 72,
        summaryGap: MMSpacing.m,
        bracketWidth: MMSpacing.m,
        labelGap: MMSpacing.s,
        balanced: true,
        structure: layoutStructureOf(structure),
      ).layout(tree, summaries: summaries);
      layoutCount++;
      _geometry = geometry;
      _summaryGeometry = summaryGeometry;
    }
    return _layout!;
  }

  double get noteHeaderHeight =>
      math.max(
        _touchControls ? MMSizes.touchTarget : MMSpacing.xxxl,
        _textScaler.scale(MMTypography.footnote.fontSize! * MMTypography.footnote.height!) + MMSpacing.l,
      ) +
      MMSizes.hairline;
  double get noteRowMinHeight => noteActionSize;
  double get noteActionSize => _touchControls ? MMSizes.touchTarget : MMSpacing.xl + MMSpacing.xs;
  double get noteActionsWidth => MMSpacing.s + noteActionSize * 2 + MMSpacing.xxs;

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

  /// [text] laid out in [width]. With [note] it is a note's text in that
  /// format, drawn as shown, or with [source] as edited (the markup shown).
  ({Size size, int lines}) _measure(
    String text,
    TextStyle style,
    double width, {
    TextFormat? note,
    bool source = false,
  }) {
    final key = (text: text, style: style, width: width, note: note, source: source);
    final cached = _measurements.remove(key);
    if (cached != null) {
      _measurements[key] = cached;
      return cached;
    }
    // The in-place editor sets its style without the ambient one
    // (MMInlineTextField), so a note being edited is measured the same way.
    final merged = (source ? const TextStyle(inherit: false, textBaseline: TextBaseline.alphabetic) : _baseStyle).merge(
      style,
    );
    final shown = text.isEmpty ? ' ' : text;
    final painter = TextPainter(
      text: note == null
          ? TextSpan(text: shown, style: merged)
          : source
          ? noteSourceSpan(shown, note, merged)
          : noteSpan(shown, note, merged),
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

  /// The default width of an excerpt card: the narrowest of
  /// [_NodeSpec.excerptWidths] at which its text fits in
  /// [_NodeSpec.maxQuoteLines] lines, else the widest.
  double _excerptWidthFor(Card card) {
    final segments = _content!.segmentsOf(card);
    for (final width in _NodeSpec.excerptWidths) {
      final textWidth = width - _NodeSpec._cardInset - _NodeSpec._quoteInset;
      // Merged parts are drawn as separate paragraphs beside their dots.
      final lines = segments.length < 2
          ? _measure(segments.map((s) => s.text).join('\n'), MMTypography.readingExcerpt, textWidth).lines
          : segments.fold<int>(
              0,
              (n, s) =>
                  n +
                  _measure(
                    s.text,
                    s.annotationId == null ? MMTypography.body : MMTypography.readingExcerpt,
                    textWidth - 12,
                  ).lines,
            );
      if (lines <= _NodeSpec.maxQuoteLines) return width;
    }
    return _NodeSpec.excerptWidths.last;
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

typedef _MeasureKey = ({String text, TextStyle style, double width, TextFormat? note, bool source});

enum _Kind { root, topic, excerpt, note, image, research }

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
    this.truncated = false,
    this.expanded = false,
    this.format = TextFormat.plain,
    this.maxLines = maxQuoteLines,
    this.resizable = false,
    this.segments = const [],
    this.source,
  }) : label = label ?? title;

  final _Kind kind;
  final CardSource? source;
  String? sourceDocumentTitle;
  int? sourceDocumentIndex;

  /// Shown title; empty for an excerpt or image without one (no title row).
  final String title;

  /// What the node is called in its title editor and in the excerpt-target
  /// mark (the node itself is named by its content).
  final String label;

  /// The quote as shown: at most [maxLines] lines, ending with an ellipsis
  /// when cut. The source ([meta]) is shown on hover or selection.
  final String? quote;
  final String? meta;
  final MMAnnotationColor? color;
  Size size;
  List<Card> attachedNotes = const [];
  bool notesExpanded = false;
  double notesHeight = 0;
  double get contentHeight => size.height - notesHeight;

  /// Image cards: package file name and the picture's height, from the
  /// area's aspect ratio (layout needs it before the file is decoded). No
  /// picture in a compact map.
  final String? image;
  final double imageHeight;

  /// Kept out of review: drawn faded.
  final bool suspended;

  /// The card's preview cuts its text (quote past [maxLines] lines, or a
  /// title past one line): it offers to show the whole text.
  final bool truncated;

  /// The whole text is shown (only ever set on a [truncated] card).
  final bool expanded;

  /// A note's text format: Markdown is shown formatted.
  final TextFormat format;

  /// Lines of the quote in the preview: fewer in a compact map.
  final int maxLines;

  /// Excerpts, images and research notes can be made wider or narrower.
  final bool resizable;
  final List<({String text, String? annotationId, MMAnnotationColor color})> segments;

  static const excerptWidth = 240.0;

  /// Default excerpt widths, narrowest first: a card widens one step while
  /// its text needs more than [maxQuoteLines] lines, up to about 25 CJK
  /// characters a line at the widest. A width set by hand always wins.
  static const excerptWidths = [excerptWidth, 320.0, 400.0];
  static const maxQuoteLines = 4;
  static const compactQuoteLines = 2;

  /// Card padding left and right of the text (12 + 38) and the quote's own
  /// padding (16).
  static const _cardInset = 12.0 + 38;
  static const _quoteInset = 16.0;
  static final titleStyle = MMTypography.headline.copyWith(height: 17 / 13);
  static final noteStyle = MMTypography.body.copyWith(height: 19 / 13);

  /// Widest an unsized note grows, and a note's padding and pen icon.
  static const _noteWidth = 230.0;
  static const _noteInset = 48.0;

  /// "Show full text" / "Show less" below a cut card: gap and line height.
  static const toggleGap = MMSpacing.xs;
  static const toggleLineHeight = 14.0;

  /// A research note card: kind line, title (two lines at most), body
  /// preview (two lines at most) and the way to the whole note.
  static const researchInset = 15.0 + 12.0;
  static const researchTitleLines = 2;
  static const researchBodyLines = 2;
  static final researchBodyStyle = MMTypography.callout.copyWith(fontWeight: FontWeight.w400, height: 16 / 12);

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
    bool expanded = false,

    /// The card's width in this map (excerpts, images and research notes);
    /// null for the default.
    double? width,
    bool compact = false,
    ResearchNote? note,
    int sourceCount = 0,
  }) {
    // Excerpts and images show a title row only when they have a title (or
    // one is being typed).
    final titled = card.title.isNotEmpty || editing;
    final titleRow = titled ? cache._textScaler.scale(17) + 6 : 0;
    final source = doc == null
        ? null
        : a!.isText
        ? doc.title
        : '${doc.title} · ${l.pageNumber(a.page)}';
    final cardWidth = (width ?? (card.kind == CardKind.excerpt ? cache._excerptWidthFor(card) : excerptWidth))
        .clamp(MapNode.minWidth, MapNode.maxWidth)
        .toDouble();
    // Title text beside the color dot (9) and its gap (7).
    final titleWidth = cardWidth - _cardInset - 16;
    switch (card.kind) {
      case CardKind.topic:
        final s = cache._measure(card.title, MMTypography.headline, 220 - 28).size;
        final source = card.source;
        final extraWidth = source != null
            ? cache._measure(l.notePage(source.page), MMTypography.footnote, 120).size.width + 12 + 6
            : 0.0;
        return _NodeSpec._(
          _Kind.topic,
          card.title,
          null,
          null,
          null,
          Size(s.width + 32 + extraWidth, s.height + 18),
          suspended: card.suspended,
          source: source,
        );
      case CardKind.research when note != null:
        // The card's width is the user's; a compact map shows the title
        // line and the way to the note only.
        final scale = cache._textScaler.scale;
        final textWidth = cardWidth - researchInset;
        final title = cache._clip(note.title, titleStyle, textWidth, compact ? 1 : researchTitleLines);
        final body = compact ? '' : cache._clip(note.body.trim(), researchBodyStyle, textWidth, researchBodyLines);
        final titleLines = cache._measure(title, titleStyle, textWidth).lines;
        final bodyLines = body.isEmpty ? 0 : cache._measure(body, researchBodyStyle, textWidth).lines;
        final height =
            10 +
            scale(14) +
            MMSpacing.xs +
            titleLines * scale(17) +
            (bodyLines == 0 ? 0 : MMSpacing.xxs + bodyLines * scale(16)) +
            MMSpacing.s -
            MMSpacing.xxs +
            scale(toggleLineHeight) +
            10;
        return _NodeSpec._(
          _Kind.research,
          title,
          body,
          l.researchCardKind(sourceCount),
          null,
          Size(cardWidth, height.ceilToDouble()),
          label: note.title,
          suspended: card.suspended,
          resizable: true,
        );
      case CardKind.note:
        // A note is measured as it is drawn: formatted, or with its markup
        // while it is edited.
        final s = cache
            ._measure(card.title, noteStyle, _noteWidth - _noteInset, note: card.textFormat, source: editing)
            .size;
        return _NodeSpec._(
          _Kind.note,
          card.title,
          null,
          null,
          null,
          Size(s.width + _noteInset, s.height + 16),
          suspended: card.suspended,
          format: card.textFormat,
        );
      case CardKind.research:
        // A compact map shows a research note's first line only.
        final textWidth = (width == null ? _noteWidth : cardWidth) - _noteInset;
        final shown = compact && !editing ? cache._clip(card.title, noteStyle, textWidth, 1) : card.title;
        final s = cache._measure(shown, noteStyle, textWidth).size;
        return _NodeSpec._(
          _Kind.note,
          shown,
          null,
          null,
          null,
          Size(width == null ? s.width + _noteInset : cardWidth, s.height + 16),
          label: card.title,
          suspended: card.suspended,
          resizable: true,
        );
      case CardKind.image:
        final label = card.title.isEmpty ? l.imageExcerpt : card.title;
        if (compact && !editing) {
          // The title row alone, named by its label when untitled.
          final height = 11 + cache._textScaler.scale(17) + 11 + 2;
          return _NodeSpec._(
            _Kind.image,
            label,
            null,
            source,
            MMAnnotationColor.fromIndex(a?.colorIndex ?? 0),
            Size(cardWidth, height.toDouble()),
            label: label,
            suspended: card.suspended,
            resizable: true,
          );
        }
        final r = a?.isText == true ? null : a?.rects.firstOrNull;
        final aspect = a?.capture == null
            ? (r == null || r.right <= r.left ? 0.6 : (r.top - r.bottom).abs() / (r.right - r.left))
            : a!.capture!.height / a.capture!.width;
        // Preserve short selections' aspect ratio too, without tinted strips
        // above/below the picture. Tall images still fit within the preview.
        final imageHeight = ((cardWidth - _cardInset) * aspect).clamp(1.0, 200.0);
        final height = 11 + titleRow + imageHeight + 11 + 2;
        return _NodeSpec._(
          _Kind.image,
          card.title,
          null,
          source,
          MMAnnotationColor.fromIndex(a?.colorIndex ?? 0),
          Size(cardWidth, height.toDouble()),
          image: card.imageFileName,
          imageHeight: imageHeight,
          label: label,
          suspended: card.suspended,
          resizable: true,
        );
      case CardKind.excerpt:
        final maxLines = compact ? compactQuoteLines : maxQuoteLines;
        final textWidth = cardWidth - _cardInset - _quoteInset;
        final allSegments = cache._content!.segmentsOf(card);
        final full = allSegments.map((s) => s.text).join('\n');
        final clipped = cache._clip(full, MMTypography.readingExcerpt, textWidth, maxLines);
        // While the title is typed the field keeps one line, so the card
        // shows its preview.
        final titleLines = card.title.isEmpty || editing ? 1 : cache._measure(card.title, titleStyle, titleWidth).lines;
        final segmentLines = card.segments.length < 2
            ? 0
            : allSegments.fold<int>(
                0,
                (count, segment) =>
                    count +
                    cache
                        ._measure(
                          segment.text,
                          segment.annotationId == null ? MMTypography.body : MMTypography.readingExcerpt,
                          textWidth - 12,
                        )
                        .lines,
              );
        // A merged card shows every part in full; compact keeps each part to
        // [compactQuoteLines].
        final merged = card.segments.length > 1;
        final truncated = merged
            ? compact &&
                  !editing &&
                  allSegments.any(
                    (segment) =>
                        cache
                            ._measure(
                              segment.text,
                              segment.annotationId == null ? MMTypography.body : MMTypography.readingExcerpt,
                              textWidth - 12,
                            )
                            .lines >
                        maxLines,
                  )
            : !editing && (clipped != full || titleLines > 1 || segmentLines > maxLines);
        final open = truncated && expanded;
        final quote = open ? full : clipped;
        final lines = cache._measure(quote, MMTypography.readingExcerpt, textWidth).lines;
        final scale = cache._textScaler.scale;
        final shownTitle = titled ? (open ? titleLines : 1) * scale(17) + 6 : 0;
        final toggle = truncated ? toggleGap + scale(toggleLineHeight) : 0;
        final shownSegments = <({String text, String? annotationId, MMAnnotationColor color})>[];
        var segmentHeight = 0.0;
        if (merged) {
          for (final segment in allSegments) {
            final style = segment.annotationId == null ? MMTypography.body : MMTypography.readingExcerpt;
            final text = open || !compact ? segment.text : cache._clip(segment.text, style, textWidth - 12, maxLines);
            final measured = cache._measure(text, style, textWidth - 12);
            shownSegments.add((
              text: text,
              annotationId: segment.annotationId,
              color: MMAnnotationColor.fromIndex(
                cache._content!.annotation(segment.annotationId ?? '')?.colorIndex ?? 0,
              ),
            ));
            segmentHeight += measured.size.height;
          }
        }
        final sourceNames = {
          for (final segment in allSegments)
            if (cache._content!.annotation(segment.annotationId ?? '') case final annotation?)
              if (cache._content!.document(annotation.documentId) case final document?) document.title,
        };
        final sourceCount = allSegments.where((s) => s.annotationId != null).length;
        final meta = card.segments.length > 1 ? '${sourceNames.join('、')} · ${l.mergedSources(sourceCount)}' : source;
        final metaHeight = shownSegments.isEmpty || meta == null
            ? 0.0
            : cache._measure(meta, MMTypography.footnote, textWidth).size.height.clamp(0, scale(28)) + 6;
        final height =
            11 +
            shownTitle +
            (shownSegments.isEmpty
                ? lines * scale(20) + 12
                : segmentHeight + (shownSegments.length - 1) * 13 + metaHeight + 12) +
            toggle +
            11 +
            2;
        return _NodeSpec._(
          _Kind.excerpt,
          card.title,
          quote,
          meta,
          MMAnnotationColor.fromIndex(a?.colorIndex ?? 0),
          Size(cardWidth, height.toDouble()),
          label: card.title.isEmpty ? (clipped.isEmpty ? l.untitledExcerpt : clipped) : card.title,
          suspended: card.suspended,
          truncated: truncated,
          expanded: open,
          segments: shownSegments,
          maxLines: maxLines,
          resizable: true,
        );
    }
  }
}
