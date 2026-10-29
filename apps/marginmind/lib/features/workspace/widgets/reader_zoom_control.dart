import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../shared/l10n.dart';

/// A menu entry that remains open while the reader adjusts the PDF size.
class ReaderZoomSlider extends PopupMenuEntry<Object> {
  const ReaderZoomSlider({super.key, required this.pdf, required this.enabled});

  final MMPdfViewController pdf;
  final bool enabled;

  @override
  double get height => 88;
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
    _value = (math.log(widget.pdf.zoom / widget.pdf.widthZoom) / math.ln2).clamp(-2.0, 2.0);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 260,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.s),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${(math.pow(2, _value) * 100).round()}%', style: context.mmText.callout),
          Row(
            children: [
              Icon(MMIcons.zoomOut, size: MMSpacing.l, semanticLabel: context.l10n.zoomOut),
              Expanded(
                child: Slider(
                  key: const ValueKey('reader-zoom-slider'),
                  value: _value,
                  min: -2,
                  max: 2,
                  secondaryTrackValue: 0,
                  semanticFormatterCallback: (value) => '${(math.pow(2, value) * 100).round()}%',
                  onChanged: !widget.enabled || !widget.pdf.isReady
                      ? null
                      : (value) {
                          // A small center detent makes width fitting easy to recover.
                          final next = value.abs() < .06 ? 0.0 : value;
                          setState(() => _value = next);
                          widget.pdf.setWidthZoom(math.pow(2, next).toDouble());
                        },
                ),
              ),
              Icon(MMIcons.zoomIn, size: MMSpacing.l, semanticLabel: context.l10n.zoomIn),
            ],
          ),
        ],
      ),
    ),
  );
}
