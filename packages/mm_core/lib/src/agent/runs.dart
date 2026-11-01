import 'models.dart';
import 'tasks.dart';

enum RunStatus {
  created,
  validating,
  running,
  awaitingUser,
  paused,
  interrupted,
  completed,
  partial,
  failed,
  cancelled,
}

class RunContext {
  RunContext({
    required this.runId,
    required this.config,
    required Map<String, String> knowledgeVersions,
    this.parentRunId,
    this.branchId,
  }) : knowledgeVersions = Map.unmodifiable(knowledgeVersions);
  final String runId;
  final String? parentRunId, branchId;
  final ResolvedTaskConfig config;
  final Map<String, String> knowledgeVersions;
}

class ValidationIssue {
  const ValidationIssue({required this.code, required this.path, required this.reason, this.retryable = false});
  final String code, path, reason;
  final bool retryable;
}

class ValidationReport {
  ValidationReport({List<ValidationIssue> issues = const [], Set<String> missingInputIds = const {}})
    : issues = List.unmodifiable(issues),
      missingInputIds = Set.unmodifiable(missingInputIds);
  final List<ValidationIssue> issues;
  final Set<String> missingInputIds;
  bool get complete => issues.isEmpty && missingInputIds.isEmpty;
}

abstract interface class TaskValidator<T> {
  ValidationReport validate(T result, Map<String, dynamic> expectedInputManifest);
}

class RunUsage {
  const RunUsage({
    this.modelCalls = 0,
    this.repairs = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.reasoningTokens,
    this.elapsed = Duration.zero,
  });
  final int modelCalls, repairs, inputTokens, outputTokens;
  final int? reasoningTokens;
  final Duration elapsed;
}

class RunResult<T> {
  RunResult({
    required this.runId,
    required this.status,
    required this.validation,
    this.value,
    this.failureCode,
    this.usage = const RunUsage(),
    List<String> evidenceIds = const [],
  }) : evidenceIds = List.unmodifiable(evidenceIds) {
    if (!{RunStatus.completed, RunStatus.partial, RunStatus.failed, RunStatus.cancelled}.contains(status) ||
        (status == RunStatus.completed && (!validation.complete || value == null))) {
      throw ArgumentError('Completed results require a value and complete validation');
    }
  }
  final String runId;
  final RunStatus status;
  final T? value;
  final String? failureCode;
  final ValidationReport validation;
  final RunUsage usage;
  final List<String> evidenceIds;
}

class RunEvent {
  const RunEvent({required this.runId, required this.sequence, required this.status, this.stage, this.draft});
  final String runId;
  final int sequence;
  final RunStatus status;
  final String? stage, draft;
}

class RunManifest {
  RunManifest({
    required this.context,
    required this.taskType,
    required this.inputFingerprint,
    required this.promptVersion,
    required this.schemaVersion,
    required this.status,
    required this.revision,
    this.stage,
    this.failureCode,
    this.resultReference,
    this.usage = const RunUsage(),
    List<String> evidenceIds = const [],
    Map<String, dynamic> checkpoint = const {},
  }) : evidenceIds = List.unmodifiable(evidenceIds),
       checkpoint = freezeAgentJson(checkpoint);
  final RunContext context;
  final TaskType taskType;
  final String inputFingerprint, promptVersion, schemaVersion;
  final RunStatus status;
  final int revision;
  final String? stage, failureCode, resultReference;
  final RunUsage usage;
  final List<String> evidenceIds;

  /// Versioned adapter-owned envelope. Never put protocol blocks in diagnostics.
  final Map<String, dynamic> checkpoint;
}

abstract interface class AgentRuntime {
  RunHandle<T> start<T>(TaskRequest<T> request, RunContext context);
}

abstract interface class RunHandle<T> {
  Stream<RunEvent> get events;
  Future<RunResult<T>> get result;
  Future<void> pause();
  Future<void> resume();
  Future<void> cancel();
}

abstract interface class RunStore {
  Future<RunManifest?> load(String runId);

  /// Atomic compare-and-swap; null expectedRevision creates a new record.
  Future<void> checkpoint(RunManifest snapshot, {required int? expectedRevision});

  /// Atomically persists terminal manifest and encoded domain result, without regenerating on I/O failure.
  Future<void> complete(RunManifest snapshot, Map<String, dynamic> result, {required int expectedRevision});
}

abstract interface class ProviderPolicyCompiler {
  ProviderCallPolicy compile({
    required TaskCategory category,
    required ReasoningPolicy requested,
    required CapabilityIdentity identity,
    required ModelCapabilityProfile capabilities,
  });
}
