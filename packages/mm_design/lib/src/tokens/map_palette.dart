import 'package:flutter/widgets.dart';

import 'colors.dart';

/// How a mind map draws its first-level topics.
enum MMTopicStyle {
  /// The topic fill of the system look.
  plain,

  /// Filled with the branch color.
  fill,

  /// A light wash of the branch color.
  tint,

  /// The canvas, outlined in the branch color.
  outline,
}

/// The colors of one mind map palette in one appearance: the center topic,
/// first-level topics, branch lines and summaries. Excerpt color bars,
/// highlights and relation lines keep their own colors in every palette.
@immutable
class MMMapColors {
  const MMMapColors({
    required this.root,
    required this.onRoot,
    this.branches = const [],
    this.topicStyle = MMTopicStyle.plain,
    this.summary,
    this.onSummary,
  });

  final Color root;
  final Color onRoot;

  /// Taken in turn by the center topic's branches; empty for the system look
  /// (lines in [MMColors.line]).
  final List<Color> branches;
  final MMTopicStyle topicStyle;

  /// Summary fill and text; null keeps the system look (a topic fill).
  final Color? summary;
  final Color? onSummary;

  /// Lighter text on dark fills, darker text on light ones.
  static const _darkText = Color(0xFF1D1D1F);
  static const _lightText = Color(0xFFFFFFFF);

  /// The color of the branch at [index] among the center topic's children
  /// (cycling), or null for the system look.
  Color? branch(int index) => branches.isEmpty ? null : branches[index % branches.length];

  /// Line color of the branch at [index]: the system's [MMColors.line]
  /// without branch colors.
  Color line(int index, MMColors colors) => branch(index) ?? colors.line;

  /// The fill of a first-level topic of the branch at [index] on [colors].
  Color topicFill(int index, MMColors colors) {
    final plain = Color.alphaBlend(colors.fill, colors.canvas);
    final color = branch(index);
    if (color == null) return plain;
    return switch (topicStyle) {
      MMTopicStyle.plain => plain,
      MMTopicStyle.fill => color,
      MMTopicStyle.tint => Color.alphaBlend(color.withValues(alpha: tintAlpha(colors.brightness)), colors.canvas),
      MMTopicStyle.outline => colors.canvas,
    };
  }

  /// The text on [topicFill]: whichever of near-black and white reads better
  /// on a filled topic, the label color otherwise.
  Color topicText(int index, MMColors colors) {
    final color = branch(index);
    if (color == null || topicStyle != MMTopicStyle.fill) return colors.label;
    return contrastRatio(_darkText, color) >= contrastRatio(_lightText, color) ? _darkText : _lightText;
  }

  /// The outline of a first-level topic, if the palette draws one.
  Color? topicBorder(int index) => topicStyle == MMTopicStyle.outline ? branch(index) : null;

  /// How much of the branch color a tinted topic shows.
  static double tintAlpha(Brightness brightness) => brightness == Brightness.dark ? 0.34 : 0.2;
}

/// The six mind map palettes (design canvas 03 · mind map styles), each in a
/// light and a dark version. Text on every fill reaches 4.5:1 (tokens_test).
@immutable
class MMMapPalette {
  const MMMapPalette._(this.name, this.light, this.dark);

  /// Matches the stored palette name.
  final String name;
  final MMMapColors light;
  final MMMapColors dark;

  MMMapColors of(Brightness brightness) => brightness == Brightness.dark ? dark : light;

  /// The current look: dark center topic, neutral topics and lines.
  static const system = MMMapPalette._(
    'system',
    MMMapColors(root: Color(0xFF1D1D1F), onRoot: Color(0xFFFFFFFF)),
    MMMapColors(root: Color(0xFFF5F5F7), onRoot: Color(0xFF1D1D1F)),
  );

  static const rainbow = MMMapPalette._(
    'rainbow',
    MMMapColors(
      root: Color(0xFF1F2A6B),
      onRoot: Color(0xFFFFFFFF),
      branches: [
        Color(0xFFF2C14E),
        Color(0xFFE07A5F),
        Color(0xFF3D5A99),
        Color(0xFF81B29A),
        Color(0xFFA57BE3),
        Color(0xFF4FB0C6),
      ],
      topicStyle: MMTopicStyle.fill,
      summary: Color(0xFFE07A5F),
      onSummary: Color(0xFF1D1D1F),
    ),
    MMMapColors(
      root: Color(0xFF3D4DB0),
      onRoot: Color(0xFFFFFFFF),
      branches: [
        Color(0xFFF2C14E),
        Color(0xFFE07A5F),
        Color(0xFF6F8BD0),
        Color(0xFF81B29A),
        Color(0xFFA57BE3),
        Color(0xFF4FB0C6),
      ],
      topicStyle: MMTopicStyle.fill,
      summary: Color(0xFFE07A5F),
      onSummary: Color(0xFF1D1D1F),
    ),
  );

