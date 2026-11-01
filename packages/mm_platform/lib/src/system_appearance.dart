import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Host appearance, accessibility and pointer timing. On platforms
/// without the native channel every value is the default.
@immutable
class SystemAppearance {
  const SystemAppearance({
    this.accentColor,
    this.reduceTransparency = false,
    this.reduceMotion = false,
    this.increaseContrast = false,
    this.doubleClickInterval = const Duration(milliseconds: 300),
  });

  /// System accent (System Settings › Appearance), or null to keep the
  /// design default.
  final Color? accentColor;
  final bool reduceTransparency;
  final bool reduceMotion;
  final bool increaseContrast;

  /// Pointer double-click timing from the host OS.
  final Duration doubleClickInterval;

  factory SystemAppearance.fromMap(Map<Object?, Object?> map) {
    final accent = map['accent'];
    final interval = map['doubleClickIntervalMs'];
    return SystemAppearance(
      accentColor: accent is int ? Color(accent) : null,
      reduceTransparency: map['reduceTransparency'] == true,
      reduceMotion: map['reduceMotion'] == true,
      increaseContrast: map['increaseContrast'] == true,
      doubleClickInterval: interval is int && interval > 0
          ? Duration(milliseconds: interval)
          : const Duration(milliseconds: 300),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SystemAppearance &&
      other.accentColor == accentColor &&
      other.reduceTransparency == reduceTransparency &&
      other.reduceMotion == reduceMotion &&
      other.increaseContrast == increaseContrast &&
      other.doubleClickInterval == doubleClickInterval;

  @override
  int get hashCode => Object.hash(accentColor, reduceTransparency, reduceMotion, increaseContrast, doubleClickInterval);
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

  /// Emits when preferences change or the app becomes active again.
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
