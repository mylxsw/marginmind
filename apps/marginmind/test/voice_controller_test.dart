import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/voice/voice_controller.dart';
import 'package:marginmind/features/voice/voice_protocol.dart';
import 'package:marginmind/features/voice/voice_settings.dart';

import 'voice_support.dart';

const settings = VoiceSettings(provider: VoiceProvider.aliyun);
Future<String> key() async => 'test-key';
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('streams microphone immediately and flushes the last PCM bytes before finish', () async {
    final mic = FakeMicrophone(), session = FakeVoiceSession();
    final controller = VoiceController(microphone: mic, sessionFactory: session.factory);
    addTearDown(controller.dispose);
    await controller.start(settings, key);
    expect(controller.phase, VoicePhase.recording);
    mic.audio.add(Uint8List.fromList([1, 2]));
    session.onText!('临时结果');
    expect(controller.text, '临时结果');
    mic.tail = Uint8List.fromList([3, 4]);
    await controller.finish();
    expect(session.packets, [
      [1, 2],
      [3, 4],
    ]);
    expect(controller.text, '最终识别结果。');
    expect(controller.phase, VoicePhase.idle);
    expect(controller.error, null);
  });

  test('denied permission and missing key never start microphone or service', () async {
    final mic = FakeMicrophone()..allowed = false, session = FakeVoiceSession();
    final controller = VoiceController(microphone: mic, sessionFactory: session.factory);
    addTearDown(controller.dispose);
    await controller.start(settings, key);
    expect(controller.error, VoiceError.permission);
    expect(mic.starts, 0);
    expect(session.onText, null);
    await controller.start(settings, () async => '');
    expect(controller.error, VoiceError.configuration);
    expect(mic.starts, 0);
  });

  test('cancelling a permission request prevents late microphone startup', () async {
    final mic = FakeMicrophone()..permission = Completer<bool>(), session = FakeVoiceSession();
    final controller = VoiceController(microphone: mic, sessionFactory: session.factory);
    addTearDown(controller.dispose);
    final starting = controller.start(settings, key);
    await settle();
    await controller.cancel();
    mic.permission!.complete(true);
    await starting;
    expect(mic.starts, 0);
    expect(controller.phase, VoicePhase.idle);
  });

  test('cancel during native microphone startup serializes cleanup before a new recording', () async {
    final mic = FakeMicrophone()..opening = Completer<Stream<Uint8List>>();
    final session = FakeVoiceSession();
    final controller = VoiceController(microphone: mic, sessionFactory: session.factory);
    addTearDown(controller.dispose);
    final first = controller.start(settings, key);
    await settle();
    expect(mic.starts, 1);
    final cancelled = controller.cancel();
    final second = controller.start(settings, key);
    await settle();
    expect(mic.starts, 1);
    mic.opening!.complete(mic.audio.stream);
    mic.opening = null;
    await Future.wait([first, cancelled, second]);
    expect(mic.starts, 2);
    expect(controller.phase, VoicePhase.recording);
  });

  test('service errors retain partial transcript and stop recording; old callbacks are ignored', () async {
    final mic = FakeMicrophone(), session = FakeVoiceSession();
    final controller = VoiceController(microphone: mic, sessionFactory: session.factory);
    addTearDown(controller.dispose);
    await controller.start(settings, key);
    session.onText!('保留已经识别的文字');
    session.onError!(const VoiceProtocolFailure('network'));
    await settle();
    expect(controller.error, VoiceError.connection);
    expect(controller.text, '保留已经识别的文字');
    expect(controller.phase, VoicePhase.idle);
    expect(session.cancelled, true);
    expect(mic.stops, greaterThan(0));
    session.onText!('迟到的文字');
    expect(controller.text, '保留已经识别的文字');
  });

  test('finish remains busy until the final result; cancel discards late final callback', () async {
    final mic = FakeMicrophone(), session = FakeVoiceSession()..finishing = Completer<String>();
    final controller = VoiceController(microphone: mic, sessionFactory: session.factory);
    addTearDown(controller.dispose);
    await controller.start(settings, key);
    final finishing = controller.finish();
    await settle();
    expect(controller.phase, VoicePhase.finishing);
    await controller.cancel();
    session.finishing!.complete('不应插入');
    await finishing;
    expect(controller.text, '');
    expect(controller.phase, VoicePhase.idle);
  });
}
