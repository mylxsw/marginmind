import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../foundation/appearance.dart';

/// The three approved palettes of the circular assistant mark.
enum MMAssistantPalette { iris, jade, apricot }

/// Circular assistant with capsule eyes tilted by eight degrees.
/// Idle icons schedule no frames. Only the eyes respond to interaction/work.
class MMAssistantIcon extends StatefulWidget {
  const MMAssistantIcon({
    super.key,
    this.palette = MMAssistantPalette.iris,
    this.size,
    this.thinking = false,
    this.animated = true,
  });

  final MMAssistantPalette palette;
  final double? size;
  final bool thinking;

  /// False for static colour swatches. Accessibility, TickerMode and app
  /// visibility also suspend all motion.
  final bool animated;

  @override
  State<MMAssistantIcon> createState() => _MMAssistantIconState();
}

class _MMAssistantIconState extends State<MMAssistantIcon> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  late final _x = AnimationController.unbounded(vsync: this);
  late final _y = AnimationController.unbounded(vsync: this);
  late final _scan = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  late final _working = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
    ..addStatusListener((status) {
      if (status == AnimationStatus.dismissed) _scan.stop();
    });
  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: 1);
  bool _reduced = false, _visible = true;
  late bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _enabled => widget.animated && !_reduced && _visible && _foreground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MMAppearance.reduceMotionOf(context);
    _visible = TickerMode.valuesOf(context).enabled;
    _syncMotion();
  }

  @override
  void didUpdateWidget(MMAssistantIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
    if (oldWidget.thinking && !widget.thinking) _blinkOnce();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  void _syncMotion() {
    if (!_enabled) {
      for (final controller in [_blink, _x, _y, _scan, _working]) {
        controller.stop();
        controller.value = 0;
      }
    } else if (widget.thinking) {
      if (!_scan.isAnimating) _scan.repeat();
      if (_working.value != 1) _working.forward();
    } else if (_working.value > 0) {
      // Fade the current scan out instead of snapping the eyes to centre.
      _working.reverse();
    } else {
      _scan.stop();
    }
  }

  void _blinkOnce() {
    if (_enabled && !_blink.isAnimating) _blink.forward(from: 0);
  }

  void _look(Offset position) {
    if (!_enabled || widget.thinking) return;
    void move(AnimationController controller, double target) =>
        controller.animateWith(SpringSimulation(_spring, controller.value, target, controller.velocity));
    move(_x, position.dx);
    move(_y, position.dy);
  }

  void _hover(Offset position) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.isEmpty) return;
    _look(
      Offset(
        (position.dx / box.size.width * 2 - 1).clamp(-1.0, 1.0) * 10,
        (position.dy / box.size.height * 2 - 1).clamp(-1.0, 1.0) * 6,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in [_blink, _x, _y, _scan, _working]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return ExcludeSemantics(
      child: Opacity(
        opacity: theme.opacity ?? 1,
        child: SizedBox.square(
          dimension: widget.size ?? theme.size ?? 24,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _blinkOnce(),
            child: MouseRegion(
              opaque: false,
              onEnter: (event) {
                _hover(event.localPosition);
                _blinkOnce();
              },
              onHover: (event) => _hover(event.localPosition),
              onExit: (_) => _look(Offset.zero),
              child: RepaintBoundary(
                child: CustomPaint(painter: _AssistantPainter(widget.palette, _blink, _x, _y, _scan, _working)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantPainter extends CustomPainter {
  _AssistantPainter(this.palette, this.blink, this.x, this.y, this.scan, this.working)
    : super(repaint: Listenable.merge([blink, x, y, scan, working]));

  final MMAssistantPalette palette;
  final Animation<double> blink, x, y, scan, working;

  @override
  void paint(Canvas canvas, Size size) {
    final (start, end, eyes) = switch (palette) {
      MMAssistantPalette.iris => (const Color(0xFF6254DB), const Color(0xFF3278C8), const Color(0xFFFFFFFF)),
      MMAssistantPalette.jade => (const Color(0xFF087E84), const Color(0xFF168B7B), const Color(0xFFFFFFFF)),
      MMAssistantPalette.apricot => (const Color(0xFFF9AE62), const Color(0xFFF28B52), const Color(0xFF643321)),
    };
    // Keep the approved SVG's geometry and gradient, cropped to its circle.
    canvas.scale(size.width / 184, size.height / 184);
    canvas.translate(-36, -36);
    final fill = Paint()
      ..shader = LinearGradient(
        colors: [start, end],
        begin: const Alignment(-.625, -.6875),
        end: const Alignment(.671875, .609375),
      ).createShader(const Rect.fromLTWH(0, 0, 256, 256));
    canvas.drawCircle(const Offset(128, 128), 92, fill);
    final eyePaint = Paint()..color = eyes;
    final phase = scan.value * math.pi * 2;
    final blend = Curves.easeInOut.transform(working.value);
    final gaze = Offset(
      x.value * (1 - blend) + math.sin(phase) * 8 * blend,
      y.value * (1 - blend) + (math.cos(phase) - 1) * 2 * blend,
    );
    final t = blink.value;
    final openness = t < .4
        ? 1 - Curves.easeInCubic.transform(t / .4) * .86
        : .14 + Curves.easeOutCubic.transform((t - .4) / .6) * .86;
    final height = 52 * openness;
    for (final eyeX in [100.0, 156.0]) {
      canvas.save();
      canvas.translate(eyeX + gaze.dx, 124 + gaze.dy);
      canvas.rotate(8 * math.pi / 180);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-10, -height / 2, 20, height), const Radius.circular(10)),
        eyePaint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_AssistantPainter oldDelegate) => oldDelegate.palette != palette;
}
