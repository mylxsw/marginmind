import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  test('all twelve stable task identities and quick/heavy knowledge boundaries', () {
    expect(TaskType.values.map((v) => v.key).toSet().length, 13);
    expect(TaskType.values.where((v) => v.category == TaskCategory.quick).map((v) => v.key), [
      'selection_translate',
      'word_lookup',
      'title_generate',
    ]);
    expect(TaskType.documentTranslate.knowledgePacks, ['translation.document']);
    expect(TaskType.fromKey('future_task'), isNull);
    expect(TaskType.fromKey('map_generate'), TaskType.mapGenerate);
  });
  test('routing freezes nested data and preserves unknown bindings without interpreting them', () {
    final future = {
      'mode': 'future',
      'value': <dynamic>[1],
    };
    final json = <String, dynamic>{
      'version': 1,
      'revision': 3,
      'bindings': {
        'new_task': future,
        'word_lookup': {
          'mode': 'explicit',
          'model': {'serviceId': 'a', 'modelId': 'm'},
        },
      },
    };
    final config = RoutingConfig(document: json);
    (future['value'] as List).add(2);
    expect((config.toJson()['bindings']['new_task']['value'] as List), [1]);
    expect(() => config.toJson()['bindings']['new_task']['value'].add(3), throwsUnsupportedError);
    expect(config.binding(TaskType.wordLookup).model, const ModelReference('a', 'm'));
    expect(config.binding(TaskType.titleGenerate).mode, TaskBindingMode.inherit);
    expect(config.defaultModel(TaskCategory.quick), isNull);
    expect(() => RoutingConfig(document: {'version': 2, 'revision': 1}), throwsA(isA<ConfigurationFailure>()));
  });
  test('quick cannot authorize tools or unlimited repair; false completion is rejected', () {
    expect(
      () => TaskSpec(
        type: TaskType.wordLookup,
        inputSchema: 'i',
        resultSchema: 'o',
        promptVersion: '1',
        schemaVersion: '1',
        completionRule: 'valid',
        allowedTools: {'network'},
      ),
      throwsArgumentError,
    );
    expect(
      () => RunResult<String>(
        runId: 'r',
        status: RunStatus.completed,
        value: 'partial',
        validation: ValidationReport(missingInputIds: {'paragraph-2'}),
      ),
      throwsArgumentError,
    );
    expect(
      RunResult<String>(
        runId: 'r',
        status: RunStatus.partial,
        value: 'partial',
        validation: ValidationReport(missingInputIds: {'paragraph-2'}),
      ).validation.complete,
      isFalse,
    );
  });
  test('capability identity is service, endpoint, protocol, revision and adapter specific', () {
    CapabilityIdentity key({String service = 'a', String fingerprint = 'f', String adapter = '1', int revision = 1}) =>
        CapabilityIdentity(
          model: ModelReference(service, 'same-name'),
          protocol: ModelProtocol.responses,
          endpointFingerprint: fingerprint,
          adapterVersion: adapter,
          serviceRevision: revision,
        );
    expect(key(), key());
    expect({key(), key(service: 'b'), key(fingerprint: 'g'), key(adapter: '2'), key(revision: 2)}.length, 5);
  });

  test('document origin round-trips how it was formatted, and old documents have none', () {
    final origin = DocumentOrigin(
      url: 'https://example.com',
      capturedAt: DateTime.utc(2026, 11, 3),
      formatting: const DocumentOriginFormatting(
        model: 'Claude',
        promptVersion: 'web-format-1',
        edited: true,
        unformattedSections: 2,
      ),
    );
    final restored = DocumentOrigin.fromJson(origin.toJson()).formatting!;
    expect(
      (restored.model, restored.promptVersion, restored.edited, restored.unformattedSections),
      ('Claude', 'web-format-1', true, 2),
    );
    final plain = DocumentOrigin(url: 'https://example.com', capturedAt: DateTime.utc(2026)).toJson();
    expect(plain.containsKey('formatting'), isFalse);
    expect(DocumentOrigin.fromJson(plain).formatting, isNull);
    expect(const DocumentOriginFormatting(model: 'm', promptVersion: 'p').toJson().keys, ['model', 'promptVersion']);
  });
}
