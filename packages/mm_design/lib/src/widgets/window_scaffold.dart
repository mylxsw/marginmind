import 'package:flutter/material.dart';

import '../foundation/appearance.dart';
import '../foundation/input_mode.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'menu.dart';

/// Window-level hooks the platform layer provides: window dragging, title
/// bar double-click, and how much the toolbar must leave for the window
/// buttons when the sidebar is hidden.
class MMWindowChrome extends InheritedWidget {
  const MMWindowChrome({
    super.key,
    required super.child,
    this.toolbarLeadingInset = 0,
    this.onDragStart,
    this.onTitleDoubleTap,
  });

  final double toolbarLeadingInset;
  final VoidCallback? onDragStart;
  final VoidCallback? onTitleDoubleTap;

  static MMWindowChrome? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MMWindowChrome>();

  @override
  bool updateShouldNotify(MMWindowChrome oldWidget) =>
      oldWidget.toolbarLeadingInset != toolbarLeadingInset ||
      oldWidget.onDragStart != onDragStart ||
      oldWidget.onTitleDoubleTap != onTitleDoubleTap;
}

/// The window layout used by every MarginMind window: a collapsible
/// floating sidebar, a unified toolbar and the content below it.
class MMWindowScaffold extends StatelessWidget {
  const MMWindowScaffold({
    super.key,
    required this.toolbar,
    required this.body,
    this.sidebar,
    this.sidebarVisible = true,
    this.sidebarWidth = MMSizes.sidebarWidth,
    this.onDragStart,
    this.onTitleDoubleTap,
    this.showsWindowButtons = true,
  });

  final Widget toolbar;
  final Widget body;
  final Widget? sidebar;
  final bool sidebarVisible;
  final double sidebarWidth;
  final VoidCallback? onDragStart;
  final VoidCallback? onTitleDoubleTap;

  /// Whether the system draws window buttons inside our content (macOS with
  /// a transparent title bar). When the sidebar hides, the toolbar shifts
  /// right to make room for them.
  final bool showsWindowButtons;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final open = sidebar != null && sidebarVisible;
    final fullWidth = sidebarWidth + MMSizes.sidebarInset;
    final duration = MMAppearance.duration(context, MMMotion.layout);

    return MMInputMode(
      child: MMContextMenuHost(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: ColoredBox(
            color: c.windowBackground,
            child: MMWindowChrome(
              toolbarLeadingInset: !open && showsWindowButtons ? MMSizes.windowButtonsWidth : 0,
              onDragStart: onDragStart,
              onTitleDoubleTap: onTitleDoubleTap,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (sidebar != null)
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: open ? fullWidth : 0),
                      duration: duration,
                      curve: MMMotion.layoutCurve,
                      builder: (context, width, child) => SizedBox(
                        width: width,
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.centerRight,
                            minWidth: fullWidth,
                            maxWidth: fullWidth,
                            child: child,
                          ),
                        ),
                      ),
                      child: ExcludeFocus(excluding: !open, child: sidebar!),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        toolbar,
                        Expanded(child: body),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
