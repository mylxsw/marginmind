import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:window_manager/window_manager.dart';

/// Native window setup and the few window actions the UI needs.
abstract final class DesktopWindow {
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
}
