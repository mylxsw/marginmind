import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'phone_tabs.dart';

/// Whether the app runs on a phone or tablet, where layout and controls
/// are touch-first. Read from the host OS, not the target-platform override,
/// so widget tests stay on desktop unless they override this.
final touchPlatformProvider = Provider<bool>((_) => !kIsWeb && (Platform.isIOS || Platform.isAndroid));

/// Whether the touch platform is a phone: its screen is narrower than the
/// compact breakpoint in portrait. Tablets keep their layouts in Split View.
final phoneProvider = Provider<bool>((ref) {
  if (!ref.watch(touchPlatformProvider)) return false;
  final displays = WidgetsBinding.instance.platformDispatcher.displays;
  if (displays.isEmpty) return false;
  final display = displays.first;
  return display.size.shortestSide / display.devicePixelRatio < MMSizeClass.compactMaxWidth;
});

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
      builder: (context, child) {
        final touchPlatform = ref.watch(touchPlatformProvider);
        final phone = ref.watch(phoneProvider);
        final size = MediaQuery.sizeOf(context);
        final safe = MediaQuery.paddingOf(context);
        final tabs =
            phone &&
            MMSizeClass.fromSize(Size(size.width - safe.horizontal, size.height - safe.vertical)) ==
                MMSizeClass.compact;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: systemBarsStyle(Theme.of(context).brightness),
          child: MMInput(
            touchPlatform: touchPlatform,
            phone: phone,
            child: MMAppearance(
              reduceTransparency: system.reduceTransparency,
              reduceMotion: system.reduceMotion,
              child: MMHudHost(
                bottom:
                    (tabs ? MMTabBar.heightOf(context) : 0) +
                    (pillShown ? pagePillClearance + MMSpacing.s : MMHudHost.defaultBottom),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
      home: const AppShell(),
    );
  }
}

/// Status and navigation bars drawn over the app (edge to edge): clear,
/// with icons that contrast with the theme's window background.
SystemUiOverlayStyle systemBarsStyle(Brightness brightness) {
  final icons = brightness == Brightness.dark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: brightness,
    statusBarIconBrightness: icons,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarContrastEnforced: false,
  );
}

/// Picks the screen for the current route and installs menus/shortcuts.
/// A phone gets the bottom tabs; system back goes up a level once the
/// screen has nothing of its own to close (see [MMBackHandler]).
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  /// Leaves text editing first, then goes up: review back to its study
  /// set, other screens to the library. The library lets the app close.
  static bool back(WidgetRef ref) {
    final focus = FocusManager.instance.primaryFocus;
    final field = focus?.context;
    if (field != null &&
        (field.widget is EditableText || field.findAncestorWidgetOfExactType<EditableText>() != null)) {
      focus!.unfocus();
      return true;
    }
    final navigation = ref.read(navigationProvider.notifier);
    switch (ref.read(navigationProvider)) {
      case LibraryRoute():
        return false;
      case ReviewRoute(:final studySetId):
        navigation.openStudySet(studySetId);
      case _:
        navigation.back();
    }
    return true;
  }

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
    final switcher = AnimatedSwitcher(
      duration: MMAppearance.duration(context, MMMotion.standard),
      child: KeyedSubtree(key: ValueKey(route.runtimeType), child: screen),
    );
    return MMBackHandler(
      onBack: () => back(ref),
      child: AppMenus(
        child: Material(
          type: MaterialType.transparency,
          // Always in the tree, so rotating a phone keeps the screen's state.
          child: MMWindowBottomBar(bar: showsPhoneTabs(context) ? const PhoneTabBar() : null, child: switcher),
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
