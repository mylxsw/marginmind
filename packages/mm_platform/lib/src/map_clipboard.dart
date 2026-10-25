import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The native pasteboard writes both representations in the same item.
abstract final class MMMapClipboard {
  static const channel = MethodChannel('marginmind/map_clipboard');

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
