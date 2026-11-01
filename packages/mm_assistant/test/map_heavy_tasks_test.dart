import 'dart:async';
import 'dart:convert';

import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'map_generation_test.dart' as fixtures;

String covered(String text, Map<String, Object?> payload) =>
    '$text\n${jsonEncode({'coverage': payload['requiredCoverage'] ?? []})}';

void main() {
  test('runtime stages split a 65000-character page without losing text or source slices', () async {
    final sent = <String>[];
    var call = 0;
    final model = ModelMapGenerator.runtime((system, payload, cancel, validate) async {
      expect(jsonEncode(payload).length, lessThanOrEqualTo(mapStageInputCharacters));
      sent.addAll((payload['pages'] as Map).values.cast<String>());
      final result = jsonEncode({
        'k': 'point',
        'id': 'p',
        'parent': 'ROOT',
        'title': 'Part ${call++}',
        'doc': 'D1',
        'page': 1,
      });
      expect(validate(covered(result, payload)).complete, isTrue);
      return covered(result, payload);
    });
    final text = List.generate(65000, (i) => String.fromCharCode(65 + i % 26)).join();
    final lines = await model
        .readChapter(
          MapChapterInput(
            chapterId: 'huge',
            documentAlias: 'D1',
            context: fixtures.context(MapLinePhase.chapter),
            textByPage: {1: text},
          ),
          CancellationToken(),
        )
        .toList();
    expect(sent.join(), text);
    expect(lines, hasLength(7));
    expect(lines.map((l) => l.id).toSet(), hasLength(7));
    expect(lines.every((l) => l.source?.page == 1), isTrue);
    await model.close();
  });

  test('partial NDJSON repair retains refs and only adds corrected missing content', () async {
    var calls = 0;
    final reports = <ValidationReport>[];
    final model = ModelMapGenerator.runtime((system, payload, cancel, validate) async {
      final text = calls++ == 0
          ? '${fixtures.topic}\n{"ref":"b","parent":"a","title":"Child","extra":true}'
          : '{"ref":"b","parent":"a","title":"Child"}';
      if (calls == 2) {
        expect((payload['accepted'] as List).first, fixtures.topic);
        expect(payload['rejected'], hasLength(1));
      }
      reports.add(validate(covered(text, payload)));
      return covered(text, payload);
    });
    final lines = await model.generate(fixtures.build(MapLinePhase.generation, []), CancellationToken()).toList();
    expect(lines.map((l) => l.title), ['Topic', 'Child']);
    expect(lines.last.parentId, 'new:${lines.first.id}');
    expect(reports.first.complete, isFalse);
    expect(reports.last.complete, isTrue);
    expect(calls, 2);
  });

  test('persistent invalid content stays partial after two local repairs, with accepted work preserved', () async {
    var calls = 0;
    final model = ModelMapGenerator.runtime((system, payload, cancel, validate) async {
      return covered(calls++ == 0 ? '${fixtures.topic}\nbad' : 'bad', payload);
    });
    final lines = <MapLine>[];
    await expectLater(() async {
      await for (final line in model.generate(fixtures.build(MapLinePhase.generation, []), CancellationToken())) {
        lines.add(line);
      }
    }, throwsA(isA<MapGenerationFailure>().having((e) => e.code, 'code', 'partialMapContent')));
    expect(lines.single.title, 'Topic');
    expect(calls, 3);
  });

  test('final points are reduced in bounded levels before map synthesis', () async {
    final lengths = <int>[];
    var reductions = 0;
    final model = ModelMapGenerator.runtime((system, payload, cancel, validate) async {
      lengths.add(jsonEncode(payload).length);
      final reduce = system.contains('Merge this batch');
      final text = reduce
          ? jsonEncode({
              'k': 'point',
              'id': 'p',
              'parent': 'ROOT',
              'title': 'Summary ${reductions++}',
              'doc': 'D1',
              'page': 1,
            })
          : fixtures.topic;
      expect(validate(covered(text, payload)).complete, isTrue);
      return covered(text, payload);
    });
    final points = List.generate(
      500,
      (i) => MapLine(
        id: 'p$i',
        kind: MapLineKind.point,
        parentId: 'private-map',
        title: 'Point $i ${'x' * 100}',
        source: CardSource(documentId: 'private-document', page: 1),
      ),
    );
    final lines = await model.generate(fixtures.build(MapLinePhase.generation, points), CancellationToken()).toList();
    expect(lines.single.title, 'Topic');
    expect(reductions, greaterThan(1));
    expect(lengths.every((n) => n <= mapStageInputCharacters), isTrue);
  });

  test('expansion runtime validation records missing depth and repaired descendants', () async {
    var calls = 0;
    final reports = <ValidationReport>[];
    final model = ModelIdeaExpander.runtime((system, payload, cancel, validate) async {
      final text = calls++ == 0
          ? '{"ref":"a","parent":"T1","title":"Child"}'
          : '{"ref":"b","parent":"a","title":"Grandchild"}';
      reports.add(validate(text));
      return text;
    });
    final context = ExpansionContext(
      targets: {'T1': 'target'},
      details: {'T1': ExpansionTargetContext(title: 'Root')},
      draftPrefix: 'draft-',
    );
    final request = ExpansionRequest(studySetId: 'study', mapId: 'map', targetIds: ['target'], depth: 2);
    final lines = await model.expand(request, context, CancellationToken()).toList();
    expect(lines.map((l) => l.title), ['Child', 'Grandchild']);
    expect(reports.first.issues.single.code, 'missingDepth');
    expect(reports.last.complete, isTrue);
  });

  test('missing target is reported and never silently completes', () async {
    ValidationReport? report;
    final model = ModelIdeaExpander.runtime((system, payload, cancel, validate) async {
      const text = '{"ref":"a","parent":"T1","title":"Child"}';
      report = validate(text);
      return text;
    });
    final context = ExpansionContext(
      targets: {'T1': 'one', 'T2': 'two'},
      details: {
        'T1': ExpansionTargetContext(title: 'One'),
        'T2': ExpansionTargetContext(title: 'Two'),
      },
      draftPrefix: 'draft-',
    );
    final request = ExpansionRequest(studySetId: 'study', mapId: 'map', targetIds: ['one', 'two']);
    await expectLater(
      model.expand(request, context, CancellationToken()).toList(),
      throwsA(isA<ResearchFailure>().having((e) => e.code, 'code', 'incompleteDepth')),
    );
    expect(report!.missingInputIds, {'T2'});
  });
  test('valid NDJSON without coverage stays partial and repairs only the missing receipt', () async {
    var calls = 0;
    ValidationReport? first;
    final model = ModelMapGenerator.runtime((system, payload, cancel, validate) async {
      final text = calls++ == 0 ? fixtures.point : jsonEncode({'coverage': payload['requiredCoverage']});
      first ??= validate(text);
      return text;
    });
    final lines = await model.readChapter(fixtures.chapter(), CancellationToken()).toList();
    expect(lines.single.title, 'First');
    expect(first!.missingInputIds, {'page:1', 'annotation:A1'});
    expect(calls, 2);
  });

  test('update rejects a move cycle and repairs without replaying accepted changes', () async {
    var calls = 0;
    final model = ModelMapGenerator.runtime((system, payload, cancel, validate) async {
      final text = calls++ == 0
          ? '{"op":"move","node":"N1","parent":"N3"}'
          : '{"op":"rename","node":"N1","title":"Safe"}';
      final response = covered(text, payload);
      if (calls == 1) expect(validate(response).issues.any((i) => i.code == 'cycle'), isTrue);
      return response;
    });
    final input = fixtures.build(MapLinePhase.diff, []);
    final context = MapLineContext(
      phase: MapLinePhase.diff,
      mapId: 'map',
      draftPrefix: 'd-',
      documents: const {},
      pages: const {},
      nodes: {'N1': 'one', 'N3': 'three'},
    );
    final lines = await model
        .update(
          MapBuildInput(
            title: input.title,
            generation: input.generation,
            context: context,
            points: [],
            existingParents: {'N1': 'ROOT', 'N3': 'N1'},
          ),
          CancellationToken(),
        )
        .toList();
    expect(lines.single.kind, MapLineKind.rename);
    expect(calls, 2);
  });

  test('retrying a long chapter reuses completed slices and only purchases the failed slice', () async {
    var calls = 0;
    var fail = true;
    final model = ModelMapGenerator.runtime((system, payload, cancel, validate) async {
      calls++;
      final page = (payload['pages'] as Map).values.single as String;
      if (page.startsWith('B') && fail) {
        fail = false;
        throw const ResearchFailure(ResearchFailureKind.network);
      }
      return covered(
        jsonEncode({'k': 'point', 'id': 'p', 'parent': 'ROOT', 'title': page.substring(0, 1), 'doc': 'D1', 'page': 1}),
        payload,
      );
    });
    final input = MapChapterInput(
      chapterId: 'long',
      documentAlias: 'D1',
      context: fixtures.context(MapLinePhase.chapter),
      textByPage: {1: '${'A' * 10000}${'B' * 10000}${'C' * 10000}'},
    );
    await expectLater(model.readChapter(input, CancellationToken()).toList(), throwsA(isA<MapGenerationFailure>()));
    final lines = await model.readChapter(input, CancellationToken()).toList();
    expect(lines.map((l) => l.title), ['A', 'B', 'C']);
    expect(calls, 4);
  });
  test('closing runtime generators cancels their owned request without cancelling the shared job', () async {
    for (final expand in [false, true]) {
      final started = Completer<void>();
      final job = CancellationToken();
      Future<String> execute(
        String system,
        Map<String, Object?> payload,
        CancellationToken cancel,
        ValidationReport Function(String) validate,
      ) async {
        started.complete();
        await cancel.whenCancelled;
        throw const ResearchFailure(ResearchFailureKind.cancelled);
      }

      final map = ModelMapGenerator.runtime(execute);
      final ideas = ModelIdeaExpander.runtime(execute);
      final result = expand
          ? ideas
                .expand(
                  ExpansionRequest(studySetId: 's', mapId: 'm', targetIds: ['target']),
                  ExpansionContext(
                    targets: {'T1': 'target'},
                    details: {'T1': ExpansionTargetContext(title: 'Root')},
                    draftPrefix: 'd-',
                  ),
                  job,
                )
                .toList()
          : map.readChapter(fixtures.chapter(), job).toList();
      final check = expectLater(
        result,
        throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.cancelled)),
      );
      await started.future;
      if (expand) {
        ideas.close();
      } else {
        await map.close();
      }
      await check;
      expect(job.isCancelled, isFalse);
    }
  });
}
