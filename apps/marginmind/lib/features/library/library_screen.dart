import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../app/app.dart';
import '../../app/app_commands.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../settings/settings_window.dart';
import '../../shared/l10n.dart';
import '../../shared/pdf_drop.dart';
import '../workspace/widgets/notices.dart';
import 'library_controller.dart';
import 'new_study_set.dart';
import 'sample_study_set.dart';
import 'widgets/continue_card.dart';
import 'widgets/study_set_card.dart';
import 'widgets/study_set_list.dart';

/// The first window: every study set, filters in the sidebar, icon or list
/// view, search and "new study set" (design canvas artboard 00).
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  late final TextEditingController _search;
  final _searchFocus = FocusNode();

  /// Whether the sidebar drawer of a touch window is out.
  bool _drawer = false;

  void _setDrawer(bool open) {
    if (_drawer != open) setState(() => _drawer = open);
  }

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(libraryViewProvider).query.search);
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String _filterTitle(LibraryFilter filter, List<Folder> folders) {
    final l = context.l10n;
    return switch (filter) {
      AllFilter() => l.libraryTitleAll,
      RecentFilter() => l.libraryRecent,
      StarredFilter() => l.libraryStarred,
      DueFilter() => l.libraryDue,
      FolderFilter(:final folderId) => folders.where((f) => f.id == folderId).firstOrNull?.name ?? l.libraryUnfiled,
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(focusRequestsProvider, (_, next) {
      if (next?.$1 == FocusTarget.search) _searchFocus.requestFocus();
    });
    // On touch the sidebar is a drawer: its commands move the drawer, and
    // picking a filter puts it away.
    final touchPlatform = MMInput.of(context).touchPlatform;
    ref.listen(libraryViewProvider.select((v) => v.sidebarVisible), (_, _) {
      if (touchPlatform) _setDrawer(!_drawer);
    });
    ref.listen(libraryViewProvider.select((v) => v.query.filter), (_, _) {
      if (touchPlatform) _setDrawer(false);
    });
    final sizeClass = MMSizeClass.of(context);

    final l = context.l10n;
    final view = ref.watch(libraryViewProvider);
    final controller = ref.read(libraryViewProvider.notifier);
    final sets = ref.watch(studySetsProvider).value ?? const <StudySet>[];
    final folders = ref.watch(foldersProvider).value ?? const <Folder>[];
    final now = ref.watch(clockProvider)();
    final visible = view.query.apply(sets);
    final dueTotal = sets.fold<int>(0, (n, s) => n + s.dueCount);

    // An empty library or result says so in the body; no "No study sets".
    final subtitle = visible.isEmpty
        ? null
        : [l.librarySetCount(visible.length), if (dueTotal > 0) l.libraryDueCount(dueTotal)].join(' · ');

    final sortLabel = switch (view.query.sort) {
      LibrarySort.recent => l.sortRecent,
      LibrarySort.title => l.sortTitle,
      LibrarySort.cardCount => l.sortCards,
    };

    return MMWindowScaffold(
      sidebarVisible: touchPlatform ? _drawer : view.sidebarVisible,
      sidebarOverlay: touchPlatform,
      onSidebarDismiss: () => _setDrawer(false),
      onDragStart: WindowChrome.onDragStart,
      onTitleDoubleTap: WindowChrome.onTitleDoubleTap,
      showsWindowButtons: WindowChrome.showsWindowButtons,
      sidebar: _LibrarySidebar(sets: sets, folders: folders, filter: view.query.filter),
      toolbar: MMToolbar(
        title: _filterTitle(view.query.filter, folders),
        subtitle: subtitle,
        leading: view.sidebarVisible && !touchPlatform
            ? null
            : MMIconButton(
                icon: MMIcons.sidebar,
                tooltip: l.showSidebar,
                size: context.mmToolbarIcon,
                onPressed: touchPlatform ? () => _setDrawer(true) : controller.toggleSidebar,
              ),
        actions: [
          if (sizeClass != MMSizeClass.compact) ...[
            MMToolbarGroup(
              children: [
                MMToolbarButton(
                  icon: MMIcons.grid,
                  tooltip: AppShortcuts.tip(l.viewAsIcons, AppShortcuts.view1),
                  selected: view.viewMode == LibraryViewMode.grid,
                  onPressed: () => controller.setViewMode(LibraryViewMode.grid),
                ),
                MMToolbarButton(
                  icon: MMIcons.list,
                  tooltip: AppShortcuts.tip(l.viewAsList, AppShortcuts.view2),
                  selected: view.viewMode == LibraryViewMode.list,
                  onPressed: () => controller.setViewMode(LibraryViewMode.list),
                ),
              ],
            ),
            MMToolbarGroup(
              children: [
                MMToolbarButton(
                  icon: MMIcons.sort,
                  label: sizeClass == MMSizeClass.regular ? l.sortBy(sortLabel) : null,
                  tooltip: sizeClass == MMSizeClass.regular ? l.sortTooltip : l.sortBy(sortLabel),
                  onPressed: controller.cycleSort,
                ),
              ],
            ),
          ],
          MMToolbarSearchField(
            placeholder: l.search,
            controller: _search,
            focusNode: _searchFocus,
            onChanged: controller.setSearch,
            width: sizeClass == MMSizeClass.compact ? MMSizes.compactSearchWidth : 200,
          ),
          MMToolbarGroup(
            children: [
              MMToolbarButton(
                icon: MMIcons.add,
                tooltip: AppShortcuts.tip(l.newStudySet, AppShortcuts.newStudySet),
                onPressed: () => newStudySetFromPdfs(context, ref),
              ),
            ],
          ),
        ],
      ),
      body: PdfDropTarget(
        label: l.dropToCreateSet,
        onDrop: (files) async {
          final notice = await controller.createFromFiles(files);
          if (context.mounted) showNotice(context, notice, rootTitle: '');
        },
        child: _LibraryBody(sets: sets, visible: visible, folders: folders, view: view, now: now),
      ),
    );
  }
}

