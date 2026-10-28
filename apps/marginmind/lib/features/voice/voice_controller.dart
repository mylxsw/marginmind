import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_platform/mm_platform.dart';

import 'voice_protocol.dart';
import 'voice_session.dart';
import 'voice_settings.dart';

enum VoicePhase { idle, connecting, recording, finishing }

enum VoiceError { permission, configuration, connection, recording, timeout, empty }

final voiceControllerFactoryProvider = Provider<VoiceController Function()>(
  (ref) =>
      () => VoiceController(),
);

/// One dictation's lifetime is owned by its composer. Cancelling invalidates all
/// pending permissions/handshakes so no late callback can reopen the microphone.
class VoiceController extends ChangeNotifier {
  VoiceController({VoiceMicrophone? microphone, VoiceSessionFactory? sessionFactory})
    : _microphone = microphone ?? RecordMicrophone(),
      _sessionFactory = sessionFactory ?? ((s, k, text, error) => RealtimeVoiceSession(s, k, text, error));

  final VoiceMicrophone _microphone;
  final VoiceSessionFactory _sessionFactory;
  VoicePhase phase = VoicePhase.idle;
  VoiceError? error;
  String text = '';
  bool get active => phase != VoicePhase.idle;
  VoiceSession? _session;
  StreamSubscription<Uint8List>? _audio;
  Completer<void>? _audioDone;
  Timer? _limit;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _cleanup;
  Future<Stream<Uint8List>>? _openingMicrophone;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> start(VoiceSettings settings, Future<String> Function() loadKey) async {
    if (active || _disposed) return;
    final generation = ++_generation;
    error = null;
    text = '';
    phase = VoicePhase.connecting;
    _notify();
    try {
      await _cleanup;
      if (!_current(generation)) return;
      if (!settings.valid || settings.provider == VoiceProvider.none) {
        throw const VoiceProtocolFailure('configuration');
      }
      final key = await loadKey();
      if (!_current(generation)) return;
      if (key.isEmpty) throw const VoiceProtocolFailure('configuration');
      if (!await _microphone.hasPermission()) throw const VoiceProtocolFailure('permission');
      if (!_current(generation)) return;
      final session = _sessionFactory(
        settings,
        key,
        (value) {
          if (!_current(generation)) return;
          text = value;
          _notify();
        },
        (failure) {
          if (_current(generation)) unawaited(_failed(failure));
        },
      );
      _session = session;
      await session.start();
      if (!_current(generation)) {
        await session.cancel();
        return;
      }
      final opening = _microphone.start();
      _openingMicrophone = opening;
      final stream = await opening;
      if (!_current(generation)) return;
      _openingMicrophone = null;
      final audioDone = Completer<void>();
      _audioDone = audioDone;
      _audio = stream.listen(
        (bytes) {
          try {
            session.addAudio(bytes);
          } catch (failure) {
            unawaited(_failed(failure));
          }
        },
        onError: (Object failure) => unawaited(_failed(failure)),
        onDone: () {
          if (!audioDone.isCompleted) audioDone.complete();
          if (_current(generation) && phase == VoicePhase.recording) {
            unawaited(_failed(const VoiceProtocolFailure('recording')));
          }
        },
      );
      phase = VoicePhase.recording;
      // Bound accidental unattended recordings to five minutes.
      _limit = Timer(const Duration(minutes: 5), () => unawaited(finish()));
      _notify();
    } catch (failure) {
      if (_current(generation)) await _failed(failure);
    }
  }

  Future<void> finish() async {
    if (phase != VoicePhase.recording) return;
    final generation = _generation;
    phase = VoicePhase.finishing;
    _limit?.cancel();
    _notify();
    try {
      // stop() flushes the plugin's last PCM bytes before closing its stream.
      await _microphone.stop();
      await _audioDone?.future.timeout(const Duration(seconds: 2));
      await _audio?.cancel();
      _audio = null;
      if (!_current(generation)) return;
      final value = await _session!.finish();
      if (!_current(generation)) return;
      text = value;
      error = value.trim().isEmpty ? VoiceError.empty : null;
      _session = null;
      phase = VoicePhase.idle;
      _notify();
    } catch (failure) {
      if (_current(generation)) await _failed(failure);
    }
  }

  Future<void> _failed(Object failure) async {
    if (_disposed || !active) return;
    error = switch (failure) {
      VoiceProtocolFailure(code: 'permission') => VoiceError.permission,
      VoiceProtocolFailure(code: 'configuration') => VoiceError.configuration,
      VoiceProtocolFailure(code: 'recording') => VoiceError.recording,
      TimeoutException() => VoiceError.timeout,
      _ => VoiceError.connection,
    };
    await cancel(); // Keep any transcript already received.
  }

  Future<void> cancel() async {
    ++_generation;
    _limit?.cancel();
    final session = _session;
    _session = null;
    final audio = _audio;
    _audio = null;
    if (_audioDone case final done? when !done.isCompleted) done.complete();
    _audioDone = null;
    final opening = _openingMicrophone;
    _openingMicrophone = null;
    final previousCleanup = _cleanup;
    phase = VoicePhase.idle;
    // Serialize microphone cleanup before another start.
    _cleanup = () async {
      await previousCleanup;
      await session?.cancel();
      await audio?.cancel();
      try {
        await opening;
      } catch (_) {
        /* Failed to open the device. */
      }
      try {
        await _microphone.stop();
      } catch (_) {
        /* Device already gone. */
      }
    }();
    _notify();
    await _cleanup;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(cancel().whenComplete(_microphone.dispose));
    super.dispose();
  }
}
