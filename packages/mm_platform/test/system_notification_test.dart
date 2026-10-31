import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('marginmind/system_notification');

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('system notification support is exposed for the native macOS channel', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(MMSystemNotification.supported, platform == TargetPlatform.macOS);
    }
  });

  test('MMSystemNotification.show sends title and body and handles empty/error states gracefully', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });

    expect(await MMSystemNotification.show(title: '', body: 'doc'), isFalse);
    expect(await MMSystemNotification.show(title: 'done', body: ''), isFalse);
    expect(calls, isEmpty);

    expect(await MMSystemNotification.show(title: '全文翻译完成', body: 'Learning and memory'), isTrue);
    expect(calls.length, 1);
    expect(calls.single.method, 'notify');
    expect(calls.single.arguments, {'title': '全文翻译完成', 'body': 'Learning and memory'});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'notification');
    });
    expect(await MMSystemNotification.show(title: '全文翻译完成', body: 'Learning and memory'), isFalse);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    expect(await MMSystemNotification.show(title: '全文翻译完成', body: 'Learning and memory'), isFalse);
  });
}
