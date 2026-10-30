import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart' show ModelReference;
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../assistant_controller.dart';
import '../../workspace/workspace_controller.dart';
import '../../research/research_origin.dart' show researchCardTitle;
import '../assistant_services.dart';
import '../expansion_controller.dart';
import 'dashed_border.dart';

String expansionDirectionLabel(AppLocalizations l, ExpansionDirection direction) => switch (direction) {
  ExpansionDirection.auto => l.mapIdeaDirectionAuto,
  ExpansionDirection.why => l.mapIdeaDirectionWhy,
  ExpansionDirection.example => l.mapIdeaDirectionExample,
  ExpansionDirection.counter => l.mapIdeaDirectionCounter,
  ExpansionDirection.question => l.mapIdeaDirectionQuestion,
  ExpansionDirection.action => l.mapIdeaDirectionAction,
};

class ExpansionOptions extends StatelessWidget {
  const ExpansionOptions({super.key, required this.request, required this.onChanged});
  final ExpansionRequest request;
  final ValueChanged<ExpansionRequest> onChanged;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    void change({ExpansionDirection? direction, int? depth, int? breadth}) => onChanged(
      ExpansionRequest(
        studySetId: request.studySetId,
        mapId: request.mapId,
        targetIds: request.targetIds,
        scope: request.scope,
        commonParentId: request.commonParentId,
        plan: request.plan,
        round: request.round,
        direction: direction ?? request.direction,
        depth: depth ?? request.depth,
        breadth: breadth ?? request.breadth,
        grounded: request.grounded,
        hint: request.hint,
      ),
    );
    final c = context.mmColors;
    Widget option(String label, Widget control) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
        const SizedBox(height: MMSpacing.xs),
        control,
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: MMSpacing.xs,
          runSpacing: MMSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: MMSpacing.xs),
              child: Text(l.mapIdeaDirection, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
            ),
            for (final d in ExpansionDirection.values)
              Semantics(
                inMutuallyExclusiveGroup: true,
                checked: d == request.direction,
                child: MMInteractive(
                  key: ValueKey('expansion-direction-${d.name}'),
                  semanticLabel: expansionDirectionLabel(l, d),
                  selected: d == request.direction,
                  onTap: () => change(direction: d),
                  builder: (context, state) => Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: d == request.direction ? c.research : (state.hovered ? c.hover : Colors.transparent),
                      border: d == request.direction ? null : Border.all(color: c.line, width: .5),
                      borderRadius: BorderRadius.circular(MMRadii.row),
                    ),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        expansionDirectionLabel(l, d),
                        style: context.mmText.footnote.copyWith(
                          color: d == request.direction ? c.onResearch : c.secondaryLabel,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: MMSpacing.m),
        LayoutBuilder(
          builder: (context, constraints) {
            final depth = option(
              l.mapIdeaDepth,
              MMSegmentedControl<int>(
                expand: true,
                key: const ValueKey('expansion-depth'),
                value: request.depth,
                onChanged: (n) => change(depth: n),
                segments: [for (var n = 1; n <= 3; n++) MMSegment(value: n, label: l.mapIdeaDepthLevels(n))],
              ),
            );
            final amount = option(
              l.mapIdeaAmount,
              MMSegmentedControl<int>(
                expand: true,
                key: const ValueKey('expansion-amount'),
                value: request.breadth,
                onChanged: (n) => change(breadth: n),
                segments: [
                  for (final (n, label) in [
                    (3, l.mapIdeaAmountFew),
                    (5, l.mapIdeaAmountSome),
                    (8, l.mapIdeaAmountMany),
                  ])
                    MMSegment(value: n, label: label),
                ],
              ),
            );
            // English labels need more room than the short Chinese labels.
            if (constraints.maxWidth < 300 || l.localeName != 'zh') {
              return Column(
                children: [
                  depth,
                  const SizedBox(height: MMSpacing.s),
                  amount,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: depth),
                const SizedBox(width: MMSpacing.m),
                Expanded(child: amount),
              ],
            );
          },
        ),
      ],
    );
  }
}

class ExpansionSection extends ConsumerStatefulWidget {
  const ExpansionSection({
    super.key,
    required this.studySetId,
    required this.mapId,
    required this.targetId,
    this.targetIds,
  });
  final String studySetId, mapId, targetId;
  final List<String>? targetIds;
  @override
  ConsumerState<ExpansionSection> createState() => _ExpansionSectionState();
}

