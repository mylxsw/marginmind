import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Wire formats ported from Typeflux's DoubaoProtocol and
/// AliCloudFunASRRequestConfiguration. Audio is always PCM16 / 16 kHz / mono.
class VoiceProtocolFailure implements Exception {
  const VoiceProtocolFailure([this.code = 'protocol']);
  final String code;
}

typedef VoiceSnapshot = ({String text, bool finalResult});

class DoubaoProtocol {
  static Uint8List packet(List<int> payload, {int type = 2, int flags = 0, int serialization = 0}) {
    final frame = Uint8List(8 + payload.length);
    frame.setAll(0, [0x11, type << 4 | flags, serialization << 4, 0]);
    ByteData.sublistView(frame).setUint32(4, payload.length);
    frame.setAll(8, payload);
    return frame;
  }

  static Uint8List request(String uid) => packet(
    utf8.encode(
      jsonEncode({
        'user': {'uid': uid},
        'audio': {'format': 'pcm', 'codec': 'raw', 'rate': 16000, 'bits': 16, 'channel': 1},
        'request': {
          'model_name': 'bigmodel',
          'enable_punc': true,
          'enable_ddc': true,
          'enable_nonstream': true,
          'show_utterances': true,
          'result_type': 'full',
          'end_window_size': 3000,
          'force_to_speech_time': 1000,
        },
      }),
    ),
    type: 1,
    serialization: 1,
  );

  static VoiceSnapshot? decode(List<int> bytes) {
    if (bytes.length < 8) throw const VoiceProtocolFailure();
    final data = Uint8List.fromList(bytes);
    final type = data[1] >> 4, flags = data[1] & 15, compression = data[2] & 15;
    var offset = (data[0] & 15) * 4;
    if (data[0] >> 4 != 1 || offset < 4 || ![0, 1].contains(compression)) {
      throw const VoiceProtocolFailure();
    }
    if (flags & 1 != 0) offset += 4;
    int? errorCode;
    if (type == 15) {
      if (offset + 4 > data.length) throw const VoiceProtocolFailure();
      errorCode = ByteData.sublistView(data).getUint32(offset);
      offset += 4;
    } else if (type != 9) {
      throw const VoiceProtocolFailure();
    }
    if (offset + 4 > data.length) throw const VoiceProtocolFailure();
    final size = ByteData.sublistView(data).getUint32(offset);
    offset += 4;
    if (offset + size > data.length) throw const VoiceProtocolFailure();
    List<int> payload = data.sublist(offset, offset + size);
    if (compression == 1) payload = gzip.decode(payload);
    if (errorCode != null) throw VoiceProtocolFailure(errorCode.toString());
    if (data[2] >> 4 != 1) throw const VoiceProtocolFailure();
    final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    final code = json['code'];
    if (code != null && code != 0 && code != 20000000) throw VoiceProtocolFailure('$code');
    final result = (json['result'] as Map<String, dynamic>?) ?? json;
    var text = (result['text'] as String? ?? '').trim();
    if (text.isEmpty) {
      final utterances = (result['utterances'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final confirmed = utterances.where((u) => u['definite'] == true).map((u) => u['text'] as String? ?? '');
      final partial = utterances.where((u) => u['definite'] != true).lastOrNull;
      text = [...confirmed, if (partial != null) partial['text'] as String? ?? ''].join();
    }
    // async final uses flag 4; older sequence protocols use a negative last sequence.
    return (text: text, finalResult: flags & 4 != 0 || flags & 2 != 0);
  }
}

class AliyunProtocol {
  static Map<String, Object> start(String taskId, String model) => {
    'header': {'action': 'run-task', 'task_id': taskId, 'streaming': 'duplex'},
    'payload': {
      'task_group': 'audio',
      'task': 'asr',
      'function': 'recognition',
      'model': model,
      'parameters': {
        'format': 'pcm',
        'sample_rate': 16000,
        'max_sentence_silence': 800,
        'heartbeat': false,
        'semantic_punctuation_enabled': model != 'paraformer-realtime-v2',
        if (model == 'paraformer-realtime-v2') ...{
          'disfluency_removal_enabled': true,
          'punctuation_prediction_enabled': true,
        },
      },
      'input': <String, Object>{},
    },
  };

  static Map<String, Object> finish(String taskId) => {
    'header': {'action': 'finish-task', 'task_id': taskId, 'streaming': 'duplex'},
    'payload': {'input': <String, Object>{}},
  };

  final _confirmed = <String, String>{};
  String _partial = '';
  bool get hasPartial => _partial.isNotEmpty;
  String get text {
    var result = '';
    for (final segment in [..._confirmed.values, _partial]) {
      if (segment.isEmpty) continue;
      if (result.isNotEmpty && _needsSpace(result, segment)) result += ' ';
      result += segment;
    }
    return result.trim();
  }

  void sentence(Map<String, dynamic> sentence) {
    final value = (sentence['text'] as String? ?? '').trim();
    if (value.isEmpty) return; // Ignore heartbeats.
    if (sentence['sentence_end'] == true) {
      // begin_time is stable across revisions and prevents duplicate finals.
      final id = '${sentence['begin_time'] ?? _confirmed.length}';
      _confirmed[id] = value;
      _partial = '';
    } else {
      _partial = value;
    }
  }

  static bool _needsSpace(String before, String after) {
    final a = before[before.length - 1], b = after[0];
    if (RegExp(r'\s').hasMatch(a) || RegExp(r'\s').hasMatch(b)) return false;
    if (',.!?;:)]}"\'，。！？；：、）】》'.contains(b) || '([{"\'（【《'.contains(a)) return false;
    final cjk = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]');
    return !cjk.hasMatch(a) && !cjk.hasMatch(b);
  }
}
