import 'package:flutter/material.dart';

import '../foundation/appearance.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';

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
///
/// The background fills the window; sidebar, toolbar and content stay inside
/// the safe area (status bar, home indicator, landscape side insets). With
/// [sidebarOverlay] the sidebar is a drawer over the content instead of a
/// column beside it, and tapping outside calls [onSidebarDismiss].
class MMWindowScaffold extends StatelessWidget {
  const MMWindowScaffold({
    super.key,
    required this.toolbar,
    required this.body,
    this.sidebar,
    this.sidebarVisible = true,
    this.sidebarWidth = MMSizes.sidebarWidth,
    this.sidebarOverlay = false,
    this.onSidebarDismiss,
    this.onDragStart,
    this.onTitleDoubleTap,
    this.showsWindowButtons = true,
  });

  final Widget toolbar;
  final Widget body;
  final Widget? sidebar;
  final bool sidebarVisible;
  final double sidebarWidth;
  final bool sidebarOverlay;
  final VoidCallback? onSidebarDismiss;
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
    final inline = open && !sidebarOverlay;
    final fullWidth = sidebarWidth + MMSizes.sidebarInset;
    final duration = MMAppearance.duration(context, MMMotion.layout);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        toolbar,
        Expanded(child: body),
      ],
    );

    return ColoredBox(
      color: c.windowBackground,
      child: SafeArea(
        child: MMWindowChrome(
          toolbarLeadingInset: !inline && showsWindowButtons ? MMSizes.windowButtonsWidth : 0,
          onDragStart: onDragStart,
          onTitleDoubleTap: onTitleDoubleTap,
          child: sidebarOverlay
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: ExcludeFocus(excluding: open, child: content),
                    ),
                    if (sidebar != null)
                      MMDrawer(open: open, width: fullWidth, onDismiss: onSidebarDismiss, child: sidebar!),
                  ],
                )
              : Row(
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
                    Expanded(child: content),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A panel that slides over the content from one edge, above a scrim that
/// dismisses it: the sidebar of a touch window, or a floating right panel.
/// Closed, it waits off-screen and keeps its state.
class MMDrawer extends StatelessWidget {
  const MMDrawer({
    super.key,
    required this.open,
    required this.width,
    required this.child,
    this.onDismiss,
    this.end = false,
    this.inset = 0,
  });

  final bool open;
  final double width;
  final Widget child;
  final VoidCallback? onDismiss;

  /// Slides in from the right edge instead of the left.
  final bool end;

  /// Gap to the window edges (the sidebar brings its own margin).
  final double inset;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final duration = MMAppearance.duration(context, MMMotion.layout);
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = width.clamp(0.0, (constraints.maxWidth - inset * 2).clamp(0.0, double.infinity));
          return Stack(
            children: [
              IgnorePointer(
                ignoring: !open,
                child: AnimatedOpacity(
                  opacity: open ? 1 : 0,
                  duration: duration,
                  child: GestureDetector(
                    key: const ValueKey('mm-drawer-scrim'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onDismiss,
                    child: SizedBox.expand(child: ColoredBox(color: c.scrim)),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: duration,
                curve: MMMotion.layoutCurve,
                top: inset,
                bottom: inset,
                left: end ? null : (open ? inset : -w - inset),
                right: end ? (open ? inset : -w - inset) : null,
                width: w,
                child: ExcludeFocus(excluding: !open, child: child),
              ),
            ],
          );
        },
      ),
    );
  }
}