class _ExpansionSectionState extends ConsumerState<ExpansionSection> {
  late ExpansionRequest _request;
  String _hint = '';
  bool _grounded = true;
  @override
  void initState() {
    super.initState();
    _request = ref.read(expansionControllerProvider(widget.studySetId).notifier).request(widget.mapId, widget.targetId);
    _grounded = _request.grounded;
  }

  void _start({ExpansionScope scope = ExpansionScope.children, bool branchesOnly = false}) {
    if (ref.read(assistantControllerProvider.notifier).busy ||
        ref.read(expansionControllerProvider(widget.studySetId)) != null) {
      return;
    }
    final controller = ref.read(expansionControllerProvider(widget.studySetId).notifier);
    final request = controller.request(
      widget.mapId,
      widget.targetId,
      targets: widget.targetIds,
      scope: scope,
      commonParentId: {ExpansionScope.group, ExpansionScope.siblings}.contains(scope) ? _commonParent : null,
      direction: _request.direction,
      depth: branchesOnly ? 1 : _request.depth,
      breadth: _request.breadth,
      grounded: _grounded,
      hint: String.fromCharCodes(_hint.runes.take(200)),
    );
    Navigator.of(context).pop();
    if (widget.targetId == widget.mapId && !branchesOnly && scope == ExpansionScope.children) {
      controller.planMap(
        controller.request(
          widget.mapId,
          widget.mapId,
          scope: ExpansionScope.map,
          breadth: 8,
          depth: request.depth,
          direction: request.direction,
          grounded: request.grounded,
          hint: request.hint,
        ),
      );
    } else {
      controller.start(request);
    }
  }

