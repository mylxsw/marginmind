import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../features/library/library_controller.dart';
import '../features/library/widgets/new_study_set_sheet.dart';
import '../features/workspace/widgets/notices.dart';
import '../features/workspace/workspace_controller.dart';
import '../settings/settings_sheet.dart';
import '../shared/l10n.dart';
import 'navigation.dart';

/// A user-invocable command: one definition feeds the macOS menu bar,
/// keyboard shortcuts on other platforms and tooltips.
class AppCommand {
  const AppCommand(this.label, this.onInvoke, {this.shortcut});

  final String label;
  final SingleActivator? shortcut;

  /// Null disables the command in the current context.
  final VoidCallback? onInvoke;
}

/// Global shortcuts. Defined in macOS terms; [primaryShortcut] swaps ⌘ for
/// Ctrl on Windows and Linux.
abstract final class AppShortcuts {
  static SingleActivator get settings => primaryShortcut(LogicalKeyboardKey.comma);
  static SingleActivator get newStudySet => primaryShortcut(LogicalKeyboardKey.keyN);
  static SingleActivator get showLibrary => primaryShortcut(LogicalKeyboardKey.keyL, shift: true);
  static SingleActivator get find => primaryShortcut(LogicalKeyboardKey.keyF);
  static SingleActivator get toggleSidebar => primaryShortcut(LogicalKeyboardKey.keyS, control: true);
  static SingleActivator get view1 => primaryShortcut(LogicalKeyboardKey.digit1);
  static SingleActivator get view2 => primaryShortcut(LogicalKeyboardKey.digit2);
  static SingleActivator get view3 => primaryShortcut(LogicalKeyboardKey.digit3);
  static SingleActivator get importDocument => primaryShortcut(LogicalKeyboardKey.keyO);
  static SingleActivator get addTopic => primaryShortcut(LogicalKeyboardKey.keyN, shift: true);
  static SingleActivator get addNote => primaryShortcut(LogicalKeyboardKey.keyN, alt: true);
  static SingleActivator get revealSource => primaryShortcut(LogicalKeyboardKey.keyL);
  static SingleActivator get gallery => primaryShortcut(LogicalKeyboardKey.keyG, alt: true);

  /// "Tooltip (⌘1)".
  static String tip(String label, SingleActivator shortcut) => '$label（${describeShortcut(shortcut)}）';
}