class _LibrarySidebar extends ConsumerWidget {
  const _LibrarySidebar({required this.sets, required this.folders, required this.filter});

  final List<StudySet> sets;
  final List<Folder> folders;
  final LibraryFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final controller = ref.read(libraryViewProvider.notifier);
    final starred = sets.where((s) => s.starred).length;
    final due = sets.fold<int>(0, (n, s) => n + s.dueCount);
    final hasLogs = sets.any((s) => s.reviewLogCount > 0);
    final hasUnfiled = sets.any((s) => s.folderId == null);

    MMSidebarItem item(IconData icon, String label, LibraryFilter f, {Widget? trailing}) => MMSidebarItem(
      icon: icon,
      label: label,
      trailing: trailing,
      selected: filter == f,
      onTap: () => controller.setFilter(f),
    );
    // Like Finder and Mail: only a non-zero count says something. "Recent"
    // has no count of its own.
    Widget? count(int n) => n > 0 ? MMCount(n) : null;

    return MMSidebar(
      topTrailing: MMIconButton(
        icon: MMIcons.sidebar,
        tooltip: AppShortcuts.tip(l.hideSidebar, AppShortcuts.toggleSidebar),
        onPressed: controller.toggleSidebar,
      ),
      footer: Row(
        children: [
          const Spacer(),
          MMIconButton(
            icon: MMIcons.settings,
            tooltip: AppShortcuts.tip(l.settingsTitle, AppShortcuts.settings),
            onPressed: () => showSettings(context),
          ),
        ],
      ),
      children: [
        MMSidebarSection(
          title: l.librarySection,
          children: [
            item(MMIcons.grid, l.libraryTitleAll, LibraryFilter.all, trailing: count(sets.length)),
            item(MMIcons.recent, l.libraryRecent, LibraryFilter.recent),
            item(MMIcons.star, l.libraryStarred, LibraryFilter.starred, trailing: count(starred)),
            item(MMIcons.review, l.libraryDue, LibraryFilter.due, trailing: due > 0 ? MMBadge('$due') : null),
          ],
        ),
        if (hasLogs)
          MMSidebarSection(
            title: l.sectionLearn,
            children: [
              MMSidebarItem(
                key: const ValueKey('library-statistics'),
                icon: MMIcons.statistics,
                label: l.statistics,
                onTap: () => ref.read(navigationProvider.notifier).showStats(),
              ),
            ],
          ),
        if (folders.isNotEmpty || hasUnfiled)
          MMSidebarSection(
            title: l.libraryFolders,
            children: [
              for (final f in folders)
                item(
                  MMIcons.folder,
                  f.name,
                  FolderFilter(f.id),
                  trailing: count(sets.where((s) => s.folderId == f.id).length),
                ),
              if (hasUnfiled)
                item(
                  MMIcons.folder,
                  l.libraryUnfiled,
                  const FolderFilter(null),
                  trailing: count(sets.where((s) => s.folderId == null).length),
                ),
            ],
          ),
      ],
    );
  }
}

class _LibraryBody extends ConsumerStatefulWidget {
  const _LibraryBody({
    required this.sets,
    required this.visible,
    required this.folders,
    required this.view,
    required this.now,
  });

  final List<StudySet> sets;
  final List<StudySet> visible;
  final List<Folder> folders;
  final LibraryViewState view;
  final DateTime now;

  @override
  ConsumerState<_LibraryBody> createState() => _LibraryBodyState();
}

class _LibraryBodyState extends ConsumerState<_LibraryBody> {
  /// Clicking an item also takes keyboard focus, so ↩ / ⌘↓ / Esc act on the
  /// selection like in Finder.
  final _focus = FocusNode(debugLabel: 'LibraryBody');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sets = widget.sets;
    final visible = widget.visible;
    final folders = widget.folders;
    final view = widget.view;
    final now = widget.now;
    final l = context.l10n;
    final t = context.mmText;
    final controller = ref.read(libraryViewProvider.notifier);

