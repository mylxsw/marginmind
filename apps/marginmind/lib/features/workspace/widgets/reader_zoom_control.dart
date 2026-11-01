import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../shared/l10n.dart';

/// A compact menu row that stays open while buttons or a vertical drag zoom.
class ReaderZoomControl extends PopupMenuEntry<Object> {
  const ReaderZoomControl({super.key, required this.pdf, required this.enabled})
    : ratio = null,
      onZoom = null,
      ready = null;
  const ReaderZoomControl.source({
    super.key,
    required this.ratio,
    required this.onZoom,
    required this.ready,
    required this.enabled,
  }) : pdf = null;

  final MMPdfViewController? pdf;
  final double Function()? ratio;
  final ValueChanged<double>? onZoom;
  final bool Function()? ready;
  final bool enabled;

  @override
  double get height => MMSizes.dropdownRowHeight;
  @override
  bool represents(Object? value) => false;
  @override
  State<ReaderZoomControl> createState() => _ReaderZoomControlState();
}

class _ReaderZoomControlState extends State<ReaderZoomControl> {
  final _focus = FocusNode();
  late double _value;
  int? _pointer;
  double _lastY = 0;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _value = _readValue();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  double _readValue() {
    final ratio = widget.ratio?.call() ?? widget.pdf!.zoom / widget.pdf!.widthZoom;
    return ratio.isFinite && ratio > 0 ? (math.log(ratio) / math.ln2).clamp(-2.0, 2.0) : 0;
  }

  bool get _enabled => widget.enabled && (widget.ready?.call() ?? widget.pdf!.isReady);

  void _change(double value) {
    if (!_enabled) return;
    final next = value.clamp(-2.0, 2.0);
    setState(() => _value = next);
    final ratio = math.pow(2, next).toDouble();
    if (widget.onZoom != null) {
      widget.onZoom!(ratio);
    } else {
      widget.pdf!.setWidthZoom(ratio);
    }
  }

  void _endPointer(PointerEvent event) {
    if (event.pointer == _pointer) setState(() => _pointer = null);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final touch = context.mmTouch || context.mmTouchPlatform;
    final percentage = '${(math.pow(2, _value) * 100).round()}%';
    return SizedBox(
      key: const ValueKey('reader-zoom-control'),
      width: 260,
      height: touch ? MMSizes.touchTarget : widget.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s),
        child: Row(
          children: [
            Expanded(child: Text(l.readerZoomLabel, style: context.mmText.callout)),
            MMToolbarButton(
              icon: MMReaderIcons.zoomOut,
              tooltip: l.zoomOut,
              onPressed: _enabled && _value > -2 ? () => _change(_value - .25) : null,
            ),
            Focus(
              focusNode: _focus,
              canRequestFocus: _enabled,
              onFocusChange: (_) => setState(() {}),
              onKeyEvent: (_, event) {
                if (!_enabled || (event is! KeyDownEvent && event is! KeyRepeatEvent)) return KeyEventResult.ignored;
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
                  _change(_value + (key == LogicalKeyboardKey.arrowUp ? .25 : -.25));
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Semantics(
                label: l.readerZoomLabel,
                value: percentage,
                increasedValue: _enabled && _value < 2
                    ? '${(math.pow(2, (_value + .25).clamp(-2.0, 2.0)) * 100).round()}%'
                    : null,
                decreasedValue: _enabled && _value > -2
                    ? '${(math.pow(2, (_value - .25).clamp(-2.0, 2.0)) * 100).round()}%'
                    : null,
                hint: l.readerZoomDragHint,
                enabled: _enabled,
                slider: true,
                onIncrease: _enabled && _value < 2 ? () => _change(_value + .25) : null,
                onDecrease: _enabled && _value > -2 ? () => _change(_value - .25) : null,
                child: Tooltip(
                  message: l.readerZoomDragHint,
                  child: MouseRegion(
                    cursor: _enabled ? SystemMouseCursors.resizeUpDown : SystemMouseCursors.basic,
                    onEnter: (_) => setState(() => _hovered = true),
                    onExit: (_) => setState(() => _hovered = false),
                    child: Listener(
                      key: const ValueKey('reader-zoom-percentage'),
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (event) {
                        if (!_enabled || event.buttons != kPrimaryButton || _pointer != null) return;
                        _focus.requestFocus();
                        setState(() {
                          _pointer = event.pointer;
                          _lastY = event.position.dy;
                          _value = _readValue();
                        });
                      },
                      onPointerMove: (event) {
                        if (event.pointer != _pointer) return;
                        // 160 logical pixels doubles/halves the scale. Clamp each
                        // move so reversing at a limit responds immediately.
                        final delta = event.position.dy - _lastY;
                        _lastY = event.position.dy;
                        _change(_value - delta / 160);
                      },
                      onPointerUp: _endPointer,
                      onPointerCancel: _endPointer,
                      child: Container(
                        width: 54,
                        height: touch ? MMSizes.touchTarget : widget.height,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _pointer != null
                              ? context.mmColors.accentTint
                              : _hovered
                              ? context.mmColors.hover
                              : null,
                          borderRadius: BorderRadius.circular(MMRadii.row),
                          border: _focus.hasFocus ? Border.all(color: context.mmColors.accent) : null,
                        ),
                        child: ExcludeSemantics(
                          child: Text(
                            percentage,
                            style: context.mmText.callout.copyWith(
                              color: _enabled ? context.mmColors.label : context.mmColors.secondaryLabel,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            MMToolbarButton(
              icon: MMReaderIcons.zoomIn,
              tooltip: l.zoomIn,
              onPressed: _enabled && _value < 2 ? () => _change(_value + .25) : null,
            ),
          ],
        ),
      ),
    );
  }
}
