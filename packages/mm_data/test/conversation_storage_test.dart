import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late ConversationStorage storage;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mm-conversation-');
    storage = ConversationStorage(dir);
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test('snapshot captured before await, serialized writes and delete', () async {
    final state = await storage.loadOrCreate('session', {'a': 1});
    expect(await storage.exist('session'), false);
    final first = storage.save(state);
    state.metadata['a'] = 2;
    await first;
    expect((await storage.loadOrCreate('session', null)).metadata['a'], 1);
    final second = storage.save(state);
    state.metadata['a'] = 3;
    final third = storage.save(state);
    await Future.wait([second, third]);
    expect((await storage.loadOrCreate('session', null)).metadata['a'], 3);
    await storage.delete('session');
    expect(await storage.exist('session'), false);
    await storage.delete('session');
  });
  test('traversal, symlink escape and corrupt data are rejected without overwrite', () async {
    for (final id in ['../outside', '/tmp/test', 'a/b', '']) {
      await expectLater(storage.loadOrCreate(id, null), throwsFormatException);
    }
    final state = AgentState(sessionId: 'valid');
    await storage.save(state);
    final path = '${dir.path}/conversations/valid.json';
    await File(path).writeAsString('corrupt');
    await expectLater(storage.loadOrCreate('valid', null), throwsA(anything));
    expect(await File(path).readAsString(), 'corrupt');
    await File(path).delete();
    await Link(path).create('${dir.path}/outside');
    await expectLater(storage.save(state), throwsA(isA<FileSystemException>()));
    await Link(path).delete();
    await Directory('${dir.path}/conversations').delete();
    await Link('${dir.path}/conversations').create(dir.path);
    await expectLater(storage.exist('valid'), throwsA(isA<FileSystemException>()));
  });
  test('failed replacement leaves target and removes temporary file; queue recovers', () async {
    await Directory('${dir.path}/conversations/id.json').create(recursive: true);
    await expectLater(storage.save(AgentState(sessionId: 'id')), throwsA(isA<FileSystemException>()));
    expect(await Directory('${dir.path}/conversations/id.json').exists(), true);
    expect(await Directory('${dir.path}/conversations').list().length, 1);
    await storage.save(AgentState(sessionId: 'other'));
    expect(await storage.exist('other'), true);
  });
  test('identity mismatch is corrupt; running flag is retained for controller recovery', () async {
    await storage.save(AgentState(sessionId: 'id', isRunning: true));
    expect((await storage.loadOrCreate('id', null)).isRunning, true);
    final f = File('${dir.path}/conversations/id.json');
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    j['sessionId'] = 'other';
    await f.writeAsString(jsonEncode(j));
    await expectLater(storage.loadOrCreate('id', null), throwsFormatException);
  });
  test('ResearchNote legacy and conversation roundtrip/copy compatibility', () {
    final now = DateTime.utc(2026);
    final old = ResearchNote(id: 'n', title: 't', body: 'b', createdAt: now, updatedAt: now);
    expect(old.toJson().containsKey('conversationId'), false);
    expect(ResearchNote.fromJson(old.toJson()).conversationId, isNull);
    final note = ResearchNote.fromJson({...old.toJson(), 'conversationId': 'conv', 'sessionId': 'legacy'})
        .copyWith(body: 'edited');
    expect(note.conversationId, 'conv');
    expect(note.sessionId, 'legacy');
    expect(note.toJson()['conversationId'], 'conv');
  });
  test('list returns saved conversation IDs only', () async {
    expect(await storage.list(), isEmpty);
    await storage.save(AgentState(sessionId: 'one'));
    await storage.save(AgentState(sessionId: 'two'));
    final conversations = Directory('${dir.path}/conversations');
    await File('${conversations.path}/note.txt').writeAsString('x');
    await File('${conversations.path}/bad name.json').writeAsString('{}');
    await Link('${conversations.path}/link.json').create('${conversations.path}/one.json');
    expect((await storage.list())..sort(), ['one', 'two']);
    await storage.delete('one');
    expect(await storage.list(), ['two']);
  });
}
