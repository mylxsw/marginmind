import 'dart:async';
import 'dart:typed_data';

import 'package:mm_platform/mm_platform.dart';
import 'package:marginmind/features/voice/voice_session.dart';

class FakeMicrophone implements VoiceMicrophone {
  var audio = StreamController<Uint8List>.broadcast(sync: true);
  Completer<bool>? permission;
  Completer<Stream<Uint8List>>? opening;
  bool allowed = true, disposed = false;
  int starts = 0, stops = 0;
  Uint8List? tail;
  @override
  Future<bool> hasPermission() async => permission == null ? allowed : permission!.future;
  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    if (audio.isClosed) audio = StreamController<Uint8List>.broadcast(sync: true);
    return opening == null ? audio.stream : opening!.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (tail != null) {
      audio.add(tail!);
      tail = null;
    }
    if (starts > 0 && !audio.isClosed) await audio.close();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await audio.close();
  }
}

class FakeVoiceSession implements VoiceSession {
  void Function(String)? onText;
  void Function(Object)? onError;
  Completer<void>? starting;
  Completer<String>? finishing;
  final packets = <List<int>>[];
  String result = '最终识别结果。';
  bool cancelled = false;
  @override
  Future<void> start() async {
    await starting?.future;
  }

  @override
  void addAudio(Uint8List bytes) => packets.add(bytes.toList());
  @override
  Future<String> finish() async => finishing == null ? result : finishing!.future;
  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  VoiceSessionFactory get factory => (settings, key, text, error) {
    onText = text;
    onError = error;
    return this;
  };
}
