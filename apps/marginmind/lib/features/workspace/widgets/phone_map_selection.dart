import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show DeviceGestureSettings;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import 'map_drop.dart';

/// Survives the one-frame pane remount when a phone rotates. Leaving the
/// workspace/map releases the draft with the last listener.
final phoneMapSelectionProvider = Provider.autoDispose.family<PhoneMapSelectionController, String>((ref, id) {
  final controller = PhoneMapSelectionController();
  ref.onDispose(controller.dispose);
  return controller;
});

enum PhoneMapSelectionMode { tap, box }

/// A local draft. Workspace selection changes only when the user presses Done.
class PhoneMapSelectionController extends ChangeNotifier {
  bool active = false;
  PhoneMapSelectionMode mode = PhoneMapSelectionMode.tap;
  Set<String> _selected = {};
  Set<String> _base = {};
  Rect? frame;
  ({Set<String> selected, Set<String> base, Rect? frame})? _beforeStroke;

  Set<String> get selected => Set.unmodifiable(_selected);

  void begin(Iterable<String> selection) {
    _selected = selection.toSet();
    _base = {..._selected};
    frame = null;
    _beforeStroke = null;
    mode = PhoneMapSelectionMode.tap;
    active = true;
    notifyListeners();
  }

  void cancel() {
    if (!active) return;
    active = false;
    _beforeStroke = null;
    notifyListeners();
  }

  void setMode(PhoneMapSelectionMode next) {
    if (mode == next) return;
    finishStroke();
    _base = {..._selected};
    frame = null;
    mode = next;
    notifyListeners();
  }

  void toggle(String id) {
    if (!_selected.remove(id)) _selected.add(id);
    _base = {..._selected};
    frame = null;
    notifyListeners();
  }

  void clear() {
    _selected = {};
    _base = {};
    frame = null;
    _beforeStroke = null;
    notifyListeners();
  }

  void beginStroke({required bool newFrame}) {
    _beforeStroke = (selected: {..._selected}, base: {..._base}, frame: frame);
    if (newFrame) _base = {..._selected};
  }

  void updateFrame(Rect rect, Map<String, Rect> nodes) {
    frame = rect;
    _selected = {
      ..._base,
      for (final e in nodes.entries)
        if (rect.inflate(.001).contains(e.value.center)) e.key,
    };
    notifyListeners();
  }

  void finishStroke() => _beforeStroke = null;

  void rollbackStroke() {
    final before = _beforeStroke;
    if (before == null) return;
    _beforeStroke = null;
    _selected = before.selected;
    _base = before.base;
    frame = before.frame;
    notifyListeners();
  }
}

enum _FramePart { topLeft, topRight, bottomLeft, bottomRight, edge, fresh }

/// Owns touch input while selecting; node editing and dragging cannot win it.
/// The frame is stored in scene coordinates, so camera changes preserve it.
class PhoneMapSelectionLayer extends StatefulWidget {
  const PhoneMapSelectionLayer({
    super.key,
    required this.controller,
    required this.transformation,
    required this.nodes,
    required this.onDone,
    this.topInset = 0,
    this.labelForNode,
  });

  final PhoneMapSelectionController controller;
  final TransformationController transformation;
  final Map<String, Rect> Function() nodes;
  final VoidCallback onDone;
  final double topInset;
  final String Function(String)? labelForNode;

  @override
  State<PhoneMapSelectionLayer> createState() => _PhoneMapSelectionLayerState();
}

class _PhoneMapSelectionLayerState extends State<PhoneMapSelectionLayer> with SingleTickerProviderStateMixin {
  final _pointers = <int>{};
  Offset? _down;
  Offset? _lastPoint;
  Offset? _strokeStart;
  Rect? _startFrame;
  _FramePart _part = _FramePart.fresh;
  bool _stroke = false;
  bool _multitouch = false;
  double _previousScale = 1;
  int _previousCount = 0;
  late final Ticker _ticker = createTicker(_scrollTick);
  Duration? _edgeSince;
  Duration _lastTick = Duration.zero;
  Size _size = Size.zero;

  PhoneMapSelectionController get selection => widget.controller;
  Offset _scene(Offset point) => widget.transformation.toScene(point);
  Rect _screen(Rect rect) => MatrixUtils.transformRect(widget.transformation.value, rect);
  EdgeInsets get _safe => MediaQuery.paddingOf(context);
  double get _top => math.max(widget.topInset, _safe.top);
  double get _bottom => math.max(30, _safe.bottom + 8);
  Rect get _workArea => Rect.fromLTRB(
    _safe.left + 12,
    _top + 68,
    math.max(_safe.left + 12, _size.width - _safe.right - 12),
    math.max(_top + 68, _size.height - _bottom - 108),
  );

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _stopScroll() {
    _ticker.stop();
    _edgeSince = null;
    _lastTick = Duration.zero;
  }

