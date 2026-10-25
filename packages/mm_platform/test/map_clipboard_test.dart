import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MMMapClipboard.channel,
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
  testWidgets('macOS transports both formats in one native item and propagates write failures', (tester) async {
    Object? written;
    var fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MMMapClipboard.channel, (
      call,
    ) async {
      if (call.method == 'write') {
        if (fail) throw PlatformException(code: 'write_failed');
        written = call.arguments;
        return null;
      }
      return {'text': 'Outline', 'internal': 'JSON'};
    });
    await MMMapClipboard.write(text: 'Outline', internal: 'JSON');
    expect(written, {'text': 'Outline', 'internal': 'JSON'});
    expect(await MMMapClipboard.read(), (text: 'Outline', internal: 'JSON'));
    fail = true;
    await expectLater(MMMapClipboard.write(text: 'Cut', internal: 'JSON'), throwsA(isA<PlatformException>()));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MMMapClipboard.channel,
      (_) async => null,
    );
    expect(await MMMapClipboard.read(), (text: '', internal: null));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  testWidgets('other platforms use system text clipboard including empty data', (tester) async {
    Object? written;
    var empty = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          written = call.arguments;
          return null;
        }
        if (call.method == 'Clipboard.getData') return empty ? null : {'text': 'External'};
        return null;
      },
    );
    await MMMapClipboard.write(text: 'External', internal: 'JSON');
    expect(written, {'text': 'External'});
    expect(await MMMapClipboard.read(), (text: 'External', internal: null));
    empty = true;
    expect(await MMMapClipboard.read(), (text: '', internal: null));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
