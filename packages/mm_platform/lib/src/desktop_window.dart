import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:window_manager/window_manager.dart';

/// Native window setup and the few window actions the UI needs.
abstract final class DesktopWindow {
  /// Whether the window is full screen, kept current from the native
  /// enter / leave events. Menus read it to offer the opposite action.
  static final ValueListenable<bool> fullScreen = _fullScreen;
  static final _fullScreen = ValueNotifier<bool>(false);
  static final _listener = _FullScreenListener();

  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  static bool get isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Whether the system draws window buttons on top of Flutter content.
  /// True on macOS (transparent, full-size title bar); other platforms keep
  /// their native title bar for now.
  static bool get drawsWindowButtonsInContent => isMacOS;

  /// Call once before `runApp` to configure native chrome before showing it.
  static Future<void> initialize({
    required String title,
    required Size minimumSize,
    Size initialSize = const Size(1280, 820),
  }) async {
    if (!isDesktop) return;
    await windowManager.ensureInitialized();
    windowManager.removeListener(_listener);
    windowManager.addListener(_listener);
    _fullScreen.value = await windowManager.isFullScreen();

    if (isMacOS) {
      await WindowManipulator.initialize();
      await WindowManipulator.makeTitlebarTransparent();
      await WindowManipulator.enableFullSizeContentView();
      await WindowManipulator.hideTitle();
      // MainFlutterWindow installs the unified native toolbar and forwards
      // its content events to Flutter. AppKit owns the window button layout.
    }

    final options = WindowOptions(title: title, size: initialSize, minimumSize: minimumSize, center: true);
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  /// Update the system window name even when its title bar text is hidden.
  static Future<void> setTitle(String title) async {
    if (isDesktop) await windowManager.setTitle(title);
  }

  /// Starts a native window drag (call from a pan-start on empty chrome).
  static void startDragging() {
    if (isDesktop) windowManager.startDragging();
  }

  /// Title-bar double-click behavior: zoom / unzoom.
  static Future<void> toggleZoom() async {
    if (!isDesktop) return;
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @visibleForTesting
  static void debugSetFullScreen(bool value) => _fullScreen.value = value;

  /// Enters full screen, or leaves it when the window already is. [fullScreen]
  /// follows once the system reports the transition.
  static Future<void> toggleFullScreen() async {
    if (!isDesktop) return;
    await windowManager.setFullScreen(!await windowManager.isFullScreen());
  }
}

class _FullScreenListener with WindowListener {
  @override
  void onWindowEnterFullScreen() => DesktopWindow._fullScreen.value = true;

  @override
  void onWindowLeaveFullScreen() => DesktopWindow._fullScreen.value = false;
}