  static const fresh = MMMapPalette._(
    'fresh',
    MMMapColors(
      root: Color(0xFF1E7F74),
      onRoot: Color(0xFFFFFFFF),
      branches: _freshBranches,
      topicStyle: MMTopicStyle.tint,
      summary: Color(0xFF2A9D8F),
      onSummary: Color(0xFF1D1D1F),
    ),
    MMMapColors(
      root: Color(0xFF48C9B0),
      onRoot: Color(0xFF1D1D1F),
      branches: _freshBranches,
      topicStyle: MMTopicStyle.tint,
      summary: Color(0xFF2A9D8F),
      onSummary: Color(0xFF1D1D1F),
    ),
  );
  static const _freshBranches = [
    Color(0xFF2A9D8F),
    Color(0xFF5DADE2),
    Color(0xFF8AB17D),
    Color(0xFF48C9B0),
    Color(0xFF7FB3D5),
    Color(0xFFA3C4BC),
  ];

  static const warm = MMMapPalette._(
    'warm',
    MMMapColors(
      root: Color(0xFFB5452E),
      onRoot: Color(0xFFFFFFFF),
      branches: _warmBranches,
      topicStyle: MMTopicStyle.tint,
      summary: Color(0xFFB5452E),
      onSummary: Color(0xFFFFFFFF),
    ),
    MMMapColors(
      root: Color(0xFFE58A6F),
      onRoot: Color(0xFF1D1D1F),
      branches: _warmBranches,
      topicStyle: MMTopicStyle.tint,
      summary: Color(0xFFE58A6F),
      onSummary: Color(0xFF1D1D1F),
    ),
  );
  static const _warmBranches = [
    Color(0xFFE76F51),
    Color(0xFFF4A261),
    Color(0xFFE9C46A),
    Color(0xFFC08552),
    Color(0xFFD4A373),
    Color(0xFFBC6C25),
  ];

  static const morandi = MMMapPalette._(
    'morandi',
    MMMapColors(
      root: Color(0xFF5C5F55),
      onRoot: Color(0xFFFFFFFF),
      branches: _morandiBranches,
      topicStyle: MMTopicStyle.fill,
      summary: Color(0xFF9A8C98),
      onSummary: Color(0xFF1D1D1F),
    ),
    MMMapColors(
      root: Color(0xFF8A8D80),
      onRoot: Color(0xFF1D1D1F),
      branches: _morandiBranches,
      topicStyle: MMTopicStyle.fill,
      summary: Color(0xFF9A8C98),
      onSummary: Color(0xFF1D1D1F),
    ),
  );
  static const _morandiBranches = [
    Color(0xFFA5A58D),
    Color(0xFFCB997E),
    Color(0xFF9A8C98),
    Color(0xFF6B9080),
    Color(0xFFB7B7A4),
    Color(0xFFC9ADA7),
  ];

  /// Black and white, for printing.
  static const ink = MMMapPalette._(
    'ink',
    MMMapColors(
      root: Color(0xFF000000),
      onRoot: Color(0xFFFFFFFF),
      branches: [Color(0xFF3A3A3C)],
      topicStyle: MMTopicStyle.outline,
      summary: Color(0xFF3A3A3C),
      onSummary: Color(0xFFFFFFFF),
    ),
    MMMapColors(
      root: Color(0xFFFFFFFF),
      onRoot: Color(0xFF000000),
      branches: [Color(0xFFD1D1D6)],
      topicStyle: MMTopicStyle.outline,
      summary: Color(0xFFD1D1D6),
      onSummary: Color(0xFF1D1D1F),
    ),
  );

  /// In the order offered to the user.
  static const values = [system, rainbow, fresh, warm, morandi, ink];

  /// The palette stored as [name]; the system look for an unknown one.
  static MMMapPalette byName(String name) => values.firstWhere((p) => p.name == name, orElse: () => system);
}
