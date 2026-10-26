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

class GalleryRoute extends AppRoute {
  const GalleryRoute({this.returnTo = const LibraryRoute()});

  final AppRoute returnTo;
}

class AppNavigation extends Notifier<AppRoute> {
  @override
  AppRoute build() => const LibraryRoute();

  void showLibrary() => state = const LibraryRoute();

  void openStudySet(String id) => state = WorkspaceRoute(id);

  void startReview(String id, {String? mapId, String? branchId, String? tag}) =>
      state = ReviewRoute(id, mapId: mapId, branchId: branchId, tag: tag);

  void showGallery() {
    if (state is! GalleryRoute) state = GalleryRoute(returnTo: state);
  }

  void back() {
    final current = state;
    state = current is GalleryRoute ? current.returnTo : const LibraryRoute();
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
