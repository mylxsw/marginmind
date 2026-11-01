import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/providers.dart';
import '../workspace/workspace_controller.dart';
import 'assistant_controller.dart';
import 'assistant_reader.dart';
import 'assistant_scope.dart';
import 'assistant_writes.dart';
import 'expansion_context.dart';
import 'map_task_factory.dart';

/// Shares the assistant's exclusive model slot, including across preview requests.
final expansionBusyProvider = NotifierProvider<ExpansionBusy, bool>(ExpansionBusy.new);

class ExpansionBusy extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

// Optional injection for deterministic UI tests; production uses the scoped factory.
final ideaExpanderFactoryProvider = Provider<Future<IdeaExpander> Function()?>((ref) => null);

final expansionControllerProvider = NotifierProvider.autoDispose.family<ExpansionController, ExpansionPreview?, String>(
  ExpansionController.new,
  dependencies: [assistantMapEditExecutorProvider, workspaceProvider],
);

enum ExpansionPhase { planning, plan, generating, review, stopped, error }

class ExpansionPreview {
  ExpansionPreview({
    required this.request,
    required this.baseRevision,
    this.drafts = const [],
    this.phase = ExpansionPhase.generating,
    this.failure,
    this.isApplying = false,
    required this.proposalId,
    this.activeTargetId,
    this.planItems = const [],
    this.disabledPlan = const {},
    this.targetFailures = const {},
  });
  final ExpansionRequest request;
  final int baseRevision;
  final List<ExpansionDraft> drafts;
  final ExpansionPhase phase;
  final ResearchFailure? failure;
  final bool isApplying;
  final String proposalId;
  final String? activeTargetId;
  final List<ExpansionPlanItem> planItems;
  final Set<int> disabledPlan;
  final Map<String, ResearchFailure> targetFailures;
  Map<String, String> get moves {
    if (request.scope != ExpansionScope.group) return const {};
    final parent = drafts.where((d) => d.kept && d.parentRef == request.commonParentId).firstOrNull;
    return parent == null ? const {} : {for (final id in request.targetIds) id: 'new:${parent.id}'};
  }

  bool get isMapPlan => request.scope == ExpansionScope.map && request.plan.isEmpty;

  int get selectedCount => drafts.where((d) => d.kept).length;
  ExpansionPreview copyWith({
    List<ExpansionDraft>? drafts,
    ExpansionPhase? phase,
    ResearchFailure? failure,
    bool? isApplying,
    String? activeTargetId,
    List<ExpansionPlanItem>? planItems,
    Set<int>? disabledPlan,
    Map<String, ResearchFailure>? targetFailures,
  }) => ExpansionPreview(
    request: request,
    targetFailures: targetFailures ?? this.targetFailures,
    planItems: planItems ?? this.planItems,
    disabledPlan: disabledPlan ?? this.disabledPlan,
    baseRevision: baseRevision,
    drafts: drafts ?? this.drafts,
    phase: phase ?? this.phase,
    failure: failure,
    isApplying: isApplying ?? this.isApplying,
    proposalId: proposalId,
    activeTargetId: activeTargetId ?? this.activeTargetId,
  );
}

class ExpansionController extends Notifier<ExpansionPreview?> {
  ExpansionController(this.arg);
  final String arg;
  CancellationToken? _cancel;
  final _expanders = <IdeaExpander>{};
  MapTaskExecutor? _executor;
  MapTaskSession? _taskSession;
  Future<IdeaExpander> _newExpander() async {
    final injected = ref.read(ideaExpanderFactoryProvider);
    if (injected != null) return injected();
    final session = _taskSession ??= MapTaskSession(ref, arg, mapExpandSpec);
    return ModelIdeaExpander.runtime(_executor ??= session.execute, continuationRepairs: session.continuationRound);
  }

  int _generation = 0, _call = 0;
  bool _disposed = false, _ownsBusy = false;
  final _excluded = <String>[];
  @override
  ExpansionPreview? build() {
    final workspace = ref.read(workspaceProvider(arg).notifier);
    final busy = ref.read(expansionBusyProvider.notifier);
    listenSelf((_, next) => workspace.expansionPreviewActive = next != null);
    ref.onDispose(() {
      _disposed = true;
      workspace.expansionPreviewActive = false;
      if (_ownsBusy) {
        Future.microtask(() {
          if (busy.ref.mounted) busy.set(false);
        });
      }
      _cancel?.cancel();
      for (final expander in _expanders.toList()) {
        expander.close();
      }
    });
    return null;
  }

