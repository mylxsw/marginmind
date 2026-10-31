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
MapBuildInput build(MapLinePhase phase, List<MapLine> points) => MapBuildInput(
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
