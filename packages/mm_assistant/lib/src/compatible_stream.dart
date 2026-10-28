import 'dart:convert';
import 'dart:typed_data';

/// Some compatible services repeat the full function name with each argument
/// delta. The SDK concatenates names, so translate repeated/cumulative names
/// into deltas before its parser sees them. Arguments remain untouched.
Stream<Uint8List> normalizeCompatibleToolNames(Stream<Uint8List> source) async* {
  final names = <(int, int), String>{};
  await for (var line in source.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.startsWith('data:')) {
      final payload = line.substring(5).trim();
      if (payload.isNotEmpty && payload != '[DONE]') {
        final dynamic data;
        try {
          data = jsonDecode(payload);
        } on FormatException {
          // Leave malformed events for the SDK's existing protocol handling.
          yield Uint8List.fromList(utf8.encode('$line\n'));
          continue;
        }
        if (data is Map && data['choices'] is List) {
          for (final choice in data['choices'] as List) {
            if (choice is! Map) continue;
            final delta = choice['delta'];
            if (delta is! Map || delta['tool_calls'] is! List) continue;
            for (final call in delta['tool_calls'] as List) {
              if (call is! Map || call['index'] is! int) continue;
              final function = call['function'];
              if (function is! Map || function['name'] is! String) continue;
              final key = (choice['index'] as int? ?? 0, call['index'] as int);
              final previous = names[key] ?? '';
              final incoming = function['name'] as String;
              if (previous.isNotEmpty && incoming.startsWith(previous)) {
                function['name'] = incoming.substring(previous.length);
                names[key] = incoming;
              } else {
                names[key] = previous + incoming;
              }
            }
          }
          line = 'data: ${jsonEncode(data)}';
        }
      }
    }
    yield Uint8List.fromList(utf8.encode('$line\n'));
  }
}
