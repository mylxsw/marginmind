import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mm_core/mm_core.dart';

import 'task_runtime/registry.dart';

/// Each bounded domain stage is persisted, including accepted partial output.
typedef MapTaskExecutor = Future<String> Function(
  String instructions,
  Map<String, Object?> payload,
  CancellationToken cancel,
  ValidationReport Function(String) validate,
);

final mapExpandSpec = _spec(TaskType.mapExpand);
final mapGenerateSpec = _spec(TaskType.mapGenerate);
TaskSpec _spec(TaskType type) => TaskSpec(
  type: type,
  inputSchema: 'map-stage-v1',
  resultSchema: 'validated-map-ndjson-v1',
  promptVersion: 'map-heavy-1',
  schemaVersion: '1',
  completionRule: 'Every assigned target or range is covered; all lines pass domain validation',
  requiredCapabilities: {ModelCapability.tools, ModelCapability.historyReplay},
  maxOutputTokens: 8192,
  // Domain repair retains accepted refs and requests only missing descendants.
  maxRepairs: 0,
);

String mapTaskFingerprint(Map<String, dynamic> input) => sha256.convert(utf8.encode(jsonEncode(input))).toString();

void registerMapTaskDefinition(
  TaskRegistry registry, {
  required TaskSpec spec,
  required String instructions,
  required ValidationReport Function(String) validate,
}) {
  registry.register<String>(
    TaskDefinition<String>(
      spec: spec,
      instructions: instructions,
      decode: (text) => text,
      encode: (text) => {'text': text},
      restore: (json) => json['text'] as String,
      validator: _MapValidator(validate),
      validateInput: (input) => jsonEncode(input).length <= mapStageInputCharacters
          ? ValidationReport()
          : ValidationReport(
              issues: [const ValidationIssue(code: 'capacity', path: r'$', reason: 'Split this stage before dispatch')],
            ),
    ),
  );
}

const mapStageInputCharacters = 24000;
const mapResponseCharacters = 256000;

class _MapValidator implements TaskValidator<String> {
  _MapValidator(this.check);
  final ValidationReport Function(String) check;
  @override
  ValidationReport validate(String value, Map<String, dynamic> input) {
    if (value.length > mapResponseCharacters) {
      return ValidationReport(
        issues: [const ValidationIssue(code: 'responseCapacity', path: r'$', reason: 'Response too large')],
      );
    }
    return check(value);
  }
}

/// Domain packs exported for the parent assembly's final registry aggregation.
final mapTaskKnowledgeBundles = <KnowledgeBundle>[
  KnowledgeBundle(
    id: 'mindmap.expand',
    version: '2',
    instructions: 'Expand only assigned targets. Each target needs a result or explicit missing status. Every visible branch must reach requested depth. Edits remain proposals requiring revision checks and user confirmation.',
  ),
  KnowledgeBundle(
    id: 'mindmap.document',
    version: '2',
    instructions: 'Read every assigned range, merge points in bounded levels, and report coverage IDs. Valid NDJSON alone is insufficient. Never edit protected nodes or apply writes. Preserve provenance, dependencies and acyclic structure.',
  ),
];

/// A generator owns cancellation independently of the caller's shared job token.
Future<String> executeMapStage(
  MapTaskExecutor execute,
  String instructions,
  Map<String, Object?> payload,
  CancellationToken cancel,
  ValidationReport Function(String) validate,
  Set<CancellationToken> active,
) async {
  cancel.check();
  final token = CancellationToken();
  CancellationToken? linked = token;
  active.add(token);
  unawaited(cancel.whenCancelled.then((_) => linked?.cancel()));
  try {
    return await token.bind(execute(instructions, payload, token, validate));
  } finally {
    linked = null;
    active.remove(token);
    token.cancel();
  }
}