  String? get _commonParent {
    final content = ref.read(workspaceProvider(widget.studySetId).notifier).content;
    final parents = {
      for (final id in widget.targetIds ?? [widget.targetId])
        content.node(id, mapId: widget.mapId)?.parentId ?? widget.mapId,
    };
    return parents.length == 1 ? parents.single : null;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, c = context.mmColors;
    final busy =
        ref.watch(expansionBusyProvider) ||
        ref.watch(assistantControllerProvider.select((s) => s.running)) ||
        ref.watch(assistantBackgroundProvider) != null;
    final title = widget.targetId == widget.mapId
        ? l.mapIdeaExpandMap
        : (widget.targetIds?.length ?? 1) > 1
        ? l.mapIdeaExpandEach(widget.targetIds!.length)
        : l.mapIdeaExpand;
    return Padding(
      padding: const EdgeInsets.only(bottom: MMSpacing.s),
      child: Container(
        padding: const EdgeInsets.all(MMSpacing.m),
        decoration: BoxDecoration(
          color: c.fill,
          border: Border.all(color: c.separator, width: .5),
          borderRadius: BorderRadius.circular(MMRadii.ideaSection),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  widget.targetId == widget.mapId ? MMIcons.network : MMIcons.expandIdeas,
                  size: 15,
                  color: c.research,
                ),
                const SizedBox(width: MMSpacing.s),
                Expanded(child: Text(title, style: context.mmText.headline)),
              ],
            ),
            const SizedBox(height: MMSpacing.m),
            ExcludeFocus(
              excluding: busy,
              child: IgnorePointer(
                ignoring: busy,
                child: AnimatedOpacity(
                  opacity: busy ? .45 : 1,
                  duration: MMMotion.quick,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ExpansionOptions(request: _request, onChanged: (r) => setState(() => _request = r)),
                      const SizedBox(height: MMSpacing.m),
                      MMTextField(
                        maxLength: 200,
                        placeholder: l.mapIdeaHint,
                        semanticLabel: l.mapIdeaHint,
                        onChanged: (v) => _hint = v,
                        onSubmitted: (_) => _start(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: MMSpacing.m),
            Row(
              children: [
                MMSwitch(
                  value: _grounded,
                  semanticLabel: l.mapIdeaGrounded,
                  color: c.research,
                  onChanged: busy ? null : (v) => setState(() => _grounded = v),
                ),
                const SizedBox(width: MMSpacing.xs),
                Text(l.mapIdeaGrounded, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
                const Spacer(),
                MMInteractive(
                  key: const ValueKey('expansion-start'),
                  onTap: busy ? null : () => _start(),
                  autofocus: true,
                  semanticLabel: title,
                  builder: (context, state) => Opacity(
                    opacity: state.enabled ? 1 : .45,
                    child: Container(
                      height: MMInput.touchInputOf(context) ? MMSizes.touchTarget : MMSizes.ideaPrimaryButton,
                      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          state.pressed ? c.pressed : (state.hovered ? c.hover : Colors.transparent),
                          c.research,
                        ),
                        borderRadius: BorderRadius.circular(MMRadii.row),
                        boxShadow: state.focused
                            ? [BoxShadow(color: c.research.withValues(alpha: .25), spreadRadius: 2)]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l.mapIdeaExpand, style: context.mmText.headline.copyWith(color: c.onResearch)),
                          const SizedBox(width: MMSpacing.m),
                          Text(
                            '⌥⇥',
                            style: context.mmText.footnote.copyWith(color: c.onResearch.withValues(alpha: .7)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (widget.targetId == widget.mapId)
              MMButton(
                label: l.mapIdeaBranchesOnly,
                variant: MMButtonVariant.plain,
                onPressed: busy ? null : () => _start(branchesOnly: true),
              ),
            if ((widget.targetIds?.length ?? 1) > 1) ...[
              const SizedBox(height: MMSpacing.s),
              Row(
                children: [
                  for (final (scope, label) in [
                    (ExpansionScope.group, l.mapIdeaGroup),
                    (ExpansionScope.siblings, l.mapIdeaFillSiblings),
                  ])
                    Expanded(
                      child: Tooltip(
                        message: _commonParent == null ? l.mapEditDifferentParents : '',
                        child: MMButton(
                          label: label,
                          variant: MMButtonVariant.plain,
                          onPressed: _commonParent == null || busy ? null : () => _start(scope: scope),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MapGhostNode extends StatefulWidget {
  const MapGhostNode({
    super.key,
    required this.draft,
    required this.focused,
    required this.generating,
    required this.onToggle,
    required this.onEdit,
    required this.onMore,
    this.onHover,
    this.onEditingChanged,
  });
  final ExpansionDraft draft;
  final bool focused, generating;
  final VoidCallback onToggle;
  final ValueChanged<String> onEdit;
  final VoidCallback? onMore;
  final ValueChanged<bool>? onHover;
  final VoidCallback? onEditingChanged;
  @override
  State<MapGhostNode> createState() => MapGhostNodeState();
}

class MapGhostNodeState extends State<MapGhostNode> {
  TextEditingController? _text;
  bool get editing => _text != null;
  void beginEdit() {
    if (widget.generating || _text != null) return;
    setState(
      () =>
          _text = TextEditingController(text: widget.draft.title)
            ..selection = TextSelection(baseOffset: 0, extentOffset: widget.draft.title.length),
    );
    widget.onEditingChanged?.call();
  }

  void _finish(bool save) {
    final text = _text;
    if (text == null) return;
    if (save) widget.onEdit(text.text);
    setState(() => _text = null);
    widget.onEditingChanged?.call();
    // Let the EditableText detach before disposing its controller.
    WidgetsBinding.instance.addPostFrameCallback((_) => text.dispose());
  }

  @override
  void dispose() {
    _text?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors, l = context.l10n, d = widget.draft;
    return Semantics(
      button: true,
      toggled: d.kept,
      focusable: true,
      focused: widget.focused,
      label: l.mapIdeaDraftSemantics(d.title, d.kept ? l.mapIdeaDraftKept : l.mapIdeaDraftSkipped),
      hint: [
        if (d.tag != ExpansionDirection.auto) expansionDirectionLabel(l, d.tag),
        if (d.page != null) l.pageNumber(d.page!),
      ].join(', '),
      customSemanticsActions: {
        CustomSemanticsAction(label: l.mapIdeaDraftEdit): beginEdit,
        if (widget.onMore != null) CustomSemanticsAction(label: l.mapIdeaDraftMore): widget.onMore!,
      },
      child: MouseRegion(
        onEnter: (_) => widget.onHover?.call(true),
        onExit: (_) => widget.onHover?.call(false),
        child: GestureDetector(
          onTap: widget.generating ? null : widget.onToggle,
          onDoubleTap: beginEdit,
          onLongPressStart: widget.generating
              ? null
              : (details) => showMMMenu(
                  context,
                  position: details.globalPosition,
                  entries: [
                    MMMenuItem(d.kept ? l.mapIdeaDraftSkip : l.mapIdeaDraftKeep, widget.onToggle),
                    MMMenuItem(l.mapIdeaDraftEdit, beginEdit),
                    if (widget.onMore != null) MMMenuItem(l.mapIdeaDraftMore, widget.onMore),
                  ],
                ),
          child: Container(
            decoration: BoxDecoration(
              color: d.kept ? Color.alphaBlend(c.researchWash, c.canvas) : c.canvas,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [if (widget.focused) BoxShadow(color: c.research, spreadRadius: 2)],
            ),
            foregroundDecoration: ShapeDecoration(shape: _DraftBorder(color: d.kept ? c.research : c.line)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_text != null)
                  CallbackShortcuts(
                    bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => _finish(false)},
                    child: TextField(
                      autofocus: true,
                      controller: _text,
                      style: context.mmText.body,
                      decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                      onSubmitted: (_) => _finish(true),
                      onTapOutside: (_) => _finish(true),
                    ),
                  )
                else
                  Text(
                    d.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.mmText.body.copyWith(
                      color: d.kept ? c.label : c.secondaryLabel,
                      decoration: d.kept ? null : TextDecoration.lineThrough,
                    ),
                  ),
                if (d.tag != ExpansionDirection.auto || d.page != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (d.tag != ExpansionDirection.auto)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(color: c.research, borderRadius: BorderRadius.circular(4)),
                          child: Text(
                            expansionDirectionLabel(l, d.tag),
                            style: context.mmText.footnote.copyWith(color: c.onResearch),
                          ),
                        ),
                      if (d.page != null) ...[
                        if (d.tag != ExpansionDirection.auto) const SizedBox(width: 6),
                        Container(
                          height: MMSizes.mapDraftTag,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: c.fill,
                            borderRadius: BorderRadius.circular(MMRadii.mapDraftTag),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(MMIcons.document, size: 10, color: c.secondaryLabel),
                              const SizedBox(width: 3),
                              Text('p.${d.page}', style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DraftBorder extends RoundedRectangleBorder {
  const _DraftBorder({required this.color}) : super(borderRadius: const BorderRadius.all(Radius.circular(12)));
  final Color color;
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final path = getOuterPath(rect, textDirection: textDirection);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (var n = 0.0; n < metric.length; n += 7) {
        canvas.drawPath(metric.extractPath(n, (n + 4).clamp(0, metric.length)), paint);
      }
    }
  }
}

class ExpansionBar extends ConsumerWidget {
  const ExpansionBar({super.key, required this.studySetId, required this.onKeep});
  final String studySetId;
  final VoidCallback onKeep;
  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;
      final s = ref.watch(expansionControllerProvider(studySetId));
      if (s == null) return const SizedBox.shrink();
      final controller = ref.read(expansionControllerProvider(studySetId).notifier),
          l = context.l10n,
          c = context.mmColors;
      final currentModel = ref.watch(assistantServicesProvider).value?.configuration;
      final local = ref
          .watch(enabledAssistantModelsProvider)
          .values
          .expand((models) => models)
          .where((m) => m.provider == AssistantProvider.ollama && m.localEnabled)
          .firstOrNull;
      final generating = s.phase == ExpansionPhase.generating, error = s.phase == ExpansionPhase.error;
      String failure() => s.failure?.code == 'incompleteDepth'
          ? l.mapIdeaIncompleteDepth
          : switch (s.failure?.kind) {
              ResearchFailureKind.network => l.assistantErrorNetwork,
              ResearchFailureKind.authentication => l.assistantErrorKey,
              ResearchFailureKind.budget => l.assistantErrorBudget,
              _ => l.assistantErrorFailed,
            };
      Future<void> adjust() async {
        var request = s.request;
        final result = await showDialog<ExpansionRequest>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              content: SizedBox(
                width: MMSizes.ideaAdjustWidth,
                child: ExpansionOptions(request: request, onChanged: (r) => update(() => request = r)),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
                TextButton(onPressed: () => Navigator.pop(context, request), child: Text(l.mapIdeaRegenerateAdjusted)),
              ],
            ),
          ),
        );
        if (result != null) await controller.regenerate(result);
      }

      return Material(
        color: c.glassOpaque,
        borderRadius: BorderRadius.circular(24),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error
                        ? failure()
                        : s.phase == ExpansionPhase.stopped
                        ? (s.failure?.code == 'incompleteDepth' ? l.mapIdeaIncompleteDepth : l.mapIdeaStopped)
                        : generating
                        ? l.mapIdeaDraftCount(s.drafts.length)
                        : l.mapIdeaKeptCount(s.selectedCount, s.drafts.length),
                    style: context.mmText.callout,
                  ),
                ),
                const SizedBox(width: 8),
                if (s.failure != null && !error)
                  Tooltip(
                    message: failure(),
                    child: Icon(MMIcons.warning, size: 14, color: c.critical),
                  ),
                if (generating)
                  TextButton(onPressed: controller.stop, child: Text('${l.assistantStop}  Esc'))
                else ...[
                  _BarAction(
                    compact: compact,
                    onPressed: s.isApplying ? null : () => controller.regenerate(),
                    label: error ? l.assistantRetry : l.mapIdeaRegenerate,
                    icon: MMIcons.history,
                  ),
                  if (error && currentModel?.provider != AssistantProvider.ollama && local?.serviceId != null)
                    TextButton(
                      onPressed: () async {
                        await ref
                            .read(assistantServicesProvider.notifier)
                            .setDefault(ModelReference(local!.serviceId!, local.model));
                        await controller.regenerate();
                      },
                      child: Text(l.assistantUseLocal),
                    ),
                  if (!error)
                    _BarAction(
                      compact: compact,
                      onPressed: s.isApplying ? null : adjust,
                      label: l.mapIdeaAdjust,
                      icon: MMIcons.adjust,
                    ),
                  _BarAction(
                    compact: compact,
                    onPressed: s.isApplying ? null : controller.discard,
                    label: l.mapIdeaDiscard,
                    icon: MMIcons.close,
                  ),
                  if (!error)
                    FilledButton(
                      onPressed: s.isApplying || s.selectedCount == 0 ? null : onKeep,
                      style: FilledButton.styleFrom(backgroundColor: c.research, foregroundColor: c.onResearch),
                      child: Text('${l.mapIdeaKeep(s.selectedCount)}  ↩'),
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Reuses the preview geometry without inserting anything into persisted content.
class ExpansionWorking extends StatefulWidget {
  const ExpansionWorking({super.key, this.placeholder = false, this.animate = true});
  final bool placeholder, animate;
  @override
  State<ExpansionWorking> createState() => _ExpansionWorkingState();
}

class _ExpansionWorkingState extends State<ExpansionWorking> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: MMMotion.pulse);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(ExpansionWorking old) {
    super.didUpdateWidget(old);
    _update();
  }

  void _update() {
    if (widget.animate && !MMAppearance.reduceMotionOf(context)) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final c = context.mmColors, t = _pulse.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: widget.placeholder ? Color.lerp(c.researchWash, c.researchTint, t) : null,
              borderRadius: BorderRadius.circular(MMRadii.card),
              border: widget.placeholder ? null : Border.all(color: c.research, width: 2),
              boxShadow: widget.placeholder ? null : [BoxShadow(color: c.researchTint, spreadRadius: 6 + 4 * t)],
            ),
            child: widget.placeholder
                ? CustomPaint(
                    painter: DashedBorderPainter(color: c.research, radius: MMRadii.card, dash: 4, gap: 3),
                    child: const SizedBox.expand(),
                  )
                : null,
          );
        },
      ),
    ),
  );
}

class _BarAction extends StatelessWidget {
  const _BarAction({required this.compact, required this.onPressed, required this.label, required this.icon});
  final bool compact;
  final VoidCallback? onPressed;
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => compact
      ? MMIconButton(
          size: MMInput.touchInputOf(context) ? 44 : 30,
          iconSize: 14,
          icon: icon,
          tooltip: label,
          onPressed: onPressed,
        )
      : TextButton(onPressed: onPressed, child: Text(label));
}

class ExpansionDraftControls extends StatelessWidget {
  const ExpansionDraftControls({
    super.key,
    required this.draft,
    required this.onToggle,
    required this.onEdit,
    this.onMore,
  });
  final ExpansionDraft draft;
  final VoidCallback onToggle, onEdit;
  final VoidCallback? onMore;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final size = MMInput.touchInputOf(context) ? 44.0 : 22.0;
    return MMGlass(
      padding: const EdgeInsets.all(1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MMIconButton(
            size: size,
            iconSize: 14,
            icon: draft.kept ? MMIcons.close : MMIcons.check,
            tooltip: draft.kept ? l.mapIdeaDraftSkip : l.mapIdeaDraftKeep,
            onPressed: onToggle,
          ),
          MMIconButton(size: size, iconSize: 14, icon: MMIcons.pen, tooltip: l.mapIdeaDraftEdit, onPressed: onEdit),
          if (onMore != null)
            MMIconButton(size: size, iconSize: 14, icon: MMIcons.ai, tooltip: l.mapIdeaDraftMore, onPressed: onMore),
        ],
      ),
    );
  }
}

class ExpansionPlanSheet extends ConsumerWidget {
  const ExpansionPlanSheet({super.key, required this.studySetId});
  final String studySetId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(expansionControllerProvider(studySetId))!;
    final controller = ref.read(expansionControllerProvider(studySetId).notifier);
    final content = ref.read(workspaceProvider(studySetId).notifier).content;
    final l = context.l10n, c = context.mmColors;
    final busy =
        ref.watch(expansionBusyProvider) ||
        ref.watch(assistantControllerProvider).running ||
        ref.watch(assistantBackgroundProvider) != null;
    final total = [
      for (var i = 0; i < s.planItems.length; i++)
        if (!s.disabledPlan.contains(i)) s.planItems[i].add + (s.planItems[i].title == null ? 0 : 1),
    ].fold(0, (a, b) => a + b);
    return TapRegion(
      onTapOutside: (_) => controller.discard(),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): controller.discard,
          const SingleActivator(LogicalKeyboardKey.enter): () => controller.startPlan(),
        },
        child: Focus(
          autofocus: true,
          child: Material(
            key: const ValueKey('expansion-plan'),
            color: Colors.transparent,
            child: MMGlass(
              borderRadius: BorderRadius.circular(MMRadii.dropdown),
              child: SizedBox(
                width: MMSizes.ideaPlanWidth,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(MMIcons.network, size: 16, color: c.research),
                          const SizedBox(width: 8),
                          Expanded(child: Text(l.mapIdeaWholeMap, style: context.mmText.headline)),
                          MMIconButton(icon: MMIcons.close, tooltip: l.cancel, onPressed: controller.discard),
                        ],
                      ),
                      if (s.phase == ExpansionPhase.planning)
                        const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())
                      else if (s.phase == ExpansionPhase.error)
                        Row(
                          children: [
                            Icon(MMIcons.warning, size: 16, color: c.critical),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.failure?.kind == ResearchFailureKind.network
                                    ? l.assistantErrorNetwork
                                    : l.assistantErrorFailed,
                              ),
                            ),
                            TextButton(onPressed: () => controller.regenerate(), child: Text(l.assistantRetry)),
                          ],
                        )
                      else ...[
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                for (var i = 0; i < s.planItems.length; i++)
                                  SizedBox(
                                    height: MMSizes.ideaPlanRow,
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: !s.disabledPlan.contains(i),
                                          activeColor: c.research,
                                          onChanged: (v) => controller.updatePlan(i, enabled: v),
                                        ),
                                        Expanded(
                                          child: Text(
                                            s.planItems[i].title ?? researchCardTitle(content, s.planItems[i].targetId),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        MMIconButton(
                                          size: MMSizes.ideaStepperButton.width,
                                          iconSize: 12,
                                          key: ValueKey('plan-minus-$i'),
                                          icon: MMIcons.zoomOut,
                                          tooltip: l.mapIdeaFewer,
                                          onPressed: s.disabledPlan.contains(i) || s.planItems[i].add == 1
                                              ? null
                                              : () => controller.updatePlan(i, add: s.planItems[i].add - 1),
                                        ),
                                        SizedBox(
                                          width: 28,
                                          child: Center(child: Text(l.mapIdeaAddCount(s.planItems[i].add))),
                                        ),
                                        MMIconButton(
                                          size: MMSizes.ideaStepperButton.width,
                                          iconSize: 12,
                                          key: ValueKey('plan-plus-$i'),
                                          icon: MMIcons.zoomIn,
                                          tooltip: l.mapIdeaMore,
                                          onPressed: s.disabledPlan.contains(i) || s.planItems[i].add == 8
                                              ? null
                                              : () => controller.updatePlan(i, add: s.planItems[i].add + 1),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l.mapIdeaAddCount(total),
                                style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
                              ),
                            ),
                            TextButton(onPressed: controller.discard, child: Text(l.cancel)),
                            FilledButton(
                              onPressed: total == 0 || busy ? null : () => controller.startPlan(),
                              style: FilledButton.styleFrom(backgroundColor: c.research, foregroundColor: c.onResearch),
                              child: Text(l.mapIdeaStart),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
