import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('marginmind/speech');
  test('system speech receives the term and requested voice; stop releases it', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    await MMSpeech.speak('meticulous', language: 'en-GB');
    await MMSpeech.stop();
    expect(calls.map((c) => c.method), ['speak', 'stop']);
    expect(calls.first.arguments, {'text': 'meticulous', 'language': 'en-GB'});
  });
  test('failed and unavailable speech propagates speak errors; stop stays best effort', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'speech');
    });
    await expectLater(MMSpeech.speak('word', language: 'en-US'), throwsA(isA<PlatformException>()));
    await MMSpeech.stop();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await MMSpeech.stop();
  });
}
