import 'package:meta/meta.dart';

import 'study_set.dart';

/// Which slice of the library the sidebar selected.
sealed class LibraryFilter {
  const LibraryFilter();

  static const all = AllFilter();
  static const recent = RecentFilter();
  static const starred = StarredFilter();
  static const due = DueFilter();
}

class AllFilter extends LibraryFilter {
  const AllFilter();
}

/// The most recently opened study sets.
class RecentFilter extends LibraryFilter {
  const RecentFilter({this.limit = 4});

  final int limit;
}

class StarredFilter extends LibraryFilter {
  const StarredFilter();
}

/// Study sets that have cards due for review.
class DueFilter extends LibraryFilter {
  const DueFilter();
}

/// A user folder; `folderId == null` means "Unfiled".
@immutable
class FolderFilter extends LibraryFilter {
  const FolderFilter(this.folderId);

  final String? folderId;

  @override
  bool operator ==(Object other) => other is FolderFilter && other.folderId == folderId;

  @override
  int get hashCode => folderId.hashCode;
}

enum LibrarySort { recent, title, cardCount }

/// Pure filtering, searching and sorting of the library. Kept out of the UI
/// so it can be unit tested and reused by the menu bar and Spotlight later.
@immutable
class LibraryQuery {
  const LibraryQuery({this.filter = LibraryFilter.all, this.search = '', this.sort = LibrarySort.recent});

  final LibraryFilter filter;
  final String search;
  final LibrarySort sort;

  LibraryQuery copyWith({LibraryFilter? filter, String? search, LibrarySort? sort}) {
    return LibraryQuery(filter: filter ?? this.filter, search: search ?? this.search, sort: sort ?? this.sort);
  }

  List<StudySet> apply(List<StudySet> sets) {
    final needle = search.trim().toLowerCase();
    Iterable<StudySet> result = sets;

    switch (filter) {
      case AllFilter():
        break;
      case RecentFilter(:final limit):
        final byRecent = [...sets]..sort(_byRecent);
        result = byRecent.take(limit);
      case StarredFilter():
        result = result.where((s) => s.starred);
      case DueFilter():
        result = result.where((s) => s.dueCount > 0);
      case FolderFilter(:final folderId):
        result = result.where((s) => s.folderId == folderId);
    }

    if (needle.isNotEmpty) {
      result = result.where((s) => s.title.toLowerCase().contains(needle));
    }

    final list = result.toList();
    switch (sort) {
      case LibrarySort.recent:
        list.sort(_byRecent);
      case LibrarySort.title:
        list.sort((a, b) => a.title.compareTo(b.title));
      case LibrarySort.cardCount:
        list.sort((a, b) => b.cardCount.compareTo(a.cardCount));
    }
    return list;
  }

  static int _byRecent(StudySet a, StudySet b) => b.lastOpenedAt.compareTo(a.lastOpenedAt);
}
