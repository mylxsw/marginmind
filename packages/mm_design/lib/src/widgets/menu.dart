import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/interactive.dart';
import '../foundation/adaptive.dart';
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
  final touch = MMInput.touchInputOf(context);
  final host = context.findAncestorStateOfType<_MMContextMenuHostState>();
  if (touch && host != null) {
    final selected = await host.show(position, entries, minWidth);
    selected?.call();
    return;
  }
  final selected = await showGeneralDialog<VoidCallback>(
    context: context,
    routeSettings: const RouteSettings(name: _contextMenuRoute),
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
          child: SingleChildScrollView(
            child: _Menu(entries: entries, minWidth: minWidth, touch: touch),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
  );
  selected?.call();
}

const _contextMenuRoute = 'marginmind-context-menu';

/// Dismisses an open context menu when a held pointer becomes a drag.
/// The predicate stops at every other route, including the underlying page.
void dismissMMMenu(BuildContext context) {
  final host = context.findAncestorStateOfType<_MMContextMenuHostState>();
  if (host?.isOpen ?? false) {
    host!.close();
    return;
  }
  Navigator.of(context, rootNavigator: true).popUntil((route) => route.settings.name != _contextMenuRoute);
}

/// Touch menus use a page-owned portal: pushing a route would cancel the
/// pointer that is still held on a draggable node. Disposing the page also
/// disposes its menu, focus scope and barrier.
class MMContextMenuHost extends StatefulWidget {
  const MMContextMenuHost({super.key, required this.child});
  final Widget child;

  @override
  State<MMContextMenuHost> createState() => _MMContextMenuHostState();
}

class _MMContextMenuHostState extends State<MMContextMenuHost> {
  final _portal = OverlayPortalController();
  final _focus = FocusScopeNode(debugLabel: 'Touch context menu');
  FocusNode? _previousFocus;
  Completer<VoidCallback?>? _result;
  Offset _position = Offset.zero;
  List<MMMenuEntry> _entries = const [];
  double _minWidth = 190;

  bool get isOpen => _result != null;

  Future<VoidCallback?> show(Offset position, List<MMMenuEntry> entries, double minWidth) {
    close();
    _position = position;
    _entries = entries;
    _minWidth = minWidth;
    final result = _result = Completer<VoidCallback?>();
    _previousFocus = FocusManager.instance.primaryFocus;
    _portal.show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_result, result)) _focus.requestFocus();
    });
    return result.future;
  }

  void close([VoidCallback? selected]) {
    final result = _result;
    if (result == null) return;
    _result = null;
    _portal.hide();
    final previous = _previousFocus;
    _previousFocus = null;
    if (previous?.context != null) previous!.requestFocus();
    result.complete(selected);
  }

  @override
  void dispose() {
    _result?.complete();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _portal,
    overlayChildBuilder: (context) => CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: FocusScope(
        node: _focus,
        autofocus: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: ModalBarrier(
                dismissible: true,
                onDismiss: close,
                semanticsLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
              ),
            ),
            Positioned.fill(
              child: CustomSingleChildLayout(
                delegate: _MenuLayout(_position),
                child: SingleChildScrollView(
                  child: _Menu(entries: _entries, minWidth: _minWidth, touch: true, onSelected: close),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    child: widget.child,
  );
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
  const _Menu({required this.entries, required this.minWidth, required this.touch, this.onSelected});

  final List<MMMenuEntry> entries;
  final double minWidth;
  final bool touch;
  final ValueChanged<VoidCallback>? onSelected;

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
                    MMMenuItem() => _MenuRow(item: e, autofocus: i == 0, touch: touch, onSelected: onSelected),
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
  const _MenuRow({required this.item, required this.autofocus, required this.touch, this.onSelected});

  final MMMenuItem item;
  final bool autofocus;
  final bool touch;
  final ValueChanged<VoidCallback>? onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final enabled = item.onSelected != null;
    return MMInteractive(
      onTap: !enabled
          ? null
          : () {
              if (onSelected != null) {
                onSelected!(item.onSelected!);
              } else {
                Navigator.of(context).pop(item.onSelected);
              }
            },
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
          height: touch ? 44 : 24,
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
