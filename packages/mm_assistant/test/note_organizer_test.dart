import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_assistant/src/study_notes/schema.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'support.dart';

final date = DateTime.utc(2026);
NoteMaterials materials([int count = 1, bool chapters = false]) => NoteMaterials([
  for (var i = 1; i <= count; i++)
    NoteMaterial(
      ref: 'h$i',
      sourceId: 'a$i',
      text: '检索练习有助于记忆。',
      groupKey: chapters ? 'g${i ~/ 100}' : 'g',
      groupTitle: '记忆',
      createdAt: date,
    ),
], collectedAt: date);
const outlineJson = '{"sections":[{"title":"记忆","refs":["h1"]}]}';
const draftJson =
    '{"sections":[{"title":"记忆","blocks":[{"type":"quote","ref":"h1"},{"type":"summary","text":"主动回想"}],"question":"如何练习？"}]}';
NoteOutline get outline => NoteOutline.fromJson(jsonDecode(outlineJson));
StudyNote note([NoteDepth depth = NoteDepth.deep]) => StudyNote(
  id: 'note',
  title: '笔记',
  scope: const WholeSet(),
  settings: NoteSettings(depth: depth),
  createdAt: date,
  updatedAt: date,
  organizedAt: date,
);
Matcher failure(ResearchFailureKind kind) => isA<ResearchFailure>().having((e) => e.kind, 'kind', kind);

class PendingClient extends ScriptClient {
  PendingClient() : super([]);
  final started = Completer<void>();
  CancelToken? token;
  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) {
    token = cancelToken;
    started.complete();
    return Completer<ModelMessage>().future;
  }
}

