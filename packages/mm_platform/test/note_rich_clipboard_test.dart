import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(MMMapClipboard.channel, null);
  });
  test('rich clipboard transports both representations and losslessly transports PNG', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(MMMapClipboard.channel, (call) async {
      calls.add(call);
      return null;
    });
    await MMMapClipboard.writeRichText(html: '<h1>A</h1>', text: 'A');
    expect(calls.single.method, 'writeRichText');
    expect(calls.single.arguments, {'html': '<h1>A</h1>', 'text': 'A'});
    await MMMapClipboard.writeImage(Uint8List.fromList([1, 2, 3]));
    expect(calls.last.method, 'writeImage');
    expect((calls.last.arguments as Map)['bytes'], [1, 2, 3]);
    messenger.setMockMethodCallHandler(
      MMMapClipboard.channel,
      (_) async => throw PlatformException(code: 'clipboard_write'),
    );
    await expectLater(MMMapClipboard.writeRichText(html: '', text: ''), throwsA(isA<PlatformException>()));
    await expectLater(MMMapClipboard.writeImage(Uint8List(0)), throwsA(isA<PlatformException>()));
  });
  test('unsupported platforms do not invoke structured clipboard channels', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await expectLater(MMMapClipboard.writeRichText(html: '', text: ''), throwsUnsupportedError);
    await expectLater(MMMapClipboard.writeImage(Uint8List(0)), throwsUnsupportedError);
  });
}
