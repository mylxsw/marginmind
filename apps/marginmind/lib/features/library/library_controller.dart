import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';

enum LibraryViewMode { grid, list }

class LibraryViewState {
  const LibraryViewState({
    this.query = const LibraryQuery(),
    this.viewMode = LibraryViewMode.grid,
    this.selectedId,
    this.sidebarVisible = true,
  });

  final LibraryQuery query;
  final LibraryViewMode viewMode;
  final String? selectedId;
  final bool sidebarVisible;

  LibraryViewState copyWith({
    LibraryQuery? query,
    LibraryViewMode? viewMode,
    String? selectedId,
    bool clearSelection = false,
    bool? sidebarVisible,
  }) {
    return LibraryViewState(
      query: query ?? this.query,
      viewMode: viewMode ?? this.viewMode,
      selectedId: clearSelection ? null : (selectedId ?? this.selectedId),
      sidebarVisible: sidebarVisible ?? this.sidebarVisible,
    );
  }
}

/// UI state of the library window: filter, search, sort, view mode,
/// selection and sidebar visibility.
class LibraryViewController extends Notifier<LibraryViewState> {
  @override
  LibraryViewState build() => const LibraryViewState();

  void setFilter(LibraryFilter filter) =>
      state = state.copyWith(query: state.query.copyWith(filter: filter), clearSelection: true);

  void setSearch(String text) => state = state.copyWith(query: state.query.copyWith(search: text));

  void setSort(LibrarySort sort) => state = state.copyWith(query: state.query.copyWith(sort: sort));

  void cycleSort() {
    const order = LibrarySort.values;
    setSort(order[(order.indexOf(state.query.sort) + 1) % order.length]);
  }

  void setViewMode(LibraryViewMode mode) => state = state.copyWith(viewMode: mode);

  void select(String? id) => state = id == null ? state.copyWith(clearSelection: true) : state.copyWith(selectedId: id);

  void toggleSidebar() => state = state.copyWith(sidebarVisible: !state.sidebarVisible);

  /// Records the open and switches to the study set's workspace.
  Future<void> open(String id) async {
    await ref.read(studySetRepositoryProvider).markOpened(id);
    ref.read(navigationProvider.notifier).openStudySet(id);
  }
}

final libraryViewProvider = NotifierProvider<LibraryViewController, LibraryViewState>(LibraryViewController.new);
