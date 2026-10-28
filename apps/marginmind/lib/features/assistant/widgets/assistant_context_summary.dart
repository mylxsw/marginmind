import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../assistant_controller.dart';
import 'assistant_messages.dart' show contextIcon, contextLabel;

/// One quiet line for the next question's references. Expand only to manage
/// them; excluded automatic references stay here so they can be restored.
class AssistantContextSummary extends StatefulWidget {
  const AssistantContextSummary({super.key, required this.items, required this.outgoing, required this.onChange});

  final List<ContextItem> items, outgoing;
  final ValueChanged<ContextItem> onChange;

  @override
  State<AssistantContextSummary> createState() => _AssistantContextSummaryState();
}

class _AssistantContextSummaryState extends State<AssistantContextSummary> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final outgoing = widget.outgoing;
    final count = l.assistantContextCount(outgoing.length);
    final preview = outgoing
        .map(
          (item) => switch (item.kind) {
            ContextKind.page => l.assistantCurrentPage(item.page ?? 1),
            ContextKind.selection => l.assistantSelectionContext,
            _ => contextLabel(l, item),
          },
        )
        .join(' · ')
        .replaceAll(RegExp(r'\s+'), ' ');
    final labels = outgoing.map((item) => contextLabel(l, item)).join('\n');
    return Padding(
      padding: const EdgeInsets.all(MMSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            expanded: _expanded,
            child: MMInteractive(
              key: const ValueKey('assistant-context-summary'),
              onTap: () => setState(() => _expanded = !_expanded),
              semanticLabel: '$count, $labels',
              tooltip: labels.isEmpty ? l.assistantManageContexts : '${l.assistantManageContexts}\n$labels',
              builder: (context, s) => Container(
                height: MMSizes.field,
                padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s),
                decoration: BoxDecoration(
                  color: s.hovered || s.focused ? c.hover : Colors.transparent,
                  borderRadius: BorderRadius.circular(MMRadii.row),
                ),
                child: Row(
                  children: [
                    Icon(
                      outgoing.length == 1 ? contextIcon(outgoing.first) : MMIcons.link,
                      size: MMSpacing.m,
                      color: c.secondaryLabel,
                    ),
                    const SizedBox(width: MMSpacing.s),
                    Expanded(
                      child: Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.footnote.copyWith(color: c.secondaryLabel),
                      ),
                    ),
                    const SizedBox(width: MMSpacing.s),
                    Text(count, style: t.footnote.copyWith(color: c.secondaryLabel)),
                    const SizedBox(width: MMSpacing.xs),
                    Icon(_expanded ? MMIcons.chevronUp : MMIcons.chevronDown, size: MMSpacing.m, color: c.icon),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: MMSpacing.xs),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: MMSizes.field * 4),
                child: SingleChildScrollView(
                  key: const ValueKey('assistant-context-list'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final item in widget.items)
                        _ContextRow(
                          key: ValueKey('context-chip-${item.id}'),
                          item: item,
                          included: outgoing.any((c) => c.id == item.id),
                          onChange: () => widget.onChange(item),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ContextRow extends StatelessWidget {
  const _ContextRow({super.key, required this.item, required this.included, required this.onChange});

  final ContextItem item;
  final bool included;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final l = context.l10n;
    final label = contextLabel(l, item);
    final row = SizedBox(
      height: MMSizes.field,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s),
        child: Row(
          children: [
            Icon(contextIcon(item), size: MMSpacing.m, color: c.icon),
            const SizedBox(width: MMSpacing.s),
            Expanded(
              child: Tooltip(
                message: label,
                child: Text(
                  label.replaceAll(RegExp(r'\s+'), ' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.mmText.callout.copyWith(
                    color: c.secondaryLabel,
                    decoration: included ? null : TextDecoration.lineThrough,
                  ),
                ),
              ),
            ),
            const SizedBox(width: MMSpacing.s),
            if (item.auto) ...[
              Text(l.assistantAutoContext, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
              const SizedBox(width: MMSpacing.s),
              MMCheckbox(value: included, color: c.research, semanticLabel: label, onChanged: null),
            ] else
              MMIconButton(
                key: ValueKey('context-remove-${item.id}'),
                icon: MMIcons.close,
                iconSize: MMSpacing.m,
                size: MMSizes.field,
                color: c.secondaryLabel,
                tooltip: '${l.assistantRemoveContext} · $label',
                onPressed: onChange,
              ),
          ],
        ),
      ),
    );
    if (!item.auto) return row;
    return Semantics(
      checked: included,
      child: MMInteractive(
        key: ValueKey('context-remove-${item.id}'),
        onTap: onChange,
        isButton: false,
        semanticLabel: '$label, ${l.assistantAutoContext}',
        builder: (context, s) => DecoratedBox(
          decoration: BoxDecoration(
            color: s.hovered || s.focused ? c.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(MMRadii.row),
          ),
          child: row,
        ),
      ),
    );
  }
}
