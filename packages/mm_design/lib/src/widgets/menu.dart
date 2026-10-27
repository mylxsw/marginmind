import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/interactive.dart';
import '../icons/mm_icons.dart';
import '../theme/mm_theme.dart';
import 'glass.dart';

/// An entry in a context menu: [MMMenuItem] or [MMMenuDivider].
sealed class MMMenuEntry {
  const MMMenuEntry();
}

class MMMenuItem extends MMMenuEntry {
  const MMMenuItem(this.label, this.onSelected, {this.destructive = false, this.shortcut, this.checked});

  final String label;

  /// Non-null leaves a check column: true shows the mark (pop-up buttons,
  /// the model menu).
  final bool? checked;

  /// Null disables the item.
  final VoidCallback? onSelected;

  /// Red label, for delete / remove.
  final bool destructive;

  /// Shown right-aligned in secondary text, e.g. "⌘L".
  final String? shortcut;
}

class MMMenuDivider extends MMMenuEntry {
  const MMMenuDivider();
}

/// A group title in secondary text, e.g. "Research “Anchoring”". Not selectable.
class MMMenuHeader extends MMMenuEntry {
  const MMMenuHeader(this.label);

  final String label;
}

/// Shows a macOS-style context menu at [position] (global coordinates).
/// Clicking outside or pressing Esc closes it; choosing an item closes it
/// and then runs the item's callback.
Future<void> showMMMenu(
  BuildContext context, {
  required Offset position,
  required List<MMMenuEntry> entries,
  double minWidth = 190,
}) async {
  final selected = await showGeneralDialog<VoidCallback>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: const Duration(milliseconds: 90),
    pageBuilder: (context, _, _) => CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop()},
      child: FocusScope(
        autofocus: true,
        child: CustomSingleChildLayout(
          delegate: _MenuLayout(position),
          child: _Menu(entries: entries, minWidth: minWidth),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
  );
  selected?.call();
}

class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout(this.position);

  final Offset position;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  /// Opens down-right of the pointer, flipping when it would leave the window.
  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = position.dx;
    var y = position.dy;
    if (x + child.width > size.width - 8) x = (x - child.width).clamp(8, size.width);
    if (y + child.height > size.height - 8) y = (y - child.height).clamp(8, size.height);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MenuLayout old) => old.position != position;
}

class _Menu extends StatelessWidget {
  const _Menu({required this.entries, required this.minWidth});

  final List<MMMenuEntry> entries;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth, maxWidth: minWidth < 300 ? 300 : minWidth),
        child: MMGlass(
          borderRadius: BorderRadius.circular(12),
          padding: const EdgeInsets.all(5),
          color: c.glassOpaque.withValues(alpha: 0.92),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, e) in entries.indexed)
                  switch (e) {
                    MMMenuItem() => _MenuRow(item: e, autofocus: i == 0),
                    MMMenuDivider() => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      child: Container(height: 0.5, color: c.separator),
                    ),
                    MMMenuHeader(:final label) => Padding(
                      padding: const EdgeInsets.fromLTRB(9, 4, 9, 2),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.mmText.subheadline.copyWith(color: c.secondaryLabel),
                      ),
                    ),
                  },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item, required this.autofocus});

  final MMMenuItem item;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final enabled = item.onSelected != null;
    return MMInteractive(
      onTap: enabled ? () => Navigator.of(context).pop(item.onSelected) : null,
      semanticLabel: item.label,
      builder: (context, s) {
        final highlighted = s.hovered || s.focused;
        final fg = !enabled
            ? c.secondaryLabel
            : highlighted
            ? c.onAccent
            : item.destructive
            ? const Color(0xFFE5484D)
            : c.label;
        return Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: highlighted && enabled ? c.accentFill : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              if (item.checked != null)
                SizedBox(width: 20, child: item.checked! ? Icon(MMIcons.check, size: 14, color: fg) : null),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.body.copyWith(color: fg),
                ),
              ),
              if (item.shortcut != null) ...[
                const SizedBox(width: 24),
                Text(item.shortcut!, style: t.body.copyWith(color: highlighted ? c.onAccent : c.secondaryLabel)),
              ],
            ],
          ),
        );
      },
    );
  }
}
