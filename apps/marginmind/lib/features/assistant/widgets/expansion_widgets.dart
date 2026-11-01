import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../assistant_controller.dart';
import '../../workspace/workspace_controller.dart';
import '../../research/research_origin.dart' show researchCardTitle;
import '../assistant_services.dart';
import '../expansion_controller.dart';
import '../map_task_route.dart';
import '../settings/ai_task_status.dart';
import '../../workspace/widgets/map_source_chip.dart';
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
  const ExpansionOptions({super.key, required this.request, required this.onChanged, this.showModel = true});
  final ExpansionRequest request;
  final ValueChanged<ExpansionRequest> onChanged;
  final bool showModel;
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
    final directionColumns = l.localeName == 'zh' ? 3 : 2;
    TableRow row(String label, Widget control, {bool top = false, bool last = false}) => TableRow(
      children: [
        TableCell(
          verticalAlignment: top ? TableCellVerticalAlignment.top : TableCellVerticalAlignment.middle,
          child: Padding(
            padding: EdgeInsets.only(right: 12, top: top ? 7 : 0, bottom: last ? 0 : 18),
            child: Text(label, softWrap: false, style: context.mmText.callout.copyWith(color: c.secondaryLabel)),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: last ? 0 : 18),
          child: control,
        ),
      ],
    );
    return Table(
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        if (showModel)
          row(context.l10n.aiTasksModel, MapTaskRoute(studySetId: request.studySetId, type: TaskType.mapExpand)),
        row(
          l.mapIdeaDirection,
          Column(
            children: [
              for (var start = 0; start < ExpansionDirection.values.length; start += directionColumns) ...[
                if (start > 0) const SizedBox(height: 6),
                Row(
                  children: [
                    for (var i = start; i < start + directionColumns; i++) ...[
                      if (i > start) const SizedBox(width: 6),
                      Expanded(child: _direction(context, ExpansionDirection.values[i], change)),
                    ],
                  ],
                ),
              ],
            ],
          ),
          top: true,
        ),
        row(
          l.mapIdeaDepth,
          MMSegmentedControl<int>(
            expand: true,
            key: const ValueKey('expansion-depth'),
            value: request.depth,
            onChanged: (n) => change(depth: n),
            segments: [for (var n = 1; n <= 3; n++) MMSegment(value: n, label: l.mapIdeaDepthLevels(n))],
          ),
        ),
        row(
          l.mapIdeaAmount,
          MMSegmentedControl<int>(
            expand: true,
            key: const ValueKey('expansion-amount'),
            value: request.breadth,
            onChanged: (n) => change(breadth: n),
            segments: [
              for (final (n, label) in [(3, l.mapIdeaAmountFew), (5, l.mapIdeaAmountSome), (8, l.mapIdeaAmountMany)])
                MMSegment(value: n, label: label),
            ],
          ),
          last: true,
        ),
      ],
    );
  }

  Widget _direction(
    BuildContext context,
    ExpansionDirection direction,
    void Function({ExpansionDirection? direction, int? depth, int? breadth}) change,
  ) {
    final c = context.mmColors;
    final selected = direction == request.direction;
    final label = expansionDirectionLabel(context.l10n, direction);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: MMInteractive(
        key: ValueKey('expansion-direction-${direction.name}'),
        semanticLabel: label,
        tooltip: label,
        selected: selected,
        onTap: () => change(direction: direction),
        builder: (context, state) => Container(
          height: context.mmTouch ? MMSizes.touchTarget : 30,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? c.research : (state.hovered ? c.hover : Colors.transparent),
            border: selected ? null : Border.all(color: c.line, width: .5),
            borderRadius: BorderRadius.circular(MMRadii.row),
            boxShadow: state.focused ? [BoxShadow(color: c.research.withValues(alpha: .3), spreadRadius: 2)] : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.mmText.footnote.copyWith(color: selected ? c.onResearch : c.secondaryLabel),
          ),
        ),
      ),
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
    required this.onClose,
    this.compact = false,
  });
  final VoidCallback onClose;
  final bool compact;
  final String studySetId, mapId, targetId;
  final List<String>? targetIds;
  @override
  ConsumerState<ExpansionSection> createState() => _ExpansionSectionState();
}