  ExpansionRequest request(
    String mapId,
    String target, {
    ExpansionDirection? direction,
    int? depth,
    int? breadth,
    bool? grounded,
    String? hint,
    int round = 0,
    List<String>? targets,
    ExpansionScope scope = ExpansionScope.children,
    String? commonParentId,
    Map<String, int> plan = const {},
  }) {
    final prefs = ref.read(sharedPreferencesProvider), key = 'expansion.$arg';
    return ExpansionRequest(
      studySetId: arg,
      mapId: mapId,
      targetIds: targets ?? [target],
      scope: scope,
      commonParentId: commonParentId,
      plan: plan,
      direction:
          direction ??
          ExpansionDirection.values.where((d) => d.name == prefs.getString('$key.direction')).firstOrNull ??
          ExpansionDirection.auto,
      depth: depth ?? (prefs.getInt('$key.depth') ?? 1).clamp(1, 3),
      breadth: breadth ?? ({3, 5, 8}.contains(prefs.getInt('$key.breadth')) ? prefs.getInt('$key.breadth')! : 5),
      grounded: grounded ?? prefs.getBool('$key.grounded') ?? true,
      hint: hint,
      round: round,
    );
  }

  Future<void> continueTask(String id) async {
    if ((state != null && !{ExpansionPhase.error, ExpansionPhase.stopped}.contains(state!.phase)) ||
        ref.read(expansionBusyProvider) ||
        ref.read(assistantControllerProvider.notifier).busy) {
      throw StateError('Assistant is busy');
    }
    final session = await MapTaskSession.restore(ref, arg, mapExpandSpec, id);
    final workflow = session.workflow!;
    if (workflow['sourceRevision'] != mapTaskFingerprint(ref.read(workspaceProvider(arg).notifier).content.toJson())) {
      throw const ConfigurationFailure('mapSourceRevisionChanged');
    }
    final request = _restoreExpansionRequest(Map<String, dynamic>.from(workflow['request']));
    if (request.studySetId != arg) throw const ConfigurationFailure('mapSessionMismatch');
    if (state != null) {
      stop();
      state = null;
    }
    _executor = session.execute;
    _taskSession = session;
    _excluded
      ..clear()
      ..addAll(List<String>.from(workflow['excluded']));
    _call = workflow['callStart'] as int;
    if (workflow['planning'] == true) {
      await planMap(request, continuing: session);
    } else {
      state = ExpansionPreview(
        request: request,
        baseRevision: workflow['baseRevision'],
        proposalId: workflow['proposalId'],
        drafts: [for (final d in workflow['seedDrafts']) _restoreExpansionDraft(d)],
      );
      await _generate(request);
    }
  }

  Future<void> _saveWorkflow(ExpansionRequest request, {bool planning = false}) async {
    if (ref.read(ideaExpanderFactoryProvider) != null) return;
    final session = _taskSession ??= MapTaskSession(ref, arg, mapExpandSpec);
    _executor = session.execute;
    session.explicitContinuation = true;
    await session.saveWorkflow({
      'request': _expansionRequestJson(request),
      'planning': planning,
      'proposalId': state!.proposalId,
      'baseRevision': state!.baseRevision,
      'sourceRevision': mapTaskFingerprint(ref.read(workspaceProvider(arg).notifier).content.toJson()),
      'excluded': _excluded.toList(),
      'callStart': _call,
      'seedDrafts': [for (final d in state!.drafts) _expansionDraftJson(d)],
    });
  }

  Future<void> start(ExpansionRequest request) async {
    if (state != null || ref.read(assistantControllerProvider.notifier).busy || ref.read(expansionBusyProvider)) {
      throw StateError('Assistant is busy');
    }
    _excluded.clear();
    _executor = null;
    _taskSession = null;
    _call = 0;
    final snapshot = ref.read(workspaceProvider(arg).notifier).content;
    state = ExpansionPreview(
      request: request,
      baseRevision: assistantMapRevision(snapshot, request.mapId),
      proposalId: 'expansion-${DateTime.now().microsecondsSinceEpoch}',
    );
    await _generate(request);
  }

