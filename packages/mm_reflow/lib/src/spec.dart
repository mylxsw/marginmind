part of '../mm_reflow.dart';

/// Everything that can alter geometry or paint. Font digests must change after
/// font loading/fallback; callers await font loading before requesting layout.
@immutable
class LayoutSpec {
  const LayoutSpec({
    required this.width,
    this.pageHeight = 640,
    this.fontSize = 16,
    this.lineHeight = 1.5,
    this.padding = EdgeInsets.zero,
    this.fontFamily,
    this.fontDigest = '',
    this.locale = const Locale('en'),
    this.direction = TextDirection.ltr,
    this.textScale = 1,
    this.readerStyle = MMReaderStyle.white,
    this.engineVersion = 1,
  });
  final double width, pageHeight, fontSize, lineHeight, textScale;
  final EdgeInsets padding;
  final String? fontFamily;
  final String fontDigest;
  final Locale locale;
  final TextDirection direction;
  final MMReaderStyle readerStyle;
  final int engineVersion;
  double get contentWidth => width - padding.horizontal;
  double get contentHeight => pageHeight - padding.vertical;

  void validate() {
    if (![
          width,
          pageHeight,
          fontSize,
          lineHeight,
          textScale,
          contentWidth,
          contentHeight,
        ].every((v) => v.isFinite && v > 0) ||
        ![padding.left, padding.top, padding.right, padding.bottom].every((v) => v.isFinite && v >= 0)) {
      throw ArgumentError('Layout dimensions must be finite and positive');
    }
  }

  Object get _key => (
    width,
    pageHeight,
    fontSize,
    lineHeight,
    padding,
    fontFamily,
    fontDigest,
    locale,
    direction,
    textScale,
    readerStyle,
    engineVersion,
  );
  @override
  bool operator ==(Object other) => other is LayoutSpec && other._key == _key;
  @override
  int get hashCode => _key.hashCode;
}

/// Optional facts at the parser boundary, pending GUL-584's typed IR fields.
/// Keys are source paths, table block IDs and resource paths respectively.
/// Missing facts mean no container box, no repeated header, placeholder image.
/// [revision] must change whenever these facts or resource bytes change.
class LayoutResources {
  LayoutResources({
    this.revision = '',
    Map<String, String> fontFamilies = const {},
    Map<String, MMBookImage> images = const {},
    Map<String, Size> intrinsicSizes = const {},
    Map<String, Map<String, String>> containerStyles = const {},
    Map<String, int> headerRows = const {},
  }) : fontFamilies = Map.unmodifiable(fontFamilies),
       images = Map.unmodifiable(images),
       intrinsicSizes = Map.unmodifiable(intrinsicSizes),
       containerStyles = Map.unmodifiable(
         containerStyles.map((k, v) => MapEntry(k, Map<String, String>.unmodifiable(v))),
       ),
       headerRows = Map.unmodifiable(headerRows);
  final String revision;
  final Map<String, String> fontFamilies;
  final Map<String, MMBookImage> images;
  final Map<String, Size> intrinsicSizes;
  final Map<String, Map<String, String>> containerStyles;
  final Map<String, int> headerRows;

  // Image identity is essential: a newly decoded handle must never reuse a
  // paragraph that still borrows a previous (possibly disposed) handle.
  bool matches(LayoutResources other) =>
      revision == other.revision &&
      _sameMap(fontFamilies, other.fontFamilies) &&
      _sameMap(images, other.images) &&
      _sameMap(intrinsicSizes, other.intrinsicSizes) &&
      _sameMap(headerRows, other.headerRows) &&
      containerStyles.length == other.containerStyles.length &&
      containerStyles.entries.every((e) => _sameMap(e.value, other.containerStyles[e.key] ?? {}));
}

bool _sameMap<K, V>(Map<K, V> a, Map<K, V> b) =>
    a.length == b.length && a.entries.every((e) => b.containsKey(e.key) && b[e.key] == e.value);

/// A screen rectangle is valid only for the layout generation that produced it.
/// [page] is null in chapter coordinates; repeated headers are decorative and
/// never produce a second source anchor.
@immutable
class LayoutBox {
  const LayoutBox(this.rect, this.generation, {this.page});
  final Rect rect;
  final int generation;
  final int? page;
  Offset get center => rect.center;
}

/// A source-stable viewport bookmark. Persist [position]; the fraction is a
/// transient reading aid, never a persisted page number or screen coordinate.
class ViewportBookmark {
  const ViewportBookmark(this.position, this.lineFraction, {this.revision});
  final String? revision;
  final TextAnchor position;
  final double lineFraction;
}

/// Non-text interaction at an anchored range (link or EPUB footnote reference).
class LayoutLink {
  const LayoutLink(this.anchor, this.target, {this.footnote = false});
  final TextAnchor anchor;
  final String target;
  final bool footnote;
}
