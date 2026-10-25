import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../features/gallery/gallery_screen.dart';
import '../features/library/library_screen.dart';
import '../features/workspace/workspace_screen.dart';
import '../settings/app_settings.dart';
import '../settings/system_appearance.dart';
import '../shared/l10n.dart';
import 'app_commands.dart';
import 'navigation.dart';

class MarginMindApp extends ConsumerWidget {
  const MarginMindApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final system = ref.watch(systemAppearanceProvider);
    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.appName,
      debugShowCheckedModeBanner: false,
      theme: MMTheme.light(systemAccent: system.accentColor),
      darkTheme: MMTheme.dark(systemAccent: system.accentColor),
      themeMode: settings.themeMode,
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MMAppearance(
        reduceTransparency: system.reduceTransparency,
        reduceMotion: system.reduceMotion,
        child: MMHudHost(child: child ?? const SizedBox.shrink()),
      ),
      home: const AppShell(),
    );
  }
}

/// Picks the screen for the current route and installs menus/shortcuts.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(navigationProvider);
    final screen = switch (route) {
      LibraryRoute() => const LibraryScreen(),
      WorkspaceRoute(:final studySetId) => WorkspaceScreen(key: ValueKey(studySetId), studySetId: studySetId),
      GalleryRoute() => const GalleryScreen(),
    };
    return AppMenus(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedSwitcher(
          duration: MMAppearance.duration(context, MMMotion.standard),
          child: KeyedSubtree(key: ValueKey(route.runtimeType), child: screen),
        ),
      ),
    );
  }
}

/// Window callbacks shared by every screen's [MMWindowScaffold].
abstract final class WindowChrome {
  static VoidCallback? get onDragStart => DesktopWindow.isMacOS ? DesktopWindow.startDragging : null;

  static VoidCallback? get onTitleDoubleTap => DesktopWindow.isMacOS ? DesktopWindow.toggleZoom : null;

  static bool get showsWindowButtons => DesktopWindow.drawsWindowButtonsInContent;
}
