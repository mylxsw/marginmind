import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'annotation_color_button.dart';

/// One color circle followed by two mutually exclusive text marker buttons.
class TextAnnotationTools extends ConsumerStatefulWidget {
  const TextAnnotationTools({
    super.key,
    required this.studySetId,
    this.selectionAction = false,
    this.compact = false,
    this.enabled = true,
    this.onOpenChanged,
    this.colorOnly = false,
  });

  final String studySetId;
  final bool selectionAction, compact, enabled, colorOnly;
  final ValueChanged<bool>? onOpenChanged;

  @override
  ConsumerState<TextAnnotationTools> createState() => _TextAnnotationToolsState();
}

class _TextAnnotationToolsState extends ConsumerState<TextAnnotationTools> {
  bool _busy = false;

  Future<void> _select(AnnotationTool tool) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
      await controller.applyPendingTextAnnotation(tool);
      if (!widget.selectionAction) await controller.setTool(tool);
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong, icon: MMIcons.close);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider(widget.studySetId));
    final id = widget.selectionAction && state.pending is PendingHighlight
        ? (state.pending as PendingHighlight).annotationId
        : null;
    final annotation = state.content?.annotation(id ?? '');
    final tool = annotation == null
        ? (widget.selectionAction && state.tool != AnnotationTool.underline ? AnnotationTool.highlight : state.tool)
        : annotation.kind == AnnotationKind.underline
        ? AnnotationTool.underline
        : AnnotationTool.highlight;
    final l = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnnotationColorButton(
          key: const ValueKey('annotation-color'),
          studySetId: widget.studySetId,
          color: annotation == null ? state.color : MMAnnotationColor.fromIndex(annotation.colorIndex),
          annotationId: id,
          underline: tool == AnnotationTool.underline,
          compact: widget.compact,
          enabled: widget.enabled && !_busy,
          onOpenChanged: widget.onOpenChanged,
        ),
        if (!widget.colorOnly) ...[
          MMToolbarButton(
            key: ValueKey(widget.selectionAction ? 'selection-highlight' : 'reader-highlight'),
            icon: MMIcons.highlight,
            tooltip: l.toolHighlight,
            compact: widget.compact,
            selected: tool == AnnotationTool.highlight,
            onPressed: widget.enabled && !_busy ? () => _select(AnnotationTool.highlight) : null,
          ),
          MMToolbarButton(
            key: ValueKey(widget.selectionAction ? 'selection-underline' : 'reader-underline'),
            icon: MMIcons.underline,
            tooltip: l.toolUnderline,
            compact: widget.compact,
            selected: tool == AnnotationTool.underline,
            onPressed: widget.enabled && !_busy ? () => _select(AnnotationTool.underline) : null,
          ),
        ],
      ],
    );
  }
}
