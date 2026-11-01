import 'dart:async';

import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import 'task_run_store.dart';

/// One owner and one active Runtime handle, including workflow pauses and save
/// retries. Conversation persistence is delegated back to AssistantController.
class AssistantTaskSession implements AssistantTaskControls {
  AssistantTaskSession({
    required this.assembly,
    required this.owner,
    required this.request,
    required this.initialContext,
    required this.changed,
    this.prepareNetwork,
    RunContext? queuedPhase,
  }) : _context = initialContext,
       _configurationIntent = queuedPhase;
  final PersistentTaskAssembly assembly;
  final AssistantTaskOwner owner;
  final TaskRequest<String> request;
  final void Function(AssistantTaskSession) changed;
  final Future<void> Function(RunContext)? prepareNetwork;
  final RunContext initialContext;
  RunContext _context;
  RunContext? _configurationIntent;
  RuntimeRunHandle<String>? _live;
  PersistentAssistantSummary? summary;
  bool _paused = false, _waiting = false, _persistenceFailure = false;
  bool _permissionWaiting = false, _networkNeedsRefresh = false, _providerWaiting = false;
  RunStatus _status = RunStatus.created;
  Completer<void>? _gate;
  @override
  RunContext get context => summary?.context ?? _live?.context ?? _context;
  @override
  RunStatus get status => _permissionWaiting
      ? RunStatus.awaitingUser
      : saveFailed || _paused
      ? RunStatus.paused
      : summary?.status ?? _live?.status ?? _status;
  @override
  bool get saveFailed => _persistenceFailure || _live?.persistenceError != null || summary?.saveFailed == true;
  @override
  int? get completed => summary?.coveredLeaves.length;
  @override
  int? get total => summary?.leafIds.length;
  void _changed() => changed(this);

  Future<void> remember({RunStatus? persistedStatus}) async {
    final records =
        owner.conversationState.metadata.putIfAbsent('assistant.taskRecords.v1', () => <String, dynamic>{}) as Map;
    records[owner.requestId] = {
      'version': 1,
      'type': request.spec.type.key,
      'status': (persistedStatus ?? status).name,
      'input': request.input,
      'fingerprint': request.inputFingerprint,
      'context': encodeRunContext(context),
      'maxOutputTokens': request.maxOutputTokens,
      'images': [for (final image in request.images) image.toJson()],
      if (_configurationIntent != null) 'configurationIntent': encodeRunContext(_configurationIntent!),
    };
    await owner.checkpointConversation();
  }

  Future<void> _ready() async {
    while (_paused || _waiting) {
      _gate ??= Completer<void>();
      await owner.cancel.bind(_gate!.future);
    }
    owner.cancel.check();
  }

  Future<RunResult<String>> runTask() async {
    final saved = await assembly.runs.load(context.runId);
    if (saved != null) _context = saved.context;
    if (saved?.status == RunStatus.completed) _configurationIntent = null;
    await remember();
    try {
      final result = await dispatch(request, context);
      final usage = await _rememberUsage();
      return RunResult<String>(
        runId: result.runId,
        status: result.status,
        value: result.value,
        validation: result.validation,
        failureCode: result.failureCode,
        usage: usage,
      );
    } finally {
      // The persisted manifest decides whether this is a resumable checkpoint
      // or an immutable terminal attempt requiring an explicit branch retry.
      final stored = await assembly.runs.load(context.runId);
      if (stored != null) _status = stored.status;
      await remember(persistedStatus: stored?.status);
    }
  }

  Future<RunResult<String>> runSummary({List<SummaryUnit>? units, int? capacity}) async {
    summary = await PersistentAssistantSummary.open(
      store: assembly.runs,
      reader: assembly.runs,
      spec: request.spec,
      context: _context,
      units: units,
      question: request.input['question'],
      requestCharacters: capacity,
      evidence: owner.conversationState.metadata['assistant.evidence.v1'] as Map<String, dynamic>?,
    );
    owner.restoreEvidence(summary!.evidence);
    // Entering runSummary is an explicit start/resume from the UI, never an
    // automatic replay merely because an archive was opened.
    while (true) {
      owner.cancel.check();
      if ({RunStatus.partial, RunStatus.failed, RunStatus.cancelled}.contains(summary!.status)) {
        summary = await summary!.continuation();
      }
      _context = summary!.context;
      await remember();
      try {
        if (_configurationIntent != null) {
          await summary!.pause();
          await _applyConfiguration();
        }
        final value = await summary!.run(
          dispatch: dispatch,
          cancel: owner.cancel,
          beforeStage: _ready,
          changed: () {
            _status = summary!.status;
            _changed();
          },
        );
        owner.conversationState.metadata['assistant.summaryCoverage.v1'] = value.coveredIds;
        final usage = await _rememberUsage();
        _status = RunStatus.completed;
        _changed();
        return RunResult<String>(
          runId: context.runId,
          status: RunStatus.completed,
          validation: ValidationReport(),
          value: value.text,
          usage: usage,
        );
      } on RunStoreConflict {
        rethrow;
      } catch (_) {
        if (owner.cancel.isCancelled) rethrow;
        _persistenceFailure = summary!.saveFailed || summary!.status == RunStatus.completed;
        _status = summary!.status;
        _waiting = true;
        _changed();
        await _ready(); // explicit resume/save retry; successful children stay cached
      }
    }
  }

