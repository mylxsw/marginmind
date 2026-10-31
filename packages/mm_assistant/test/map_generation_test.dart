import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dart_agent_core/eval.dart';
import 'package:dio/dio.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'support.dart';
import 'expansion_test.dart' show RecordedChunks;

MapLineContext context(MapLinePhase phase, {String prefix = 'draft-'}) => MapLineContext(
  phase: phase,
  mapId: 'private-map',
  draftPrefix: prefix,
  documents: {'D1': 'private-document'},
  pages: {
    'D1': {1, 2},
  },
  annotations: {'A1': 'private-mark'},
  nodes: {'N1': 'private-node', 'N2': 'private-protected'},
  protectedNodeIds: {'private-protected'},
);
MapChapterInput chapter({String id = 'chapter', String prefix = 'draft-'}) => MapChapterInput(
  chapterId: id,
  documentAlias: 'D1',
  context: context(MapLinePhase.chapter, prefix: prefix),
  textByPage: {1: 'source $id'},
  annotations: {'A1': 'quote'},
);
MapBuildInput build(
  MapLinePhase phase,
  List<MapLine> points, {
  bool onlyNewContent = true,
  List<String> titleConstraints = const [],
}) => MapBuildInput(
  onlyNewContent: onlyNewContent,
  titleConstraints: titleConstraints,
  title: 'Map',
  generation: MapGeneration(
    sources: [MapSource(documentId: 'private-document', fingerprint: 'hash', readThrough: 2)],
    organization: MapOrganization.topic,
    depth: 3,
    generatedAt: DateTime.utc(2026),
  ),
  context: context(phase),
  points: points,
  existingTitles: {'N1': 'Old', 'private-leak': 'omit'},
  existingParents: {'N1': 'ROOT', 'private-leak': 'private-id'},
);
ModelMapGenerator generator(LLMClient client, {ResearchBudget? budget, void Function(String)? invalid}) =>
    ModelMapGenerator(
      AssistantConnection(client, Dio()),
      'fake',
      chapterBudget: budget ?? const ResearchBudget(duration: Duration(seconds: 2)),
      buildBudget: budget ?? const ResearchBudget(duration: Duration(seconds: 2)),
      onInvalidLine: invalid,
    );
