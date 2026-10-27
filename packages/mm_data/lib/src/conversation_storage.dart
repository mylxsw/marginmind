import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:path/path.dart' as p;

/// One instance per study-set package. Operations capture state at invocation
/// and serialize through a queue, including deletion and reads.
class ConversationStorage implements StateStorage {
  ConversationStorage(this.studySetDirectory);
  final Directory studySetDirectory;
  Future<void> _tail = Future.value();
  int _sequence = 0;
  Future<T> _serial<T>(Future<T> Function() work) {
    final next = _tail.then((_) => work());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<File> _file(String id) async {
    if (!_id.hasMatch(id)) {
      throw const FormatException('Invalid conversation ID');
    }
    final root = await studySetDirectory.resolveSymbolicLinks();
    final dir = Directory(p.join(root, 'conversations'));
    if (await FileSystemEntity.type(dir.path, followLinks: false) == FileSystemEntityType.link) {
      throw const FileSystemException('Conversation directory is a link');
    }
    await dir.create();
    final file = File(p.join(dir.path, '$id.json'));
    if (await FileSystemEntity.type(file.path, followLinks: false) == FileSystemEntityType.link) {
      throw const FileSystemException('Conversation file is a link');
    }
    return file;
  }

  @override
  Future<AgentState> loadOrCreate(String sessionId, Map<String, dynamic>? initialMetadata) => _serial(() async {
    final file = await _file(sessionId);
    if (!await file.exists()) return AgentState(sessionId: sessionId, metadata: initialMetadata);
    final state = AgentState.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    if (state.sessionId != sessionId) throw const FormatException('Conversation identity mismatch');
    // UI recovery is performed by AssistantController before any further request.
    return state;
  });
  @override
  Future<void> save(AgentState state) {
    final id = state.sessionId;
    final snapshot = jsonEncode(state.toJson());
    return _serial(() async {
      final file = await _file(id);
      final temp = File('${file.path}.${pid}_${DateTime.now().microsecondsSinceEpoch}_${_sequence++}.tmp');
      try {
        await temp.create(exclusive: true);
        await temp.writeAsString(snapshot, flush: true);
        await temp.rename(file.path);
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    });
  }

  @override
  Future<void> delete(String sessionId) => _serial(() async {
    final file = await _file(sessionId);
    if (await file.exists()) await file.delete();
  });

  /// IDs of the saved conversations, in no particular order. Names that are
  /// not valid IDs, temporary files and links are skipped.
  Future<List<String>> list() => _serial(() async {
    final root = await studySetDirectory.resolveSymbolicLinks();
    final dir = Directory(p.join(root, 'conversations'));
    if (await FileSystemEntity.type(dir.path, followLinks: false) != FileSystemEntityType.directory) return const [];
    return [
      await for (final entry in dir.list(followLinks: false))
        if (entry is File && entry.path.endsWith('.json'))
          if (p.basenameWithoutExtension(entry.path) case final id when _id.hasMatch(id)) id,
    ];
  });
  static final _id = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');

  @override
  Future<bool> exist(String sessionId) => _serial(() async => (await _file(sessionId)).exists());
}
