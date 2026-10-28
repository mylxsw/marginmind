import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A context menu reachable with a secondary click or a touch long press.
/// Keeping both recognizers in one region prevents nested menus firing twice.
class MMContextMenuRegion extends StatelessWidget {
  const MMContextMenuRegion({
    super.key,
    required this.child,
    this.onSecondaryTapUp,
    this.onTapUp,
    this.behavior,
    this.longPressEnabled = true,
    this.longPressHitTest,
  });

  final Widget child;
  final GestureTapUpCallback? onSecondaryTapUp;
  final GestureTapUpCallback? onTapUp;
  final HitTestBehavior? behavior;
  final bool longPressEnabled;

  /// A canvas may offer menus only over its painted lines, leaving blank
  /// space and nodes to their own pan/zoom and drag recognizers.
  final bool Function(Offset localPosition)? longPressHitTest;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: behavior,
    onTapUp: onTapUp,
    onSecondaryTapUp: onSecondaryTapUp,
    child: RawGestureDetector(
      behavior: behavior,
      gestures: {
        if (longPressEnabled && onSecondaryTapUp != null)
          _ContextLongPressRecognizer: GestureRecognizerFactoryWithHandlers<_ContextLongPressRecognizer>(
            _ContextLongPressRecognizer.new,
            (recognizer) {
              recognizer.hitTest = longPressHitTest;
              recognizer.onLongPressStart = (details) {
                HapticFeedback.selectionClick();
                onSecondaryTapUp!(
                  TapUpDetails(
                    globalPosition: details.globalPosition,
                    localPosition: details.localPosition,
                    kind: PointerDeviceKind.touch,
                  ),
                );
              };
            },
          ),
      },
      child: child,
    ),
  );
}

class _ContextLongPressRecognizer extends LongPressGestureRecognizer {
  _ContextLongPressRecognizer() : super(supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus});
  bool Function(Offset)? hitTest;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      super.isPointerAllowed(event) && (hitTest?.call(event.localPosition) ?? true);
}
