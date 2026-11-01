import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../shared/l10n.dart';

/// A menu entry that remains open while the reader adjusts page size.
class ReaderZoomSlider extends PopupMenuEntry<Object> {
  const ReaderZoomSlider({super.key, required this.pdf, required this.enabled})
    : ratio = null,
      onZoom = null,
      ready = null;
  const ReaderZoomSlider.source({
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
  double get height => 56;
  @override
  bool represents(Object? value) => false;
  @override
  State<ReaderZoomSlider> createState() => _ReaderZoomSliderState();
}

class _ReaderZoomSliderState extends State<ReaderZoomSlider> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = (math.log((widget.ratio?.call() ?? widget.pdf!.zoom / widget.pdf!.widthZoom)) / math.ln2).clamp(-2.0, 2.0);
  }

  bool get _enabled => widget.enabled && (widget.ready?.call() ?? widget.pdf!.isReady);

  void _change(double value) {
    final bounded = value.clamp(-2.0, 2.0);
    final next = bounded.abs() < .06 ? 0.0 : bounded;
    setState(() => _value = next);
    final ratio = math.pow(2, next).toDouble();
    if (widget.onZoom != null) {
      widget.onZoom!(ratio);
    } else {
      widget.pdf!.setWidthZoom(ratio);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 260,
    height: widget.height,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.xs),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        ),
        child: Row(
          children: [
            MMToolbarButton(
              icon: MMReaderIcons.zoomOut,
              tooltip: context.l10n.zoomOut,
              onPressed: _enabled && _value > -2 ? () => _change(_value - .25) : null,
            ),
            Expanded(
              child: Slider(
                key: const ValueKey('reader-zoom-slider'),
                value: _value,
                min: -2,
                max: 2,
                secondaryTrackValue: 0,
                semanticFormatterCallback: (value) => '${(math.pow(2, value) * 100).round()}%',
                onChanged: _enabled ? _change : null,
              ),
            ),
            Text('${(math.pow(2, _value) * 100).round()}%', style: context.mmText.footnote),
            MMToolbarButton(
              icon: MMReaderIcons.zoomIn,
              tooltip: context.l10n.zoomIn,
              onPressed: _enabled && _value < 2 ? () => _change(_value + .25) : null,
            ),
          ],
        ),
      ),
    ),
  );
}
