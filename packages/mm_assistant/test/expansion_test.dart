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

final req = ExpansionRequest(studySetId: 'private-set', mapId: 'private-map', targetIds: ['private-node'], depth: 3);
ExpansionContext context() => ExpansionContext(
  targets: {'T1': 'private-node'},
  details: {
    'T1': ExpansionTargetContext(title: 'Topic', children: ['Existing'], pages: {47: 'Source'}),
  },
  draftPrefix: 'run-',
);
ModelIdeaExpander expander(LLMClient client, {ResearchBudget? budget, void Function(String)? invalid}) =>
    ModelIdeaExpander(
      AssistantConnection(client, Dio()),
      'fake',
      budget: budget ?? const ResearchBudget(duration: Duration(seconds: 2)),
      onInvalidLine: invalid,
    );
const first = '{"ref":"a","parent":"T1","title":"New","page":47}';
void main() {
  test('stream chunks crossing lines and no trailing newline, recorded and replayed', () async {
    final store = InMemoryRecordingStore();
    final full = '$first\r\ninvalid\n{"ref":"b","parent":"a","title":"Child"}';
    final recording = RecordingLLMClient(inner: ScriptClient([answer(full)]), store: store);
    // SDK 2.1.8 only records generate(); replay synthesizes one stream chunk.
    for (final source in [RecordedChunks(recording), ReplayLLMClient(store: store)]) {
      final invalid = <String>[];
      final drafts = await expander(source, invalid: invalid.add).expand(req, context(), CancellationToken()).toList();
      expect(drafts.map((d) => d.title), ['New', 'Child']);
      expect(drafts.first.page, 47);
      expect(drafts.last.parentRef, 'new:${drafts.first.id}');
      expect(invalid, ['json']);
    }
  });
  test('prompt snapshots and no host IDs or tools in requests', () async {
    final client = ScriptClient([answer(first)]);
    await expander(client).expand(req, context(), CancellationToken()).toList();
    final payload = jsonEncode(client.requests.single.map((m) => m.toJson()).toList());
    expect(payload, isNot(contains('private-')));
    expect(client.toolRequests.single, isEmpty);
    expect(expansionSystemPrompt, File('test/fixtures/expansion-system.txt').readAsStringSync());
    expect(expansionPlanSystemPrompt, File('test/fixtures/expansion-plan-system.txt').readAsStringSync());
  });
  test('per-target provenance and global duplicate/ref checks', () async {
    final ctx = ExpansionContext(
      targets: {'T1': 'a', 'T2': 'b'},
      details: {
        'T1': ExpansionTargetContext(title: 'A', pages: {1: 'one'}),
        'T2': ExpansionTargetContext(title: 'B', pages: {2: 'two'}),
      },
      draftPrefix: 'call-',
    );
    final model = ScriptClient([
      answer(
        [
          '{"ref":"a","parent":"T1","title":"Hello","page":2}',
          '{"ref":"b","parent":"T2","title":"Ｈｅｌｌｏ！"}',
          '{"ref":"a","parent":"T2","title":"Bad ref"}',
          '{"ref":"c","parent":"T2","title":"Other","page":2}',
          '{"ref":"d","parent":"gone","title":"Orphan"}',
          '[]',
          '{"ref":"e","parent":"T1","title":"Invalid","extra":1}',
        ].join('\n'),
      ),
    ]);
    final values = await expander(model).expand(req, ctx, CancellationToken()).toList();
    expect(values.length, 2);
    expect(values.first.page, isNull);
    expect(values.last.page, 2);
  });
  test('all invalid, empty, refusal, truncation, tools and missing stop are failures', () async {
    for (final reply in [
      answer(''),
      answer('broken'),
      answer('[]'),
      answer(first, stop: 'length'),
      answer(first, stop: 'refusal'),
      answer(first, stop: null),
      call('bad', '{}'),
    ]) {
      await expectLater(
        expander(ScriptClient([reply])).expand(req, context(), CancellationToken()).toList(),
        throwsA(isA<ResearchFailure>()),
      );
    }
  });
  test('cancellation before start and during silent stream cancels transport', () async {
    final early = CancellationToken()..cancel();
    await expectLater(
      expander(ScriptClient([])).expand(req, context(), early).toList(),
      throwsA(isA<ResearchFailure>()),
    );
    final cancel = CancellationToken();
    CancelToken? transport;
    final opened = Completer<void>();
    final controller = StreamController<StreamingMessage>();
    final model = expander(
      StreamClient((token) {
        transport = token;
        opened.complete();
        return controller.stream;
      }),
    );
    final run = model.expand(req, context(), cancel).toList();
    final check = expectLater(
      run,
      throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.cancelled)),
    );
    await opened.future;
    cancel.cancel();
    await check;
    expect(transport!.isCancelled, isTrue);
    await controller.close();
  });
  test('close interrupts a silent stream and plan counts apply to generation', () async {
    final opened = Completer<void>();
    final source = StreamController<StreamingMessage>();
    final model = expander(
      StreamClient((_) {
        opened.complete();
        return source.stream;
      }),
    );
    final check = expectLater(
      model.expand(req, context(), CancellationToken()).toList(),
      throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.cancelled)),
    );
    await opened.future;
    model.close();
    await check;
    await source.close();
    final planned = ExpansionRequest(
      studySetId: 'set',
      mapId: 'map',
      targetIds: ['private-node'],
      scope: ExpansionScope.map,
      plan: {'private-node': 1},
    );
    final values = await expander(ScriptClient([answer('$first\n{"ref":"b","parent":"T1","title":"Second"}')]))
        .expand(planned, context(), CancellationToken())
        .toList();
    expect(values, hasLength(1));
    expect(() => ExpansionTargetContext(title: 'x', pages: {0: 'bad'}), throwsArgumentError);
    expect(() => ExpansionTargetContext(title: 'x', pages: {1: ''}), throwsArgumentError);
  });
  test('partial failure retains delivered drafts, network errors are redacted', () async {
    final drafts = <ExpansionDraft>[];
    final failure = DioException(
      requestOptions: RequestOptions(path: 'secret'),
      type: DioExceptionType.connectionError,
      message: 'SECRET',
    );
    final model = expander(
      StreamClient((_) async* {
        yield StreamingMessage(modelMessage: answer('$first\n', stop: null));
        throw failure;
      }),
    );
    await expectLater(
      model.expand(req, context(), CancellationToken()).forEach(drafts.add),
      throwsA(
        isA<ResearchFailure>()
            .having((e) => e.kind, 'kind', ResearchFailureKind.network)
            .having((e) => e.message, 'message', isNull),
      ),
    );
    expect(drafts.length, 1);
    for (final entry in {
      401: ResearchFailureKind.authentication,
      403: ResearchFailureKind.authentication,
      429: ResearchFailureKind.rateLimited,
      503: ResearchFailureKind.unavailable,
      400: ResearchFailureKind.network,
    }.entries) {
      expect(
        expansionFailure(
          DioException(
            requestOptions: RequestOptions(),
            response: Response(requestOptions: RequestOptions(), statusCode: entry.key),
          ),
        ).kind,
        entry.value,
      );
    }
    expect(expansionFailure(TimeoutException('secret')).kind, ResearchFailureKind.timeout);
    expect(
      expansionFailure(DioException(requestOptions: RequestOptions(), type: DioExceptionType.receiveTimeout)).kind,
      ResearchFailureKind.timeout,
    );
    expect(
      expansionFailure(DioException(requestOptions: RequestOptions(), type: DioExceptionType.cancel)).kind,
      ResearchFailureKind.cancelled,
    );
    expect(expansionFailure(StateError('secret')).kind, ResearchFailureKind.protocol);
  });
  test('deadline and input/output byte budgets', () async {
    for (final budget in [const ResearchBudget(inputCharacters: 1), const ResearchBudget(responseBytes: 1)]) {
      await expectLater(
        expander(ScriptClient([answer(first)]), budget: budget).expand(req, context(), CancellationToken()).toList(),
        throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.budget)),
      );
    }
    final controller = StreamController<StreamingMessage>();
    await expectLater(
      expander(
        StreamClient((_) => controller.stream),
        budget: const ResearchBudget(duration: Duration(milliseconds: 10)),
      ).expand(req, context(), CancellationToken()).toList(),
      throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.timeout)),
    );
    await controller.close();
  });
  test('oversized line is skipped and parsing resumes', () async {
    final invalid = <String>[];
    final values = await expander(
      ScriptClient([answer('${'x' * 65537}\n$first')]),
      invalid: invalid.add,
    ).expand(req, context(), CancellationToken()).toList();
    expect(values.single.title, 'New');
    expect(invalid, ['lineSize']);
  });
  test('plan is structure only, deduplicated, bounded per parent, no total cap', () async {
    final targets = {'T1': 'root', for (var i = 2; i < 20; i++) 'T$i': 'branch$i'};
    final ctx = ExpansionContext(
      targets: targets,
      details: {
        for (final key in targets.keys) key: ExpansionTargetContext(title: key, pages: {47: 'PRIVATE SOURCE'}),
      },
      draftPrefix: 'p',
    );
    final client = ScriptClient([
      answer(
        [
          'bad',
          for (var i = 2; i < 20; i++) '{"branch":"T$i","add":5,"reason":"thin"}',
          '{"branch":"T2","add":1,"reason":"empty"}',
          for (var i = 0; i < 5; i++) '{"branch":"T1","add":3,"reason":"newBranch","title":"New $i"}',
        ].join('\n'),
      ),
    ]);
    final items = await expander(client).plan(ctx, 5, CancellationToken());
    expect(items.length, 21);
    expect(items.fold<int>(0, (n, i) => n + i.add), 99);
    expect(jsonEncode(client.requests.single.map((m) => m.toJson()).toList()), isNot(contains('PRIVATE SOURCE')));
    await expectLater(
      expander(ScriptClient([answer('invalid')])).plan(ctx, 5, CancellationToken()),
      throwsA(isA<ResearchFailure>()),
    );
    await expectLater(expander(ScriptClient([])).plan(ctx, 9, CancellationToken()), throwsA(isA<ResearchFailure>()));
    expect(() => ExpansionContext(targets: {'bad': 'x'}, details: {}, draftPrefix: 'x'), throwsArgumentError);
  });
  test('memory executor mirrors expansion exemption and conversation limit', () async {
    final executor = MemoryMapEditExecutor(studySetId: 'set', mapId: 'main', parents: {'main': null});
    final request = ExpansionRequest(studySetId: 'set', mapId: 'main', targetIds: ['main']);
    final proposal = expansionToProposal(
      request,
      [for (var i = 0; i < 60; i++) ExpansionDraft(id: 'd$i', parentRef: 'main', title: 'Topic $i')],
      proposalId: 'expansion',
      baseRevision: 0,
    );
    final selected = proposal.operations.map((o) => o.id).toSet();
    final chat = MapEditProposal.fromJson(Map<String, dynamic>.from(proposal.toJson()));
    await expectLater(executor.apply(chat, selected), throwsFormatException);
    expect((await executor.apply(proposal, selected)).nodeIds, hasLength(60));
    expect(
      () => validateOperations(
        [const MapEditOperation(id: 'r', kind: MapEditKind.rename, nodeId: 'main', title: 'Rename')],
        {'main': null},
        expansion: true,
      ),
      throwsFormatException,
    );
  });
  test('fake supports UI success, partial failure and cancellation', () async {
    final fake = FakeIdeaExpander(
      drafts: [const ExpansionDraft(id: 'a', parentRef: 'p', title: 'A')],
      items: [const ExpansionPlanItem(targetId: 'p', add: 3, reason: 'empty')],
    );
    expect((await fake.expand(req, context(), CancellationToken()).toList()).length, 1);
    expect((await fake.plan(context(), 5, CancellationToken())).length, 1);
    expect(fake.expansionCalls, 1);
    expect(fake.planCalls, 1);
    fake.close();
    expect(fake.closed, isTrue);
    final bad = FakeIdeaExpander(failure: const ResearchFailure(ResearchFailureKind.network));
    await expectLater(bad.expand(req, context(), CancellationToken()).toList(), throwsA(isA<ResearchFailure>()));
    await expectLater(bad.plan(context(), 5, CancellationToken()), throwsA(isA<ResearchFailure>()));
  });
}

class RecordedChunks extends ScriptClient {
  RecordedChunks(this.inner) : super([]);
  final LLMClient inner;
  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    final reply = await inner.generate(
      messages,
      tools: tools,
      toolChoice: toolChoice,
      modelConfig: modelConfig,
      jsonOutput: jsonOutput,
      cancelToken: cancelToken,
    );
    final text = reply.textOutput!;
    return Stream.fromIterable([
      StreamingMessage(modelMessage: answer(text.substring(0, 20), stop: null)),
      StreamingMessage(modelMessage: answer(text.substring(20, text.length - 8), stop: null)),
      StreamingMessage(modelMessage: answer(text.substring(text.length - 8))),
    ]);
  }
}
