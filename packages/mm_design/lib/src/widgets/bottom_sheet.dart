import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/appearance.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';

/// A sheet rising from the bottom of a compact window. Its handle drags it:
/// down far enough dismisses it. With [expand] it has a medium and a full
/// height to drag between; otherwise it fits its content. While the soft
/// keyboard is up the sheet sits on it, and an [expand] sheet takes the
/// full height. Fills its parent, which should cover the window.
class MMBottomSheet extends StatefulWidget {
  const MMBottomSheet({super.key, required this.child, this.onDismiss, this.expand = false, this.scrim = false});

  final Widget child;
  final VoidCallback? onDismiss;
  final bool expand;

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
      _height = ((_height ?? medium) - d.delta.dy).clamp(0.0, max);
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
    final dismiss = height < medium * 0.6 || (velocity > 700 && height <= medium);
    setState(() {
      _dragging = false;
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
    final duration = _dragging ? Duration.zero : MMAppearance.duration(context, MMMotion.layout);
    return LayoutBuilder(
      builder: (context, constraints) {
        final max = (constraints.maxHeight - safe.top - MMSpacing.s - keyboard).clamp(0.0, double.infinity);
        final medium = max * MMSizes.bottomSheetMedium;
        final handle = GestureDetector(
          key: const ValueKey('mm-bottom-sheet-handle'),
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => setState(() => _dragging = true),
          onVerticalDragUpdate: (d) => _update(d, medium, max),
          onVerticalDragEnd: (d) => _end(d, medium, max),
          child: SizedBox(
            height: MMSizes.bottomSheetHandle,
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
        final bottom = SizedBox(height: keyboard > 0 ? 0 : safe.bottom);
        final body = MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: _SheetScope(child: widget.child),
        );
        final sheet = DecoratedBox(
          key: const ValueKey('mm-bottom-sheet'),
          decoration: BoxDecoration(
            color: c.windowBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(MMRadii.sheet)),
            border: Border(top: BorderSide(color: c.hairline, width: 0.5)),
            boxShadow: c.sheetShadow,
          ),
          child: Padding(
            padding: EdgeInsets.only(left: safe.left, right: safe.right),
            child: widget.expand
                ? AnimatedContainer(
                    duration: duration,
                    curve: MMMotion.layoutCurve,
                    height: keyboard > 0 ? max : (_height ?? medium),
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
          ),
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
              left: 0,
              right: 0,
              bottom: keyboard - _offset,
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

/// Presents [builder] in a fitted [MMBottomSheet] route: the compact form of
/// sheets and dialogs. Dragging it down pops it like Esc does.
Future<T?> showMMBottomSheet<T>({required BuildContext context, required WidgetBuilder builder}) {
  final c = context.mmColors;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: c.scrim,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: MMAppearance.duration(context, MMMotion.standard),
    pageBuilder: (context, _, _) => CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: FocusScope(
        autofocus: true,
        child: MMBottomSheet(
          onDismiss: () => Navigator.of(context).maybePop(),
          child: Builder(builder: builder),
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
