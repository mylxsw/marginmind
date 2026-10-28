import 'package:flutter/services.dart';

/// Native implementations own temporary files and their sharing lifetime.
class MobileFileShare {
  const MobileFileShare({this.channel = const MethodChannel('marginmind/file_share')});
  final MethodChannel channel;

  Future<bool> share(String name, Uint8List bytes) async {
    if (name.isEmpty || name.contains(RegExp(r'[/\\\x00-\x1f]')) || bytes.isEmpty) {
      throw ArgumentError('Invalid shared file');
    }
    return await channel.invokeMethod<bool>('share', {'name': name, 'bytes': bytes}) ?? false;
  }
}
