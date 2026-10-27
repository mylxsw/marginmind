import 'package:flutter/services.dart';

/// macOS encoders. PDF commands contain paths, images and individual text lines,
/// never a screenshot; the text remains searchable when opened in Preview.
class NativeMapExport {
  // Named channel injection keeps native failure paths testable.
  // ignore: prefer_initializing_formals
  const NativeMapExport({MethodChannel channel = const MethodChannel('marginmind/map_export')}) : _channel = channel;
  final MethodChannel _channel;

  Future<Uint8List> pdf(Map<String, Object?> scene) => _encode('pdf', scene);

  Future<Uint8List> png(int width, int height, List<Map<String, Object?>> tiles) =>
      _encode('png', {'width': width, 'height': height, 'tiles': tiles});

  Future<Uint8List> _encode(String method, Map<String, Object?> arguments) async {
    final bytes = await _channel.invokeMethod<Uint8List>(method, arguments);
    if (bytes == null || bytes.isEmpty) throw StateError('Empty map export');
    return bytes;
  }
}
