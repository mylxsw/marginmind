import 'package:meta/meta.dart';

import '../content/text_anchor.dart';

/// A study set groups documents, their annotations and the mind maps built
/// from them. On disk it will be one `.mmset` package.
@immutable
class StudySet {
  const StudySet({
    required this.id,
    required this.title,
    required this.colorIndex,
    required this.createdAt,
    required this.lastOpenedAt,
    this.folderId,
    this.starred = false,
    this.documentCount = 0,
    this.cardCount = 0,
    this.dueCount = 0,
    this.reviewLogCount = 0,
    this.readPages = 0,
    this.totalPages = 0,
    this.lastPosition,
  }) : assert(colorIndex >= 0 && colorIndex < 6);

  final String id;
  final String title;

  /// Index into the six annotation colors; never a raw color value, so
  /// themes and palettes can change without migrating data.
  final int colorIndex;
  final String? folderId;
  final bool starred;
  final int documentCount;
  final int cardCount;

  /// Cards whose review is due now.
  final int dueCount;

  /// Ratings recorded in the review log; statistics need at least one.
  final int reviewLogCount;
  final int readPages;
  final int totalPages;

  /// Human readable "where I stopped", e.g. a document title and page.
  final LastReadingPosition? lastPosition;
  final DateTime createdAt;
  final DateTime lastOpenedAt;

  /// Reading progress in the range 0–1.
  double get progress => totalPages == 0 ? 0 : (readPages / totalPages).clamp(0.0, 1.0);

  StudySet copyWith({
    String? title,
    int? colorIndex,
    String? folderId,
    bool clearFolder = false,
    bool? starred,
    int? documentCount,
    int? cardCount,
    int? dueCount,
    int? reviewLogCount,
    int? readPages,
    int? totalPages,
    LastReadingPosition? lastPosition,
    DateTime? lastOpenedAt,
  }) {
    return StudySet(
      id: id,
      title: title ?? this.title,
      colorIndex: colorIndex ?? this.colorIndex,
      folderId: clearFolder ? null : (folderId ?? this.folderId),
      starred: starred ?? this.starred,
      documentCount: documentCount ?? this.documentCount,
      cardCount: cardCount ?? this.cardCount,
      dueCount: dueCount ?? this.dueCount,
      reviewLogCount: reviewLogCount ?? this.reviewLogCount,
      readPages: readPages ?? this.readPages,
      totalPages: totalPages ?? this.totalPages,
      lastPosition: lastPosition ?? this.lastPosition,
      createdAt: createdAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }
}

@immutable
class LastReadingPosition {
  const LastReadingPosition({required this.documentTitle, int? page, this.position})
    // Keep the existing public named page parameter.
    // ignore: prefer_initializing_formals
    : _page = page;
  final ReadingPosition? position;

  final String documentTitle;
  final int? _page;
  int get page => position is TextReadingPosition
      ? (throw StateError('Text progress has no page'))
      : position is PdfPosition
      ? (position as PdfPosition).page
      : _page!;
}

/// Input for creating a study set.
@immutable
class NewStudySet {
  const NewStudySet({required this.title, required this.colorIndex, this.folderId});

  final String title;
  final int colorIndex;
  final String? folderId;
}