  Future<void> planMap(ExpansionRequest request, {MapTaskSession? continuing}) async {
    if (state != null || ref.read(assistantControllerProvider.notifier).busy || ref.read(expansionBusyProvider)) {
      throw StateError('Assistant is busy');
    }
    if (continuing == null) {
      _excluded.clear();
      _executor = null;
      _taskSession = null;
      _call = 0;
    }
    final workspace = ref.read(workspaceProvider(arg).notifier);
    state = ExpansionPreview(
      request: request,
      baseRevision: assistantMapRevision(workspace.content, request.mapId),
      proposalId:
          continuing?.workflow?['proposalId'] as String? ?? 'expansion-${DateTime.now().microsecondsSinceEpoch}',
      phase: ExpansionPhase.planning,
    );
    final epoch = ++_generation, cancel = _cancel = CancellationToken();
    _ownsBusy = true;
    ref.read(expansionBusyProvider.notifier).set(true);
    IdeaExpander? expander;
    try {
      await _saveWorkflow(request, planning: true);
      final snapshot = workspace.content;
      final reader = WorkspaceReader(
        content: () => snapshot,
        contexts: const [],
        filePath: workspace.filePath,
        pageText: ref.read(assistantPageTextProvider),
      );
      final context = await ExpansionContextBuilder(reader)
          .build(snapshot, request, cancellation: cancel, rootTitle: ref.read(studySetProvider(arg))?.title);
      cancel.check();
      expander = await _newExpander();
      _expanders.add(expander);
      cancel.check();
      final items = (await expander.plan(context, 8, cancel)).toList();
      items.sort((a, b) {
        int rank(ExpansionPlanItem item) => item.reason == 'empty'
            ? 0
            : item.reason == 'thin'
            ? 1
            : 2;
        return rank(a).compareTo(rank(b));
      });
      if (!_disposed && epoch == _generation) {
        state = state!.copyWith(phase: ExpansionPhase.plan, planItems: List.unmodifiable(items));
      }
    } catch (error) {
      if (!_disposed && epoch == _generation) {
        state = state!.copyWith(
          phase: ExpansionPhase.error,
          failure: error is ResearchFailure ? error : const ResearchFailure(ResearchFailureKind.unavailable),
        );
      }
    } finally {
      expander?.close();
      _expanders.remove(expander);
      if (!_disposed && epoch == _generation) {
        _ownsBusy = false;
        ref.read(expansionBusyProvider.notifier).set(false);
      }
    }
  }

  void updatePlan(int index, {bool? enabled, int? add}) {
    if (state?.phase != ExpansionPhase.plan) return;
    final old = state!, items = old.planItems.toList(), disabled = {...old.disabledPlan};
    if (index < 0 || index >= items.length) return;
    final item = items[index];
    if (enabled != null) {
      enabled ? disabled.remove(index) : disabled.add(index);
    }
    if (add != null) {
      items[index] = ExpansionPlanItem(
        targetId: item.targetId,
        add: add.clamp(1, 8),
        reason: item.reason,
        title: item.title,
      );
    }
    state = old.copyWith(planItems: List.unmodifiable(items), disabledPlan: Set.unmodifiable(disabled));
  }

  Future<void> startPlan() async {
    if (state?.phase != ExpansionPhase.plan ||
        ref.read(assistantControllerProvider.notifier).busy ||
        ref.read(expansionBusyProvider)) {
      return;
    }
    final old = state!, drafts = <ExpansionDraft>[], counts = <String, int>{};
    for (var i = 0; i < old.planItems.length; i++) {
      if (old.disabledPlan.contains(i)) continue;
      final item = old.planItems[i];
      if (item.title != null) {
        final id = '${old.proposalId}-branch-$i';
        drafts.add(ExpansionDraft(id: id, parentRef: old.request.mapId, title: item.title!));
        counts['new:$id'] = item.add;
      } else {
        counts[item.targetId] = item.add;
      }
    }
    if (counts.isEmpty) return;
    final r = old.request;
    final next = request(
      r.mapId,
      r.mapId,
      scope: ExpansionScope.map,
      breadth: 8,
      depth: r.depth,
      direction: r.direction,
      grounded: r.grounded,
      hint: r.hint,
      plan: counts,
    );
    state = ExpansionPreview(
      request: next,
      baseRevision: old.baseRevision,
      proposalId: old.proposalId,
      drafts: List.unmodifiable(drafts),
    );
    await _generate(next);
  }

