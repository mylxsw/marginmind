import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/providers.dart';
import '../../../settings/highlight_palette.dart';
import '../../../shared/l10n.dart';
import '../../assistant/widgets/assistant_overlays.dart' show boundsOf, inScope;
import 'highlight_custom_color_picker.dart';
import 'annotation_palette.dart';

/// One colored brush opens the palette. Picking a swatch is the only commit.
class HighlightColorButton extends ConsumerStatefulWidget {
  const HighlightColorButton({
    super.key,
    required this.color,
    required this.onChanged,
    this.selected = false,
    this.compact = false,
    this.enabled = true,
    this.onOpenChanged,
    this.onOpen,
    this.colors,
    this.mixed = false,
  }) : moreOnly = false;

  /// A fourth inline color dot that opens the full picker directly.
  const HighlightColorButton.more({
    super.key,
    required this.color,
    required this.onChanged,
    this.onOpenChanged,
    this.enabled = true,
  }) : selected = false,
       compact = false,
       onOpen = null,
       colors = null,
       mixed = false,
       moreOnly = true;

  final bool moreOnly, enabled;
  final MMAnnotationColor color;
  final Future<void> Function(MMAnnotationColor) onChanged;
  final bool selected, compact;
  final ValueChanged<bool>? onOpenChanged;
  final Future<void> Function()? onOpen;

  /// Optional palette for another annotation surface; PDF uses frequent colors.
  final List<MMAnnotationColor>? colors;
  final bool mixed;

  @override
  ConsumerState<HighlightColorButton> createState() => _HighlightColorButtonState();
}

class _HighlightColorButtonState extends ConsumerState<HighlightColorButton> {
  bool _open = false;

  Future<void> _show() async {
    if (_open) return;
    final anchor = boundsOf(context);
    final onChanged = widget.onChanged;
    setState(() => _open = true);
    widget.onOpenChanged?.call(true);
    try {
      unawaited(_openTool());
      final picked = await showGeneralDialog<MMAnnotationColor>(
        context: context,
        barrierColor: Colors.transparent,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
        transitionDuration: MMMotion.popup,
        pageBuilder: (_, _, _) => inScope(
          context,
          CustomSingleChildLayout(
            delegate: AnnotationPalettePlacement(anchor),
            child: _HighlightColors(
              current: widget.color,
              moreOnly: widget.moreOnly,
              colors: widget.colors,
              mixed: widget.mixed,
            ),
          ),
        ),
        transitionBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      );
      if (mounted && picked != null) await onChanged(picked);
    } finally {
      if (mounted) {
        setState(() => _open = false);
        widget.onOpenChanged?.call(false);
      }
    }
  }

  Future<void> _openTool() async {
    try {
      await widget.onOpen?.call();
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong, icon: MMIcons.close);
    }
  }

  @override
  Widget build(BuildContext context) => widget.moreOnly
      ? AnnotationMoreColorsButton(onPressed: widget.enabled ? _show : null)
      : MMToolbarButton(
          icon: MMIcons.highlight,
          tint: (_open || widget.selected) && !widget.mixed ? widget.color.color : null,
          tooltip: context.l10n.chooseHighlightColor,
          selected: _open || widget.selected,
          compact: widget.compact,
          onPressed: widget.enabled ? _show : null,
        );
}

class _HighlightColors extends ConsumerStatefulWidget {
  const _HighlightColors({required this.current, this.moreOnly = false, this.colors, this.mixed = false});
  final bool moreOnly;
  final MMAnnotationColor current;
  final List<MMAnnotationColor>? colors;
  final bool mixed;
  @override
  ConsumerState<_HighlightColors> createState() => _HighlightColorsState();
}

class _HighlightColorsState extends ConsumerState<_HighlightColors> {
  late bool _more = widget.moreOnly;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final palette = ref.watch(highlightPaletteProvider);
    final colors = widget.colors ?? palette.frequent(ref.read(clockProvider)());
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop()},
      child: FocusScope(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: _more
              ? SingleChildScrollView(
                  child: HighlightCustomColorPicker(
                    current: widget.current,
                    onSelected: (color) => Navigator.of(context).pop(color),
                    onCancel: () => Navigator.of(context).pop(),
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: MMFloatingToolbar(
                    key: const ValueKey('highlight-color-palette'),
                    children: [
                      for (final color in colors)
                        MMFloatingToolbarColor(
                          color: color,
                          tooltip: l.colorName(color),
                          selected: !widget.mixed && color == widget.current,
                          onPressed: () => Navigator.of(context).pop(color),
                        ),
                      AnnotationMoreColorsButton(onPressed: () => setState(() => _more = true)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
