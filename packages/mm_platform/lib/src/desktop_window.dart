import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:macos_window_utils/macos/ns_window_button_type.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:window_manager/window_manager.dart';

/// Where the window buttons should sit, in logical pixels from the window's
/// top-left corner. Matches the floating sidebar: inset 8 + padding.
@immutable
class WindowButtonsPlacement {
  const WindowButtonsPlacement({this.closeCenter = const Offset(30, 34)});

  final Offset closeCenter;
}

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

  /// Call once before `runApp`. Never blocks app start: every native step
  /// has a timeout, and showing the window waits for the first frame, so it
  /// is scheduled rather than awaited.
  static Future<void> initialize({
    required String title,
    required Size minimumSize,
    Size initialSize = const Size(1280, 820),
    WindowButtonsPlacement placement = const WindowButtonsPlacement(),
  }) async {
    if (!isDesktop) return;
    await windowManager.ensureInitialized();

    if (isMacOS) {
      await WindowManipulator.initialize();
      await WindowManipulator.makeTitlebarTransparent();
      await WindowManipulator.enableFullSizeContentView();
      await WindowManipulator.hideTitle();
      await _placeWindowButtons(placement);
    }

    final options = WindowOptions(title: title, size: initialSize, minimumSize: minimumSize, center: true);
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  /// Moves close / minimize / zoom together so the close button is centered
  /// on [WindowButtonsPlacement.closeCenter]. The default buttons are
  /// vertically centered in the title bar, so their distance from the bottom
  /// equals their distance from the top.
  static Future<void> _placeWindowButtons(WindowButtonsPlacement placement) async {
    final close = await WindowManipulator.getStandardWindowButtonPosition(buttonType: NSWindowButtonType.closeButton);
    final dx = placement.closeCenter.dx - (close.left + close.width / 2);
    final dy = placement.closeCenter.dy - (close.top + close.height / 2);
    for (final type in [
      NSWindowButtonType.closeButton,
      NSWindowButtonType.miniaturizeButton,
      NSWindowButtonType.zoomButton,
    ]) {
      final frame = await WindowManipulator.getStandardWindowButtonPosition(buttonType: type);
      await WindowManipulator.overrideStandardWindowButtonPosition(
        buttonType: type,
        offset: Offset(frame.left + dx, frame.top + dy),
      );
    }
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
