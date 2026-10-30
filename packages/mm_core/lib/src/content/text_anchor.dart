import 'package:meta/meta.dart';

/// Half-open UTF-16 offsets in canonical chapter text, independent of layout.
@immutable
class TextAnchor {
  const TextAnchor(
    this.chapterId,
    this.start,
    this.end,
    this.quote, {
    this.prefix = '',
    this.suffix = '',
    this.revision = '',
    this.normalizationVersion = 1,
  });
  final String chapterId, quote, prefix, suffix, revision;
  final int start, end, normalizationVersion;
  void validate() {
    if (chapterId.isEmpty ||
        revision.isEmpty ||
        start < 0 ||
        end < start ||
        end - start != quote.length ||
        normalizationVersion != 1) {
      throw ArgumentError('Invalid text anchor');
    }
  }

  Map<String, Object?> toJson() => {
    'chapterId': chapterId,
    'start': start,
    'end': end,
    'quote': quote,
    'prefix': prefix,
    'suffix': suffix,
    'revision': revision,
    'normalizationVersion': normalizationVersion,
  };
  factory TextAnchor.fromJson(Map<String, Object?> j) {
    final anchor = TextAnchor(
      j['chapterId'] as String,
      j['start'] as int,
      j['end'] as int,
      j['quote'] as String,
      prefix: j['prefix'] as String? ?? '',
      suffix: j['suffix'] as String? ?? '',
      revision: j['revision'] as String? ?? '',
      normalizationVersion: j['normalizationVersion'] as int? ?? 1,
    );
    anchor.validate();
    return anchor;
  }
}

sealed class ReadingPosition {
  const ReadingPosition();
  Map<String, Object?> toJson();
  factory ReadingPosition.fromJson(Map<String, Object?> j) => switch (j['type']) {
    'pdf' => PdfPosition(j['page'] as int, y: (j['y'] as num?)?.toDouble()),
    'text' => TextReadingPosition(
      revision: j['revision'] as String,
      chapterId: j['chapterId'] as String,
      offset: j['offset'] as int,
      affinity: ReadingAffinity.values.byName(j['affinity'] as String? ?? 'downstream'),
    ),
    _ => throw const FormatException('Unknown reading position'),
  };
}

final class PdfPosition extends ReadingPosition {
  PdfPosition(this.page, {this.y}) {
    if (page < 1 || (y != null && (!y!.isFinite || y! < 0))) throw ArgumentError('Invalid page');
  }
  final int page;
  final double? y;
  @override
  Map<String, Object?> toJson() => {'type': 'pdf', 'page': page, if (y != null) 'y': y};
}

// Names avoid colliding with Flutter's TextPosition/TextAffinity.
enum ReadingAffinity { upstream, downstream }

final class TextReadingPosition extends ReadingPosition {
  TextReadingPosition({
    required this.revision,
    required this.chapterId,
    required this.offset,
    this.affinity = ReadingAffinity.downstream,
  }) {
    if (chapterId.isEmpty || revision.isEmpty || offset < 0) throw ArgumentError('Invalid text position');
  }
  final String revision, chapterId;
  final int offset;
  final ReadingAffinity affinity;
  @override
  Map<String, Object?> toJson() => {
    'type': 'text',
    'revision': revision,
    'chapterId': chapterId,
    'offset': offset,
    'affinity': affinity.name,
  };
}

/// Callers provide spine order; unrecognized chapters keep their existing order.
int compareReadingPositions(ReadingPosition a, ReadingPosition b, {List<String> chapters = const []}) {
  if (a is PdfPosition && b is PdfPosition) return a.page.compareTo(b.page);
  if (a is TextReadingPosition && b is TextReadingPosition) {
    if (a.chapterId == b.chapterId) return a.offset.compareTo(b.offset);
    final x = chapters.indexOf(a.chapterId), y = chapters.indexOf(b.chapterId);
    if (x >= 0 && y >= 0) return x.compareTo(y);
  }
  return 0;
}
