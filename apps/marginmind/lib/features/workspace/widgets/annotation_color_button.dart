import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../settings/highlight_palette.dart';
import '../../../shared/l10n.dart';
import '../../assistant/widgets/assistant_overlays.dart' show boundsOf, inScope;
import '../workspace_controller.dart';
import 'annotation_line_style_picker.dart';
import 'annotation_palette.dart';
import 'highlight_custom_color_picker.dart';

/// The color circle owns settings only; tool selection remains on the pens.
class AnnotationColorButton extends ConsumerStatefulWidget {
  const AnnotationColorButton({
    super.key,
    required this.studySetId,
    required this.color,
    this.annotationId,
    this.underline = false,
    this.compact = false,
    this.enabled = true,
    this.onOpenChanged,
  });

  final String studySetId;
  final MMAnnotationColor color;
  final String? annotationId;
  final bool underline, compact, enabled;
  final ValueChanged<bool>? onOpenChanged;

  @override
  ConsumerState<AnnotationColorButton> createState() => _AnnotationColorButtonState();
}

class _AnnotationColorButtonState extends ConsumerState<AnnotationColorButton> {
  final _overlay = OverlayPortalController();
  final _anchor = GlobalKey();
  final _paletteFocus = FocusScopeNode();
  bool _open = false, _custom = false, _busy = false;
  List<MMAnnotationColor> _colors = const [];
  FocusNode? _previousFocus;

  WorkspaceController get _controller => ref.read(workspaceProvider(widget.studySetId).notifier);

  @override
  void dispose() {
    _paletteFocus.dispose();
    super.dispose();
  }

  void _close() {
    if (!_open) return;
    _overlay.hide();
    setState(() => _open = false);
    widget.onOpenChanged?.call(false);
    if (_previousFocus?.context != null) _previousFocus!.requestFocus();
  }

  void _toggle() {
    if (_open) return _close();
    _previousFocus = FocusManager.instance.primaryFocus;
    _colors = ref.read(highlightPaletteProvider).recent(limit: 4);
    setState(() {
      _open = true;
      _custom = false;
    });
    widget.onOpenChanged?.call(true);
    _overlay.show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open) _paletteFocus.requestFocus();
    });
  }

  Future<void> _change({MMAnnotationColor? color, AnnotationLineStyle? style}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (color != null) await _controller.setAnnotationColor(color, annotationId: widget.annotationId);
      if (style != null) {
        await _controller.styleUnderline(
          annotationId: widget.annotationId,
          color: widget.color,
          style: style,
          shareColor: true,
        );
      }
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong, icon: MMIcons.close);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _more() async {
    if (_custom || _busy) return;
    _custom = true;
    try {
      final anchor = boundsOf(_anchor.currentContext!);
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
            delegate: AnnotationPalettePlacement(anchor),
            child: Material(
              type: MaterialType.transparency,
              child: SingleChildScrollView(
                child: HighlightCustomColorPicker(
                  current: widget.color,
                  onSelected: (color) => Navigator.of(context).pop(color),
                  onCancel: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ),
      );
      if (mounted && picked != null) {
        await _change(color: picked);
        if (mounted) setState(() => _colors = ref.read(highlightPaletteProvider).recent(limit: 4));
      }
    } finally {
      _custom = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider(widget.studySetId));
    final annotation = state.content?.annotation(widget.annotationId ?? '');
    final style = annotation?.lineStyle ?? state.underlineStyle;
    final colors = [..._colors];
    if (colors.isEmpty) colors.add(widget.color);
    final l = context.l10n, c = context.mmColors;
    return OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: (context) => CustomSingleChildLayout(
        delegate: AnnotationPalettePlacement(boundsOf(_anchor.currentContext!)),
        child: TapRegion(
          groupId: annotationTapGroup(widget.studySetId),
          onTapOutside: (_) {
            if (!_custom) _close();
          },
          child: CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
            child: FocusScope(
              node: _paletteFocus,
              autofocus: true,
              child: Material(
                type: MaterialType.transparency,
                child: SingleChildScrollView(
                  key: const ValueKey('annotation-color-palette'),
                  scrollDirection: Axis.horizontal,
                  child: MMFloatingToolbar(
                    children: [
                      for (final color in colors)
                        MMFloatingToolbarColor(
                          color: color,
                          tooltip: l.colorName(color),
                          selected: color == widget.color,
                          onPressed: _busy ? null : () => _change(color: color),
                        ),
                      AnnotationMoreColorsButton(onPressed: _busy ? null : _more),
                      if (widget.underline) ...[
                        const MMToolbarDivider(),
                        AnnotationLineStylePicker(
                          value: style,
                          onChanged: _busy ? null : (v) => _change(style: v),
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
      child: MMInteractive(
        key: _anchor,
        tooltip: l.galleryColors,
        semanticLabel: '${l.galleryColors}: ${l.colorName(widget.color)}',
        onTap: widget.enabled ? _toggle : null,
        builder: (context, s) {
          final size = widget.compact && !context.mmTouch ? const Size(30, 26) : context.mmToolbarButton;
          return Container(
            width: size.width,
            height: size.height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: s.hovered || s.pressed ? c.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(MMRadii.capsuleButton),
              border: s.focused ? Border.all(color: c.accent, width: 2) : null,
            ),
            child: Container(
              key: const ValueKey('annotation-current-color'),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.enabled ? widget.color.color : widget.color.color.withValues(alpha: .3),
              ),
            ),
          );
        },
      ),
    );
  }
}
