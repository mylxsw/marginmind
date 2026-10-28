import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../features/gallery/gallery_screen.dart';
import '../features/library/library_screen.dart';
import '../features/review/review_screen.dart';
import '../features/review/stats_screen.dart';
import '../features/workspace/widgets/reader_pane.dart';
import '../features/workspace/workspace_controller.dart';
import '../features/workspace/workspace_screen.dart';
import '../settings/app_settings.dart';
import '../settings/system_appearance.dart';
import '../shared/l10n.dart';
import 'app_commands.dart';
import 'navigation.dart';

/// Whether the app runs on a phone or tablet, where layout and controls
/// are touch-first. Read from the host OS, not the target-platform override,
/// so widget tests stay on desktop unless they override this.
final touchPlatformProvider = Provider<bool>((_) => !kIsWeb && (Platform.isIOS || Platform.isAndroid));

class MarginMindApp extends ConsumerWidget {
  const MarginMindApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final system = ref.watch(systemAppearanceProvider);
    // The page pill sits at the bottom centre of the reader: the HUD goes above it.
    final route = ref.watch(navigationProvider);
    final pillShown =
        route is WorkspaceRoute &&
        ref.watch(
          workspaceProvider(route.studySetId)
              .select((s) => s.activeDocumentId != null && s.layout != MMSplitMode.secondary),
        );
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
      builder: (context, child) => MMInput(
        touchPlatform: ref.watch(touchPlatformProvider),
        child: MMAppearance(
          reduceTransparency: system.reduceTransparency,
          reduceMotion: system.reduceMotion,
          child: MMHudHost(
            bottom: pillShown ? pagePillClearance + MMSpacing.s : MMHudHost.defaultBottom,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
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
      ReviewRoute(:final studySetId) => ReviewScreen(key: ValueKey('review-$studySetId'), studySetId: studySetId),
      StatsRoute(:final studySetId) => StatsScreen(key: ValueKey('stats-$studySetId'), studySetId: studySetId),
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
