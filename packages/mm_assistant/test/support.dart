import 'dart:async';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_assistant/mm_assistant.dart';

class ScriptClient implements LLMClient {
  ScriptClient(this.replies);
  final List<ModelMessage> replies;
  int calls = 0;
  final requests = <List<LLMMessage>>[];
  final toolRequests = <List<Tool>>[];
  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    requests.add(messages);
    toolRequests.add(List.of(tools ?? []));
    return replies[calls++];
  }

  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async => Stream.value(
    StreamingMessage(
      modelMessage: await generate(
        messages,
        tools: tools,
        toolChoice: toolChoice,
        modelConfig: modelConfig,
        cancelToken: cancelToken,
      ),
    ),
  );
}

class Reader implements StudySetReader {
  @override
  Future<List<ReadPage>> readSelection(String selectionId, ReadScope scope, CancellationToken cancel) async => [
    const ReadPage('doc', 1, 'selection'),
  ];
  @override
  Future<List<ReadPage>> readPages(
    String documentId,
    int from,
    int to,
    ReadScope scope,
    CancellationToken cancel,
  ) async => [for (var i = from; i <= to; i++) ReadPage(documentId, i, 'page $i')];
  @override
  Future<List<StudySearchHit>> searchStudySet(
    String query,
    int limit,
    ReadScope scope,
    CancellationToken cancel,
  ) async => [const StudySearchHit(title: 'hit', locator: 'doc:1')];
  @override
  Future<List<BranchNode>> readBranch(String mapId, String nodeId, ReadScope scope, CancellationToken cancel) async => [
    const BranchNode(id: 'root', title: 'Root'),
  ];
}

ModelMessage answer(String text, {String? stop = 'stop'}) =>
    ModelMessage(model: 'fake', textOutput: text, stopReason: stop);
ModelMessage call(String name, String args, {String id = 'call'}) => ModelMessage(
  model: 'fake',
  stopReason: 'tool_calls',
  functionCalls: [FunctionCall(id: id, name: name, arguments: args)],
);
AssistantRun makeRun(
  LLMClient client, {
  String? skill,
  RunBudget? budget,
  bool online = true,
  AgentState? state,
  AssistantNetwork? network,
  StudySetReader? reader,
}) => createAssistantRun(
  client: client,
  model: 'fake',
  state: state ?? AgentState(sessionId: 'conversation'),
  requestId: 'request',
  reader: reader ?? Reader(),
  scope: ReadScope(studySetId: 'set', documents: {'doc'}, selections: {'sel'}, maps: {'map'}),
  mapId: 'map',
  baseRevision: 0,
  parents: {'root': null, 'child': 'root'},
  primaryDocumentId: 'doc',
  skill: skill,
  budget: budget,
  online: online,
  network: network,
);

class StreamClient extends ScriptClient {
  StreamClient(this.source) : super([]);
  final Stream<StreamingMessage> Function(CancelToken? token) source;
  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    calls++;
    return source(cancelToken);
  }
}