  Future<RunResult<String>> dispatch(TaskRequest<String> task, RunContext stageContext) async {
    await _ready();
    if (summary != null && request.images.isNotEmpty) {
      task = TaskRequest<String>(
        spec: task.spec,
        input: task.input,
        inputFingerprint: task.inputFingerprint,
        images: request.images,
      );
    }
    final saved = await assembly.runs.load(stageContext.runId);
    if (saved != null && (saved.taskType != task.spec.type || saved.inputFingerprint != task.inputFingerprint)) {
      throw const ConfigurationFailure('assistantTaskCheckpointMismatch');
    }
    if (saved?.status == RunStatus.completed) {
      final result = await assembly.runs.loadResult(stageContext.runId);
      final value = result?['value']?['text'];
      if (value is! String) throw const ConfigurationFailure('assistantTaskResultMissing');
      owner.restoreCheckpoint(saved!);
      _status = RunStatus.completed;
      _changed();
      return RunResult<String>(
        runId: stageContext.runId,
        status: RunStatus.completed,
        validation: ValidationReport(),
        value: value,
        usage: saved.usage,
      );
    }
    if (saved != null && {RunStatus.failed, RunStatus.partial, RunStatus.cancelled}.contains(saved.status)) {
      throw const ConfigurationFailure('assistantTerminalTaskRequiresRetry');
    }
    final desired =
        _configurationIntent ??
        (summary != null && summary!.context.phase > (saved?.context.phase ?? stageContext.phase)
            ? summary!.context
            : null);
    final planned = desired != null && saved?.checkpoint['pending'] == null
        ? decodeRunContext({
            ...encodeRunContext(desired),
            'runId': stageContext.runId,
            'parentRunId': saved?.context.parentRunId ?? stageContext.parentRunId,
          })
        : saved?.context ?? stageContext;
    owner.streamDrafts = task.streamDrafts;
    owner.recoverProviderChild = _recoverProviderChild;
    await prepareNetwork?.call(planned); // bind tools before the SDK agent is constructed
    final handle = saved == null
        ? assembly.runtime.start(task, planned)
        : await assembly.runtime.recover(task, saved.context);
    _live = handle;
    if (summary == null) _context = handle.context;
    final subscription = handle.events.listen((event) {
      if (task.streamDrafts) owner.acceptRuntimeEvent(event);
      _status = event.status;
      _changed();
    });
    owner.permissions.onWaitingChanged = (waiting) {
      _permissionWaiting = waiting;
      _status = waiting ? RunStatus.awaitingUser : handle.status;
      changed(this);
    };
    var finished = false;
    var received = false;
    Future<void>? cancellation;
    unawaited(
      owner.cancel.whenCancelled.then((_) {
        if (!finished) {
          cancellation ??= handle.cancel();
          cancellation!.ignore();
        }
      }),
    );
    try {
      if (desired != null && saved?.checkpoint['pending'] == null && handle.context.phase < desired.phase) {
        await handle.useConfiguration(planned);
      }
      if (saved != null) {
        final metadata = (saved.checkpoint['state'] as Map?)?['metadata'] as Map?;
        for (final id in metadata?['runtime.providerChildren.v1'] as List? ?? []) {
          final child = await assembly.runs.load(id as String);
          if (child?.status == RunStatus.validating) await _recoverProviderChild(id);
          if (child == null || {RunStatus.created, RunStatus.running, RunStatus.interrupted}.contains(child.status)) {
            throw const ConfigurationFailure('providerChildInterrupted');
          }
        }
        await handle.resume();
      }
      _changed();
      final result = await owner.cancel.bind(handle.result);
      received = true;
      final committed = await assembly.runs.load(handle.context.runId);
      if (committed != null) owner.restoreCheckpoint(committed);
      _status = result.status;
      return result;
    } finally {
      try {
        if (!received &&
            !{RunStatus.completed, RunStatus.partial, RunStatus.failed, RunStatus.cancelled}.contains(handle.status)) {
          await (cancellation ??= handle.cancel());
          // Cancellation signals the SDK first. Keep this owner alive until the
          // Runtime persists its terminal result and releases its resources.
          if (handle.persistenceError == null) await handle.result;
        } else if (cancellation != null) {
          await cancellation;
        }
      } finally {
        finished = true;
        _permissionWaiting = false;
        owner.permissions.onWaitingChanged = null;
        await subscription.cancel();
        if (summary == null) _context = handle.context;
        _live = null;
        owner.synchronize();
        _changed();
      }
    }
  }

