import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// System notification delivery for background task completion.
abstract final class MMSystemNotification {
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static const _channel = MethodChannel('marginmind/system_notification');
  static const int maxTitleLength = 256;
  static const int maxBodyLength = 512;

  static Future<bool> show({required String title, required String body}) async {
    if (title.isEmpty || body.isEmpty) return false;
    final safeTitle = _truncate(title, maxTitleLength);
    final safeBody = _truncate(body, maxBodyLength);
    try {
      await _channel.invokeMethod<void>('notify', {'title': safeTitle, 'body': safeBody});
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength - 1)}…';
  }
}
