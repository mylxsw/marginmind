import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../features/workspace/workspace_controller.dart';
import '../shared/l10n.dart';
import 'navigation.dart';
import 'providers.dart';

/// Whether [context]'s window shows a phone's bottom tabs: a phone in the
/// compact size class. An iPad in Split View keeps the Source | Map switch.
bool showsPhoneTabs(BuildContext context) =>
    MMInput.of(context).phone && MMSizeClass.of(context) == MMSizeClass.compact;

enum PhoneTab { library, source, map, review }

/// The tab a [route] belongs to; [mapShown] for a workspace on its map.
PhoneTab? phoneTabOf(AppRoute route, {bool mapShown = false}) => switch (route) {
  LibraryRoute() || StatsRoute(studySetId: null) => PhoneTab.library,
  WorkspaceRoute() => mapShown ? PhoneTab.map : PhoneTab.source,
  ReviewRoute() || StatsRoute() => PhoneTab.review,
  GalleryRoute() => null,
};

/// A phone's app navigation: Library, Source, Map and Review. The last
/// three belong to the study set opened last and wait for one.
class PhoneTabBar extends ConsumerWidget {
  const PhoneTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final route = ref.watch(navigationProvider);
    final navigation = ref.read(navigationProvider.notifier);
    final recent = navigation.recentStudySetId;
    final hasSet = recent != null && ref.watch(studySetProvider(recent)) != null;
    final mapShown =
        route is WorkspaceRoute &&
        ref.watch(workspaceProvider(route.studySetId).select((s) => s.layout == MMSplitMode.secondary));

    void select(int index) {
      final tab = PhoneTab.values[index];
      if (tab == PhoneTab.library) return navigation.showLibrary();
      final id = recent!;
      if (tab == PhoneTab.review) {
        if (route is! ReviewRoute || route.studySetId != id) navigation.startReview(id);
        return;
      }
      if (route is! WorkspaceRoute || route.studySetId != id) navigation.openStudySet(id);
      ref
          .read(workspaceProvider(id).notifier)
          .setLayout(tab == PhoneTab.map ? MMSplitMode.secondary : MMSplitMode.primary);
    }

    return MMTabBar(
      key: const ValueKey('phone-tabs'),
      tabs: [
        MMTab(icon: MMIcons.library, label: l.librarySection),
        MMTab(icon: MMIcons.reading, label: l.paneSource, enabled: hasSet),
        MMTab(icon: MMIcons.mindMap, label: l.paneMap, enabled: hasSet),
        MMTab(icon: MMIcons.review, label: l.review, enabled: hasSet),
      ],
      selected: phoneTabOf(route, mapShown: mapShown)?.index,
      onSelected: select,
    );
  }
}
