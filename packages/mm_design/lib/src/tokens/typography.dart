import 'package:flutter/painting.dart';

/// macOS text styles. The family is left null so Flutter uses the system UI
/// font on macOS (SF Pro + PingFang); other platforms get the fallbacks.
abstract final class MMTypography {
  static const List<String> _sansFallback = ['PingFang SC', 'Noto Sans CJK SC', 'Noto Sans SC', 'Microsoft YaHei'];
  static const List<String> _serifFallback = ['Noto Serif CJK SC', 'Noto Serif SC', 'STSong', 'SimSun'];

  static const TextStyle _base = TextStyle(
    fontFamilyFallback: _sansFallback,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static final largeTitle = _base.copyWith(fontSize: 26, height: 32 / 26, fontWeight: FontWeight.w400);
  static final phoneLargeTitle = _base.copyWith(
    fontSize: 34,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );
  static final title2 = _base.copyWith(fontSize: 20, height: 26 / 20, fontWeight: FontWeight.w700);
  static final title3 = _base.copyWith(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w600);
  static final headline = _base.copyWith(fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w600);
  static final body = _base.copyWith(fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w400);
  static final callout = _base.copyWith(fontSize: 12, height: 15 / 12, fontWeight: FontWeight.w500);
  static final subheadline = _base.copyWith(fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w600);
  static final footnote = _base.copyWith(fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w400);

  /// Source text: books speak in Songti, the user speaks in the system font.
  static const readingBody = TextStyle(
    fontFamily: 'Songti SC',
    fontFamilyFallback: _serifFallback,
    fontSize: 16.5,
    height: 32 / 16.5,
  );
  static const readingExcerpt = TextStyle(
    fontFamily: 'Songti SC',
    fontFamilyFallback: _serifFallback,
    fontSize: 13,
    height: 20 / 13,
  );
  static const mono = TextStyle(
    fontFamily: 'SF Mono',
    fontFamilyFallback: ['Menlo', 'JetBrains Mono', 'Consolas', 'monospace'],
    fontSize: 12,
    height: 16 / 12,
  );
}

abstract final class MMReaderTypography {
  static const fontSizes = [13.0, 14.5, 15.5, 16.5, 18.0, 20.0, 22.0, 25.0];
  static const defaultSize = 3;
  static const defaultSizePhone = 4;
  static const lineHeights = [1.6, 1.9, 2.2];
  static const serif = 'Songti SC';
  static const sans = 'Noto Sans';
}

abstract final class MMNoteTypography {
  static final title = MMTypography.title2.copyWith(fontSize: 24, height: 31 / 24);
  static final heading = MMTypography.headline.copyWith(fontSize: 17, height: 22 / 17);
  static final body = MMTypography.body.copyWith(fontSize: 14, height: 24.5 / 14);
  static final quote = MMTypography.readingBody.copyWith(fontSize: 15, height: 27.75 / 15);
  static final context = MMTypography.readingBody.copyWith(fontSize: 14, height: 26 / 14);
}
