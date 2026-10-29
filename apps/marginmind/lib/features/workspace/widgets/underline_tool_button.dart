import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../settings/highlight_palette.dart';
import '../../../shared/l10n.dart';
import '../../assistant/widgets/assistant_overlays.dart' show boundsOf, inScope;
import '../workspace_controller.dart';
import 'annotation_palette.dart';
import 'highlight_custom_color_picker.dart';
import 'underline_style_toolbar.dart';

Object annotationTapGroup(String studySetId) => ValueKey('annotation-tools-$studySetId');

/// Non-modal: settings stay open while choosing colors/styles, and clicks
/// outside still reach the reader. The target id is captured once per opening.
class UnderlineToolButton extends ConsumerStatefulWidget {
  const UnderlineToolButton({
    super.key,
    required this.studySetId,
    this.compact = false,
    this.enabled = true,
    this.selectionAction = false,
    this.onOpenChanged,
    this.onApplied,
  });

  final String studySetId;
  final bool compact, selectionAction, enabled;
  final ValueChanged<bool>? onOpenChanged;
  final VoidCallback? onApplied;

  @override
  ConsumerState<UnderlineToolButton> createState() => _UnderlineToolButtonState();
}

class _UnderlineToolButtonState extends ConsumerState<UnderlineToolButton> {
  final _overlay = OverlayPortalController();
  final _anchor = GlobalKey();
  bool _open = false, _busy = false, _custom = false;
  String? _targetId;
  FocusNode? _previousFocus;

  WorkspaceController get _controller => ref.read(workspaceProvider(widget.studySetId).notifier);

  void _close({bool exit = false}) {
    if (!_open) return;
    _overlay.hide();
    setState(() => _open = false);
    widget.onOpenChanged?.call(false);
    if (_previousFocus?.context != null) _previousFocus!.requestFocus();
    if (exit) _controller.setTool(AnnotationTool.select);
    if (widget.selectionAction && _targetId != null) widget.onApplied?.call();
    _targetId = null;
  }

  Future<void> _show() async {
    if (_busy) return;
    if (_open) {
      _close();
      return;
    }
    _previousFocus = FocusManager.instance.primaryFocus;
    setState(() {
      _open = true;
      _busy = true;
    });
    widget.onOpenChanged?.call(true);
    try {
      final controller = _controller;
      final state = ref.read(workspaceProvider(widget.studySetId));
      _targetId = null;
      switch (state.pending) {
        case PendingSelection(:final documentId, :final selection):
          _targetId = await controller.underline(
            documentId,
            selection,
            keepPending: widget.selectionAction,
            addToMap: !widget.selectionAction && state.syncToMap,
          );
        case PendingHighlight(:final annotationId):
          final annotation = controller.content.annotation(annotationId);
          if (annotation != null && annotation.quote.isNotEmpty) {
            _targetId = annotationId;
            await controller.styleUnderline(
              annotationId: annotationId,
              color: MMAnnotationColor.fromIndex(annotation.colorIndex),
              style: annotation.kind == AnnotationKind.underline ? annotation.lineStyle : state.underlineStyle,
            );
          }
        case null:
        case PendingResearchNote():
          break;
      }
      if (!widget.selectionAction) await controller.setTool(AnnotationTool.underline);
      if (mounted && _open) _overlay.show();
    } catch (_) {
      if (mounted) {
        _close();
        MMHud.show(context, context.l10n.somethingWentWrong, icon: MMIcons.close);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change({MMAnnotationColor? color, AnnotationLineStyle? style}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final state = ref.read(workspaceProvider(widget.studySetId));
      final annotation = state.content?.annotation(_targetId ?? '');
      await _controller.styleUnderline(
        annotationId: _targetId,
        color:
            color ?? (annotation == null ? state.underlineColor : MMAnnotationColor.fromIndex(annotation.colorIndex)),
        style: style ?? annotation?.lineStyle ?? state.underlineStyle,
      );
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong, icon: MMIcons.close);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _more(MMAnnotationColor color) async {
    if (_custom || _busy) return;
    _custom = true;
    try {
      final picked = await showGeneralDialog<MMAnnotationColor>(
        context: context,
        barrierColor: Colors.transparent,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
        transitionDuration: MMAppearance.duration(context, MMMotion.quick),
        transitionBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
        pageBuilder: (_, _, _) => inScope(
          context,
          CustomSingleChildLayout(
            delegate: AnnotationPalettePlacement(boundsOf(_anchor.currentContext!)),
            child: Material(
              type: MaterialType.transparency,
              child: SingleChildScrollView(
                child: HighlightCustomColorPicker(
                  current: color,
                  onSelected: (v) => Navigator.of(context).pop(v),
                  onCancel: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ),
      );
      if (mounted && picked != null) await _change(color: picked);
    } finally {
      _custom = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider(widget.studySetId));
    ref.listen(workspaceProvider(widget.studySetId).select((s) => s.tool), (_, tool) {
      if (!widget.selectionAction && _open && tool != AnnotationTool.underline) _close();
    });
    ref.listen(workspaceProvider(widget.studySetId).select((s) => s.pending), (_, pending) {
      if (!widget.selectionAction && _open && !_busy && pending != null) _close();
    });
    final pendingId = widget.selectionAction && state.pending is PendingHighlight
        ? (state.pending as PendingHighlight).annotationId
        : null;
    final annotation = state.content?.annotation(_targetId ?? pendingId ?? '');
    final color = annotation == null ? state.underlineColor : MMAnnotationColor.fromIndex(annotation.colorIndex);
    final style = annotation?.lineStyle ?? state.underlineStyle;
    final selected =
        _open ||
        (!widget.selectionAction && state.tool == AnnotationTool.underline) ||
        (widget.selectionAction &&
            switch (state.pending) {
              PendingHighlight(:final annotationId) =>
                state.content?.annotation(annotationId)?.kind == AnnotationKind.underline,
              _ => false,
            });
    final colors = {...ref.watch(highlightPaletteProvider).recent()};
    if (!colors.contains(color)) {
      if (colors.length >= 3) colors.remove(colors.last);
      colors.add(color);
    }
    return OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: (context) => CustomSingleChildLayout(
        delegate: AnnotationPalettePlacement(boundsOf(_anchor.currentContext!)),
        child: TapRegion(
          groupId: annotationTapGroup(widget.studySetId),
          onTapOutside: (_) {
            if (!_custom && !_busy) _close();
          },
          child: CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => _close(exit: true)},
            child: FocusScope(
              autofocus: true,
              child: Material(
                type: MaterialType.transparency,
                child: UnderlineStyleToolbar(
                  key: const ValueKey('underline-style-toolbar'),
                  color: color,
                  style: style,
                  colors: colors.toList(),
                  onColor: _busy ? null : (v) => _change(color: v),
                  onStyle: _busy ? null : (v) => _change(style: v),
                  onMore: () => _more(color),
                  onClose: _close,
                ),
              ),
            ),
          ),
        ),
      ),
      child: TapRegion(
        groupId: annotationTapGroup(widget.studySetId),
        child: MMToolbarButton(
          key: _anchor,
          icon: MMIcons.underline,
          tooltip: context.l10n.toolUnderline,
          compact: widget.compact,
          selected: selected,
          tint: selected ? color.color : null,
          onPressed: widget.enabled ? _show : null,
        ),
      ),
    );
  }
}
