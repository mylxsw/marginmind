import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('marginmind/map_export');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );
  test('encodes scenes and PNG tiles and rejects empty native responses', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return Uint8List.fromList([1, 2]);
    });
    const encoder = NativeMapExport();
    expect(await encoder.pdf({'width': 10.0}), [1, 2]);
    expect(await encoder.png(10, 20, []), [1, 2]);
    expect(calls.first.method, 'pdf');
    expect(calls.last.arguments, {'width': 10, 'height': 20, 'tiles': []});
    for (final value in [null, Uint8List(0)]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => value,
      );
      await expectLater(encoder.pdf({}), throwsStateError);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'export_failed'),
    );
    await expectLater(encoder.png(1, 1, []), throwsA(isA<PlatformException>()));
  });
}
