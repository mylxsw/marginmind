// Release size probe: retains the real factory and runs one offline SDK turn.
// No model service is contacted. Not part of the normal application entrypoint.
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import '../../../packages/mm_assistant/test/support.dart';

import 'package:marginmind/main.dart' as app;

Future<void> main() async {
  final provider = AssistantProvider
      .values[int.parse(Platform.environment['MM_SIZE_PROVIDER'] ?? '0') % AssistantProvider.values.length];
  final endpoint = switch (provider) {
    AssistantProvider.claude => 'https://api.anthropic.com/v1/messages',
    AssistantProvider.responses => 'https://api.openai.com/v1/responses',
    _ => 'https://example.com/v1/chat/completions',
  };
  if (provider != AssistantProvider.ollama) {
    final connection = connectAssistant(
      AssistantModel(provider: provider, model: 'size-probe', endpoint: endpoint),
      'unused',
    );
    // Dynamic type usage keeps all provider branches reachable by the AOT compiler.
    stdout.writeln(connection.client.runtimeType);
    connection.close();
  }
  final run = createAssistantRun(
    client: ScriptClient([answer('offline size probe')]),
    model: 'fake',
    state: AgentState(sessionId: 'probe'),
    requestId: 'probe',
    reader: Reader(),
    scope: ReadScope(studySetId: 'probe'),
    mapId: 'map',
    baseRevision: 0,
    parents: {},
    online: false,
  );
  await run.run('probe').drain<void>();
  await app.main();
}
