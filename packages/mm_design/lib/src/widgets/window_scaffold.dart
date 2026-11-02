import 'package:flutter/material.dart';

import '../foundation/adaptive.dart';
import '../foundation/appearance.dart';
import '../theme/mm_theme.dart';
import '../tokens/colors.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'glass.dart';
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
/// sidebar (flat on desktop), a unified toolbar and the content below it.
///
/// The background fills the window; sidebar, toolbar and content stay inside
/// the safe area (status bar, home indicator, landscape side insets). With
/// [sidebarOverlay] the sidebar is a drawer over the content instead of a
/// column beside it, and tapping outside calls [onSidebarDismiss].
///
/// An [MMWindowBottomBar] above puts its bar (a phone's tabs) below the
/// content while the soft keyboard is down. [sheet] lies over everything,
/// the bar included, and handles the keyboard itself.
///
/// On a touch platform the toolbar is a glass bar over the top of the
/// content, behind the status bar, and the bottom bar floats over the
/// content. An [extendBody] body runs beneath both and keeps clear of them
/// with [MMChromeInsets]; any other body is laid out between them.
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
    this.sheet,
    this.toolbarBottom,
    this.extendBody = false,
  }) : topSafeAreaColor = null,
       contentBuilder = null,
       toolbarExtent = MMSizes.toolbarHeight;

  const MMWindowScaffold.contentBuilder({
    super.key,
    required this.contentBuilder,
    this.topSafeAreaColor,
    this.sidebar,
    this.sidebarVisible = true,
    this.sidebarWidth = MMSizes.sidebarWidth,
    this.sidebarOverlay = false,
    this.onSidebarDismiss,
    this.onDragStart,
    this.onTitleDoubleTap,
    this.showsWindowButtons = true,
    this.sheet,
    this.toolbarExtent = MMSizes.paneHeaderHeight,
  }) : toolbar = const SizedBox.shrink(),
       body = const SizedBox.shrink(),
       toolbarBottom = null,
       extendBody = false;

  /// Background behind the status bar, matching custom window chrome.
  final Color? topSafeAreaColor;

  final LayoutWidgetBuilder? contentBuilder;
  final double toolbarExtent;
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

  /// Usually an [MMBottomSheet]; fills the window.
  final Widget? sheet;

  /// A strip below the toolbar and on the same glass, such as the search
  /// field of a compact library.
  final PreferredSizeWidget? toolbarBottom;

  /// Whether the body of a touch window runs beneath the glass toolbar and
  /// the floating bottom bar, reading [MMChromeInsets] to keep its controls
  /// and the ends of its scroll views clear of them. Pointer windows ignore
  /// it.
  final bool extendBody;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final open = sidebar != null && sidebarVisible;
    final inline = open && !sidebarOverlay;
    final fullWidth = sidebarWidth;
    final duration = MMAppearance.duration(context, MMMotion.layout);
    if (MMInput.of(context).touchPlatform && contentBuilder == null) {
      return _touch(context, c, open, inline, fullWidth, duration);
    }
    final content = contentBuilder != null
        ? LayoutBuilder(builder: contentBuilder!)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              toolbar,
              ?toolbarBottom,
              Expanded(child: body),
            ],
          );
    final row = _row(open, fullWidth, duration, content);
    final safe = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bar = keyboard > 0 ? null : MMWindowBottomBar.maybeOf(context);

    // The column and stack stay in the tree whether or not the bar and the
    // sheet show, so the content keeps its state when they come and go.
    return MMContextMenuHost(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _window(context, c, open, inline, fullWidth, safe, keyboard, bar != null, content, row)),
              ?bar,
            ],
          ),
          ?sheet,
        ],
      ),
    );
  }

  Widget _window(
    BuildContext context,
    MMColors c,
    bool open,
    bool inline,
    double fullWidth,
    EdgeInsets safe,
    double keyboard,
    bool bar,
    Widget content,
    Widget row,
  ) => Padding(
    padding: EdgeInsets.only(bottom: keyboard),
    // Above the keyboard or a bottom bar the home indicator inset no
    // longer applies.
    child: MediaQuery.removePadding(
      context: context,
      removeBottom: keyboard > 0 || bar,
      child: ColoredBox(
        color: c.windowBackground,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (topSafeAreaColor != null && safe.top > 0)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: safe.top,
                child: ColoredBox(color: topSafeAreaColor!),
              ),
            MMWindowChrome(
              toolbarLeadingInset: !inline && showsWindowButtons ? MMSizes.windowButtonsWidth : 0,
              onDragStart: onDragStart,
              onTitleDoubleTap: onTitleDoubleTap,
              child: sidebarOverlay
                  // The drawer's scrim covers the whole window, insets included.
                  ? Stack(
                      children: [
                        Positioned.fill(
                          child: SafeArea(
                            child: ExcludeFocus(excluding: open, child: content),
                          ),
                        ),
                        if (sidebar != null)
                          MMDrawer(
                            open: open,
                            width: fullWidth + safe.left,
                            onDismiss: onSidebarDismiss,
                            child: sidebar!,
                          ),
                      ],
                    )
                  : SafeArea(child: row),
            ),
          ],
        ),
      ),
    ),
  );

  /// The sidebar column beside [content]; [wrapSidebar] adapts the sidebar
  /// to where the row sits.
  Widget _row(bool open, double fullWidth, Duration duration, Widget content, [Widget Function(Widget)? wrapSidebar]) =>
      TweenAnimationBuilder<double>(
        tween: Tween(end: sidebar != null && open ? fullWidth : 0),
        duration: duration,
        curve: MMMotion.layoutCurve,
        builder: (context, width, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sidebar != null)
              SizedBox(
                width: width,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerRight,
                    minWidth: fullWidth,
                    maxWidth: fullWidth,
                    child: ExcludeFocus(
                      excluding: !open,
                      child: wrapSidebar == null ? sidebar! : wrapSidebar(sidebar!),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Builder(
                builder: (context) {
                  final chrome = MMWindowChrome.maybeOf(context);
                  return MMWindowChrome(
                    toolbarLeadingInset:
                        !MMInput.of(context).touchPlatform && showsWindowButtons && (!open || width < fullWidth - .01)
                        ? MMSizes.windowButtonsWidth
                        : 0,
                    onDragStart: chrome?.onDragStart,
                    onTitleDoubleTap: chrome?.onTitleDoubleTap,
                    child: content,
                  );
                },
              ),
            ),
          ],
        ),
      );

  /// A touch window: the content fills it edge to edge under the glass
  /// toolbar and the floating bottom bar; the drawer lies over both.
  Widget _touch(BuildContext context, MMColors c, bool open, bool inline, double fullWidth, Duration duration) {
    final safe = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final scope = keyboard > 0 ? null : context.dependOnInheritedWidgetOfExactType<MMWindowBottomBar>();
    final bar = scope?.bar;
    final insets = EdgeInsets.only(
      top: safe.top + MMSizes.toolbarHeight + (toolbarBottom?.preferredSize.height ?? 0),
      // Above the keyboard the home indicator inset no longer applies.
      bottom: bar != null ? scope!.extent : (keyboard > 0 ? 0 : safe.bottom),
    );
    final chrome = Builder(
      builder: (context) {
        final side = MediaQuery.paddingOf(context);
        return Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(left: side.left, right: side.right),
                child: MediaQuery.removePadding(
                  context: context,
                  removeLeft: true,
                  removeTop: true,
                  removeRight: true,
                  removeBottom: true,
                  child: MMChromeInsets(
                    insets: extendBody ? insets : EdgeInsets.zero,
                    child: extendBody ? body : Padding(padding: insets, child: body),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: MMGlassBar(
                child: Padding(
                  padding: EdgeInsets.only(top: safe.top, left: side.left, right: side.right),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    // The insets below assume the toolbar's standard height.
                    children: [
                      SizedBox(height: MMSizes.toolbarHeight, child: toolbar),
                      ?toolbarBottom,
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    final overlay = sidebarOverlay;
    final main = overlay
        ? chrome
        : _row(
            open,
            fullWidth,
            duration,
            // The sidebar beside the content takes the leading inset.
            MediaQuery.removePadding(context: context, removeLeft: inline, child: chrome),
            (sidebar) => SafeArea(right: false, child: sidebar),
          );

    // The stack keeps the same children whether or not the bar and the
    // sheet show, so the content keeps its state when they come and go.
    return MMContextMenuHost(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: keyboard > 0,
              child: ColoredBox(
                color: c.windowBackground,
                child: MMWindowChrome(
                  toolbarLeadingInset: !inline && showsWindowButtons ? MMSizes.windowButtonsWidth : 0,
                  onDragStart: onDragStart,
                  onTitleDoubleTap: onTitleDoubleTap,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ExcludeFocus(excluding: overlay && open, child: main),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ExcludeFocus(excluding: overlay && open, child: bar ?? const SizedBox.shrink()),
                      ),
                      // The drawer and its scrim cover the whole window, bars included.
                      if (overlay && sidebar != null)
                        MMDrawer(
                          open: open,
                          width: fullWidth + safe.left,
                          onDismiss: onSidebarDismiss,
                          child: sidebar!,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ?sheet,
        ],
      ),
    );
  }
}

/// Supplies the bar [MMWindowScaffold]s below show under their content.
class MMWindowBottomBar extends InheritedWidget {
  const MMWindowBottomBar({super.key, required this.bar, this.extent = 0, required super.child});

  /// Null shows none; keeping the scope in the tree either way keeps the
  /// state of the screens below when the bar comes and goes.
  final Widget? bar;

  /// Space a floating [bar] covers above the bottom edge of a touch window,
  /// such as [MMTabBar.heightOf]: the content under it keeps clear of it.
  final double extent;

  static Widget? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MMWindowBottomBar>()?.bar;

  @override
  bool updateShouldNotify(MMWindowBottomBar oldWidget) => oldWidget.bar != bar || oldWidget.extent != extent;
}

/// The window chrome lying over an [MMWindowScaffold.extendBody] body: the
/// glass toolbar above and the floating bottom bar (or home indicator)
/// below. The body reaches beneath them; its controls and the ends of its
/// scroll views keep clear by these insets. Zero elsewhere.
class MMChromeInsets extends InheritedWidget {
  const MMChromeInsets({super.key, required this.insets, required super.child});

  final EdgeInsets insets;

  static EdgeInsets of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MMChromeInsets>()?.insets ?? EdgeInsets.zero;

  /// [child] with the insets of [context], less the ends it does not
  /// reach: a pane away from that edge of the window.
  static Widget remove(
    BuildContext context, {
    bool removeTop = false,
    bool removeBottom = false,
    required Widget child,
  }) {
    final insets = of(context);
    return MMChromeInsets(
      insets: EdgeInsets.only(top: removeTop ? 0 : insets.top, bottom: removeBottom ? 0 : insets.bottom),
      child: child,
    );
  }

  @override
  bool updateShouldNotify(MMChromeInsets oldWidget) => oldWidget.insets != insets;
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
