import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../foundation/appearance.dart';
import '../foundation/adaptive.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'flat_surface.dart';

/// A sheet rising from the bottom of a compact window. Its handle drags it:
/// down far enough dismisses it. With [expand] it has a medium and a full
/// height to drag between; otherwise it fits its content. While the soft
/// keyboard is up the sheet sits on it, and an [expand] sheet takes the
/// full height. Fills its parent, which should cover the window. On a
/// phone it floats inside the safe area on a solid, outlined surface. Glass
/// belongs to floating controls, not the reading and editing surface of a sheet.
/// Tablet and desktop retain their existing frame.
class MMBottomSheet extends StatefulWidget {
  const MMBottomSheet({
    super.key,
    required this.child,
    this.onDismiss,
    this.expand = false,
    this.scrim = false,
    this.initialFraction = MMSizes.phoneSheetMedium,
  }) : assert(initialFraction > 0 && initialFraction <= 1);

  final Widget child;
  final VoidCallback? onDismiss;
  final bool expand;
  final double initialFraction;

  /// Draws its own tap-to-dismiss scrim (in-tree panels; routes bring one).
  final bool scrim;

  /// Whether [context] is inside a bottom sheet: frames such as `MMSheet`
  /// leave the card to the sheet.
  static bool contains(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_SheetScope>() != null;

  @override
  State<MMBottomSheet> createState() => _MMBottomSheetState();
}

class _MMBottomSheetState extends State<MMBottomSheet> {
  /// Height of an [MMBottomSheet.expand] sheet; null is the medium height.
  double? _height;

  /// How far a fitted sheet is dragged down.
  double _offset = 0;
  bool _dragging = false;

  void _dismiss() => widget.onDismiss?.call();

  void _update(DragUpdateDetails d, double medium, double max) => setState(() {
    if (widget.expand) {
      final next = (_height ?? medium) - _offset - d.delta.dy;
      // Below the medium detent, move the entire sheet instead of squeezing
      // its header and composer into an ever smaller body while dismissing.
      _height = next <= medium ? null : next.clamp(medium, max);
      _offset = next < medium ? medium - next : 0;
    } else {
      _offset = (_offset + d.delta.dy).clamp(0.0, double.infinity);
    }
  });

