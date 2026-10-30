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
);

enum ExpansionPhase { generating, review, stopped, error }

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
  });
  final ExpansionRequest request;
  final int baseRevision;
  final List<ExpansionDraft> drafts;
  final ExpansionPhase phase;
  final ResearchFailure? failure;
  final bool isApplying;
  final String proposalId;
  final String? activeTargetId;
  int get selectedCount => drafts.where((d) => d.kept).length;
  ExpansionPreview copyWith({
    List<ExpansionDraft>? drafts,
    ExpansionPhase? phase,
    ResearchFailure? failure,
    bool? isApplying,
    String? activeTargetId,
  }) => ExpansionPreview(
    request: request,
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
  IdeaExpander? _expander;
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
      _expander?.close();
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
  }) {
    final prefs = ref.read(sharedPreferencesProvider), key = 'expansion.$arg';
    return ExpansionRequest(
      studySetId: arg,
      mapId: mapId,
      targetIds: [target],
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

  Future<void> _generate(ExpansionRequest request, {bool remember = true}) async {
    state = state!.copyWith(activeTargetId: request.targetIds.single);
    final epoch = ++_generation;
    final cancel = _cancel = CancellationToken();
    _ownsBusy = true;
    ref.read(expansionBusyProvider.notifier).set(true);
    IdeaExpander? expander;
    try {
      final prefs = ref.read(sharedPreferencesProvider), key = 'expansion.$arg';
      if (remember) {
        await prefs.setString('$key.direction', request.direction.name);
        await prefs.setInt('$key.depth', request.depth);
        await prefs.setInt('$key.breadth', request.breadth);
        await prefs.setBool('$key.grounded', request.grounded);
      }
      cancel.check();
      final workspace = ref.read(workspaceProvider(arg).notifier);
      final snapshot = workspace.content;
      final reader = WorkspaceReader(
        content: () => snapshot,
        contexts: const [],
        filePath: workspace.filePath,
        pageText: ref.read(assistantPageTextProvider),
      );
      final context = await ExpansionContextBuilder(reader).build(
        snapshot,
        request,
        draftTargets: state!.drafts,
        excludedTitles: _excluded,
        cancellation: cancel,
        draftPrefix: '${state!.proposalId}-${++_call}-',
      );
      cancel.check();
      expander = await ref.read(ideaExpanderFactoryProvider)();
      cancel.check();
      _expander = expander;
      final titles = {
        ...context.existingTitles,
        for (final node in snapshot.nodes.where((n) => n.mapId == request.mapId))
          snapshot.card(node.cardId)?.title ?? '',
        ..._excluded,
        ...state!.drafts.map((d) => d.title),
      }.map(normalizeExpansionTitle).toSet();
      final rejected = <String>{};
      await for (final draft in expander.expand(request, context, cancel)) {
        if (_disposed || epoch != _generation) return;
        if (rejected.contains(draft.parentRef) || !titles.add(normalizeExpansionTitle(draft.title))) {
          rejected.add('new:${draft.id}');
          continue;
        }
        state = state!.copyWith(drafts: List.unmodifiable([...state!.drafts, draft]));
      }
      if (!_disposed && epoch == _generation) state = state!.copyWith(phase: ExpansionPhase.review);
    } catch (error) {
      if (!_disposed && epoch == _generation) {
        state = state!.copyWith(
          phase: state!.drafts.isEmpty ? ExpansionPhase.error : ExpansionPhase.stopped,
          failure: error is ResearchFailure ? error : const ResearchFailure(ResearchFailureKind.unavailable),
        );
      }
    } finally {
      expander?.close();
      if (identical(_expander, expander)) _expander = null;
      if (!_disposed && epoch == _generation) {
        _ownsBusy = false;
        ref.read(expansionBusyProvider.notifier).set(false);
      }
    }
  }

  void stop() {
    if (state == null || state!.isApplying) return;
    _cancel?.cancel();
    _expander?.close();
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

  bool get _reviewable => state != null && !state!.isApplying && state!.phase != ExpansionPhase.generating;
  Future<void> continueFromDraft(String id) async {
    if (!_reviewable || ref.read(assistantControllerProvider.notifier).busy) return;
    final s = state!;
    var depth = 0, current = s.drafts.firstWhere((d) => d.id == id);
    while (true) {
      depth++;
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
      old.request.targetIds.single,
      direction: r.direction,
      depth: r.depth,
      breadth: r.breadth,
      grounded: r.grounded,
      hint: r.hint,
      round: old.request.round + 1,
    );
    state = ExpansionPreview(request: next, baseRevision: old.baseRevision, proposalId: old.proposalId);
    await _generate(next);
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