    // Dropping PDFs works here too; the drop target's hover state shows it.
    if (sets.isEmpty) {
      return MMEmptyState(
        icon: MMIcons.studySet,
        actions: [
          MMButton(
            label: l.newStudySet,
            variant: MMButtonVariant.primary,
            onPressed: () => newStudySetFromPdfs(context, ref),
          ),
          MMButton(
            label: l.openSample,
            onPressed: () async {
              try {
                final id = await createSampleStudySet(ref, l);
                await controller.open(id);
              } catch (error) {
                if (context.mounted) MMHud.show(context, l.somethingWentWrong, icon: MMIcons.close);
              }
            },
          ),
        ],
      );
    }
    if (visible.isEmpty) {
      final search = view.query.search.trim();
      return MMEmptyState(
        title: l.noResultTitle,
        message: search.isNotEmpty ? l.noResultSearch(search) : l.noResultFilter,
      );
    }

    final showContinue =
        view.viewMode == LibraryViewMode.grid && view.query.filter is AllFilter && view.query.search.trim().isEmpty;
    final recent = ([...sets]..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt))).take(3).toList();

    void open(String id) => controller.open(id);

    Future<void> confirmDelete(StudySet s) async {
      final ok = await showConfirmSheet(
        context,
        title: l.deleteStudySetTitle(s.title),
        message: l.deleteStudySetMessage,
        confirmLabel: l.delete,
      );
      if (!ok) return;
      await controller.delete(s.id);
      if (context.mounted) MMHud.show(context, l.deletedHud(s.title), icon: MMIcons.trash);
    }

    void showMenu(String id, Offset position) {
      final s = sets.where((x) => x.id == id).firstOrNull;
      if (s == null) return;
      _focus.requestFocus();
      controller.select(id);
      final repo = ref.read(studySetRepositoryProvider);
      showMMMenu(
        context,
        position: position,
        entries: [
          MMMenuItem(l.open, () => open(id)),
          if (s.dueCount > 0)
            MMMenuItem(l.reviewCount(s.dueCount), () async {
              await repo.markOpened(id);
              ref.read(navigationProvider.notifier).startReview(id);
            }),
          const MMMenuDivider(),
          MMMenuItem(l.renameEllipsis, () async {
            final title = await showRenameSheet(context, title: l.renameStudySet, initial: s.title);
            if (title != null && title.isNotEmpty) await repo.rename(id, title);
          }),
          MMMenuItem(s.starred ? l.unstar : l.star, () => repo.setStarred(id, starred: !s.starred)),
          const MMMenuDivider(),
          MMMenuItem(l.deleteEllipsis, () => confirmDelete(s), destructive: true),
        ],
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (view.selectedId != null) open(view.selectedId!);
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown, meta: true): () {
          if (view.selectedId != null) open(view.selectedId!);
        },
        const SingleActivator(LogicalKeyboardKey.escape): () => controller.select(null),
        const SingleActivator(LogicalKeyboardKey.backspace, meta: true): () {
          final s = sets.where((x) => x.id == view.selectedId).firstOrNull;
          if (s != null) confirmDelete(s);
        },
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Builder(
          builder: (_) {
            void select(String? id) {
              _focus.requestFocus();
              controller.select(id);
            }

            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => select(null),
              child: CustomScrollView(
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  if (showContinue) ...[
                    _heading(l.libraryContinue, t),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 420,
                          mainAxisExtent: 88,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        delegate: SliverChildListDelegate([
                          for (final s in recent) ContinueCard(set: s, onOpen: () => open(s.id)),
                        ]),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 28)),
                    _heading(l.libraryAllHeading, t),
                  ],
                  if (view.viewMode == LibraryViewMode.grid)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(23, 0, 23, 48),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 230,
                          mainAxisExtent: 206,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 18,
                        ),
                        delegate: SliverChildBuilderDelegate(childCount: visible.length, (context, i) {
                          final s = visible[i];
                          return GestureDetector(
                            onSecondaryTapUp: (d) => showMenu(s.id, d.globalPosition),
                            child: StudySetCard(
                              set: s,
                              now: now,
                              selected: s.id == view.selectedId,
                              onSelect: () => select(s.id),
                              onOpen: () => open(s.id),
                              onToggleStar: () =>
                                  ref.read(studySetRepositoryProvider).setStarred(s.id, starred: !s.starred),
                            ),
                          );
                        }),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
                      sliver: SliverToBoxAdapter(
                        child: StudySetList(
                          sets: visible,
                          folders: folders,
                          sort: view.query.sort,
                          selectedId: view.selectedId,
                          now: now,
                          onSort: controller.setSort,
                          onSelect: select,
                          onOpen: open,
                          onContextMenu: showMenu,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _heading(String text, MMTextStyles t) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(28, 4, 28, 12),
    sliver: SliverToBoxAdapter(
      child: Semantics(
        header: true,
        child: Text(text, style: t.title2.copyWith(fontSize: 17, height: 22 / 17)),
      ),
    ),
  );
}