  Future<void> _generate(ExpansionRequest request, {bool remember = true}) async {
    final epoch = ++_generation;
    final cancel = _cancel = CancellationToken();
    _ownsBusy = true;
    ref.read(expansionBusyProvider.notifier).set(true);
    ResearchFailure? failure;
    try {
      await _saveWorkflow(request);
      final prefs = ref.read(sharedPreferencesProvider), key = 'expansion.$arg';
      if (remember) {
        await prefs.setString('$key.direction', request.direction.name);
        await prefs.setInt('$key.depth', request.depth);
        await prefs.setInt('$key.breadth', request.breadth);
        await prefs.setBool('$key.grounded', request.grounded);
      }
      cancel.check();
      final workspace = ref.read(workspaceProvider(arg).notifier), snapshot = workspace.content;
      final reader = WorkspaceReader(
        content: () => snapshot,
        contexts: const [],
        filePath: workspace.filePath,
        pageText: ref.read(assistantPageTextProvider),
      );
      final titles = {
        snapshot.map(request.mapId)!.title,
        for (final node in snapshot.nodes.where((n) => n.mapId == request.mapId))
          snapshot.card(node.cardId)?.title ?? '',
        ..._excluded,
        ...state!.drafts.map((d) => d.title),
      }.map(normalizeExpansionTitle).toSet();
      final targets = request.scope == ExpansionScope.map
          ? request.plan.keys.toList()
          : request.scope == ExpansionScope.children
          ? request.targetIds
          : [request.commonParentId!];
      var index = 0;
      Future<void> worker() async {
        while (index < targets.length && !cancel.isCancelled && epoch == _generation) {
          final target = targets[index++];
          state = state!.copyWith(targetFailures: {...state!.targetFailures}..remove(target));
          IdeaExpander? expander;
          try {
            final r = this.request(
              request.mapId,
              target,
              direction: request.direction,
              depth: request.scope == ExpansionScope.group ? 1 : request.depth,
              breadth: request.breadth,
              hint: request.hint,
              grounded: request.grounded,
              scope: request.scope == ExpansionScope.group || request.scope == ExpansionScope.siblings
                  ? request.scope
                  : ExpansionScope.children,
              targets: request.scope == ExpansionScope.group || request.scope == ExpansionScope.siblings
                  ? request.targetIds
                  : [target],
              commonParentId: request.commonParentId,
              round: request.round,
            );
            state = state!.copyWith(activeTargetId: target);
            final prefix = '${state!.proposalId}-${++_call}-';
            var context = await ExpansionContextBuilder(reader).build(
              snapshot,
              r,
              draftTargets: state!.drafts,
              rootTitle: ref.read(studySetProvider(arg))?.title,
              excludedTitles: _excluded,
              cancellation: cancel,
              draftPrefix: prefix,
            );
            if (request.scope == ExpansionScope.map) {
              context = ExpansionContext(
                targets: context.targets,
                details: context.details,
                draftPrefix: prefix,
                excludedTitles: context.excludedTitles,
                limits: {'T1': request.plan[target]!},
              );
            }
            cancel.check();
            expander = await _newExpander();
            _expanders.add(expander);
            cancel.check();
            final rejected = <String>{};
            final depths = {for (final id in context.targets.values) id: 0};
            final parentsWithChildren = <String>{};
            await for (final draft in expander.expand(r, context, cancel)) {
              if (_disposed || epoch != _generation) return;
              if (rejected.contains(draft.parentRef) || !titles.add(normalizeExpansionTitle(draft.title))) {
                rejected.add('new:${draft.id}');
                continue;
              }
              depths['new:${draft.id}'] = (depths[draft.parentRef] ?? 0) + 1;
              parentsWithChildren.add(draft.parentRef);
              state = state!.copyWith(drafts: List.unmodifiable([...state!.drafts, draft]));
            }
            // Audit the visible tree too: global deduplication can remove a
            // child that was valid within the model's smaller context.
            if (depths.length == context.targets.length) {
              throw const ResearchFailure(ResearchFailureKind.protocol, 'missingTarget');
            }
            if (r.scope != ExpansionScope.group &&
                depths.entries.any((e) => e.value > 0 && e.value < r.depth && !parentsWithChildren.contains(e.key))) {
              throw const ResearchFailure(ResearchFailureKind.protocol, 'incompleteDepth');
            }
          } catch (error) {
            final targetFailure = error is ResearchFailure
                ? error
                : const ResearchFailure(ResearchFailureKind.unavailable);
            failure ??= targetFailure;
            if (!_disposed && epoch == _generation) {
              state = state!.copyWith(targetFailures: {...state!.targetFailures, target: targetFailure});
            }
          } finally {
            expander?.close();
            _expanders.remove(expander);
          }
        }
      }

      await Future.wait([for (var i = 0; i < targets.length.clamp(0, 3); i++) worker()]);
      if (!_disposed && epoch == _generation) {
        state = state!.copyWith(
          phase: failure == null
              ? ExpansionPhase.review
              : state!.drafts.isEmpty
              ? ExpansionPhase.error
              : ExpansionPhase.stopped,
          failure: failure,
        );
      }
    } catch (error) {
      if (!_disposed && epoch == _generation) {
        state = state!.copyWith(
          phase: state!.drafts.isEmpty ? ExpansionPhase.error : ExpansionPhase.stopped,
          failure: error is ResearchFailure ? error : const ResearchFailure(ResearchFailureKind.unavailable),
        );
      }
    } finally {
      if (!_disposed && epoch == _generation) {
        _ownsBusy = false;
        ref.read(expansionBusyProvider.notifier).set(false);
      }
    }
  }