  _FramePart _hit(Offset point) {
    final rect = selection.frame;
    if (rect == null) return _FramePart.fresh;
    final r = _screen(rect);
    final corners = {
      r.topLeft: _FramePart.topLeft,
      r.topRight: _FramePart.topRight,
      r.bottomLeft: _FramePart.bottomLeft,
      r.bottomRight: _FramePart.bottomRight,
    };
    // Nearest corner wins if two 44-point targets overlap on a small frame.
    final close = corners.entries.where((e) => (e.key - point).distance <= 22).toList()
      ..sort((a, b) => (a.key - point).distance.compareTo((b.key - point).distance));
    if (close.isNotEmpty) return close.first.value;
    if (r.inflate(12).contains(point) && !r.deflate(12).contains(point)) return _FramePart.edge;
    return _FramePart.fresh;
  }

  void _pointerDown(PointerDownEvent e) {
    if (_pointers.isEmpty) {
      _multitouch = false;
      _down = e.localPosition;
      _part = _hit(e.localPosition);
      _startFrame = selection.frame;
    }
    _pointers.add(e.pointer);
    if (_pointers.length > 1) {
      _multitouch = true;
      _stroke = false;
      selection.rollbackStroke();
      _stopScroll();
    }
  }

  void _start(ScaleStartDetails d) {
    _previousScale = 1;
    _previousCount = d.pointerCount;
    if (_multitouch || d.pointerCount > 1 || selection.mode != PhoneMapSelectionMode.box) return;
    _stroke = true;
    _strokeStart = _scene(_down ?? d.localFocalPoint);
    selection.beginStroke(newFrame: _part == _FramePart.fresh);
  }

  void _update(ScaleUpdateDetails d) {
    if (d.pointerCount > 1 || _multitouch || selection.mode == PhoneMapSelectionMode.tap) {
      if (_stroke) {
        _stroke = false;
        selection.rollbackStroke();
        _stopScroll();
      }
      if (_previousCount != d.pointerCount) {
        _previousScale = d.scale;
        _previousCount = d.pointerCount;
        return;
      }
      final m = widget.transformation.value;
      final oldScale = m.storage[0];
      final ratio = _previousCount == d.pointerCount && _previousScale > 0 ? d.scale / _previousScale : 1.0;
      final scale = (oldScale * ratio).clamp(.05, 2.5);
      final focal = d.localFocalPoint;
      final previous = focal - d.focalPointDelta;
      final anchor = widget.transformation.toScene(previous);
      widget.transformation.value = Matrix4.identity()
        ..translateByDouble(focal.dx - anchor.dx * scale, focal.dy - anchor.dy * scale, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
      _previousScale = d.scale;
      _previousCount = d.pointerCount;
      return;
    }
    if (!_stroke) return;
    _lastPoint = d.localFocalPoint;
    _updateFrame();
    final area = _workArea;
    if (area.contains(_lastPoint!) &&
        autoScrollVelocity(_lastPoint! - area.topLeft, area.size, edge: 40, maxSpeed: 240) != Offset.zero) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _stopScroll();
    }
  }

  void _updateFrame() {
    final start = _strokeStart;
    final point = _lastPoint;
    if (start == null || point == null) return;
    final p = _scene(point);
    final rect = _startFrame;
    final next = switch (_part) {
      _FramePart.topLeft when rect != null => Rect.fromPoints(rect.bottomRight, p),
      _FramePart.topRight when rect != null => Rect.fromPoints(rect.bottomLeft, p),
      _FramePart.bottomLeft when rect != null => Rect.fromPoints(rect.topRight, p),
      _FramePart.bottomRight when rect != null => Rect.fromPoints(rect.topLeft, p),
      _FramePart.edge when rect != null => rect.shift(p - start),
      _ => Rect.fromPoints(start, p),
    };
    selection.updateFrame(next, widget.nodes());
  }

  void _end(ScaleEndDetails d) {
    _stroke = false;
    selection.finishStroke();
    _lastPoint = null;
    _stopScroll();
  }

  void _tap(TapUpDetails d) {
    if (selection.mode != PhoneMapSelectionMode.tap) return;
    final hits =
        widget.nodes().entries.where((e) {
          final r = _screen(e.value);
          final target = Rect.fromCenter(
            center: r.center,
            width: math.max(44, r.width + 16),
            height: math.max(44, r.height),
          );
          return target.contains(d.localPosition);
        }).toList()..sort(
          (a, b) => (_screen(a.value).center - d.localPosition).distance.compareTo(
            (_screen(b.value).center - d.localPosition).distance,
          ),
        );
    if (hits.isNotEmpty) selection.toggle(hits.first.key);
  }

