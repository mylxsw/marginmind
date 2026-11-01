import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';

/// Changes remain a draft until Apply (or a preset) is chosen.
class HighlightCustomColorPicker extends StatefulWidget {
  const HighlightCustomColorPicker({
    super.key,
    required this.current,
    required this.onSelected,
    required this.onCancel,
  });
  final MMAnnotationColor current;
  final ValueChanged<MMAnnotationColor> onSelected;
  final VoidCallback onCancel;

  @override
  State<HighlightCustomColorPicker> createState() => _HighlightCustomColorPickerState();
}

class _HighlightCustomColorPickerState extends State<HighlightCustomColorPicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.current.color);
  late final _hex = TextEditingController(text: widget.current.hex);
  bool _valid = true;

  MMAnnotationColor get _color => MMAnnotationColor.fromColor(_hsv.toColor());

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(HSVColor value) => setState(() {
    _hsv = value;
    _valid = true;
    _hex.text = _color.hex;
  });

  void _fromHex(String value) {
    final color = MMAnnotationColor.tryParse(value.startsWith('#') ? value : '#$value');
    setState(() {
      _valid = color != null;
      if (color != null) _hsv = HSVColor.fromColor(color.color);
    });
  }

  void _apply() {
    if (_valid) widget.onSelected(_color);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, c = context.mmColors;
    return MMGlass(
      key: const ValueKey('highlight-custom-color-picker'),
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(l.highlightCustomColor, style: context.mmText.headline)),
                MMIconButton(icon: MMIcons.close, tooltip: l.cancel, onPressed: widget.onCancel, size: 26),
              ],
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final color in MMAnnotationColor.values)
                        MMFloatingToolbarColor(
                          color: color,
                          tooltip: l.colorName(color),
                          selected: color == _color,
                          onPressed: () => widget.onSelected(color),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _SaturationValue(value: _hsv, label: l.highlightColorSaturationValue, onChanged: _set),
            const SizedBox(height: 6),
            SizedBox(
              height: 34,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFFF0000),
                            Color(0xFFFFFF00),
                            Color(0xFF00FF00),
                            Color(0xFF00FFFF),
                            Color(0xFF0000FF),
                            Color(0xFFFF00FF),
                            Color(0xFFFF0000),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
                      overlayColor: c.accent.withValues(alpha: .15),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      showValueIndicator: ShowValueIndicator.never,
                    ),
                    child: Slider(
                      key: const ValueKey('highlight-color-hue'),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      label: l.highlightColorHue,
                      semanticFormatterCallback: (value) => '${l.highlightColorHue} ${value.round()}°',
                      value: _hsv.hue,
                      min: 0,
                      max: 360,
                      onChanged: (value) => _set(_hsv.withHue(value)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  key: const ValueKey('highlight-color-preview'),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _color.color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.separator),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey('highlight-color-hex'),
                    controller: _hex,
                    style: context.mmText.body,
                    maxLength: 7,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]'))],
                    decoration: InputDecoration(
                      labelText: l.highlightColorHex,
                      isDense: true,
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: _fromHex,
                    onSubmitted: (_) => _apply(),
                  ),
                ),
              ],
            ),
            if (!_valid)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l.highlightColorHexInvalid, style: context.mmText.footnote.copyWith(color: c.critical)),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MMButton(label: l.cancel, onPressed: widget.onCancel),
                const SizedBox(width: 8),
                MMButton(
                  key: const ValueKey('highlight-color-apply'),
                  label: l.done,
                  variant: MMButtonVariant.primary,
                  onPressed: _valid ? _apply : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SaturationValue extends StatelessWidget {
  const _SaturationValue({required this.value, required this.onChanged, required this.label});
  final HSVColor value;
  final ValueChanged<HSVColor> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const height = 130.0;
      final width = constraints.maxWidth;
      void update(Offset point) => onChanged(
        value.withSaturation((point.dx / width).clamp(0, 1)).withValue((1 - point.dy / height).clamp(0, 1)),
      );
      void move(double saturation, double brightness) => onChanged(
        value
            .withSaturation((value.saturation + saturation).clamp(0, 1))
            .withValue((value.value + brightness).clamp(0, 1)),
      );
      return Semantics(
        label: label,
        value: '${(value.saturation * 100).round()}%, ${(value.value * 100).round()}%',
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyUpEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.arrowLeft) {
              move(-.01, 0);
            } else if (key == LogicalKeyboardKey.arrowRight) {
              move(.01, 0);
            } else if (key == LogicalKeyboardKey.arrowUp) {
              move(0, .01);
            } else if (key == LogicalKeyboardKey.arrowDown) {
              move(0, -.01);
            } else {
              return KeyEventResult.ignored;
            }
            return KeyEventResult.handled;
          },
          child: Builder(
            builder: (context) => GestureDetector(
              key: const ValueKey('highlight-color-saturation-value'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                Focus.of(context).requestFocus();
                update(details.localPosition);
              },
              onPanStart: (details) {
                Focus.of(context).requestFocus();
                update(details.localPosition);
              },
              onPanUpdate: (details) => update(details.localPosition),
              child: SizedBox(
                height: height,
                child: CustomPaint(painter: _SaturationValuePainter(value)),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _SaturationValuePainter extends CustomPainter {
  _SaturationValuePainter(this.value);
  final HSVColor value;
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(bounds, const Radius.circular(8)));
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(colors: [Colors.white, HSVColor.fromAHSV(1, value.hue, 1, 1).toColor()])
            .createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(bounds),
    );
    canvas.restore();
    final point = Offset(value.saturation * size.width, (1 - value.value) * size.height);
    canvas.drawCircle(
      point,
      6,
      Paint()
        ..color = Colors.black.withValues(alpha: .6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    canvas.drawCircle(
      point,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter old) => old.value != value;
}
