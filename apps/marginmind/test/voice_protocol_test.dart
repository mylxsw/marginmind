import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/voice/voice_protocol.dart';

Uint8List serverFrame(Map<String, dynamic> json, {int flags = 0, bool compressed = false, int? sequence}) {
  List<int> payload = utf8.encode(jsonEncode(json));
  if (compressed) payload = gzip.encode(payload);
  final packet = DoubaoProtocol.packet(payload, type: 9, flags: flags, serialization: 1);
  if (compressed) packet[2] |= 1;
  if (sequence == null) return packet;
  return Uint8List.fromList([
    ...packet.take(4),
    ...((ByteData(4)..setInt32(0, sequence)).buffer.asUint8List()),
    ...packet.skip(4),
  ]);
}

void main() {
  test('Doubao cumulative text, gzip, sequence and async final match Typeflux', () {
    final interim = serverFrame(
      {
        'result': {'text': '我正在说话'},
      },
      flags: 1,
      sequence: 3,
      compressed: true,
    );
    expect(DoubaoProtocol.decode(interim), (text: '我正在说话', finalResult: false));
    final finalFrame = serverFrame({
      'result': {'text': '我正在说话。'},
    }, flags: 4);
    expect(DoubaoProtocol.decode(finalFrame), (text: '我正在说话。', finalResult: true));
    final utterances = serverFrame(
      {
        'result': {
          'utterances': [
            {'text': '第一句。', 'definite': true},
            {'text': '暂时', 'definite': false},
            {'text': '第二句。', 'definite': false},
          ],
        },
      },
      flags: 3,
      sequence: -1,
    );
    expect(DoubaoProtocol.decode(utterances), (text: '第一句。第二句。', finalResult: true));
  });

  test('Doubao rejects truncated packets and parses binary service error code', () {
    final frame = serverFrame({
      'result': {'text': '文本'},
    });
    for (var i = 0; i < frame.length; i++) {
      expect(() => DoubaoProtocol.decode(frame.sublist(0, i)), throwsA(isA<VoiceProtocolFailure>()));
    }
    final error = DoubaoProtocol.packet(utf8.encode('invalid token'), type: 15);
    final bytes = [...error.take(4), ...((ByteData(4)..setUint32(0, 45000001)).buffer.asUint8List()), ...error.skip(4)];
    expect(
      () => DoubaoProtocol.decode(bytes),
      throwsA(isA<VoiceProtocolFailure>().having((e) => e.code, 'code', '45000001')),
    );
  });

  test('Aliyun revisions replace interim text; duplicate final sentences do not repeat', () {
    final protocol = AliyunProtocol();
    protocol.sentence({'text': 'Hello', 'begin_time': 0, 'sentence_end': false});
    protocol.sentence({'text': 'Hello world.', 'begin_time': 0, 'sentence_end': true});
    protocol.sentence({'text': 'Hello world.', 'begin_time': 0, 'sentence_end': true});
    protocol.sentence({'text': '正在', 'begin_time': 1000, 'sentence_end': false});
    protocol.sentence({'text': '正在说中文。', 'begin_time': 1000, 'sentence_end': true});
    protocol.sentence({'text': '', 'sentence_end': false});
    expect(protocol.text, 'Hello world.正在说中文。');
    expect(protocol.hasPartial, false);
    protocol.sentence({'text': 'Next sentence.', 'begin_time': 2000, 'sentence_end': true});
    expect(protocol.text, 'Hello world.正在说中文。 Next sentence.');
    final english = AliyunProtocol()
      ..sentence({'text': 'Hello.', 'begin_time': 0, 'sentence_end': true})
      ..sentence({'text': 'How are you?', 'begin_time': 100, 'sentence_end': false});
    expect(english.text, 'Hello. How are you?');
  });
}