  void _scrollTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    final point = _lastPoint;
    final area = _workArea;
    if (!_stroke || point == null || !area.contains(point) || area.isEmpty) {
      _edgeSince = null;
      return;
    }
    final speed = autoScrollVelocity(point - area.topLeft, area.size, edge: 40, maxSpeed: 240);
    if (speed == Offset.zero) {
      _edgeSince = null;
      return;
    }
    _edgeSince ??= elapsed;
    if (elapsed - _edgeSince! < const Duration(milliseconds: 350) || dt <= 0) return;
    final nodes = widget.nodes().values;
    if (nodes.isEmpty) return;
    final content = _screen(nodes.reduce((a, b) => a.expandToInclude(b))).shift(-area.topLeft);
    final m = widget.transformation.value;
    final current = Offset(m.storage[12], m.storage[13]);
    final next = clampAutoScroll(current, speed * dt, content, area.size, margin: 40);
    if (next == current) return;
    widget.transformation.value = m.clone()..setTranslationRaw(next.dx, next.dy, 0);
    _updateFrame();
  }

  Widget _frame(BuildContext context, Rect r) {
    final c = context.mmColors;
    return Stack(
      children: [
        Positioned.fromRect(
          rect: r,
          child: DecoratedBox(
            key: const ValueKey('phone-map-selection-frame'),
            decoration: BoxDecoration(
              color: c.accentTint,
              border: Border.all(color: c.accent, width: 1.5),
            ),
          ),
        ),
        for (final corner in {
          'topLeft': r.topLeft,
          'topRight': r.topRight,
          'bottomLeft': r.bottomLeft,
          'bottomRight': r.bottomRight,
        }.entries)
          Positioned(
            left: corner.value.dx - 22,
            top: corner.value.dy - 22,
            child: SizedBox(
              key: ValueKey('phone-map-selection-handle-${corner.key}'),
              width: 44,
              height: 44,
              child: Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.windowBackground, width: 2),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => MMBackHandler(
    onBack: () {
      if (!selection.active) return false;
      selection.cancel();
      return true;
    },
    child: Semantics(
      container: true,
      explicitChildNodes: true,
      child: AnimatedBuilder(
        animation: Listenable.merge([selection, widget.transformation]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            _size = constraints.biggest;
            final l = context.l10n;
            final nodes = widget.nodes();
            return Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _pointerDown,
                    onPointerUp: (e) => _pointers.remove(e.pointer),
                    onPointerCancel: (e) {
                      _pointers.remove(e.pointer);
                      _stroke = false;
                      selection.rollbackStroke();
                      _stopScroll();
                    },
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        gestureSettings: selection.mode == PhoneMapSelectionMode.box
                            ? const DeviceGestureSettings(touchSlop: 8)
                            : MediaQuery.gestureSettingsOf(context),
                      ),
                      child: GestureDetector(
                        key: const ValueKey('phone-map-selection-input'),
                        excludeFromSemantics: true,
                        behavior: HitTestBehavior.opaque,
                        onTapUp: _tap,
                        onScaleStart: _start,
                        onScaleUpdate: _update,
                        onScaleEnd: _end,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Stack(
                      children: [
                        if (selection.frame case final rect?) _frame(context, _screen(rect)),
                        for (final id in selection.selected)
                          if (nodes[id] case final rect?)
                            Positioned(
                              left: _screen(rect).right - 8,
                              top: _screen(rect).top - 8,
                              child: Container(
                                key: ValueKey('phone-map-selected-$id'),
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(color: context.mmColors.accent, shape: BoxShape.circle),
                                child: Icon(MMIcons.check, size: 14, color: context.mmColors.onAccent),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                for (final e in nodes.entries)
                  if (_screen(e.value).overlaps(Offset.zero & _size))
                    Positioned.fromRect(
                      rect: _screen(e.value),
                      child: Semantics(
                        key: ValueKey('phone-map-select-accessibility-${e.key}'),
                        label: widget.labelForNode?.call(e.key) ?? e.key,
                        button: true,
                        selected: selection.selected.contains(e.key),
                        onTap: () => selection.toggle(e.key),
                        child: const IgnorePointer(child: SizedBox.expand()),
                      ),
                    ),
                Positioned(
                  top: _top + 8,
                  left: _safe.left + 12,
                  right: _safe.right + 12,
                  child: MMGlass(
                    key: const ValueKey('phone-map-selection-header'),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        MMButton(
                          key: const ValueKey('phone-map-selection-cancel'),
                          label: l.cancel,
                          onPressed: selection.cancel,
                        ),
                        Expanded(
                          child: Text(
                            l.mapSelectionCount(selection.selected.length),
                            textAlign: TextAlign.center,
                            style: context.mmText.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        MMButton(
                          key: const ValueKey('phone-map-selection-done'),
                          label: l.done,
                          variant: MMButtonVariant.primary,
                          onPressed: widget.onDone,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: _bottom,
                  left: _safe.left + 12,
                  right: _safe.right + 12,
                  child: MMGlass(
                    key: const ValueKey('phone-map-selection-controls'),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: MMSegmentedControl<PhoneMapSelectionMode>(
                                value: selection.mode,
                                segments: [
                                  MMSegment(value: PhoneMapSelectionMode.tap, label: l.mapSelectionTap),
                                  MMSegment(value: PhoneMapSelectionMode.box, label: l.mapSelectionBox),
                                ],
                                onChanged: selection.setMode,
                              ),
                            ),
                            const SizedBox(width: 8),
                            MMButton(
                              key: const ValueKey('phone-map-selection-clear'),
                              label: l.mapSelectionClear,
                              onPressed: selection.clear,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          selection.mode == PhoneMapSelectionMode.box ? l.mapSelectionBoxHint : l.mapSelectionTapHint,
                          style: context.mmText.footnote,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
