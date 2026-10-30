import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart' show ModelReference;
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../assistant_controller.dart';
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
        direction: direction ?? request.direction,
        depth: depth ?? request.depth,
        breadth: breadth ?? request.breadth,
        grounded: request.grounded,
        hint: request.hint,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final d in ExpansionDirection.values)
              Semantics(
                inMutuallyExclusiveGroup: true,
                checked: d == request.direction,
                child: ChoiceChip(
                  label: Text(expansionDirectionLabel(l, d)),
                  selected: d == request.direction,
                  onSelected: (_) => change(direction: d),
                  selectedColor: context.mmColors.researchWash,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        Row(
          children: [
            Text(l.mapIdeaDepth),
            const Spacer(),
            for (var n = 1; n <= 3; n++)
              TextButton(
                onPressed: () => change(depth: n),
                child: Text(
                  l.mapIdeaDepthLevels(n),
                  style: TextStyle(
                    color: request.depth == n ? context.mmColors.research : context.mmColors.secondaryLabel,
                  ),
                ),
              ),
          ],
        ),
        Row(
          children: [
            Text(l.mapIdeaAmount),
            const Spacer(),
            for (final (n, label) in [(3, l.mapIdeaAmountFew), (5, l.mapIdeaAmountSome), (8, l.mapIdeaAmountMany)])
              TextButton(
                onPressed: () => change(breadth: n),
                child: Text(
                  label,
                  style: TextStyle(
                    color: request.breadth == n ? context.mmColors.research : context.mmColors.secondaryLabel,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class ExpansionSection extends ConsumerStatefulWidget {
  const ExpansionSection({super.key, required this.studySetId, required this.mapId, required this.targetId});
  final String studySetId, mapId, targetId;
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

  void _start() {
    if (ref.read(assistantControllerProvider.notifier).busy ||
        ref.read(expansionControllerProvider(widget.studySetId)) != null) {
      return;
    }
    final controller = ref.read(expansionControllerProvider(widget.studySetId).notifier);
    final request = controller.request(
      widget.mapId,
      widget.targetId,
      direction: _request.direction,
      depth: _request.depth,
      breadth: _request.breadth,
      grounded: _grounded,
      hint: String.fromCharCodes(_hint.runes.take(200)),
    );
    Navigator.of(context).pop();
    controller.start(request);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, c = context.mmColors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.researchWash, borderRadius: BorderRadius.circular(MMRadii.ideaSection)),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: MMSizes.ideaPrimaryButton,
            child: FilledButton.icon(
              onPressed: ref.watch(expansionBusyProvider) ? null : _start,
              icon: const Icon(MMIcons.expandIdeas, size: 16),
              label: Text('${l.mapIdeaExpand}  ⌥⇥'),
              style: FilledButton.styleFrom(backgroundColor: c.research, foregroundColor: c.onResearch),
            ),
          ),
          ExpansionOptions(request: _request, onChanged: (r) => setState(() => _request = r)),
          TextField(
            maxLength: 200,
            decoration: InputDecoration(hintText: l.mapIdeaHint, counterText: '', isDense: true),
            onChanged: (v) => _hint = v,
            onSubmitted: (_) => _start(),
          ),
          Row(
            children: [
              Text(l.mapIdeaGrounded),
              const Spacer(),
              Switch(value: _grounded, onChanged: (v) => setState(() => _grounded = v)),
            ],
          ),
        ],
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
                      if (d.page != null) Text('  ${l.pageNumber(d.page!)}', style: context.mmText.footnote),
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
      String failure() => switch (s.failure?.kind) {
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
                        ? l.mapIdeaStopped
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
