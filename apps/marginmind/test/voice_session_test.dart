import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/voice/voice_protocol.dart';
import 'package:marginmind/features/voice/voice_session.dart';
import 'package:marginmind/features/voice/voice_settings.dart';

import 'voice_protocol_test.dart' show serverFrame;

void main() {
  test('Aliyun waits for task-started and drains late final sentence after task-finished', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final audio = <int>[];
    final updates = <String>[];
    final errors = <Object>[];
    late String task;
    late WebSocket remote;
    server.listen((request) async {
      remote = await WebSocketTransformer.upgrade(request);
      remote.listen((message) {
        if (message is List<int>) {
          audio.addAll(message);
          return;
        }
        final event = jsonDecode(message as String);
        task = event['header']['task_id'];
        if (event['header']['action'] == 'run-task') {
          expect(event['payload']['model'], 'paraformer-realtime-v2');
          remote.add(
            jsonEncode({
              'header': {'event': 'task-started', 'task_id': task},
            }),
          );
          remote.add(
            jsonEncode({
              'header': {'event': 'result-generated', 'task_id': task},
              'payload': {
                'output': {
                  'sentence': {'text': '最后一句还', 'begin_time': 0, 'sentence_end': false},
                },
              },
            }),
          );
        } else {
          remote.add(
            jsonEncode({
              'header': {'event': 'task-finished', 'task_id': task},
            }),
          );
          Timer(const Duration(milliseconds: 30), () {
            remote.add(
              jsonEncode({
                'header': {'event': 'result-generated', 'task_id': task},
                'payload': {
                  'output': {
                    'sentence': {'text': '最后一句还在。', 'begin_time': 0, 'sentence_end': true},
                  },
                },
              }),
            );
          });
        }
      });
    });
    final session = RealtimeVoiceSession(
      const VoiceSettings(provider: VoiceProvider.aliyun),
      'key',
      updates.add,
      errors.add,
      connect: (uri, headers) {
        expect(headers, {'Authorization': 'Bearer key'});
        return WebSocket.connect('ws://127.0.0.1:${server.port}');
      },
    );
    addTearDown(session.cancel);
    await session.start();
    session.addAudio(Uint8List.fromList(List.filled(3202, 42)));
    expect(await session.finish(), '最后一句还在。');
    expect(updates, ['最后一句还', '最后一句还在。']);
    expect(audio.take(3202), everyElement(42));
    expect(audio.length, 3202 + 64000);
    expect(errors, isEmpty);
  });

  for (final apiKey in [false, true]) {
    test('Doubao ${apiKey ? 'API key' : 'legacy credentials'} sends PCM packets and final audio marker', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final packets = <List<int>>[];
      final errors = <Object>[];
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((message) {
          final bytes = message as List<int>;
          packets.add(bytes);
          if (bytes[1] == 0x22) {
            socket.add(
              serverFrame(
                {
                  'result': {'text': '完整的最终结果。'},
                },
                flags: 4,
                compressed: true,
              ),
            );
          }
        });
      });
      final session = RealtimeVoiceSession(
        VoiceSettings(provider: VoiceProvider.doubao, appId: 'app', doubaoApiKey: apiKey),
        'secret',
        (_) {},
        errors.add,
        connect: (uri, headers) {
          expect(uri.path, '/api/v3/sauc/bigmodel_async');
          expect(headers['X-Api-Resource-Id'], 'volc.seedasr.sauc.duration');
          expect(headers['X-Api-Request-Id'], headers['X-Api-Connect-Id']);
          expect(headers['X-Api-Sequence'], '-1');
          expect(headers[apiKey ? 'X-Api-Key' : 'X-Api-Access-Key'], 'secret');
          return WebSocket.connect('ws://127.0.0.1:${server.port}');
        },
      );
      addTearDown(session.cancel);
      await session.start();
      session.addAudio(Uint8List(6402));
      expect(await session.finish(), '完整的最终结果。');
      expect(packets.map((p) => p[1]), [0x10, 0x20, 0x20, 0x20, 0x22]);
      expect(packets[3].length, 10); // Last two PCM bytes are preserved.
      expect(errors, isEmpty);
    });
  }

  test('Aliyun task failure unblocks startup with an error', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((message) {
        final task = jsonDecode(message as String)['header']['task_id'];
        socket.add(
          jsonEncode({
            'header': {'event': 'task-failed', 'task_id': task, 'error_code': 'InvalidApiKey'},
          }),
        );
      });
    });
    final errors = <Object>[];
    final session = RealtimeVoiceSession(
      const VoiceSettings(provider: VoiceProvider.aliyun),
      'key',
      (_) {},
      errors.add,
      connect: (_, headers) => WebSocket.connect('ws://127.0.0.1:${server.port}'),
    );
    addTearDown(session.cancel);
    await expectLater(session.start(), throwsA(isA<VoiceProtocolFailure>()));
    expect(errors, hasLength(1));
  });
}
