import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// System speech synthesis. Never sends the term to a remote speech service.
abstract final class MMSpeech {
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static const _channel = MethodChannel('marginmind/speech');
  static Future<void> speak(String text, {required String language}) =>
      _channel.invokeMethod<void>('speak', {'text': text, 'language': language});
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      /* Stop is best effort after a failed session. */
    } on MissingPluginException {
      /* No speech session on this host. */
    }
  }
}