  Future<RunUsage> _rememberUsage() async {
    final usage = await loadAssistantTaskUsage(assembly.runs, context.runId);
    final records =
        owner.conversationState.metadata.putIfAbsent('assistant.taskUsage.v1', () => <String, dynamic>{}) as Map;
    records[owner.requestId] = {
      'runId': context.runId,
      'quality': usage.quality.name,
      'modelCalls': usage.modelCalls,
      'repairs': usage.repairs,
      'inputTokens': usage.inputTokens,
      'outputTokens': usage.outputTokens,
      'reasoningTokens': usage.reasoningTokens,
    };
    await remember();
    return usage;
  }

  Future<Map<String, dynamic>> _recoverProviderChild(String id) async {
    final steps = assembly.runtime.providerSteps;
    var saved = await assembly.runs.load(id);
    final memory = steps.records[id];
    if (saved?.status == RunStatus.completed) {
      final value = await assembly.runs.loadResult(id);
      if (value == null) throw const ConfigurationFailure('providerResultMissing');
      return value;
    }
    if (saved?.status == RunStatus.failed || saved?.status == RunStatus.cancelled) {
      throw const ConfigurationFailure('providerChildFailed');
    }
    // In-process pending results can exist before their first durable write.
    // Restart can reconcile only the explicit durable pending checkpoint.
    if (memory == null && saved?.status != RunStatus.validating) {
      throw const ConfigurationFailure('providerChildInterrupted');
    }
    _providerWaiting = true;
    try {
      while (true) {
        _persistenceFailure = true;
        _waiting = true;
        _changed();
        await _ready();
        try {
          final result = memory != null ? await steps.retrySave(id) : await steps.recoverSave(id);
          _persistenceFailure = false;
          _changed();
          return result;
        } catch (_) {
          owner.cancel.check();
          saved = await assembly.runs.load(id);
          if (saved?.status == RunStatus.failed || saved?.status == RunStatus.cancelled) rethrow;
        }
      }
    } finally {
      _providerWaiting = false;
    }
  }

  @override
  Future<void> pause() async {
    _paused = true;
    _changed();
    try {
      await _live?.pause();
      if (summary != null && !{RunStatus.completed, RunStatus.partial, RunStatus.cancelled}.contains(summary!.status)) {
        summary!.data['paused'] = true;
        await summary!.pause();
      }
      await remember();
    } catch (_) {
      _persistenceFailure = true;
      _changed();
      rethrow;
    }
  }

  @override
  Future<void> resume() async {
    try {
      if (_configurationIntent != null) await _applyConfiguration();
      if (_networkNeedsRefresh) {
        await prepareNetwork?.call(context);
        _networkNeedsRefresh = false;
      }
      if (!_providerWaiting) await _live?.resume();
      _persistenceFailure = false;
      _paused = false;
      _waiting = false;
      summary?.data['paused'] = false;
      final gate = _gate;
      _gate = null;
      gate?.complete();
      _changed();
    } catch (_) {
      _persistenceFailure = true;
      _changed();
      rethrow;
    }
  }

  @override
  Future<void> useModel(ModelReference model) async {
    if (summary != null && _live == null && {RunStatus.partial, RunStatus.failed}.contains(summary!.status)) {
      summary = await summary!.continuation();
      await summary!.pause();
      _paused = true;
      _waiting = true;
    }
    if (status != RunStatus.paused || saveFailed) throw StateError('Pause before changing configuration');
    final current = context;
    final limit = current.config.policy.maxOutputTokens;
    final selected = TaskRequest<String>(
      spec: request.spec,
      input: request.input,
      inputFingerprint: request.inputFingerprint,
      modelOverride: model,
      maxOutputTokens: limit,
    );
    final frozen = await assembly.freeze(
      selected,
      runId: current.runId,
      knowledgeVersions: current.knowledgeVersions,
      inputRange: current.inputRange,
    );
    final next = decodeRunContext({...encodeRunContext(frozen), 'phase': current.phase + 1});
    _configurationIntent = next;
    await remember(); // Persist the explicit user action before changing an SDK phase.
    try {
      await _applyConfiguration();
    } on StateError {
      // Runtime refuses an in-flight or already validated phase. Do not leave a
      // rejected configuration intent blocking the existing result's save.
      if ((_live?.context.phase ?? current.phase) < next.phase &&
          (summary?.context.phase ?? current.phase) < next.phase) {
        _configurationIntent = null;
        await remember();
      }
      rethrow;
    }
    _changed();
  }

  Future<void> _applyConfiguration() async {
    final next = _configurationIntent!;
    if (_live != null && _live!.context.phase < next.phase) {
      final childNext = decodeRunContext({
        ...encodeRunContext(next),
        'runId': _live!.context.runId,
        'parentRunId': _live!.context.parentRunId,
      });
      await _live!.useConfiguration(childNext);
    }
    if (summary != null && summary!.context.phase < next.phase) {
      if (summary!.status != RunStatus.paused) await summary!.pause();
      await summary!.useConfiguration(next);
    }
    _context = next;
    _configurationIntent = null;
    _networkNeedsRefresh = true;
    await prepareNetwork?.call(next);
    _networkNeedsRefresh = false;
    await remember();
    _changed();
  }
}