/// Installs the menu bar (macOS) or equivalent shortcuts (elsewhere) for
/// the current route.
class AppMenus extends ConsumerWidget {
  const AppMenus({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final route = ref.watch(navigationProvider);
    final nav = ref.read(navigationProvider.notifier);
    final inLibrary = route is LibraryRoute;
    final workspaceId = route is WorkspaceRoute ? route.studySetId : null;
    final inWorkspace = workspaceId != null;

    final settings = AppCommand(l.settings, () => showSettingsSheet(context), shortcut: AppShortcuts.settings);
    final file = [
      AppCommand(l.showLibrary, inLibrary ? null : nav.showLibrary, shortcut: AppShortcuts.showLibrary),
      AppCommand(
        l.newStudySet,
        inLibrary ? () => showNewStudySetSheet(context, ref) : null,
        shortcut: AppShortcuts.newStudySet,
      ),
      AppCommand(
        l.importDocument,
        inWorkspace ? () => pickAndImportDocuments(context, ref, workspaceId) : null,
        shortcut: AppShortcuts.importDocument,
      ),
    ];
    final workspace = inWorkspace ? ref.read(workspaceProvider(workspaceId).notifier) : null;
    final selected = inWorkspace ? ref.watch(workspaceProvider(workspaceId)).selectedCardId : null;
    final map = <AppCommand>[
      AppCommand(
        l.addTopic,
        workspace == null ? null : () => workspace.addTopic(l.newTopicName),
        shortcut: AppShortcuts.addTopic,
      ),
      AppCommand(
        l.addNote,
        workspace == null ? null : () => workspace.addNote(l.newNoteText),
        shortcut: AppShortcuts.addNote,
      ),
      AppCommand(
        l.revealSource,
        workspace != null && selected != null && workspace.content.card(selected)?.annotationId != null
            ? () => workspace.revealCard(selected)
            : null,
        shortcut: AppShortcuts.revealSource,
      ),
      AppCommand(l.removeFromMap, workspace != null && selected != null ? workspace.removeSelected : null),
    ];
    final view = <AppCommand>[
      if (inLibrary) ...[
        AppCommand(
          l.viewAsIcons,
          () => ref.read(libraryViewProvider.notifier).setViewMode(LibraryViewMode.grid),
          shortcut: AppShortcuts.view1,
        ),
        AppCommand(
          l.viewAsList,
          () => ref.read(libraryViewProvider.notifier).setViewMode(LibraryViewMode.list),
          shortcut: AppShortcuts.view2,
        ),
        AppCommand(
          l.hideSidebar,
          ref.read(libraryViewProvider.notifier).toggleSidebar,
          shortcut: AppShortcuts.toggleSidebar,
        ),
      ],
      if (inWorkspace) ...[
        AppCommand(
          l.layoutReader,
          () => ref.read(workspaceProvider(workspaceId).notifier).setLayout(MMSplitMode.primary),
          shortcut: AppShortcuts.view1,
        ),
        AppCommand(
          l.layoutSplit,
          () => ref.read(workspaceProvider(workspaceId).notifier).setLayout(MMSplitMode.split),
          shortcut: AppShortcuts.view2,
        ),
        AppCommand(
          l.layoutMap,
          () => ref.read(workspaceProvider(workspaceId).notifier).setLayout(MMSplitMode.secondary),
          shortcut: AppShortcuts.view3,
        ),
        AppCommand(
          l.hideSidebar,
          ref.read(workspaceProvider(workspaceId).notifier).toggleSidebar,
          shortcut: AppShortcuts.toggleSidebar,
        ),
      ],
      AppCommand(
        l.search,
        (inLibrary || inWorkspace) ? () => ref.read(focusRequestsProvider.notifier).request(FocusTarget.search) : null,
        shortcut: AppShortcuts.find,
      ),
    ];
    final help = [AppCommand(l.componentGallery, nav.showGallery, shortcut: AppShortcuts.gallery)];

    if (DesktopWindow.isMacOS) {
      return PlatformMenuBar(
        menus: [
          PlatformMenu(
            label: l.appName,
            menus: [
              _provided(PlatformProvidedMenuItemType.about),
              PlatformMenuItemGroup(members: [_item(settings)]),
              _provided(PlatformProvidedMenuItemType.servicesSubmenu),
              PlatformMenuItemGroup(
                members: [
                  ?_maybeProvided(PlatformProvidedMenuItemType.hide),
                  ?_maybeProvided(PlatformProvidedMenuItemType.hideOtherApplications),
                  ?_maybeProvided(PlatformProvidedMenuItemType.showAllApplications),
                ],
              ),
              _provided(PlatformProvidedMenuItemType.quit),
            ],
          ),
          PlatformMenu(label: l.menuFile, menus: [for (final c in file) _item(c)]),
          PlatformMenu(
            label: l.menuView,
            menus: [
              PlatformMenuItemGroup(members: [for (final c in view) _item(c)]),
              _provided(PlatformProvidedMenuItemType.toggleFullScreen),
            ],
          ),
          PlatformMenu(
            label: l.menuWindow,
            menus: [
              _provided(PlatformProvidedMenuItemType.minimizeWindow),
              _provided(PlatformProvidedMenuItemType.zoomWindow),
              _provided(PlatformProvidedMenuItemType.arrangeWindowsInFront),
            ],
          ),
          PlatformMenu(label: l.menuHelp, menus: [for (final c in help) _item(c)]),
        ],
        child: child,
      );
    }

    return CallbackShortcuts(
      bindings: {
        for (final c in [settings, ...file, ...view, ...map, ...help])
          if (c.shortcut != null && c.onInvoke != null) c.shortcut!: c.onInvoke!,
      },
      child: Focus(autofocus: true, child: child),
    );
  }

  static PlatformMenuItem _item(AppCommand c) =>
      PlatformMenuItem(label: c.label, shortcut: c.shortcut, onSelected: c.onInvoke);

  static PlatformMenuItem _provided(PlatformProvidedMenuItemType type) =>
      PlatformMenuItemGroup(members: [?_maybeProvided(type)]);

  static PlatformMenuItem? _maybeProvided(PlatformProvidedMenuItemType type) =>
      PlatformProvidedMenuItem.hasMenu(type) ? PlatformProvidedMenuItem(type: type) : null;
}