const point = '{"k":"point","id":"p1","title":"First","doc":"D1","page":1,"marks":["A1"]}';
const topic = '{"ref":"a","parent":"ROOT","title":"Topic","doc":"D1","page":1}';
final cancelled = isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.cancelled);
void main() {
  test('truncation preserves stage, reasoning and limits without exposing response text', () async {
    final client = ScriptClient([
      ModelMessage(model: 'fake', thought: 'thinking', textOutput: 'private response', stopReason: 'length'),
    ]);
    final model = generator(client);
    await expectLater(
      model.readChapter(chapter(), CancellationToken()).toList(),
      throwsA(
        isA<MapGenerationFailure>()
            .having((e) => e.code, 'code', 'outputTruncated')
            .having((e) => e.phase, 'phase', MapLinePhase.chapter)
            .having((e) => e.reasoningCharacters, 'reasoning', 8)
            .having((e) => e.stopReason, 'stop', 'length')
            .having((e) => e.receivedLines, 'received', 1)
            .having((e) => e.acceptedLines, 'accepted', 0),
      ),
    );
    await model.close();
  });
  test('validation reports fixed rejection reasons and never response content', () async {
    final client = ScriptClient([
      answer(
        'private response\n{"ref":"a","parent":"missing","title":"private title"}\n'
        '{"ref":"b","parent":"ROOT","title":"Topic","extra":"private value"}',
      ),
    ]);
    final model = generator(client);
    try {
      await model.generate(build(MapLinePhase.generation, []), CancellationToken()).toList();
      fail('Expected failure');
    } on MapGenerationFailure catch (error) {
      expect(error.code, 'noValidMapContent');
      expect(error.phase, MapLinePhase.generation);
      expect(error.receivedLines, 3);
      expect(error.rejections, {'invalidJson': 1, 'unknownParent': 1, 'unexpectedKeys': 1});
      expect(error.message, isNull);
      expect(error.toString(), isNot(contains('private')));
    }
    await model.close();
  });
  test('retrying a partially failed chapter gets fresh reference and title state', () async {
    final client = ScriptClient([answer(point, stop: 'length'), answer(point)]);
    final model = generator(client), input = chapter();
    await expectLater(model.readChapter(input, CancellationToken()).toList(), throwsA(isA<MapGenerationFailure>()));
    final retried = await model.readChapter(input, CancellationToken()).toList();
    expect(retried.single.title, 'First');
    await model.close();
  });
  test('default output budgets leave room for reasoning in both phases', () async {
    final client = ScriptClient([answer(point), answer(topic)]);
    final model = ModelMapGenerator(AssistantConnection(client, Dio()), 'reasoning-model');
    final points = await model.readChapter(chapter(), CancellationToken()).toList();
    await model.generate(build(MapLinePhase.generation, points), CancellationToken()).toList();
    expect(client.modelConfigs.map((c) => c.maxTokens), [8192, 16384]);
    await model.close();
  });
  test('HTTP request failures preserve status and correct classification', () async {
    for (final (status, kind) in [
      (400, ResearchFailureKind.invalidRequest),
      (401, ResearchFailureKind.authentication),
      (429, ResearchFailureKind.rateLimited),
      (503, ResearchFailureKind.unavailable),
    ]) {
      final model = generator(
        StreamClient(
          (_) => Stream.error(
            DioException(
              requestOptions: RequestOptions(),
              response: Response(requestOptions: RequestOptions(), statusCode: status, data: 'private error body'),
            ),
          ),
        ),
      );
      await expectLater(
        model.readChapter(chapter(), CancellationToken()).toList(),
        throwsA(
          isA<MapGenerationFailure>()
              .having((e) => e.kind, 'kind', kind)
              .having((e) => e.statusCode, 'HTTP', status)
              .having((e) => e.message, 'redacted', isNull),
        ),
      );
      await model.close();
    }
  });
  test('update scope and edited titles reach the model without host ids', () async {
    for (final onlyNew in [true, false]) {
      final client = ScriptClient([answer('{"op":"rename","node":"N1","title":"Revised"}')]);
      final model = generator(client);
      final input = build(MapLinePhase.diff, [], onlyNewContent: onlyNew, titleConstraints: ['User title']);
      await model.update(input, CancellationToken()).toList();
      final text = (client.requests.single.last as UserMessage).contents.whereType<TextPart>().single.text;
      final payload = jsonDecode(text) as Map;
      expect(payload['scope'], contains(onlyNew ? 'new material only' : 'entire map'));
      expect(payload['preserveTitles'], ['User title']);
      expect(text, isNot(contains('private-')));
      await model.close();
    }
  });

  MapLine p(String id, [String? parent]) =>
      MapLine(id: id, kind: MapLineKind.point, title: id, parentId: parent == null ? 'private-map' : 'new:$parent');
  test('budget fitting removes deepest then latest, preserving ancestor closure and input order', () {
    final points = [p('r1'), p('c1', 'r1'), p('l1', 'c1'), p('r2'), p('c2', 'r2'), p('l2', 'c2')];
    final expected = {
      6: ['r1', 'c1', 'l1', 'r2', 'c2', 'l2'],
      5: ['r1', 'c1', 'l1', 'r2', 'c2'],
      4: ['r1', 'c1', 'r2', 'c2'],
      3: ['r1', 'c1', 'r2'],
      2: ['r1', 'r2'],
      1: ['r1'],
      0: <String>[],
    };
    for (final e in expected.entries) {
      final kept = fitPointsToBudget(points, inputCharacters: e.key + 1, measure: (ps) => ps.length + 1);
      expect(kept.map((p) => p.id), e.value);
      final refs = kept.map((p) => 'new:${p.id}').toSet();
      expect(kept.every((p) => !p.parentId!.startsWith('new:') || refs.contains(p.parentId)), isTrue);
    }
    expect(points, hasLength(6));
    expect(
      () => fitPointsToBudget(points, inputCharacters: 1, measure: (_) => 2),
      throwsA(isA<ResearchFailure>().having((e) => e.code, 'code', 'mapStructureExceedsBudget')),
    );
    for (final invalid in [
      [p('a'), p('a')],
      [p('a', 'b'), p('b', 'a')],
      [p('a', 'missing')],
      [MapLine(id: 'a', kind: MapLineKind.add)],
    ]) {
      expect(
        () => fitPointsToBudget(invalid, inputCharacters: 100, measure: (ps) => ps.length),
        throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.invalidRequest)),
      );
    }
    expect(() => fitPointsToBudget([], inputCharacters: 0, measure: (_) => 0), throwsA(isA<ResearchFailure>()));
    expect(fitPointsToBudget([], inputCharacters: 10, measure: (_) => 1), isEmpty);
  });
  test('large point lists use logarithmically many size measurements', () {
    final points = [for (var i = 0; i < 10000; i++) p('root$i')];
    var measures = 0;
    final kept = fitPointsToBudget(
      points,
      inputCharacters: 2000,
      measure: (ps) {
        measures++;
        return ps.length;
      },
    );
    expect(kept, hasLength(2000));
    expect(kept.last.id, 'root1999');
    expect(measures, lessThanOrEqualTo(17));
  });
  test('generate and update fit actual prompts, aliases and structure into configured budget', () async {
    final points = [for (var i = 0; i < 1000; i++) p('point$i', i % 3 == 0 ? null : 'point${i - i % 3}')];
    for (final phase in [MapLinePhase.generation, MapLinePhase.diff]) {
      final client = ScriptClient([
        answer(phase == MapLinePhase.generation ? topic : '{"op":"add","ref":"a","parent":"ROOT","title":"Topic"}'),
      ]);
      const budget = ResearchBudget(inputCharacters: 2400);
      final model = generator(client, budget: budget);
      final input = build(phase, points);
      final result =
          await (phase == MapLinePhase.generation
                  ? model.generate(input, CancellationToken())
                  : model.update(input, CancellationToken()))
              .toList();
      expect(result, hasLength(1));
      final request = client.requests.single;
      final text = (request.last as UserMessage).contents.whereType<TextPart>().single.text;
      expect((request.first as SystemMessage).content.length + text.length, lessThanOrEqualTo(budget.inputCharacters));
      final payload = jsonDecode(text) as Map;
      final kept = payload['points'] as List;
      expect(kept.length, inInclusiveRange(1, 999));
      expect(kept.first['title'], 'point0');
      final refs = kept.map((p) => p['id']).toSet();
      expect(kept.every((p) => p['parent'] == 'ROOT' || refs.contains(p['parent'])), isTrue);
      expect(input.points, hasLength(1000));
      expect(text, isNot(contains('private-')));
      await model.close();
    }
  });
  test('metadata-only overflows and a single oversized point fail without a model call', () async {
    for (final allowance in [5, 1300]) {
      final client = ScriptClient([]);
      final limited = generator(client, budget: ResearchBudget(inputCharacters: allowance));
      final stream = limited.generate(
        build(MapLinePhase.generation, [
          MapLine(id: 'huge', kind: MapLineKind.point, parentId: 'private-map', title: 'x' * 10000),
        ]),
        CancellationToken(),
      );
      await expectLater(
        stream.toList(),
        throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.budget)),
      );
      expect(client.calls, 0);
      await limited.close();
    }
  });
  test('three prompt snapshots', () {
    for (final e in {
      'map-chapter': mapChapterSystemPrompt,
      'map-generation': mapGenerationSystemPrompt,
      'map-update': mapUpdateSystemPrompt,
    }.entries) {
      expect(e.value, File('test/fixtures/${e.key}-system.txt').readAsStringSync().trimRight());
    }
  });
  test('recorded two chapters to map and incremental diff, with alias-only payload', () async {
    final store = InMemoryRecordingStore();
    final script = ScriptClient([
      answer('$point\r\ninvalid\n{"k":"point","id":"p2","parent":"p1","title":"Child","page":2}'),
      answer('{"k":"point","id":"p1","title":"Second","page":2}'),
      answer('$topic\n{"mark":"A1","parent":"a"}'),
      answer(
        '{"op":"add","ref":"b","parent":"N1","title":"New","page":2}\n{"op":"rename","node":"N2","title":"Forbidden"}',
      ),
    ]);
    final recorder = RecordingLLMClient(inner: script, store: store);
    for (final client in [RecordedChunks(recorder), ReplayLLMClient(store: store)]) {
      final model = generator(client);
      final first = await model.readChapter(chapter(), CancellationToken()).toList();
      final second = await model.readChapter(chapter(id: 'second', prefix: 'second-'), CancellationToken()).toList();
      final points = [...first, ...second];
      final map = await model.generate(build(MapLinePhase.generation, points), CancellationToken()).toList();
      expect(map.map((l) => l.kind), [MapLineKind.add, MapLineKind.excerpt]);
      expect(map.first.source?.documentId, 'private-document');
      final diff = await model.update(build(MapLinePhase.diff, second), CancellationToken()).toList();
      expect(diff.single.title, 'New');
      expect(first.last.parentId, 'new:${first.first.id}');
      await model.close();
    }
    expect(script.calls, 4);
    final payload = (script.requests[2].last as UserMessage).contents.whereType<TextPart>().single.text;
    expect(payload, isNot(contains('private-')));
    expect(jsonDecode(payload)['points'][1]['parent'], 'p1');
    final update = jsonDecode((script.requests[3].last as UserMessage).contents.whereType<TextPart>().single.text);
    expect(update['points'], hasLength(1));
    expect(update['points'][0]['title'], 'Second');
    expect(script.toolRequests.every((t) => t.isEmpty), isTrue);
    expect(script.modelConfigs.every((c) => c.extra?['store'] == false), isTrue);
  });
  test('single chapter failure keeps other chapter usable and retries only failure', () async {
    final client = ScriptClient([answer(point), answer('invalid'), answer(point)]);
    final model = generator(client);
    final success = await model.readChapter(chapter(), CancellationToken()).toList();
    await expectLater(
      model.readChapter(chapter(id: 'failed'), CancellationToken()).toList(),
      throwsA(isA<ResearchFailure>().having((e) => e.code, 'code', 'noValidMapContent')),
    );
    final retry = await model.readChapter(chapter(id: 'failed', prefix: 'retry-'), CancellationToken()).toList();
    expect(success.single.id, isNot(retry.single.id));
    expect(client.calls, 3);
    await model.close();
  });
  test('oversized lines discarded until LF, CRLF and final unterminated line accepted', () async {
    final invalid = <String>[];
    final client = StreamClient(
      (_) => Stream.fromIterable([
        StreamingMessage(modelMessage: answer('x' * 65537, stop: null)),
        StreamingMessage(modelMessage: answer('discard\r\ninvalid\n$point')),
      ]),
    );
    final model = generator(client, invalid: invalid.add);
    expect(await model.readChapter(chapter(), CancellationToken()).toList(), hasLength(1));
    expect(invalid, ['lineSize', 'invalidMapLine']);
    await model.close();
  });
  test('cancellation and close abort silent streams and do not yield late lines', () async {
    for (final close in [false, true]) {
      final opened = Completer<void>(), stream = StreamController<StreamingMessage>();
      CancelToken? network;
      final model = generator(
        StreamClient((token) {
          network = token;
          opened.complete();
          return stream.stream;
        }),
      );
      final cancel = CancellationToken();
      final check = expectLater(model.readChapter(chapter(), cancel).toList(), throwsA(cancelled));
      await opened.future;
      if (close) {
        await model.close();
      } else {
        cancel.cancel();
      }
      await check;
      expect(network!.isCancelled, isTrue);
      await stream.close();
      await model.close();
      await expectLater(model.readChapter(chapter(), CancellationToken()).toList(), throwsStateError);
    }
  });
  test('cancellation between yields prevents buffered late output', () async {
    final model = generator(ScriptClient([answer('$point\n{"k":"point","id":"p2","title":"Later"}')]));
    final token = CancellationToken(), seen = <MapLine>[];
    await expectLater(
      model.readChapter(chapter(), token).forEach((l) {
        seen.add(l);
        token.cancel();
      }),
      throwsA(cancelled),
    );
    expect(seen, hasLength(1));
    await model.close();
  });
  test('timeouts, bytes, input, stop reasons, control and tool protocols', () async {
    for (final (client, budget, kind) in <(LLMClient, ResearchBudget?, ResearchFailureKind)>[
      (StreamClient((_) => const Stream.empty()), null, ResearchFailureKind.protocol),
      (ScriptClient([answer(point, stop: 'length')]), null, ResearchFailureKind.budget),
      (ScriptClient([answer(point, stop: 'refusal')]), null, ResearchFailureKind.refusal),
      (ScriptClient([answer(point, stop: null)]), null, ResearchFailureKind.protocol),
      (ScriptClient([call('tool', '{}')]), null, ResearchFailureKind.toolProtocol),
      (ScriptClient([answer(point)]), const ResearchBudget(responseBytes: 5), ResearchFailureKind.budget),
      (ScriptClient([]), const ResearchBudget(inputCharacters: 5), ResearchFailureKind.budget),
      (
        StreamClient(
          (_) => Stream.error(DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError)),
        ),
        null,
        ResearchFailureKind.network,
      ),
      (
        StreamClient(
          (_) => Stream.error(
            DioException(
              requestOptions: RequestOptions(),
              response: Response(requestOptions: RequestOptions(), statusCode: 503),
            ),
          ),
        ),
        null,
        ResearchFailureKind.unavailable,
      ),
    ]) {
      final model = generator(client, budget: budget);
      await expectLater(
        model.readChapter(chapter(), CancellationToken()).toList(),
        throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', kind)),
      );
      await model.close();
    }
    final silent = StreamController<StreamingMessage>();
    final model = generator(
      StreamClient((_) => silent.stream),
      budget: const ResearchBudget(duration: Duration(milliseconds: 10)),
    );
    await expectLater(
      model.readChapter(chapter(), CancellationToken()).toList(),
      throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.timeout)),
    );
    await silent.close();
    await model.close();
  });
  test('invalid phase rejected; non-whitelisted pages and marks omitted from build input', () async {
    final client = ScriptClient([answer(topic)]), model = generator(client);
    final points = [
      MapLine(
        id: 'secret-point',
        kind: MapLineKind.point,
        title: 'Safe',
        source: CardSource(documentId: 'private-document', page: 99),
        marks: ['unknown'],
      ),
    ];
    await model.generate(build(MapLinePhase.generation, points), CancellationToken()).toList();
    final text = (client.requests.single.last as UserMessage).contents.whereType<TextPart>().single.text;
    expect(text, isNot(contains('99')));
    expect(text, isNot(contains('unknown')));
    await expectLater(
      model.generate(build(MapLinePhase.diff, []), CancellationToken()).toList(),
      throwsA(isA<ResearchFailure>()),
    );
    await model.close();
  });
}
