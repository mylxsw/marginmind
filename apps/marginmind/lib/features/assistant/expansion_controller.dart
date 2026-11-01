import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/providers.dart';
import '../workspace/workspace_controller.dart';
import 'assistant_controller.dart';
import 'assistant_reader.dart';
import 'assistant_scope.dart';
import 'assistant_settings.dart';
import 'assistant_writes.dart';
import 'expansion_context.dart';

/// Shares the assistant's exclusive model slot, including across preview requests.
final expansionBusyProvider = NotifierProvider<ExpansionBusy, bool>(ExpansionBusy.new);

class ExpansionBusy extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final ideaExpanderFactoryProvider = Provider<Future<IdeaExpander> Function()>(
  (ref) => () async {
    final model = ref.read(assistantDefaultModelProvider);
    if (model == null) throw const ResearchFailure(ResearchFailureKind.unavailable);
    final key = await assistantModelKey(ref.read(assistantSecretsProvider), model);
    if (model.provider != AssistantProvider.ollama && (key == null || key.isEmpty)) {
      throw const ResearchFailure(ResearchFailureKind.authentication);
    }
    return ModelIdeaExpander(connectAssistant(model, key ?? ''), model.model);
  },
);

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
  }) => ExpansionPreview(
    request: request,
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

  Future<void> start(ExpansionRequest request) async {
    if (state != null || ref.read(assistantControllerProvider.notifier).busy || ref.read(expansionBusyProvider)) {
      throw StateError('Assistant is busy');
    }
    _excluded.clear();
    final snapshot = ref.read(workspaceProvider(arg).notifier).content;
    state = ExpansionPreview(
      request: request,
      baseRevision: assistantMapRevision(snapshot, request.mapId),
      proposalId: 'expansion-${DateTime.now().microsecondsSinceEpoch}',
    );
    await _generate(request);
  }

  Future<void> planMap(ExpansionRequest request) async {
    if (state != null || ref.read(assistantControllerProvider.notifier).busy || ref.read(expansionBusyProvider)) {
      throw StateError('Assistant is busy');
    }
    _excluded.clear();
    final workspace = ref.read(workspaceProvider(arg).notifier);
    state = ExpansionPreview(
      request: request,
      baseRevision: assistantMapRevision(workspace.content, request.mapId),
      proposalId: 'expansion-${DateTime.now().microsecondsSinceEpoch}',
      phase: ExpansionPhase.planning,
    );
    final epoch = ++_generation, cancel = _cancel = CancellationToken();
    _ownsBusy = true;
    ref.read(expansionBusyProvider.notifier).set(true);
    IdeaExpander? expander;
    try {
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
      expander = await ref.read(ideaExpanderFactoryProvider)();
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
            expander = await ref.read(ideaExpanderFactoryProvider)();
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
            if (r.scope != ExpansionScope.group &&
                depths.entries.any((e) => e.value > 0 && e.value < r.depth && !parentsWithChildren.contains(e.key))) {
              throw const ResearchFailure(ResearchFailureKind.protocol, 'incompleteDepth');
            }
          } catch (error) {
            failure ??= error is ResearchFailure ? error : const ResearchFailure(ResearchFailureKind.unavailable);
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
    state = null;
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
      if (!_disposed) state = null;
      return receipt.nodeIds.length;
    } catch (_) {
      if (!_disposed) state = old.copyWith(failure: const ResearchFailure(ResearchFailureKind.unavailable));
      return 0;
    }
  }
}
