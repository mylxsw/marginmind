import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

const _stylusExclusion = Object();

/// Editable margin notes and selection handles retain their own gestures.
class MMStylusExclusion extends StatelessWidget {
  const MMStylusExclusion({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => MetaData(metaData: _stylusExclusion, child: child);
}

/// Pencil input has no drag slop: even a dot is a complete stroke.
/// Fingers retain the child's navigation gestures while the pen is lifted.
class MMStylusRegion extends StatefulWidget {
  const MMStylusRegion({
    super.key,
    required this.enabled,
    required this.child,
    required this.onDown,
    required this.onMove,
    required this.onUp,
    required this.onCancel,
    this.captureOnDown = true,
    this.includeMouse = false,
  });
  final bool enabled;
  final bool captureOnDown, includeMouse;
  final Widget child;
  final ValueChanged<Offset> onDown, onMove, onUp;
  final VoidCallback onCancel;

  @override
  State<MMStylusRegion> createState() => _MMStylusRegionState();
}

class _MMStylusRegionState extends State<MMStylusRegion> {
  int? _pointer;
  static bool _pen(PointerEvent e) => e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;
  bool _drawingPointer(PointerEvent e) =>
      _pen(e) || (widget.includeMouse && e.kind == PointerDeviceKind.mouse && (e.buttons & kPrimaryMouseButton) != 0);
  static bool _allowed(PointerDownEvent e) {
    final hit = HitTestResult();
    GestureBinding.instance.hitTestInView(hit, e.position, e.viewId);
    return !hit.path.any(
      (entry) =>
          entry.target is RenderMetaData && identical((entry.target as RenderMetaData).metaData, _stylusExclusion),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      _pointer = null;
      return widget.child;
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (!_drawingPointer(e) || _pointer != null || !_allowed(e)) return;
        _pointer = e.pointer;
        widget.onDown(e.localPosition);
      },
      onPointerMove: (e) {
        if (e.pointer == _pointer) widget.onMove(e.localPosition);
      },
      onPointerUp: (e) {
        if (e.pointer != _pointer) return;
        _pointer = null;
        widget.onUp(e.localPosition);
      },
      onPointerCancel: (e) {
        if (e.pointer != _pointer) return;
        _pointer = null;
        widget.onCancel();
      },
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          _StylusRecognizer: GestureRecognizerFactoryWithHandlers<_StylusRecognizer>(
            () => _StylusRecognizer(() => _pointer != null, () => widget.captureOnDown, _drawingPointer),
            (_) {},
          ),
        },
        child: widget.child,
      ),
    );
  }
}

class _StylusRecognizer extends OneSequenceGestureRecognizer {
  _StylusRecognizer(this.penDown, this.captureOnDown, this.drawingPointer);
  final bool Function() penDown;
  final bool Function() captureOnDown;
  final bool Function(PointerEvent) drawingPointer;
  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      (drawingPointer(event) && _MMStylusRegionState._allowed(event)) || event.kind == PointerDeviceKind.touch;
  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer);
    // A stationary finger may already be resting on the page. Claim its
    // still-pending gesture when the pen arrives, before it becomes a pan.
    if (captureOnDown() && (drawingPointer(event) || penDown())) resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    // A selection tap still reaches links/annotations; its first movement
    // claims a character drag without waiting for the normal 18px slop.
    if (event is PointerMoveEvent && drawingPointer(event)) resolve(GestureDisposition.accepted);
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      resolvePointer(event.pointer, GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}
  @override
  String get debugDescription => 'direct stylus';
}
