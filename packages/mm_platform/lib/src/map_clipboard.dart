import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The native pasteboard writes both representations in the same item.
abstract final class MMMapClipboard {
  static const channel = MethodChannel('marginmind/map_clipboard');

  /// Screenshot bytes, or a Finder image URL, copied into the package by callers.
  static Future<({Uint8List? bytes, String? path})?> readImage() async {
    if (defaultTargetPlatform != TargetPlatform.macOS) return null;
    final data = await channel.invokeMapMethod<String, Object?>('readImage');
    if (data == null || (data['bytes'] == null && data['path'] == null)) return null;
    return (bytes: data['bytes'] as Uint8List?, path: data['path'] as String?);
  }

  static Future<void> write({required String text, required String internal}) async {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      await channel.invokeMethod<void>('write', {'text': text, 'internal': internal});
    } else {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  static Future<({String text, String? internal})> read() async {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      final data = await channel.invokeMapMethod<String, String>('read');
      return (text: data?['text'] ?? '', internal: data?['internal']);
    }
    return (text: (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '', internal: null);
  }
}
