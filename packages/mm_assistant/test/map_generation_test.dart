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
import 'providers_test.dart' show Adapter;
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
ModelMapGenerator generator(
  LLMClient client, {
  Duration requestTimeout = const Duration(seconds: 2),
  void Function(String)? invalid,
}) => ModelMapGenerator(
  AssistantConnection(client, Dio()),
  'fake',
  requestTimeout: requestTimeout,
  onInvalidLine: invalid,
);
const point = '{"k":"point","id":"p1","title":"First","doc":"D1","page":1,"marks":["A1"]}';
const topic = '{"ref":"a","parent":"ROOT","title":"Topic","doc":"D1","page":1}';
final cancelled = isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.cancelled);
void main() {
  test('truncation preserves stage and reasoning without exposing response text', () async {
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
    final invalid = answer(
      'private response\n{"ref":"a","parent":"missing","title":"private title"}\n'
      '{"ref":"b","parent":"ROOT","title":"Topic","extra":"private value"}',
    );
    final client = ScriptClient([invalid, invalid]);
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
    expect(client.calls, 2);
    expect((client.requests.last.first as SystemMessage).content, isNot(contains('private')));
    await model.close();
  });
  test('43 unresolved parents trigger one corrected request with a fresh parser', () async {
    final invalid = [
      for (var i = 0; i < 43; i++) jsonEncode({'ref': 'a$i', 'parent': 'p1', 'title': 'Point $i'}),
    ].join('\n');
    final client = ScriptClient([answer(invalid), answer('$topic\n{"ref":"b","parent":"a","title":"Child"}')]);
    final model = generator(client);
    final result = await model.generate(build(MapLinePhase.generation, []), CancellationToken()).toList();
    expect(client.calls, 2);
    expect(result, hasLength(2));
    expect(result.last.parentId, 'new:${result.first.id}');
    expect((client.requests.last.first as SystemMessage).content, contains('previous response had no valid map lines'));
    await model.close();
  });
  test('an invalid root field and 43 disconnected children get one schema repair', () async {
    for (final phase in [MapLinePhase.generation, MapLinePhase.diff]) {
      final root = {if (phase == MapLinePhase.diff) 'op': 'add', 'ref': 'a', 'parent': 'ROOT', 'title': 'Topic'};
      final invalid = [
        jsonEncode({...root, 'extra': 'private response value'}),
        for (var i = 0; i < 43; i++)
          jsonEncode({if (phase == MapLinePhase.diff) 'op': 'add', 'ref': 'b$i', 'parent': 'a', 'title': 'Child $i'}),
      ].join('\n');
      final client = ScriptClient([
        answer(invalid),
        answer(
          '${jsonEncode(root)}\n${jsonEncode({if (phase == MapLinePhase.diff) 'op': 'add', 'ref': 'b', 'parent': 'a', 'title': 'Child'})}',
        ),
      ]);
      final model = generator(client);
      final input = build(phase, []), cancel = CancellationToken();
      final result =
          await (phase == MapLinePhase.generation ? model.generate(input, cancel) : model.update(input, cancel))
              .toList();
      expect(client.calls, 2);
      expect(result.map((line) => line.title), ['Topic', 'Child']);
      expect(result.last.parentId, 'new:${result.first.id}');
      final repair = (client.requests.last.first as SystemMessage).content;
      expect(repair, contains('unexpectedKeys'));
      expect(repair, contains('unknownParent'));
      expect(repair, isNot(contains('private response value')));
      String payload(List<LLMMessage> messages) =>
          (messages.last as UserMessage).contents.whereType<TextPart>().single.text;
      expect(payload(client.requests.first), payload(client.requests.last));
      await model.close();
    }
  });
  test('a usable draft is preserved without regenerating after rejected lines', () async {
    final client = ScriptClient([answer('$topic\n{"ref":"b","parent":"a","title":"Child","extra":true}')]);
    final model = generator(client);
    final result = await model.generate(build(MapLinePhase.generation, []), CancellationToken()).toList();
    expect(result.single.title, 'Topic');
    expect(client.calls, 1);
    await model.close();
  });
  test('truncated, refused and incomplete responses never trigger schema repair', () async {
    for (final (stop, code, kind) in [
      ('length', 'outputTruncated', ResearchFailureKind.budget),
      ('refusal', null, ResearchFailureKind.refusal),
      (null, 'incompleteStream', ResearchFailureKind.protocol),
    ]) {
      final client = ScriptClient([answer('{"ref":"a","parent":"ROOT","title":"Topic","extra":true}', stop: stop)]);
      final model = generator(client);
      await expectLater(
        model.generate(build(MapLinePhase.generation, []), CancellationToken()).toList(),
        throwsA(isA<MapGenerationFailure>().having((e) => e.kind, 'kind', kind).having((e) => e.code, 'code', code)),
      );
      expect(client.calls, 1);
      await model.close();
    }
  });
  test('schema repair stays cancellable and cancels the second network request', () async {
    final repairing = Completer<void>(), silent = StreamController<StreamingMessage>();
    CancelToken? network;
    late final StreamClient client;
    client = StreamClient((token) {
      if (client.calls == 1) {
        return Stream.value(
          StreamingMessage(modelMessage: answer('{"ref":"a","parent":"ROOT","title":"Topic","extra":true}')),
        );
      }
      network = token;
      repairing.complete();
      return silent.stream;
    });
    final model = generator(client), cancel = CancellationToken();
    final check = expectLater(model.generate(build(MapLinePhase.generation, []), cancel).toList(), throwsA(cancelled));
    await repairing.future;
    cancel.cancel();
    await check;
    expect(client.calls, 2);
    expect(network!.isCancelled, isTrue);
    await silent.close();
    await model.close();
  });
  test('out-of-order descendants resolve without another request or arbitrary reparenting', () async {
    final client = ScriptClient([
      answer(
        '{"ref":"c","parent":"b","title":"Grandchild"}\n'
        '{"ref":"b","parent":"a","title":"Child"}\n$topic',
      ),
    ]);
    final model = generator(client);
    final result = await model.generate(build(MapLinePhase.generation, []), CancellationToken()).toList();
    expect(client.calls, 1);
    expect(result.map((p) => p.title), ['Topic', 'Child', 'Grandchild']);
    expect(result[2].parentId, 'new:${result[1].id}');
    await model.close();
  });
  test('persistent missing parents stop after one repair; cycles never become a draft', () async {
    const cycle = '{"ref":"a","parent":"b","title":"A"}\n{"ref":"b","parent":"a","title":"B"}';
    final client = ScriptClient([answer(cycle), answer(cycle)]);
    final model = generator(client);
    await expectLater(
      model.generate(build(MapLinePhase.generation, []), CancellationToken()).toList(),
      throwsA(isA<MapGenerationFailure>().having((e) => e.rejections, 'rejections', {'unknownParent': 2})),
    );
    expect(client.calls, 2);
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
  test('normal stop accepts 27 valid lines despite large reasoning and reported token usage', () async {
    final output = [
      for (var i = 1; i <= 27; i++) jsonEncode({'k': 'point', 'id': 'p$i', 'title': '要点 $i', 'doc': 'D1', 'page': 1}),
    ].join('\n');
    final client = ScriptClient([
      ModelMessage(
        model: 'deepseek-flash',
        thought: '思' * 21832,
        textOutput: output,
        stopReason: 'stop',
        usage: ModelUsage(promptTokens: 100000, completionTokens: 20000, totalTokens: 120000),
      ),
      answer(topic),
      answer('{"op":"rename","node":"N1","title":"Revised"}'),
    ]);
    final model = ModelMapGenerator(AssistantConnection(client, Dio()), 'deepseek-flash');
    final points = await model.readChapter(chapter(), CancellationToken()).toList();
    expect(points, hasLength(27));
    await model.generate(build(MapLinePhase.generation, points), CancellationToken()).toList();
    await model.update(build(MapLinePhase.diff, points), CancellationToken()).toList();
    expect(client.modelConfigs.map((c) => c.maxTokens), [null, null, null]);
    await model.close();
  });
  test('compatible wire requests omit token caps and accept large responses with final usage', () async {
    final chapterOutput = [
      for (var i = 1; i <= 27; i++) jsonEncode({'k': 'point', 'id': 'p$i', 'title': 'Point $i'}),
    ].join('\n');
    final adapter = Adapter((options, n) {
      final request = options.data is String ? jsonDecode(options.data) : options.data;
      for (final field in ['max_tokens', 'max_completion_tokens', 'max_output_tokens']) {
        expect(request.containsKey(field), isFalse);
      }
      final output = n == 1
          ? '$chapterOutput${' ' * 3000000}'
          : n == 2
          ? topic
          : '{"op":"rename","node":"N1","title":"Revised"}';
      return ResponseBody.fromString(
        [
          'data: ${jsonEncode({
            'model': 'reasoning',
            'choices': [
              {
                'index': 0,
                'delta': {'content': output, 'reasoning_content': '思' * 21832},
                'finish_reason': 'stop',
              },
            ],
          })}',
          '',
          'data: ${jsonEncode({
            'model': 'reasoning',
            'choices': [],
            'usage': {'prompt_tokens': 100000, 'completion_tokens': 20000, 'total_tokens': 120000},
          })}',
          '',
          'data: [DONE]',
          '',
        ].join('\n'),
        200,
        headers: {
          Headers.contentTypeHeader: ['text/event-stream'],
        },
      );
    });
    final connection = connectAssistant(
      const AssistantModel(
        provider: AssistantProvider.compatible,
        model: 'reasoning',
        endpoint: 'https://example.com/v1',
      ),
      'fake-key',
      budget: null,
      requestTimeout: mapGenerationRequestTimeout,
      adapter: adapter,
    );
    final model = ModelMapGenerator(connection, 'reasoning');
    final points = await model.readChapter(chapter(), CancellationToken()).toList();
    expect(points, hasLength(27));
    expect(await model.generate(build(MapLinePhase.generation, points), CancellationToken()).length, 1);
    expect(await model.update(build(MapLinePhase.diff, points), CancellationToken()).length, 1);
    expect(adapter.calls, 3);
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
  test('generate and update preserve every point and parent in large requests', () async {
    final points = [for (var i = 0; i < 10000; i++) p('point$i', i % 3 == 0 ? null : 'point${i - i % 3}')];
    for (final phase in [MapLinePhase.generation, MapLinePhase.diff]) {
      final client = ScriptClient([
        answer(phase == MapLinePhase.generation ? topic : '{"op":"add","ref":"a","parent":"ROOT","title":"Topic"}'),
      ]);
      final model = generator(client);
      final input = build(phase, points);
      final result =
          await (phase == MapLinePhase.generation
                  ? model.generate(input, CancellationToken())
                  : model.update(input, CancellationToken()))
              .toList();
      expect(result, hasLength(1));
      final text = (client.requests.single.last as UserMessage).contents.whereType<TextPart>().single.text;
      expect(text.length, greaterThan(30000));
      final payload = jsonDecode(text) as Map;
      final sent = payload['points'] as List;
      expect(sent, hasLength(points.length));
      for (var i = 0; i < points.length; i++) {
        expect(sent[i]['title'], points[i].title);
        expect(sent[i]['parent'], i % 3 == 0 ? 'ROOT' : 'p${i - i % 3 + 1}');
      }
      expect(text, isNot(contains('private-')));
      await model.close();
    }
  });
  test('duplicate, missing and cyclic point references still fail before sending', () async {
    for (final points in [
      [p('a'), p('a')],
      [p('a', 'b'), p('b', 'a')],
      [p('a', 'missing')],
      [MapLine(id: 'a', kind: MapLineKind.add)],
    ]) {
      final client = ScriptClient([]), model = generator(client);
      await expectLater(
        model.generate(build(MapLinePhase.generation, points), CancellationToken()).toList(),
        throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.invalidRequest)),
      );
      expect(client.calls, 0);
      await model.close();
    }
  });
  test('chapter input and large responses have no character, line or byte quota', () async {
    final source = '文' * 100000;
    final quote = '引' * 70000;
    final chapterInput = MapChapterInput(
      chapterId: 'large',
      documentAlias: 'D1',
      textByPage: {1: source + quote},
      annotations: {'A1': '注' * 50000},
      instructions: '要求' * 2000,
      context: MapLineContext(
        phase: MapLinePhase.chapter,
        mapId: 'private-map',
        draftPrefix: 'large-',
        documents: {'D1': 'private-document'},
        pages: {
          'D1': {1},
        },
        quoteTextByPage: {
          'D1': {1: source + quote},
        },
      ),
    );
    final output = [
      for (var i = 0; i < 40; i++)
        jsonEncode({'k': 'point', 'id': 'p$i', 'title': 'Point $i', 'doc': 'D1', 'page': 1, 'quote': quote}),
    ].join('\n');
    expect(utf8.encode(output).length, greaterThan(2097152));
    final client = ScriptClient([answer(output)]), model = generator(client);
    final points = await model.readChapter(chapterInput, CancellationToken()).toList();
    expect(points, hasLength(40));
    expect(points.every((p) => p.quote == quote), isTrue);
    final payload = jsonDecode((client.requests.single.last as UserMessage).contents.whereType<TextPart>().single.text);
    expect(payload['pages']['1'], source + quote);
    expect(payload['annotations']['A1'], chapterInput.annotations['A1']);
    expect(payload['instructions'], chapterInput.instructions);
    await model.close();
  });
  test('each chapter has its own timeout without a session deadline', () async {
    final client = ScriptClient([answer(point), answer(point)]);
    final model = generator(client, requestTimeout: const Duration(milliseconds: 50));
    expect(await model.readChapter(chapter(), CancellationToken()).length, 1);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(await model.readChapter(chapter(), CancellationToken()).length, 1);
    await model.close();
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
  test('invalid long lines, CRLF and final unterminated line are parsed without clipping', () async {
    final invalid = <String>[];
    final client = StreamClient(
      (_) => Stream.fromIterable([
        StreamingMessage(modelMessage: answer('x' * 65537, stop: null)),
        StreamingMessage(modelMessage: answer('discard\r\ninvalid\n$point')),
      ]),
    );
    final model = generator(client, invalid: invalid.add);
    expect(await model.readChapter(chapter(), CancellationToken()).toList(), hasLength(1));
    expect(invalid, ['invalidMapLine', 'invalidMapLine']);
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
  test('timeouts, stop reasons, control and tool protocols', () async {
    for (final (client, kind) in <(LLMClient, ResearchFailureKind)>[
      (StreamClient((_) => const Stream.empty()), ResearchFailureKind.protocol),
      (ScriptClient([answer(point, stop: 'length')]), ResearchFailureKind.budget),
      (ScriptClient([answer(point, stop: 'refusal')]), ResearchFailureKind.refusal),
      (ScriptClient([answer(point, stop: null)]), ResearchFailureKind.protocol),
      (ScriptClient([call('tool', '{}')]), ResearchFailureKind.toolProtocol),
      (
        StreamClient(
          (_) => Stream.error(DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError)),
        ),
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
        ResearchFailureKind.unavailable,
      ),
    ]) {
      final model = generator(client);
      await expectLater(
        model.readChapter(chapter(), CancellationToken()).toList(),
        throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', kind)),
      );
      await model.close();
    }
    final silent = StreamController<StreamingMessage>();
    final model = generator(StreamClient((_) => silent.stream), requestTimeout: const Duration(milliseconds: 10));
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
