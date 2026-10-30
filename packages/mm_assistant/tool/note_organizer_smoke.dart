// Run from packages/mm_assistant with NOTE_AI_PROVIDER=claude|compatible,
// NOTE_AI_ENDPOINT, NOTE_AI_MODEL and NOTE_AI_KEY supplied by a local secret
// manager/environment. Never include a key in command arguments or evidence.
import 'dart:convert';
import 'dart:io';

import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

Future<void> main() async {
  final env = Platform.environment;
  if (['NOTE_AI_PROVIDER', 'NOTE_AI_ENDPOINT', 'NOTE_AI_MODEL', 'NOTE_AI_KEY'].any((k) => env[k]?.isNotEmpty != true)) {
    stderr.writeln('Missing NOTE_AI_PROVIDER/ENDPOINT/MODEL/KEY environment configuration.');
    exitCode = 2;
    return;
  }
  ModelNoteOrganizer? organizer;
  try {
    final provider = AssistantProvider.values.byName(env['NOTE_AI_PROVIDER']!);
    if (!{AssistantProvider.claude, AssistantProvider.compatible}.contains(provider)) {
      throw const ResearchFailure(ResearchFailureKind.invalidRequest);
    }
    final config = AssistantModel(provider: provider, model: env['NOTE_AI_MODEL']!, endpoint: env['NOTE_AI_ENDPOINT']!);
    final connection = connectAssistant(config, env['NOTE_AI_KEY']!);
    organizer = ModelNoteOrganizer(client: connection.client, model: config.model, closeConnection: connection.close);
    final now = DateTime.utc(2026, 10, 30);
    final materials = NoteMaterials([
      NoteMaterial(
        ref: 'h1',
        sourceId: 'sample-1',
        text: '先合上书，尝试回想刚读到的内容，再检查遗漏。',
        groupKey: 'chapter-1',
        groupTitle: '主动回想',
        createdAt: now,
      ),
      NoteMaterial(
        ref: 'h2',
        sourceId: 'sample-2',
        text: '把复习分散到不同的日子，每次先尝试独立回答问题。',
        groupKey: 'chapter-2',
        groupTitle: '间隔复习',
        createdAt: now,
      ),
    ], collectedAt: now);
    final settings = NoteSettings();
    final outline = await organizer.outline(materials, settings);
    final draft = await organizer.write(materials, outline, settings);
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'model': config.model,
        'outline': outline.toJson(),
        'write': draft.toJson(),
        'fallbacks': organizer.failures.map((e) => e.operation).toList(),
      }),
    );
    if (organizer.failures.isNotEmpty) exitCode = 1;
  } catch (error) {
    // Provider exceptions can contain request headers. Never print them.
    stderr.writeln('Smoke failed: ${error is ResearchFailure ? error.kind.name : error.runtimeType}');
    exitCode = 1;
  } finally {
    organizer?.close();
  }
}
