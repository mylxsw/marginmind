import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/appearance');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });
  test('reads native appearance, receives changes, and disposes channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final source = SystemAppearanceSource(channel: channel);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'accent': 0xFF123456, 'reduceMotion': true, 'doubleClickIntervalMs': 500},
    );
    final initial = await source.read();
    expect(initial.accentColor, const Color(0xFF123456));
    expect(initial.reduceMotion, isTrue);
    expect(initial.doubleClickInterval, const Duration(milliseconds: 500));
    final changes = source.changes;
    expect(source.changes.isBroadcast, isTrue);
    final next = changes.first;
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('changed', {'increaseContrast': true, 'doubleClickIntervalMs': 700}),
      ),
      (_) {},
    );
    final changed = await next;
    expect(changed, const SystemAppearance(increaseContrast: true, doubleClickInterval: Duration(milliseconds: 700)));
    expect(
      changed.hashCode,
      const SystemAppearance(increaseContrast: true, doubleClickInterval: Duration(milliseconds: 700)).hashCode,
    );
    await source.dispose();
  });
  test('missing plugin, empty native reply, and non-Mac use defaults', () async {
    final source = SystemAppearanceSource(channel: channel);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(await source.read(), const SystemAppearance());
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await source.read(), const SystemAppearance());
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(await source.read(), const SystemAppearance());
    await source.dispose();
  });
}
