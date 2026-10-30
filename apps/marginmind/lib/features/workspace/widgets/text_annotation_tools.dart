import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'annotation_color_button.dart';

/// Selection-only controls: a color circle and two text marker actions.
class TextAnnotationTools extends ConsumerStatefulWidget {
  const TextAnnotationTools({
    super.key,
    required this.studySetId,
    required this.onApplied,
    this.compact = false,
    this.enabled = true,
    this.onOpenChanged,
    this.colorOnly = false,
  });

  final String studySetId;
  final VoidCallback onApplied;
  final bool compact, enabled, colorOnly;
  final ValueChanged<bool>? onOpenChanged;

  @override
  ConsumerState<TextAnnotationTools> createState() => _TextAnnotationToolsState();
}

class _TextAnnotationToolsState extends ConsumerState<TextAnnotationTools> {
  AnnotationTool? _applying;
  bool get _busy => _applying != null;

  Future<void> _select(AnnotationTool tool) async {
    if (_busy) return;
    setState(() => _applying = tool);
    try {
      final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
      final pending = ref.read(workspaceProvider(widget.studySetId)).pending;
      await controller.applyPendingTextAnnotation(tool);
      if (mounted &&
          pending != null &&
          identical(ref.read(workspaceProvider(widget.studySetId)).pending?.toolbarIdentity, pending.toolbarIdentity)) {
        widget.onApplied();
      }
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong, icon: MMIcons.close);
    } finally {
      if (mounted) setState(() => _applying = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider(widget.studySetId));
    final id = state.pending is PendingHighlight ? (state.pending as PendingHighlight).annotationId : null;
    final annotation = state.content?.annotation(id ?? '');
    final tool = annotation == null
        ? (state.tool == AnnotationTool.underline ? AnnotationTool.underline : AnnotationTool.highlight)
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
            key: const ValueKey('selection-highlight'),
            icon: MMIcons.highlight,
            tooltip: l.toolHighlight,
            compact: widget.compact,
            selected: _applying == AnnotationTool.highlight,
            onPressed: widget.enabled && !_busy ? () => _select(AnnotationTool.highlight) : null,
          ),
          MMToolbarButton(
            key: const ValueKey('selection-underline'),
            icon: MMIcons.underline,
            tooltip: l.toolUnderline,
            compact: widget.compact,
            selected: _applying == AnnotationTool.underline,
            onPressed: widget.enabled && !_busy ? () => _select(AnnotationTool.underline) : null,
          ),
        ],
      ],
    );
  }
}