class _ExpansionSectionState extends ConsumerState<ExpansionSection> {
  late ExpansionRequest _request;
  String _hint = '';
  bool _grounded = true, _hintFocused = false;
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
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): widget.onClose},
      child: FocusScope(
        autofocus: true,
        child: Material(
          key: const ValueKey('expansion-settings'),
          color: c.glassOpaque,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: c.separator, width: .5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (widget.compact)
                      MMIconButton(
                        key: const ValueKey('expansion-back'),
                        icon: MMIcons.chevronLeft,
                        tooltip: l.back,
                        onPressed: widget.onClose,
                        size: 24,
                      )
                    else
                      Icon(
                        widget.targetId == widget.mapId ? MMIcons.mindMap : MMIcons.expandIdeas,
                        size: 16,
                        color: c.research,
                      ),
                    const SizedBox(width: MMSpacing.s),
                    Expanded(
                      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.mmText.headline),
                    ),
                    if (!widget.compact) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(6)),
                        child: Text('⌥⇥', style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
                      ),
                      const SizedBox(width: MMSpacing.s),
                    ],
                    MMIconButton(
                      key: const ValueKey('expansion-close'),
                      icon: MMIcons.close,
                      tooltip: l.closePanel,
                      onPressed: widget.onClose,
                      size: 24,
                    ),
                  ],
                ),
                Divider(height: 28, color: c.separator, thickness: .5),
                Flexible(
                  child: SingleChildScrollView(
                    child: ExcludeFocus(
                      excluding: busy,
                      child: IgnorePointer(
                        ignoring: busy,
                        child: Opacity(
                          opacity: busy ? .45 : 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ExpansionOptions(request: _request, onChanged: (r) => setState(() => _request = r)),
                              const SizedBox(height: 22),
                              Focus(
                                canRequestFocus: false,
                                onFocusChange: (focused) => setState(() => _hintFocused = focused),
                                child: Container(
                                  key: const ValueKey('expansion-hint'),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: _hintFocused ? c.research : c.line, width: .5),
                                    borderRadius: BorderRadius.circular(MMRadii.row),
                                  ),
                                  child: MMTextField(
                                    plain: true,
                                    maxLength: 200,
                                    placeholder: l.mapIdeaHint,
                                    semanticLabel: l.mapIdeaHint,
                                    onChanged: (v) => _hint = v,
                                    onSubmitted: (_) => _start(),
                                  ),
                                ),
                              ),
                              if (widget.targetId == widget.mapId) ...[
                                const SizedBox(height: MMSpacing.s),
                                MMButton(
                                  label: l.mapIdeaBranchesOnly,
                                  variant: MMButtonVariant.plain,
                                  onPressed: busy ? null : () => _start(branchesOnly: true),
                                ),
                              ],
                              if ((widget.targetIds?.length ?? 1) > 1) ...[
                                const SizedBox(height: MMSpacing.s),
                                for (final (scope, label) in [
                                  (ExpansionScope.group, l.mapIdeaGroup),
                                  (ExpansionScope.siblings, l.mapIdeaFillSiblings),
                                ])
                                  Tooltip(
                                    message: _commonParent == null ? l.mapEditDifferentParents : '',
                                    child: MMButton(
                                      label: label,
                                      variant: MMButtonVariant.plain,
                                      onPressed: _commonParent == null || busy ? null : () => _start(scope: scope),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Divider(height: 28, color: c.separator, thickness: .5),
                Row(
                  children: [
                    MMSwitch(
                      value: _grounded,
                      semanticLabel: l.mapIdeaGrounded,
                      color: c.research,
                      onChanged: busy ? null : (v) => setState(() => _grounded = v),
                    ),
                    const SizedBox(width: MMSpacing.xs),
                    Expanded(
                      child: Text(l.mapIdeaGrounded, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
                    ),
                    MMInteractive(
                      key: const ValueKey('expansion-start'),
                      onTap: busy ? null : () => _start(),
                      autofocus: true,
                      semanticLabel: title,
                      builder: (context, state) => Opacity(
                        opacity: state.enabled ? 1 : .45,
                        child: Container(
                          height: context.mmTouch ? MMSizes.touchTarget : 32,
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
                              Text(l.mapIdeaGenerate, style: context.mmText.headline.copyWith(color: c.onResearch)),
                              const SizedBox(width: MMSpacing.s),
                              Icon(MMIcons.returnKey, size: 12, color: c.onResearch.withValues(alpha: .7)),
                            ],
                          ),
                        ),
                      ),
                    ),
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

class MapGhostNode extends StatefulWidget {
  const MapGhostNode({
    super.key,
    required this.draft,
    required this.focused,
    required this.generating,
    required this.onToggle,
    this.onToggleWithUndo,
    required this.onEdit,
    required this.onMore,
    this.onHover,
    this.sourceChip,
    this.onEditingChanged,
  });
  final ExpansionDraft draft;
  final Widget? sourceChip;
  final bool focused, generating;
  final VoidCallback onToggle;

  /// Restores exactly what the first click changed when a second click edits.
  /// Required for hierarchical selections, where toggling twice is not inverse.
  final VoidCallback? Function()? onToggleWithUndo;
  final ValueChanged<String> onEdit;
  final VoidCallback? onMore;
  final ValueChanged<bool>? onHover;
  final VoidCallback? onEditingChanged;
  @override
  State<MapGhostNode> createState() => MapGhostNodeState();
}

class MapGhostNodeState extends State<MapGhostNode> {
  TextEditingController? _text;
  final _editFocus = FocusNode();
  String? _toggledDraftId;
  VoidCallback? _undoToggle;

  void _toggle() {
    _toggledDraftId = widget.draft.id;
    if (widget.onToggleWithUndo != null) {
      _undoToggle = widget.onToggleWithUndo!();
    } else {
      widget.onToggle();
    }
  }

  void _doubleEdit() {
    // The first click is immediate. A second click restores that click's
    // reversible draft toggle before opening the editor.
    if (_toggledDraftId == widget.draft.id) {
      if (widget.onToggleWithUndo != null) {
        _undoToggle?.call();
      } else {
        widget.onToggle();
      }
    }
    _undoToggle = null;
    _toggledDraftId = null;
    beginEdit();
  }

  bool get editing => _text != null;
  void beginEdit() {
    if (widget.generating || _text != null) return;
    setState(
      () =>
          _text = TextEditingController(text: widget.draft.title)
            ..selection = TextSelection(baseOffset: 0, extentOffset: widget.draft.title.length),
    );
    widget.onEditingChanged?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && editing) _editFocus.requestFocus();
    });
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
    _editFocus.dispose();
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
      label: d.page != null
          ? l.mapGenerateDraftSemantics(d.title, d.page!, d.kept ? l.mapIdeaDraftKept : l.mapIdeaDraftSkipped)
          : l.mapIdeaDraftSemantics(d.title, d.kept ? l.mapIdeaDraftKept : l.mapIdeaDraftSkipped),
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
          onLongPressStart: widget.generating || editing
              ? null
              : (details) => showMMMenu(
                  context,
                  position: details.globalPosition,
                  entries: [
                    MMMenuItem(d.kept ? l.mapIdeaDraftSkip : l.mapIdeaDraftKeep, widget.onToggle, icon: MMIcons.skip),
                    MMMenuItem(l.mapIdeaDraftEdit, beginEdit, icon: MMIcons.editNote),
                    if (widget.onMore != null) MMMenuItem(l.mapIdeaDraftMore, widget.onMore, icon: MMIcons.expandIdeas),
                  ],
                ),
          child: MMInteractive(
            immediateTap: true,
            onTap: widget.generating || editing ? null : _toggle,
            onDoubleTap: widget.generating || editing ? null : _doubleEdit,
            canRequestFocus: false,
            builder: (_, _) => Container(
              decoration: BoxDecoration(
                color: d.kept ? Color.alphaBlend(c.researchWash, c.canvas) : c.canvas,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [if (widget.focused) BoxShadow(color: c.research, spreadRadius: 2)],
              ),
              foregroundDecoration: ShapeDecoration(shape: _DraftBorder(color: d.kept ? c.research : c.line)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_text != null)
                    CallbackShortcuts(
                      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => _finish(false)},
                      child: TextField(
                        autofocus: true,
                        focusNode: _editFocus,
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
                          widget.sourceChip ?? MapSourceChip(page: d.page!),
                        ],
                      ],
                    ),
                ],
              ),
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
      final currentRoute = ref.watch(mapTaskRouteProvider((studySetId, TaskType.mapExpand))).value;
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
                child: ExpansionOptions(
                  request: request,
                  showModel: false,
                  onChanged: (r) => update(() => request = r),
                ),
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
                TickerMode(
                  enabled: !MMAppearance.reduceMotionOf(context),
                  child: RunStatusCapsule(
                    status: generating
                        ? RunStatus.running
                        : error
                        ? RunStatus.failed
                        : s.phase == ExpansionPhase.stopped
                        ? (s.failure == null ? RunStatus.cancelled : RunStatus.partial)
                        : RunStatus.awaitingUser,
                    unfinished: s.targetFailures.length,
                  ),
                ),
                const SizedBox(width: 8),
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
                  if (error && currentRoute?.effective?.serviceId != local?.serviceId && local?.serviceId != null)
                    TextButton(
                      onPressed: () async {
                        ref
                            .read(mapTaskChoicesProvider.notifier)
                            .select(
                              mapRouteKey(studySetId, TaskType.mapExpand),
                              ModelReference(local!.serviceId!, local.model),
                            );
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
                      child: Text(l.mapIdeaKeep(s.selectedCount)),
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
                          Icon(MMIcons.mindMap, size: 16, color: c.research),
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