  void stop() {
    if (state == null || state!.isApplying) return;
    _cancel?.cancel();
    for (final expander in _expanders.toList()) {
      expander.close();
    }
    ++_generation;
    _ownsBusy = false;
    ref.read(expansionBusyProvider.notifier).set(false);
    state = state!.drafts.isEmpty ? null : state!.copyWith(phase: ExpansionPhase.stopped);
  }

  void discard() {
    if (state?.isApplying == true) return;
    if (state != null) stop();
    _taskSession?.dismiss().ignore();
    state = null;
  }

  /// An immediate first click may be followed by double-click editing. Keep
  /// an exact, selection-only undo: toggling a parent twice is not an inverse
  /// because excluding it also excludes its descendants.
  void Function()? toggleForClick(String id) {
    if (!_reviewable) return null;
    final current = state!;
    final request = current.request;
    final item = current.drafts.where((d) => d.id == id).firstOrNull;
    if (item == null) return null;
    final before = {for (final d in current.drafts) d.id: d.kept};
    toggle(id, !item.kept);
    final changed = {
      for (final d in state!.drafts)
        if (before[d.id] != d.kept) d.id: d.kept,
    };
    return () {
      if (!_reviewable || !identical(state!.request, request)) return;
      state = state!.copyWith(
        drafts: [
          for (final d in state!.drafts)
            if (changed.containsKey(d.id) && d.kept == changed[d.id]) d.copyWith(kept: before[d.id]!) else d,
        ],
      );
    };
  }

  void toggle(String id, bool kept) {
    if (!_reviewable) return;
    state = state!.copyWith(drafts: selectExpansionDraft(state!.drafts, id, kept));
  }

  void edit(String id, String title) {
    if (!_reviewable || normalizeExpansionTitle(title).isEmpty) return;
    state = state!.copyWith(drafts: selectExpansionDraft(state!.drafts, id, true, title: title));
  }

  bool get _reviewable =>
      state != null &&
      !state!.isApplying &&
      {ExpansionPhase.review, ExpansionPhase.stopped, ExpansionPhase.error}.contains(state!.phase);
  Future<void> continueFromDraft(String id) async {
    if (!_reviewable || ref.read(assistantControllerProvider.notifier).busy) return;
    final s = state!;
    var depth = 0, current = s.drafts.firstWhere((d) => d.id == id);
    while (true) {
      if (!(s.request.scope == ExpansionScope.map && s.request.plan.containsKey('new:${current.id}'))) depth++;
      if (!current.parentRef.startsWith('new:')) break;
      current = s.drafts.firstWhere((d) => 'new:${d.id}' == current.parentRef);
    }
    if (depth >= 3) return;
    state = s.copyWith(phase: ExpansionPhase.generating, drafts: selectExpansionDraft(s.drafts, id, true));
    await _generate(
      request(
        s.request.mapId,
        'new:$id',
        depth: 3 - depth,
        direction: s.request.direction,
        breadth: s.request.breadth,
        grounded: s.request.grounded,
        hint: s.request.hint,
      ),
      remember: false,
    );
  }

