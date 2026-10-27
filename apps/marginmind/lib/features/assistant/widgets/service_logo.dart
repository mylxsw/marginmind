import 'package:flutter/material.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_design/mm_design.dart';

import 'service_marks.g.dart';

/// Which mark a service shows: OpenAI's own for its API, a monogram for
/// other OpenAI-compatible services.
enum ServiceBrand { anthropic, openai, compatible, gemini, ollama }

ServiceBrand serviceBrand(ServiceProtocol protocol, String endpoint) => switch (protocol) {
  ServiceProtocol.anthropic => ServiceBrand.anthropic,
  ServiceProtocol.gemini => ServiceBrand.gemini,
  ServiceProtocol.ollama => ServiceBrand.ollama,
  ServiceProtocol.openai => Uri.tryParse(endpoint.trim())?.host == 'api.openai.com'
      ? ServiceBrand.openai
      : ServiceBrand.compatible,
};

/// A service's official mark on its brand tile ([size] square, rounded).
class ServiceLogo extends StatelessWidget {
  const ServiceLogo({super.key, required this.brand, this.name = '', this.size = 30});

  final ServiceBrand brand;

  /// Its first letter is the monogram of a compatible service.
  final String name;
  final double size;

  static const _anthropic = Color(0xFFD97757);

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final radius = BorderRadius.circular(size * .24);
    final (Decoration decoration, Widget glyph) = switch (brand) {
      ServiceBrand.anthropic => (
        BoxDecoration(color: _anthropic, borderRadius: radius),
        _Mark(anthropicMark, color: Colors.white, scale: .5),
      ),
      ServiceBrand.openai => (
        BoxDecoration(color: Colors.black, borderRadius: radius),
        _Mark(openaiMark, color: Colors.white, scale: .62),
      ),
      ServiceBrand.gemini => (
        BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          border: Border.all(color: c.separator, width: .5),
        ),
        const _Mark(
          geminiMark,
          scale: .66,
          gradient: LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: [Color(0xFF1C7DFF), Color(0xFF8A5CF6), Color(0xFFE76FA8)],
          ),
        ),
      ),
      ServiceBrand.ollama => (
        BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          border: Border.all(color: c.separator, width: .5),
        ),
        _Mark(ollamaMark, color: Colors.black, scale: .64),
      ),
      ServiceBrand.compatible => (
        BoxDecoration(
          borderRadius: radius,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF6B7A8F), Color(0xFF475467)],
          ),
        ),
        Text(
          name.trim().isEmpty ? 'O' : String.fromCharCode(name.trim().runes.first).toUpperCase(),
          style: TextStyle(color: Colors.white, fontSize: size * .46, fontWeight: FontWeight.w600, height: 1),
        ),
      ),
    };
    return ExcludeSemantics(
      child: Container(
        key: ValueKey('service-logo-${brand.name}'),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: decoration,
        child: glyph,
      ),
    );
  }
}

/// A 24×24 mark scaled to [scale] of its tile, in one color or a gradient.
class _Mark extends StatelessWidget {
  const _Mark(this.path, {this.color, this.gradient, required this.scale});

  final Path Function() path;
  final Color? color;
  final Gradient? gradient;
  final double scale;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: scale,
    heightFactor: scale,
    child: CustomPaint(painter: _MarkPainter(path, color, gradient)),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.path, this.color, this.gradient);

  final Path Function() path;
  final Color? color;
  final Gradient? gradient;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()..isAntiAlias = true;
    if (gradient != null) {
      paint.shader = gradient!.createShader(const Rect.fromLTWH(0, 0, 24, 24));
    } else {
      paint.color = color!;
    }
    canvas.drawPath(path(), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.path != path || old.color != color || old.gradient != gradient;
}