void main() {
  test('embedded schema matches the domain contract', () {
    final contract = jsonDecode(File('../../docs/study-notes-ai-contract.schema.json').readAsStringSync());
    expect(noteSchemas, contract[r'$defs']);
  });

  test('outline, write, placement and prose operations use safe direct requests', () async {
    final client = ScriptClient([
      answer(outlineJson),
      answer(draftJson),
      answer('{"placements":[{"ref":"h1","sectionId":null,"title":"记忆","why":"主题相同"}]}'),
      for (var i = 0; i < 5; i++) answer('{"text":"主动回想"}'),
    ]);
    final progress = <NoteProgress>[];
    final service = ModelNoteOrganizer(client: client, model: 'fake', onProgress: progress.add);
    final m = materials();
    final o = await service.outline(m, NoteSettings());
    final draft = await service.write(m, o, NoteSettings());
    expect(draft.sections.single.blocks.first.ref, 'h1');
    expect(service.completedSections, draft.sections);
    expect((await service.place(m, note())).items.single.why, '主题相同');
    expect(await service.explain(m.items.single), '主动回想');
    for (final mode in NoteRewrite.values) {
      expect(await service.rewrite('生成内容', mode), '主动回想');
    }
    expect(await service.reviewQuestion(draft.sections.single), '主动回想');
    expect(progress.map((p) => p.stage), [NoteStage.outline, NoteStage.write, NoteStage.place]);
    expect(client.toolRequests.every((t) => t.isEmpty), isTrue);
    final request = jsonEncode(client.requests.first.map((m) => m.toJson()).toList());
    expect(request, contains('IDs only'));
    expect(request, contains('untrusted'));
    expect(service.failures, isEmpty);
    final estimate = service.estimate(m);
    expect(estimate.highlights, 1);
    expect(estimate.notes, 0);
    expect(estimate.characters, m.items.single.text.runes.length);
    expect(estimate.model, 'fake');
  });

  test('malformed JSON or invalid fields retry exactly once', () async {
    for (final invalid in ['not json', '[]', '{"sections":null}', '{"sections":[],"extra":1}']) {
      final client = ScriptClient([answer(invalid), answer(outlineJson)]);
      final service = ModelNoteOrganizer(client: client, model: 'fake');
      expect((await service.outline(materials(), NoteSettings())).sections.single.title, '记忆');
      expect(client.calls, 2);
      expect(service.failures, isEmpty);
    }
  });

  test('second schema failure falls back for outline and subsequent write', () async {
    final client = ScriptClient([answer('{}'), answer('{}')]);
    final errors = <NoteSchemaFailure>[];
    final service = ModelNoteOrganizer(client: client, model: 'fake', onFallback: errors.add);
    final m = materials(2);
    final o = await service.outline(m, NoteSettings());
    final d = await service.write(m, o, NoteSettings());
    expect(d.sections.single.blocks.map((b) => b.ref), ['h1', 'h2']);
    expect(errors.single.operation, 'outline');
    expect(errors.single.toString(), 'NoteSchemaFailure(outline)');
    expect(service.failures, errors);
    expect(client.calls, 2);
  });

  test('write rejects rewritten quote text, falls back without losing prior sections', () async {
    final client = ScriptClient([
      answer(draftJson),
      answer('{"sections":[{"title":"next","blocks":[{"type":"quote","ref":"h2","text":"fake quote"}]}]}'),
      answer('{}'),
    ]);
    final service = ModelNoteOrganizer(client: client, model: 'fake');
    final o = NoteOutline([
      ...outline.sections,
      NoteOutlineSection(title: 'next', refs: ['h2']),
    ]);
    final result = await service.write(materials(2), o, NoteSettings());
    expect(result.sections.first.question, '如何练习？');
    expect(result.sections.last.blocks.single.ref, 'h2');
    expect(service.failures.single.operation, 'write');
    expect(client.calls, 3);
  });

  test('wrong section count or title retries and retains requested section', () async {
    final client = ScriptClient([answer('{"sections":[]}'), answer(draftJson)]);
    final service = ModelNoteOrganizer(client: client, model: 'fake');
    expect((await service.write(materials(), outline, NoteSettings())).sections.single.title, '记忆');
    expect(client.calls, 2);
  });

  test('placement rejects conflicting anchors and falls back', () async {
    const bad = '{"placements":[{"ref":"h1","title":"a","why":"b","beforeBlockId":"x","afterBlockId":"y"}]}';
    final client = ScriptClient([answer(bad), answer(bad)]);
    final service = ModelNoteOrganizer(client: client, model: 'fake');
    expect((await service.place(materials(), note())).items.single.ref, 'h1');
    expect(service.failures.single.operation, 'place');
  });

  test('editing schema failure is typed and never substitutes source text', () async {
    final service = ModelNoteOrganizer(
      client: ScriptClient([answer('{"text":" "}'), answer('{"text":"ok","extra":1}')]),
      model: 'fake',
    );
    await expectLater(service.rewrite('original', NoteRewrite.concise), throwsA(isA<NoteSchemaFailure>()));
  });

  test('no AI depth and source/map outlines never call model', () async {
    final client = ScriptClient([]);
    final service = ModelNoteOrganizer(client: client, model: 'fake');
    for (final organization in NoteOrganization.values) {
      final settings = NoteSettings(organization: organization, depth: NoteDepth.none);
      final o = await service.outline(materials(), settings);
      await service.write(materials(), o, settings);
    }
    await service.outline(materials(), NoteSettings(organization: NoteOrganization.map));
    await service.place(materials(), note(NoteDepth.none));
    expect(client.calls, 0);
  });

  test('201 highlights split oversized chapter then merge with stable IDs', () async {
    final client = ScriptClient([
      answer(outlineJson),
      answer('{"sections":[{"title":"记忆","refs":["h201"]}]}'),
      answer(outlineJson),
    ]);
    final progress = <NoteProgress>[];
    final service = ModelNoteOrganizer(client: client, model: 'fake', onProgress: progress.add);
    await service.outline(materials(201), NoteSettings());
    expect(client.calls, 3);
    expect(progress.map((p) => '${p.stage.name}:${p.current}/${p.total}'), ['outline:1/2', 'outline:2/2', 'merge:1/1']);
    final second = jsonEncode(client.requests[1].map((m) => m.toJson()).toList());
    expect(second, contains('h201'));
    expect(second, isNot(contains('a201'))); // Internal persisted ID never sent as a short ID.
  });

  test('chapter batches stay separate and threshold 200 is one request', () async {
    final client = ScriptClient([for (var i = 0; i < 5; i++) answer(outlineJson)]);
    final service = ModelNoteOrganizer(client: client, model: 'fake');
    await service.outline(materials(201, true), NoteSettings());
    expect(client.calls, 4);
    await service.outline(materials(200), NoteSettings());
    expect(client.calls, 5);
  });

  test('place batches accumulate before returning one atomic preview', () async {
    final client = ScriptClient([answer('{"placements":[]}'), answer('{"placements":[]}')]);
    final service = ModelNoteOrganizer(client: client, model: 'fake');
    expect((await service.place(materials(201), note())).items, isEmpty);
    expect(client.calls, 2);
  });

  test('cancellation between sections retains completed output', () async {
    final client = ScriptClient([answer(draftJson)]);
    final service = ModelNoteOrganizer(client: client, model: 'fake');
    final o = NoteOutline([
      ...outline.sections,
      NoteOutlineSection(title: 'next', refs: ['h2']),
    ]);
    final stream = service.writeSections(materials(2), o, NoteSettings());
    await expectLater(() async {
      await for (final _ in stream) {
        service.cancel();
      }
    }(), throwsA(failure(ResearchFailureKind.cancelled)));
    expect(service.completedSections.single.title, '记忆');
    expect(client.calls, 1);
  });

  test('resume starts at the next section and retains global cross-reference indexes', () async {
    final client = ScriptClient([
      answer(
        '{"sections":[{"title":"next","blocks":[{"type":"quote","ref":"h2"},{"type":"xref","to":0,"text":"Earlier"}]}]}',
      ),
    ]);
    final service = ModelNoteOrganizer(client: client, model: 'fake');
    final proposed = NoteOutline([
      ...outline.sections,
      NoteOutlineSection(title: 'next', refs: ['h2']),
    ]);
    final sections = await service.writeSections(materials(2), proposed, NoteSettings(), startAt: 1).toList();
    expect(client.calls, 1);
    expect(sections.single.title, 'next');
    expect(sections.single.blocks.last.to, 0);
    final request = jsonEncode(client.requests.single.map((m) => m.toJson()).toList());
    expect(request, contains('sectionIndex'));
    expect(request, contains('next'));
    service.close();
  });

  test('cancellation during a request cancels transport without fallback', () async {
    final client = PendingClient();
    final service = ModelNoteOrganizer(client: client, model: 'fake');
    final pending = service.outline(materials(), NoteSettings());
    final check = expectLater(pending, throwsA(failure(ResearchFailureKind.cancelled)));
    await client.started.future;
    service.cancel();
    await check;
    expect(client.token!.isCancelled, isTrue);
    expect(service.failures, isEmpty);
  });

  test('deadline cancels transport and reports timeout', () async {
    final client = PendingClient();
    final service = ModelNoteOrganizer(client: client, model: 'fake', requestTimeout: const Duration(milliseconds: 10));
    await expectLater(service.outline(materials(), NoteSettings()), throwsA(failure(ResearchFailureKind.timeout)));
    expect(client.token!.isCancelled, isTrue);
  });

  test('unexpected stop and tools propagate protocol errors without retry', () async {
    for (final response in [answer('{}', stop: 'unexpected'), call('tool', '{}')]) {
      final client = ScriptClient([response]);
      final service = ModelNoteOrganizer(client: client, model: 'fake');
      await expectLater(service.outline(materials(), NoteSettings()), throwsA(failure(ResearchFailureKind.protocol)));
      expect(client.calls, 1);
    }
  });

  test('large multi-section notes have no cumulative input, output or response quota', () async {
    final prose = 'x' * 220000;
    ModelMessage reasoningAnswer(String text) => ModelMessage(
      model: 'reasoning',
      textOutput: text,
      stopReason: 'stop',
      usage: ModelUsage(promptTokens: 100000, completionTokens: 100000, totalTokens: 200000),
    );
    final largeDraft = jsonEncode({
      'sections': [
        {
          'title': '记忆',
          'blocks': [
            {'type': 'summary', 'text': prose},
            {'type': 'quote', 'ref': 'h1'},
          ],
        },
      ],
    });
    final client = ScriptClient([
      reasoningAnswer(outlineJson),
      for (var i = 0; i < 40; i++) reasoningAnswer(largeDraft),
    ]);
    final service = ModelNoteOrganizer(client: client, model: 'reasoning');
    final source = NoteMaterials([
      NoteMaterial(ref: 'h1', sourceId: 'a1', text: 'a' * 60000, groupKey: 'g', groupTitle: '记忆', createdAt: date),
    ], collectedAt: date);
    final proposed = await service.outline(source, NoteSettings());
    final draft = await service.write(
      source,
      NoteOutline([for (var i = 0; i < 40; i++) proposed.sections.single]),
      NoteSettings(),
    );
    expect(draft.sections, hasLength(40));
    expect(client.calls, 41);
    expect(service.failures, isEmpty);
    expect(client.modelConfigs.every((config) => config.maxTokens == null), isTrue);
  });

  test('each request gets its own timeout without a session deadline', () async {
    final client = ScriptClient([answer(outlineJson), answer(draftJson)]);
    final service = ModelNoteOrganizer(client: client, model: 'fake', requestTimeout: const Duration(milliseconds: 20));
    final proposed = await service.outline(materials(), NoteSettings());
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect((await service.write(materials(), proposed, NoteSettings())).sections, hasLength(1));
    expect(client.calls, 2);
  });

  test('truncated model output reports the output limit without schema fallback', () async {
    final service = ModelNoteOrganizer(
      client: ScriptClient([answer('{}', stop: 'length')]),
      model: 'fake',
    );
    await expectLater(service.outline(materials(), NoteSettings()), throwsA(failure(ResearchFailureKind.budget)));
    expect(service.failures, isEmpty);
  });

  test('close cancels and releases the connection', () {
    var closed = false;
    final service = ModelNoteOrganizer(client: ScriptClient([]), model: 'fake', closeConnection: () => closed = true);
    service.close();
    expect(closed, isTrue);
    expect(service.cancelToken.isCancelled, isTrue);
    expect(
      () => ModelNoteOrganizer(client: ScriptClient([]), model: 'fake', requestTimeout: Duration.zero),
      throwsA(failure(ResearchFailureKind.invalidRequest)),
    );
  });
}
