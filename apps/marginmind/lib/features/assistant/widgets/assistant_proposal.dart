import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../../research/research_origin.dart' show researchCardTitle;
import '../../workspace/workspace_controller.dart';
import '../assistant_controller.dart';
import '../assistant_reader.dart';
import '../assistant_scope.dart';

/// Whether [ref] (a node, or `new:` an earlier item) still exists in the map.
bool _exists(StudySetContent content, String mapId, String? ref) =>
    ref == null || ref.startsWith('new:') || ref == assistantRootId || content.node(ref, mapId: mapId) != null;

/// Items whose target was deleted since the proposal was made.
Set<String> staleOperations(StudySetContent content, MapEditProposal proposal) => {
  for (final op in proposal.operations)
    if (!_exists(content, proposal.mapId, op.nodeId) || !_exists(content, proposal.mapId, op.parentId)) op.id,
};

/// The map nodes an item points at, outlined while it is hovered: the node
/// itself, or the parent a new node goes under.
Set<String> previewTargets(MapEditOperation op) {
  final id = op.nodeId ?? op.parentId;
  if (id == null || id.startsWith('new:')) return const {};
  return {id};
}

/// Changes the assistant proposes to the map: each item can be left out, and
/// nothing changes until they are applied.
class ProposalCard extends ConsumerStatefulWidget {
  const ProposalCard({super.key, required this.studySetId, required this.view});

  final String studySetId;
  final ProposalView view;

  @override
  ConsumerState<ProposalCard> createState() => _ProposalCardState();
}

class _ProposalCardState extends ConsumerState<ProposalCard> {
  bool _busy = false;

  late final AssistantPreview _preview = ref.read(assistantPreviewProvider(widget.studySetId).notifier);

  @override
  void initState() {
    super.initState();
    _preview; // Read now: dispose may not use ref.
  }

  @override
  void dispose() {
    // A card going away (another conversation) leaves no outline behind.
    final preview = _preview;
    WidgetsBinding.instance.addPostFrameCallback((_) => preview.clear());
    super.dispose();
  }

