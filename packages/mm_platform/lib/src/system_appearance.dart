import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the system says about accent color and accessibility. On platforms
/// without the native channel every value is the default.
@immutable
class SystemAppearance {
  const SystemAppearance({
    this.accentColor,
    this.reduceTransparency = false,
    this.reduceMotion = false,
    this.increaseContrast = false,
  });

  /// System accent (System Settings › Appearance), or null to keep the
  /// design default.
  final Color? accentColor;
  final bool reduceTransparency;
  final bool reduceMotion;
  final bool increaseContrast;

  factory SystemAppearance.fromMap(Map<Object?, Object?> map) {
    final accent = map['accent'];
    return SystemAppearance(
      accentColor: accent is int ? Color(accent) : null,
      reduceTransparency: map['reduceTransparency'] == true,
      reduceMotion: map['reduceMotion'] == true,
      increaseContrast: map['increaseContrast'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SystemAppearance &&
      other.accentColor == accentColor &&
      other.reduceTransparency == reduceTransparency &&
      other.reduceMotion == reduceMotion &&
      other.increaseContrast == increaseContrast;

  @override
  int get hashCode => Object.hash(accentColor, reduceTransparency, reduceMotion, increaseContrast);
}

/// Reads [SystemAppearance] from the macOS runner
/// (`macos/Runner/MainFlutterWindow.swift`) and reports changes.
class SystemAppearanceSource {
  SystemAppearanceSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('marginmind/system_appearance');

  final MethodChannel _channel;
  final _changes = StreamController<SystemAppearance>.broadcast();
  bool _listening = false;

  Future<SystemAppearance> read() async {
    if (defaultTargetPlatform != TargetPlatform.macOS || kIsWeb) return const SystemAppearance();
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>('read');
      return map == null ? const SystemAppearance() : SystemAppearance.fromMap(map);
    } on MissingPluginException {
      return const SystemAppearance();
    }
  }

  /// Emits whenever the accent color or accessibility options change.
  Stream<SystemAppearance> get changes {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'changed' && call.arguments is Map) {
          _changes.add(SystemAppearance.fromMap(call.arguments as Map<Object?, Object?>));
        }
      });
    }
    return _changes.stream;
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _changes.close();
  }
}
