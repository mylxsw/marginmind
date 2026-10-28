import 'dart:convert';
import 'dart:typed_data';

import 'package:mm_assistant/src/compatible_stream.dart';
import 'package:test/test.dart';

void main() {
  test('parallel calls and choices keep separate names and unchanged argument deltas', () async {
    Map<String, dynamic> call(int index, String name, String arguments) => {
      'index': index,
      'function': {'name': name, 'arguments': arguments},
    };
    Map<String, dynamic> choice(int index, List<Map<String, dynamic>> calls) => {
      'index': index,
      'delta': {'tool_calls': calls},
    };
    final frames = [
      {
        'choices': [
          choice(0, [call(0, 'read_selection', '{'), call(1, 'read_', '{')]),
          choice(1, [call(0, 'read_branch', '{}')]),
        ],
      },
      {
        'choices': [
          choice(0, [call(1, 'pages', '"from":1}'), call(0, 'read_selection', '"selectionId":"sel"}')]),
          choice(1, [call(0, 'read_branch', '')]),
        ],
      },
    ];
    final wire = frames.map((frame) => 'data: ${jsonEncode(frame)}\n\n').join();
    final lines = await normalizeCompatibleToolNames(Stream.value(Uint8List.fromList(utf8.encode(wire))))
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.startsWith('data:'))
        .toList();
    final second = jsonDecode(lines.last.substring(5))['choices'];
    final calls = second[0]['delta']['tool_calls'];
    expect(calls[0]['function'], {'name': 'pages', 'arguments': '"from":1}'});
    expect(calls[1]['function'], {'name': '', 'arguments': '"selectionId":"sel"}'});
    expect(second[1]['delta']['tool_calls'][0]['function']['name'], '');
  });

  test('non-tool frames, invalid payloads and stream failures remain visible', () async {
    const wire = ': ping\ndata: not-json\ndata: []\ndata: [DONE]\n';
    final output = await normalizeCompatibleToolNames(Stream.value(Uint8List.fromList(utf8.encode(wire))))
        .cast<List<int>>()
        .transform(utf8.decoder)
        .join();
    expect(output, wire);
    await expectLater(normalizeCompatibleToolNames(Stream.error(StateError('disconnect'))).toList(), throwsStateError);
  });
}
