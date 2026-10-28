import 'dart:async';

import 'package:dart_agent_core/dart_agent_core.dart' hide MessageRole;
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'support.dart';

class PermissionReader extends Reader implements ReadPermissionResolver {
  int reads = 0;
  @override
  ReadPermissionRequest? describeReadPermission(String tool, Map<String, dynamic> args) {
    if (tool != 'read_pages' || args['documentId'] != 'doc' || (args['to'] as int) > 300) return null;
    return ReadPermissionRequest(
      kind: ReadPermissionKind.pages,
      title: 'Test document',
      targetId: 'doc',
      documentId: 'doc',
      from: args['from'],
      to: args['to'],
    );
  }

  @override
  Future<List<ReadPage>> readPages(
    String documentId,
    int from,
    int to,
    ReadScope scope,
    CancellationToken cancel,
  ) async {
    expect(scope.allowsPage(documentId, from), true);
    expect(scope.allowsPage(documentId, to), true);
    reads++;
    return super.readPages(documentId, from, to, scope, cancel);
  }
}

AssistantRun permissionRun(ScriptClient client, PermissionReader reader, {RunBudget? budget}) => createAssistantRun(
  client: client,
  model: 'fake',
  state: AgentState(sessionId: 'permissions'),
  requestId: 'request',
  reader: reader,
  scope: ReadScope(studySetId: 'set'),
  mapId: 'map',
  baseRevision: 0,
  parents: {'root': null},
  primaryDocumentId: 'doc',
  online: false,
  budget: budget,
);

void main() {
  test('read waits for consent, grants only requested pages and reuses consent within the run', () async {
    final reader = PermissionReader();
    final client = ScriptClient([
      call('read_pages', '{"documentId":"doc","from":193,"to":194}', id: 'first'),
      call('read_pages', '{"documentId":"doc","from":194,"to":194}', id: 'again'),
      answer('解释 [page:194] [page:195]'),
    ]);
    final run = permissionRun(client, reader);
    final asked = Completer<ReadPermissionRequest>(), decision = Completer<bool>();
    var prompts = 0;
    run.permissions.onRequest = (request) {
      prompts++;
      asked.complete(request);
      return decision.future;
    };
    final execution = run.run('解释').toList();
    final request = await asked.future;
    expect(request.title, 'Test document');
    expect([request.from, request.to], [193, 194]);
    expect(reader.reads, 0);
    expect(run.citations.items, isEmpty);
    final granted = request.grant(ReadScope(studySetId: 'set'));
    expect(granted.allowsPage('doc', 195), false);
    decision.complete(true);
    await execution;
    expect(prompts, 1);
    expect(reader.reads, 2);
    expect(run.citations.items.map((c) => c.page), [193, 194]);
    expect(client.requests.last.last, isA<FunctionExecutionResultMessage>());
  });

  test('denial performs no reads, is not a tool failure and does not ask for the same permission again', () async {
    final reader = PermissionReader();
    final client = ScriptClient([
      for (var i = 0; i < 3; i++) call('read_pages', '{"documentId":"doc","from":194,"to":194}', id: 'read-$i'),
      answer('使用已有资料回答'),
    ]);
    final run = permissionRun(client, reader);
    var prompts = 0;
    run.permissions.onRequest = (_) async {
      prompts++;
      return false;
    };
    final events = await run.run('解释').toList();
    expect(prompts, 1);
    expect(reader.reads, 0);
    expect(run.citations.items, isEmpty);
    final diagnostics = (run.agent.state.metadata['assistant.diagnostics'] as Map)['request'];
    expect(diagnostics['fallback'], isNull);
    expect((diagnostics['tools'] as List).map((tool) => tool['result']), everyElement('denied'));
    final results = events.where((event) => event.eventType == StreamingEventType.functionCallResult);
    for (final event in results) {
      expect((event.data as FunctionExecutionResultMessage).results.single.metadata?['failure'], 'permissionDenied');
    }
  });

  test('invalid arguments and unavailable resources never ask for consent', () async {
    final reader = PermissionReader();
    final client = ScriptClient([
      call('read_pages', '{"documentId":"outside","from":1,"to":1}', id: 'outside'),
      call('read_pages', '{"documentId":"doc","from":0,"to":1}', id: 'invalid'),
      answer('没有可读取的资料'),
    ]);
    final run = permissionRun(client, reader);
    run.permissions.onRequest = (_) async => fail('invalid requests must not show a permission prompt');
    await run.run('解释').toList();
    expect(reader.reads, 0);
  });

  test('a missing decision handler is reported as permission required, not a user denial', () async {
    final reader = PermissionReader();
    final run = permissionRun(
      ScriptClient([call('read_pages', '{"documentId":"doc","from":194,"to":194}'), answer('使用已有资料回答')]),
      reader,
    );
    final events = await run.run('解释').toList();
    final result =
        events.firstWhere((event) => event.eventType == StreamingEventType.functionCallResult).data
            as FunctionExecutionResultMessage;
    expect(result.results.single.metadata?['failure'], 'permissionRequired');
    expect(reader.reads, 0);
  });

  test('waiting for the user pauses the execution deadline', () async {
    final reader = PermissionReader();
    final run = permissionRun(
      ScriptClient([call('read_pages', '{"documentId":"doc","from":194,"to":194}'), answer('解释 [page:194]')]),
      reader,
      budget: RunBudget(limits: const ResearchBudget(duration: Duration(milliseconds: 100))),
    );
    final asked = Completer<void>(), decision = Completer<bool>();
    run.permissions.onRequest = (_) {
      asked.complete();
      return decision.future;
    };
    final execution = run.run('解释').toList();
    await asked.future;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(run.cancel.isCancelled, false);
    expect(reader.reads, 0);
    decision.complete(true);
    await execution;
    expect(reader.reads, 1);
  });

  test('stop cancels a pending decision; late approval cannot execute the read', () async {
    final reader = PermissionReader();
    final run = permissionRun(ScriptClient([call('read_pages', '{"documentId":"doc","from":194,"to":194}')]), reader);
    final asked = Completer<void>(), decision = Completer<bool>();
    run.permissions.onRequest = (_) {
      asked.complete();
      return decision.future;
    };
    final execution = run.run('解释').toList();
    final stopped = expectLater(
      execution,
      throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.cancelled)),
    );
    await asked.future;
    run.stop();
    await stopped;
    decision.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(reader.reads, 0);
    expect(run.citations.items, isEmpty);
  });

  test('permission view survives history roundtrip without making a grant persistent', () {
    const request = ReadPermissionRequest(
      id: 'p',
      kind: ReadPermissionKind.branch,
      title: 'Topic',
      targetId: 'node',
      mapId: 'map',
    );
    final message = Message(
      id: 'a',
      requestId: 'r',
      role: MessageRole.agent,
      permissions: [const ReadPermissionView(request)],
      traces: [const TraceStep('read', 'read_branch', TraceStatus.denied)],
    );
    final restored = Message.fromJson(message.toJson());
    expect(restored.waitingForPermission, true);
    expect(restored.permissions.single.request.toJson(), request.toJson());
    expect(restored.traces.single.status, TraceStatus.denied);
    expect(() => restored.permissions.clear(), throwsUnsupportedError);
    final freshScope = ReadScope(studySetId: 'set');
    expect(freshScope.allowsBranch('map', 'node'), false);
    expect(request.grant(freshScope).allowsBranch('map', 'node'), true);
    expect(freshScope.allowsBranch('map', 'node'), false);
  });
}