  void _end(DragEndDetails d, double medium, double max) {
    final velocity = d.velocity.pixelsPerSecond.dy;
    if (!widget.expand) {
      final dismiss = _offset > MMSizes.actionSheetRow * 1.5 || velocity > 700;
      setState(() {
        _dragging = false;
        _offset = 0;
      });
      if (dismiss) _dismiss();
      return;
    }
    final height = _height ?? medium;
    final dismiss = _offset > MMSizes.actionSheetRow * 1.5 || (velocity > 700 && height <= medium);
    setState(() {
      _dragging = false;
      _offset = 0;
      _height = dismiss || velocity > 700
          ? null
          : velocity < -700 || (height - medium).abs() > (height - max).abs()
          ? max
          : null;
    });
    if (dismiss) _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final safe = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final phone = MMInput.of(context).phone;
    final duration = _dragging ? Duration.zero : MMAppearance.duration(context, MMMotion.layout);
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = phone ? MMSizes.phoneSheetPadding : 0.0;
        final bottomInset = phone && keyboard == 0 ? safe.bottom + inset : inset;
        final max = (constraints.maxHeight - safe.top - MMSpacing.s - keyboard - bottomInset).clamp(
          0.0,
          double.infinity,
        );
        // Compact-height phones have room for one detent only. In portrait,
        // keep the document visible until the user expands the panel.
        final medium = phone && constraints.maxHeight < constraints.maxWidth
            ? max
            : max * (phone ? widget.initialFraction : MMSizes.bottomSheetMedium);
        final handle = GestureDetector(
          key: const ValueKey('mm-bottom-sheet-handle'),
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => setState(() => _dragging = true),
          onVerticalDragUpdate: (d) => _update(d, medium, max),
          onVerticalDragEnd: (d) => _end(d, medium, max),
          onVerticalDragCancel: () => setState(() {
            _dragging = false;
            _offset = 0;
          }),
          child: SizedBox(
            height: max.clamp(0.0, MMSizes.bottomSheetHandle),
            child: Center(
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(color: c.separator, borderRadius: BorderRadius.circular(2.5)),
              ),
            ),
          ),
        );
        // Above the keyboard the home indicator inset no longer applies.
        final bottom = SizedBox(height: phone || keyboard > 0 ? 0 : safe.bottom);
        // The sheet already sits on the keyboard and the insets.
        final body = MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: Builder(
            builder: (context) => MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: _SheetScope(child: widget.child),
            ),
          ),
        );
        final frame = Padding(
          padding: EdgeInsets.only(left: phone ? 0 : safe.left, right: phone ? 0 : safe.right),
          child: widget.expand
              ? AnimatedContainer(
                  duration: duration,
                  curve: MMMotion.layoutCurve,
                  height: keyboard > 0
                      ? max
                      : (_height ?? medium).clamp(max.clamp(0.0, MMSizes.bottomSheetHandle), max),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      handle,
                      Expanded(child: body),
                      bottom,
                    ],
                  ),
                )
              : ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: max),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      handle,
                      Flexible(child: body),
                      bottom,
                    ],
                  ),
                ),
        );
        final radius = phone
            ? BorderRadius.circular(
                defaultTargetPlatform == TargetPlatform.iOS ? MMRadii.phoneSheet : MMRadii.androidSheet,
              )
            : const BorderRadius.vertical(top: Radius.circular(MMRadii.sheet));
        final content = Semantics(onDismiss: widget.onDismiss, child: frame);
        final sheet = phone
            ? MMFlatSurface(
                child: DecoratedBox(
                  key: const ValueKey('mm-bottom-sheet'),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: radius,
                    border: Border.all(color: c.border, width: MMSizes.hairline),
                  ),
                  child: ClipRRect(borderRadius: radius, child: content),
                ),
              )
            : DecoratedBox(
                key: const ValueKey('mm-bottom-sheet'),
                decoration: BoxDecoration(
                  color: c.windowBackground,
                  borderRadius: radius,
                  border: Border(
                    top: BorderSide(color: c.hairline, width: MMSizes.hairline),
                  ),
                  boxShadow: c.sheetShadow,
                ),
                child: ClipRRect(borderRadius: radius, child: content),
              );
        return Stack(
          children: [
            if (widget.scrim)
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('mm-bottom-sheet-scrim'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _dismiss,
                  child: ColoredBox(color: c.scrim),
                ),
              ),
            AnimatedPositioned(
              duration: duration,
              curve: MMMotion.layoutCurve,
              left: inset + (phone ? safe.left : 0),
              right: inset + (phone ? safe.right : 0),
              bottom: keyboard + bottomInset - _offset,
              child: Material(type: MaterialType.transparency, child: sheet),
            ),
          ],
        );
      },
    );
  }
}

class _SheetScope extends InheritedWidget {
  const _SheetScope({required super.child});

  @override
  bool updateShouldNotify(_SheetScope oldWidget) => false;
}

/// Presents phone dialogs and panels in the same floating medium/large frame.
/// Short contextual menus can opt into a fitted height with [expand] false.
/// Drag, Escape and system Back all respect the route's PopScope guard.
Future<T?> showMMBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool expand = true,
  double initialFraction = MMSizes.phoneSheetMedium,
}) {
  final capturedThemes = InheritedTheme.capture(from: context, to: Navigator.of(context, rootNavigator: true).context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: MMAppearance.duration(context, MMMotion.standard),
    pageBuilder: (context, _, _) => capturedThemes.wrap(
      CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
        child: FocusScope(
          autofocus: true,
          child: MMBottomSheet(
            expand: expand && MMInput.of(context).phone,
            initialFraction: initialFraction,
            scrim: true,
            onDismiss: () => Navigator.of(context).maybePop(),
            child: Builder(builder: builder),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: MMMotion.layoutCurve);
      return SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
        child: child,
      );
    },
  );
}
