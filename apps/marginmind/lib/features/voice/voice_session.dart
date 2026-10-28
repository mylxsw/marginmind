import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mm_core/mm_core.dart';

import 'voice_protocol.dart';
import 'voice_settings.dart';

abstract interface class VoiceSession {
  Future<void> start();
  void addAudio(Uint8List bytes);
  Future<String> finish();
  Future<void> cancel();
}

typedef VoiceSessionFactory = VoiceSession Function(
  VoiceSettings settings,
  String key,
  void Function(String) onText,
  void Function(Object) onError,
);

/// Direct provider connection; credentials and PCM never pass through an app server.
class RealtimeVoiceSession implements VoiceSession {
  RealtimeVoiceSession(this.settings, this.key, this.onText, this.onError, {this.connect});

  final VoiceSettings settings;
  final String key;
  final void Function(String) onText;
  final void Function(Object) onError;
  // Injectable transport for local protocol/lifecycle tests.
  final Future<WebSocket> Function(Uri, Map<String, String>)? connect;
  final _client = HttpClient();
  final _ready = Completer<void>(), _finished = Completer<void>();
  final _aliyun = AliyunProtocol();
  final _taskId = newId().replaceAll('-', '');
  final _connectionId = newId();
  final _pending = BytesBuilder(copy: false);
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _drainTimer;
  Object? _failure;
  bool _closed = false, _ending = false, _taskFinished = false;
  String _text = '';

  @override
  Future<void> start() async {
    final doubao = settings.provider == VoiceProvider.doubao;
    final uri = Uri.parse(doubao ? 'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async' : settings.endpoint);
    final headers = doubao
        ? {
            if (settings.doubaoApiKey)
              'X-Api-Key': key
            else ...{
              'X-Api-App-Key': settings.appId,
              'X-Api-Access-Key': key,
            },
            'X-Api-Resource-Id': settings.resourceId,
            'X-Api-Request-Id': _connectionId,
            'X-Api-Connect-Id': _connectionId,
            'X-Api-Sequence': '-1',
          }
        : {'Authorization': 'Bearer $key'};
    try {
      final opening =
          connect?.call(uri, headers) ?? WebSocket.connect(uri.toString(), headers: headers, customClient: _client);
      // A cancelled or timed-out handshake may still resolve: close that socket too.
      final socket = await opening
          .then((socket) {
            if (_closed) unawaited(socket.close());
            return socket;
          })
          .timeout(const Duration(seconds: 10));
      if (_closed) throw const VoiceProtocolFailure('cancelled');
      _socket = socket;
      socket.pingInterval = const Duration(seconds: 15);
      _subscription = socket.listen(
        _receive,
        onError: _fail,
        onDone: () {
          if (_closed || _finished.isCompleted) return;
          if (_ending && (doubao || _taskFinished)) {
            _complete();
          } else {
            _fail(const VoiceProtocolFailure('disconnected'));
          }
        },
      );
      socket.add(doubao ? DoubaoProtocol.request(_taskId) : jsonEncode(AliyunProtocol.start(_taskId, settings.model)));
      if (!doubao) await _wait(_ready);
    } catch (_) {
      await cancel();
      rethrow;
    }
  }

  Future<void> _wait(Completer<void> signal) async {
    if (_failure != null) throw _failure!;
    await signal.future.timeout(const Duration(seconds: 12));
    if (_failure != null) throw _failure!;
    if (_closed) throw const VoiceProtocolFailure('cancelled');
  }

  @override
  void addAudio(Uint8List bytes) {
    if (_closed || _ending || _failure != null) return;
    _pending.add(bytes);
    // 100ms packets, matching Typeflux; never buffer a whole recording.
    if (_pending.length < 3200) return;
    final data = _pending.takeBytes();
    var offset = 0;
    while (offset + 3200 <= data.length) {
      _sendAudio(Uint8List.sublistView(data, offset, offset + 3200));
      offset += 3200;
    }
    if (offset < data.length) _pending.add(Uint8List.sublistView(data, offset));
  }

  void _sendAudio(Uint8List bytes) {
    if (_socket == null || _closed) return;
    _socket!.add(settings.provider == VoiceProvider.doubao ? DoubaoProtocol.packet(bytes) : bytes);
  }

  @override
  Future<String> finish() async {
    if (_closed) throw const VoiceProtocolFailure('cancelled');
    _ending = true;
    try {
      if (_pending.isNotEmpty) _sendAudio(_pending.takeBytes());
      if (settings.provider == VoiceProvider.doubao) {
        _socket!.add(DoubaoProtocol.packet(const [], flags: 2));
      } else {
        // Flush VAD's last sentence, then retain late sentence_end events.
        for (var i = 0; i < 20; i++) {
          _sendAudio(Uint8List(3200));
        }
        _socket!.add(jsonEncode(AliyunProtocol.finish(_taskId)));
      }
      await _wait(_finished);
      return _text;
    } finally {
      await cancel();
    }
  }

  void _receive(dynamic message) {
    if (_closed || _failure != null) return;
    try {
      if (settings.provider == VoiceProvider.doubao) {
        if (message is! List<int>) throw const VoiceProtocolFailure();
        final snapshot = DoubaoProtocol.decode(message);
        if (snapshot == null) return;
        _publish(snapshot.text);
        if (snapshot.finalResult) _complete();
      } else {
        final event =
            jsonDecode(message is String ? message : utf8.decode(message as List<int>)) as Map<String, dynamic>;
        final header = event['header'] as Map<String, dynamic>;
        if (header['task_id'] != null && header['task_id'] != _taskId) return;
        switch (header['event']) {
          case 'task-started':
            if (!_ready.isCompleted) _ready.complete();
          case 'result-generated':
            final sentence = event['payload']?['output']?['sentence'] as Map<String, dynamic>?;
            if (sentence == null) return;
            _aliyun.sentence(sentence);
            _publish(_aliyun.text);
            if (_taskFinished && !_aliyun.hasPartial) _complete();
          case 'task-finished':
            _taskFinished = true;
            if (!_aliyun.hasPartial) {
              _complete();
            } else {
              _drainTimer ??= Timer(const Duration(seconds: 3), _complete);
            }
          case 'task-failed':
            throw VoiceProtocolFailure('${header['error_code'] ?? 'service'}');
        }
      }
    } catch (error) {
      _fail(error);
    }
  }

  void _publish(String value) {
    if (value.isEmpty || value == _text) return;
    _text = value;
    onText(value);
  }

  void _complete() {
    _drainTimer?.cancel();
    if (!_finished.isCompleted) _finished.complete();
  }

  void _fail(Object error) {
    if (_closed || _failure != null) return;
    _failure = error;
    if (!_ready.isCompleted) _ready.complete();
    _complete();
    onError(error);
  }

  @override
  Future<void> cancel() async {
    if (_closed) return;
    _closed = true;
    _drainTimer?.cancel();
    _pending.clear();
    if (!_ready.isCompleted) _ready.complete();
    _complete();
    _client.close(force: true);
    await _subscription?.cancel();
    // Do not wait indefinitely for the remote close handshake.
    unawaited(_socket?.close());
    _socket = null;
  }
}