  Future<void> _apply(Set<String> stale) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = context.l10n;
    final controller = ref.read(assistantControllerProvider.notifier);
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    final id = widget.view.proposal.id;
    try {
      for (final op in stale) {
        if (widget.view.selected.contains(op)) await controller.selectOperation(id, op, false);
      }
      await controller.applyProposal(id);
      _preview.clear();
      final applied = ref
          .read(assistantControllerProvider)
          .messages
          .expand((m) => m.proposals)
          .where((p) => p.proposal.id == id)
          .firstOrNull;
      final receipt = applied?.receipt;
      if (receipt == null || !mounted) return;
      if (ref.read(workspaceProvider(widget.studySetId)).layout == MMSplitMode.primary) {
        workspace.setLayout(MMSplitMode.split);
      }
      if (receipt.nodeIds.lastOrNull case final node?) {
        await workspace.revealAnchor(
          SourceAnchor(
            target: CardTarget(cardId: node),
            mapId: applied!.proposal.mapId,
          ),
        );
      }
      if (mounted) {
        MMHud.show(
          context,
          l.assistantAppliedHud(receipt.operationIds.length),
          action: (l.undo, () => unawaited(workspace.undo())),
        );
      }
    } catch (_) {
      if (mounted) MMHud.show(context, l.assistantErrorFailed, icon: MMIcons.warning);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.assistantErrorFailed, icon: MMIcons.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final view = widget.view;
    final p = view.proposal;
    final content = ref.watch(workspaceProvider(widget.studySetId).select((s) => s.content)) ?? StudySetContent.empty;
    final stale = view.status == ProposalStatus.pending ? staleOperations(content, p) : const <String>{};
    final chosen = view.selected.difference(stale);
    final controller = ref.read(assistantControllerProvider.notifier);
    final pending = view.status == ProposalStatus.pending;
    final mapShown = ref.watch(workspaceProvider(widget.studySetId).select((s) => s.layout)) != MMSplitMode.primary;

    String titleOf(MapEditOperation op) =>
        op.title ?? op.question ?? (op.nodeId == null ? '' : researchCardTitle(content, op.nodeId!));
    String? detail(MapEditOperation op) {
      if (op.kind == MapEditKind.addReviewCard) return op.answer;
      if (op.kind == MapEditKind.rename) return null;
      final parent = op.parentId;
      if (parent == null) return null;
      if (parent.startsWith('new:')) {
        final earlier = p.operations.where((o) => o.id == parent.substring(4)).firstOrNull;
        return earlier == null ? null : '→ ${titleOf(earlier)}';
      }
      final title = parent == assistantRootId
          ? (content.map(p.mapId)?.title ?? '')
          : researchCardTitle(content, parent);
      return title.isEmpty ? null : '→ $title';
    }

    final apply = pending && chosen.isNotEmpty && !_busy ? () => _apply(stale) : null;
    return MouseRegion(
      onExit: (_) => _preview.clear(),
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.enter): ?apply},
        child: FocusTraversalGroup(
          child: Container(
            margin: const EdgeInsets.only(top: 6, bottom: MMSpacing.s),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(MMRadii.card),
              border: Border.all(color: c.research.withValues(alpha: .16)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [c.researchTint, c.card],
                stops: const [0, .8],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(MMSpacing.m, 9, MMSpacing.m, 6),
                  child: Row(
                    children: [
                      Icon(MMIcons.organize, size: 14, color: c.research),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l.assistantProposalTitle,
                          style: t.callout.copyWith(fontWeight: FontWeight.w600, color: c.research),
                        ),
                      ),
                      if (view.status == ProposalStatus.applied) MMPill(l.assistantProposalApplied, color: c.positive),
                      if (view.status == ProposalStatus.dismissed) MMPill(l.assistantProposalDismissed),
                    ],
                  ),
                ),
                for (final op in p.operations)
                  _OperationRow(
                    key: ValueKey('proposal-op-${op.id}'),
                    op: op,
                    title: titleOf(op),
                    detail: detail(op),
                    stale: stale.contains(op.id),
                    checked: chosen.contains(op.id),
                    onChanged: pending && !_busy && !stale.contains(op.id)
                        ? (v) => _run(() => controller.selectOperation(p.id, op.id, v))
                        : null,
                    onHover: pending && mapShown
                        ? (on) => on ? _preview.show(previewTargets(op)) : _preview.clear()
                        : null,
                  ),
                Container(
                  margin: const EdgeInsets.only(top: MMSpacing.xs),
                  padding: const EdgeInsets.fromLTRB(MMSpacing.m, MMSpacing.s, MMSpacing.m, 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.separator)),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: MMSpacing.s,
                    runSpacing: MMSpacing.s,
                    children: switch (view.status) {
                      ProposalStatus.pending => [
                        MMButton(
                          key: const ValueKey('proposal-dismiss'),
                          label: l.assistantDismiss,
                          onPressed: _busy ? null : () => _run(() => controller.dismissProposal(p.id)),
                        ),
                        MMButton(
                          key: const ValueKey('proposal-apply'),
                          label: l.assistantApply(chosen.length),
                          variant: MMButtonVariant.primary,
                          color: c.research,
                          onPressed: apply,
                        ),
                      ],
                      ProposalStatus.applied => [
                        MMButton(
                          key: const ValueKey('proposal-show'),
                          label: l.assistantShowInMap,
                          onPressed: view.receipt?.nodeIds.lastOrNull == null
                              ? null
                              : () => ref
                                    .read(workspaceProvider(widget.studySetId).notifier)
                                    .revealAnchor(
                                      SourceAnchor(
                                        target: CardTarget(cardId: view.receipt!.nodeIds.last),
                                        mapId: p.mapId,
                                      ),
                                    ),
                        ),
                        MMButton(
                          key: const ValueKey('proposal-undo'),
                          label: l.undo,
                          onPressed: () => ref.read(workspaceProvider(widget.studySetId).notifier).undo(),
                        ),
                      ],
                      ProposalStatus.dismissed => [
                        MMButton(
                          key: const ValueKey('proposal-reopen'),
                          label: l.assistantReopen,
                          onPressed: () => _run(() => controller.reopenProposal(p.id)),
                        ),
                      ],
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OperationRow extends StatelessWidget {
  const _OperationRow({
    super.key,
    required this.op,
    required this.title,
    required this.detail,
    required this.stale,
    required this.checked,
    required this.onChanged,
    required this.onHover,
  });

  final MapEditOperation op;
  final String title;
  final String? detail;
  final bool stale, checked;
  final ValueChanged<bool>? onChanged;
  final ValueChanged<bool>? onHover;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final (String symbol, Color color) = switch (op.kind) {
      MapEditKind.addTopic || MapEditKind.addNote || MapEditKind.addReviewCard => ('+', c.positive),
      MapEditKind.move => ('→', c.accent),
      MapEditKind.rename => ('✎', c.caution),
    };
    final off = !checked && !stale;
    return MouseRegion(
      onEnter: onHover == null ? null : (_) => onHover!(true),
      onExit: onHover == null ? null : (_) => onHover!(false),
      child: MMInteractive(
        onTap: onChanged == null ? null : () => onChanged!(!checked),
        canRequestFocus: false,
        isButton: false,
        builder: (context, s) => Container(
          color: s.hovered && onChanged != null ? c.hover : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: MMCheckbox(value: checked, onChanged: onChanged, color: c.research, semanticLabel: title),
              ),
              const SizedBox(width: MMSpacing.s),
              SizedBox(
                width: 12,
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    symbol,
                    style: t.mono.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                      fontFamilyFallback: [...?t.mono.fontFamilyFallback, ...?t.body.fontFamilyFallback],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: MMSpacing.xs),
              Expanded(
                child: AnimatedOpacity(
                  duration: MMAppearance.duration(context, MMMotion.standard),
                  opacity: off ? .5 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: t.body.copyWith(
                          color: c.label,
                          decoration: off || stale ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (stale)
                        Text(l.assistantTargetDeleted, style: t.footnote.copyWith(color: c.critical))
                      else if (detail != null)
                        Text(
                          detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.footnote.copyWith(color: c.secondaryLabel),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
