import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Top-level destinations. The library and each study set are separate
/// windows in the design; until Flutter's multi-window support is stable
/// they are routes inside one window, switched by this notifier.
sealed class AppRoute {
  const AppRoute();
}

class LibraryRoute extends AppRoute {
  const LibraryRoute();
}

class WorkspaceRoute extends AppRoute {
  const WorkspaceRoute(this.studySetId);

  final String studySetId;
}

/// Full-window review session for one study set.
class ReviewRoute extends AppRoute {
  const ReviewRoute(this.studySetId, {this.mapId, this.branchId, this.tag});

  final String? mapId;

  /// Review only this card's branch on [mapId], or only cards with [tag].
  final String? branchId;
  final String? tag;

  final String studySetId;
}

/// Review statistics of one study set, or of the whole library when null.
class StatsRoute extends AppRoute {
  const StatsRoute(this.studySetId);

  final String? studySetId;
}

class GalleryRoute extends AppRoute {
  const GalleryRoute({this.returnTo = const LibraryRoute()});

  final AppRoute returnTo;
}

class VocabularyRoute extends AppRoute {
  const VocabularyRoute({this.studySetId, this.entryId});
  final String? studySetId, entryId;
}

class AppNavigation extends Notifier<AppRoute> {
  @override
  AppRoute build() => const LibraryRoute();

  /// The study set last opened, reviewed or shown in statistics: a phone's
  /// Source, Map and Review tabs return to it from the library.
  String? get recentStudySetId => _recent;
  String? _recent;

  void showVocabulary({String? studySetId, String? entryId}) =>
      state = VocabularyRoute(studySetId: studySetId, entryId: entryId);

  void showLibrary() => state = const LibraryRoute();

  void openStudySet(String id) => state = WorkspaceRoute(_recent = id);

  void startReview(String id, {String? mapId, String? branchId, String? tag}) =>
      state = ReviewRoute(_recent = id, mapId: mapId, branchId: branchId, tag: tag);

  void showStats([String? studySetId]) {
    if (studySetId != null) _recent = studySetId;
    state = StatsRoute(studySetId);
  }

  void showGallery() {
    if (state is! GalleryRoute) state = GalleryRoute(returnTo: state);
  }

  void back() {
    final current = state;
    state = switch (current) {
      GalleryRoute() => current.returnTo,
      VocabularyRoute(:final studySetId?) => WorkspaceRoute(studySetId),
      StatsRoute(:final studySetId?) => WorkspaceRoute(studySetId),
      _ => const LibraryRoute(),
    };
  }
}

final navigationProvider = NotifierProvider<AppNavigation, AppRoute>(AppNavigation.new);

/// One-shot focus requests from menu commands (e.g. ⌘F) to whichever screen
/// owns the target field. Screens listen and call `requestFocus`.
enum FocusTarget { search, pageField }

class FocusRequests extends Notifier<(FocusTarget, int)?> {
  @override
  (FocusTarget, int)? build() => null;

  void request(FocusTarget target) => state = (target, (state?.$2 ?? 0) + 1);
}

final focusRequestsProvider = NotifierProvider<FocusRequests, (FocusTarget, int)?>(FocusRequests.new);