  Future<void> regenerate([ExpansionRequest? settings]) async {
    if (!_reviewable || ref.read(assistantControllerProvider.notifier).busy) return;
    final old = state!, r = settings ?? old.request;
    _taskSession = null;
    _executor = null; // Explicit regeneration starts a new frozen run, retaining old run attribution.
    _excluded.addAll(old.drafts.map((d) => d.title));
    final next = request(
      r.mapId,
      old.request.targetIds.first,
      targets: old.request.targetIds,
      scope: old.request.scope,
      commonParentId: old.request.commonParentId,
      plan: old.request.plan,
      direction: r.direction,
      depth: r.depth,
      breadth: old.request.scope == ExpansionScope.map ? 8 : r.breadth,
      grounded: r.grounded,
      hint: r.hint,
      round: old.request.round + 1,
    );
    state = ExpansionPreview(request: next, baseRevision: old.baseRevision, proposalId: old.proposalId);
    if (next.scope == ExpansionScope.map) {
      if (old.request.plan.isEmpty) {
        state = null;
        await planMap(next);
      } else {
        state = state!.copyWith(
          drafts: old.drafts
              .where((d) => next.plan.containsKey('new:${d.id}'))
              .map((d) => d.copyWith(kept: true))
              .toList(),
        );
        await _generate(next);
      }
    } else {
      await _generate(next);
    }
  }

  Future<int> keep() async {
    if (!_reviewable || state!.selectedCount == 0) return 0;
    final old = state!;
    state = old.copyWith(isApplying: true);
    try {
      final proposal = expansionToProposal(
        old.request,
        old.drafts,
        proposalId: old.proposalId,
        baseRevision: old.baseRevision,
        parents: {
          for (final n
              in ref.read(workspaceProvider(arg).notifier).content.nodes.where((n) => n.mapId == old.request.mapId))
            n.cardId: n.parentId,
        },
      );
      final receipt = await ref
          .read(assistantMapEditExecutorProvider(arg))
          .apply(proposal, proposal.operations.map((o) => o.id).toSet());
      _taskSession?.dismiss().ignore();
      if (!_disposed) state = null;
      return receipt.nodeIds.length;
    } catch (_) {
      if (!_disposed) state = old.copyWith(failure: const ResearchFailure(ResearchFailureKind.unavailable));
      return 0;
    }
  }
}

Map<String, dynamic> _expansionRequestJson(ExpansionRequest r) => {
  'studySetId': r.studySetId,
  'mapId': r.mapId,
  'targetIds': r.targetIds,
  'scope': r.scope.name,
  'direction': r.direction.name,
  'depth': r.depth,
  'breadth': r.breadth,
  'hint': r.hint,
  'grounded': r.grounded,
  'plan': r.plan,
  'round': r.round,
  'commonParentId': r.commonParentId,
};
ExpansionRequest _restoreExpansionRequest(Map<String, dynamic> j) => ExpansionRequest(
  studySetId: j['studySetId'],
  mapId: j['mapId'],
  targetIds: List<String>.from(j['targetIds']),
  scope: ExpansionScope.values.byName(j['scope']),
  direction: ExpansionDirection.values.byName(j['direction']),
  depth: j['depth'],
  breadth: j['breadth'],
  hint: j['hint'],
  grounded: j['grounded'],
  plan: Map<String, int>.from(j['plan']),
  round: j['round'],
  commonParentId: j['commonParentId'],
);
Map<String, dynamic> _expansionDraftJson(ExpansionDraft d) => {
  'id': d.id,
  'parentRef': d.parentRef,
  'title': d.title,
  'tag': d.tag.name,
  'page': d.page,
  'kept': d.kept,
  'edited': d.edited,
};
ExpansionDraft _restoreExpansionDraft(Map j) => ExpansionDraft(
  id: j['id'],
  parentRef: j['parentRef'],
  title: j['title'],
  tag: ExpansionDirection.values.byName(j['tag']),
  page: j['page'],
  kept: j['kept'],
  edited: j['edited'],
);
