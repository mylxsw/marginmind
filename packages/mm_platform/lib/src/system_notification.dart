import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// System notification delivery for background task completion.
abstract final class MMSystemNotification {
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static const _channel = MethodChannel('marginmind/system_notification');

  static Future<bool> show({required String title, required String body}) async {
    if (title.isEmpty || body.isEmpty) return false;
    try {
      await _channel.invokeMethod<void>('notify', {'title': title, 'body': body});
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
