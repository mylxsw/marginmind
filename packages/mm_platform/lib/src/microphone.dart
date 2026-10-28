import 'dart:typed_data';

import 'package:record/record.dart';

abstract interface class VoiceMicrophone {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> dispose();
}

class RecordMicrophone implements VoiceMicrophone {
  AudioRecorder? _recorder;
  AudioRecorder get _audio => _recorder ??= AudioRecorder();
  @override
  Future<bool> hasPermission() => _audio.hasPermission();
  @override
  Future<Stream<Uint8List>> start() =>
      _audio.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1));
  @override
  Future<void> stop() async {
    await _recorder?.stop();
  }

  @override
  Future<void> dispose() async {
    await _recorder?.dispose();
  }
}
