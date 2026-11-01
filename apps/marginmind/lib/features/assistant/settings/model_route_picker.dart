import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';

/// A model's display name and its service name: live from [catalog], else
/// the routing snapshot, else the IDs. Never matched by name.
(String service, String model) routeModelNames(
  AssistantServices catalog,
  ModelReference model, {
  String? serviceLabel,
  String? modelLabel,
}) {
  final service = catalog.services.where((s) => s.id == model.serviceId).firstOrNull;
  final entry = service?.models.where((m) => m.id == model.modelId).firstOrNull;
  return (service?.name ?? serviceLabel ?? model.serviceId, entry?.displayName ?? modelLabel ?? model.modelId);
}

/// The one rule for naming a routed model: “Service · Model” when the model's
/// display name appears in two or more services, the model name otherwise.
String routeModelLabel(AssistantServices catalog, ModelReference model, {String? serviceLabel, String? modelLabel}) {
  final (service, name) = routeModelNames(catalog, model, serviceLabel: serviceLabel, modelLabel: modelLabel);
  final services = {
    for (final s in catalog.services)
      if (s.models.any((m) => m.displayName == name)) s.id,
  }..add(model.serviceId);
  return services.length > 1 ? '$service · $name' : name;
}

/// What a picker button shows: its colour says where the value comes from.
enum ModelRouteTone {
  /// Bound to this row: primary label colour.
  explicit,

  /// Follows a default: the effective model in secondary colour.
  inherited,

  /// Needs attention (no model yet, or a model that cannot run as asked).
  caution,

  /// The reference no longer resolves: the old name, struck through.
  invalid,
}

/// One model in a picker menu, with why it cannot be chosen (disabled) or a
/// note such as “Unverified”.
class ModelRouteOption {
  const ModelRouteOption({required this.model, required this.label, this.disabledReason, this.note});
  final ModelReference model;
  final String label;
  final String? disabledReason, note;
}

/// One service's enabled models, in the Models page's order.
class ModelRouteGroup {
  const ModelRouteGroup(this.service, this.options);
  final String service;
  final List<ModelRouteOption> options;
}

/// The model menus for AI Features, task setup panels and run panels: the
/// value is a `(serviceId, modelId)` reference, never a name or an index.
class ModelRoutePicker extends StatelessWidget {
  const ModelRoutePicker({
    super.key,
    required this.label,
    required this.tone,
    required this.groups,
    required this.selected,
    required this.onChanged,
    required this.semanticLabel,
    required this.semanticValue,
    this.followLabel,
    this.followNote,
    this.tooltip,
    this.reasoning,
    this.reasoningOptions = const {},
    this.onReasoningChanged,
    this.focusNode,
    this.highlighted = false,
    this.maxWidth = 260,
  });

  /// The button text: the effective model (or a placeholder).
  final String label;
  final ModelRouteTone tone;
  final List<ModelRouteGroup> groups;

  /// The explicit choice; null when the row follows [followLabel].
  final ModelReference? selected;

  /// Null value means “follow”. Null disables the picker.
  final ValueChanged<ModelReference?>? onChanged;

  /// The first menu item (“Use Default” / “Use Setting”); omitted when null.
  final String? followLabel;

  /// Right-aligned on the follow item: the model it currently resolves to.
  final String? followNote;
  final String? tooltip;
  final String semanticLabel, semanticValue;

  /// A thinking section below the models, listed only for an explicit choice.
  final ReasoningPolicy? reasoning;
  final Set<ReasoningPolicy> reasoningOptions;
  final ValueChanged<ReasoningPolicy>? onReasoningChanged;
  final FocusNode? focusNode;

  /// Located from elsewhere (“Assign…”): an accent wash behind the button.
  final bool highlighted;
  final double maxWidth;

  bool get _enabled => onChanged != null;

  Future<void> open(BuildContext context) {
    final l = context.l10n;
    final box = context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final change = onChanged!;
    final thinking = selected != null && onReasoningChanged != null && reasoningOptions.isNotEmpty;
    return showMMMenu(
      context,
      position: anchor.bottomLeft + const Offset(0, 2),
      minWidth: box.size.width < 220 ? 220 : box.size.width,
      entries: [
        if (followLabel != null) ...[
          MMMenuItem(followLabel!, () => change(null), checked: selected == null, shortcut: followNote),
          if (groups.isNotEmpty) const MMMenuDivider(),
        ],
        for (final (i, group) in groups.indexed) ...[
          if (i > 0) const MMMenuDivider(),
          MMMenuHeader(group.service),
          for (final option in group.options)
            MMMenuItem(
              option.label,
              option.disabledReason == null ? () => change(option.model) : null,
              checked: option.model == selected,
              shortcut: option.disabledReason ?? option.note,
              disabledReason: option.disabledReason,
            ),
        ],
        if (thinking) ...[
          const MMMenuDivider(),
          MMMenuHeader(l.aiTasksThinking),
          for (final value in ReasoningPolicy.values)
            if (reasoningOptions.contains(value))
              MMMenuItem(reasoningLabel(l, value), () => onReasoningChanged!(value), checked: value == reasoning),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final color = !_enabled
        ? c.secondaryLabel
        : switch (tone) {
            ModelRouteTone.explicit => c.label,
            ModelRouteTone.inherited || ModelRouteTone.invalid => c.secondaryLabel,
            ModelRouteTone.caution => c.caution,
          };
    final button = Builder(
      builder: (context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (_enabled && event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
            open(context);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MMInteractive(
          focusNode: focusNode,
          onTap: _enabled ? () => open(context) : null,
          semanticLabel: semanticLabel,
          semanticValue: semanticValue,
          builder: (context, s) => MMControlFrame(
            child: AnimatedContainer(
              duration: MMMotion.quick,
              constraints: BoxConstraints(maxWidth: maxWidth),
              height: context.mmTouchPlatform ? MMSizes.tabletControlVisual : 22,
              padding: const EdgeInsets.only(left: MMSpacing.s, right: MMSpacing.xs),
              decoration: BoxDecoration(
                color: highlighted
                    ? c.accentTint
                    : s.hovered
                    ? c.fill
                    : c.quaternaryFill,
                borderRadius: BorderRadius.circular(context.mmTouchPlatform ? MMRadii.field : 6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body.copyWith(
                        color: color,
                        decoration: tone == ModelRouteTone.invalid ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: MMSpacing.xs),
                  Icon(MMIcons.chevronUpDown, size: context.mmTouchPlatform ? 13 : 11, color: c.icon),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

String reasoningLabel(AppLocalizations l, ReasoningPolicy value) => switch (value) {
  ReasoningPolicy.auto => l.aiTasksThinkingAuto,
  ReasoningPolicy.off => l.aiTasksThinkingOff,
  ReasoningPolicy.standard => l.aiTasksThinkingStandard,
  ReasoningPolicy.deep => l.aiTasksThinkingDeep,
};
