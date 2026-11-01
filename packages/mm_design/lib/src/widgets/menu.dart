import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/interactive.dart';
import '../foundation/adaptive.dart';
import '../foundation/back_handler.dart';
import '../icons/mm_icons.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'glass.dart';

/// An entry in a context menu: [MMMenuItem] or [MMMenuDivider].
sealed class MMMenuEntry {
  const MMMenuEntry();
}

class MMMenuItem extends MMMenuEntry {
  const MMMenuItem(
    this.label,
    this.onSelected, {
    this.destructive = false,
    this.shortcut,
    this.checked,
    this.disabledReason,
    this.badge,
  });

  final String label;
  final String? disabledReason;

  /// Non-null leaves a check column: true shows the mark (pop-up buttons,
  /// the model menu).
  final bool? checked;

  /// Null disables the item.
  final VoidCallback? onSelected;

  /// Red label, for delete / remove.
  final bool destructive;

  /// Shown right-aligned in secondary text, e.g. "⌘L".
  final String? shortcut;

  /// Optional inline tag shown beside [label] (e.g. [MMBetaBadge]).
  final Widget? badge;
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
/// and then runs the item's callback. A compact window shows an action
/// sheet at the bottom instead.
/// With [anchor], opens above the button with right edges aligned (4 px gap),
/// falling below it when there is no room above, and staying inside the window.
Future<void> showMMMenu(
  BuildContext context, {
  required Offset position,
  required List<MMMenuEntry> entries,
  double minWidth = 190,
  Rect? anchor,
}) async {
  final touch = MMInput.touchInputOf(context);
  final sheet = MMSizeClass.of(context) == MMSizeClass.compact;
  final host = context.findAncestorStateOfType<_MMContextMenuHostState>();
  if (touch && host != null) {
    final selected = await host.show(position, entries, minWidth, actionSheet: sheet, anchor: anchor);
    selected?.call();
    return;
  }
  final capturedThemes = InheritedTheme.capture(from: context, to: Navigator.of(context, rootNavigator: true).context);
  final selected = await showGeneralDialog<VoidCallback>(
    context: context,
    routeSettings: const RouteSettings(name: _contextMenuRoute),
    barrierDismissible: true,
    barrierColor: sheet ? context.mmColors.scrim : Colors.transparent,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: MMMotion.popup,
    pageBuilder: (context, _, _) => capturedThemes.wrap(
      CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop()},
        child: FocusScope(
          autofocus: true,
          child: sheet
              ? _ActionSheet(entries: entries, onSelected: (selected) => Navigator.of(context).pop(selected))
              : CustomSingleChildLayout(
                  delegate: _MenuLayout(position, anchor: anchor),
                  child: SingleChildScrollView(
                    child: _Menu(entries: entries, minWidth: minWidth, touch: touch),
                  ),
                ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
  );
  selected?.call();
}

const _contextMenuRoute = 'marginmind-context-menu';

/// A menu item's secondary text and why it is unavailable, read after its name.
String? _semanticDetail(String? detail, String? disabledReason) {
  final parts = [?detail, ?disabledReason];
  return parts.isEmpty ? null : parts.join(', ');
}

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
  Rect? _anchor;
  List<MMMenuEntry> _entries = const [];
  double _minWidth = 190;
  bool _actionSheet = false;

  bool get isOpen => _result != null;

  Future<VoidCallback?> show(
    Offset position,
    List<MMMenuEntry> entries,
    double minWidth, {
    bool actionSheet = false,
    Rect? anchor,
  }) {
    close();
    _actionSheet = actionSheet;
    _position = position;
    _anchor = anchor;
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

  bool _back() {
    if (!isOpen) return false;
    close();
    return true;
  }

  @override
  Widget build(BuildContext context) => MMBackHandler(
    onBack: _back,
    child: OverlayPortal(
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
                  color: _actionSheet ? context.mmColors.scrim : null,
                  semanticsLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
                ),
              ),
              Positioned.fill(
                child: _actionSheet
                    ? _ActionSheet(entries: _entries, onSelected: close)
                    : CustomSingleChildLayout(
                        delegate: _MenuLayout(_position, anchor: _anchor),
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
    ),
  );
}

class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout(this.position, {this.anchor});

  final Offset position;
  final Rect? anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => anchor == null
      ? constraints.loosen()
      : BoxConstraints(
          maxWidth: (constraints.maxWidth - 16).clamp(0, double.infinity),
          maxHeight: (constraints.maxHeight - 16).clamp(0, double.infinity),
        );

  /// Opens down-right of the pointer, flipping when it would leave the window.
  @override
  Offset getPositionForChild(Size size, Size child) {
    if (anchor case final button?) {
      final x = button.right - child.width;
      var y = button.top - child.height - 4;
      if (y < 8) y = button.bottom + 4;
      return Offset(x.clamp(8, size.width - child.width - 8), y.clamp(8, size.height - child.height - 8));
    }
    var x = position.dx;
    var y = position.dy;
    if (x + child.width > size.width - 8) x = (x - child.width).clamp(8, size.width);
    if (y + child.height > size.height - 8) y = (y - child.height).clamp(8, size.height);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MenuLayout old) => old.position != position || old.anchor != anchor;
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
          color: c.surface.withValues(alpha: 0.92),
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
    return Tooltip(
      message: enabled ? '' : item.disabledReason ?? '',
      child: MMInteractive(
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
        semanticValue: _semanticDetail(item.shortcut, enabled ? null : item.disabledReason),
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
                  flex: 3,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.body.copyWith(color: fg),
                        ),
                      ),
                      if (item.badge != null) ...[const SizedBox(width: 6), item.badge!],
                    ],
                  ),
                ),
                if (item.shortcut != null) ...[
                  const SizedBox(width: 24),
                  // Long notes (a model name) give way before the label does.
                  Flexible(
                    flex: 2,
                    child: Text(
                      item.shortcut!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body.copyWith(color: highlighted ? c.onAccent : c.secondaryLabel),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A context menu as an action sheet: the items in one rounded group above
/// a separate Cancel, at the bottom of the window. [onSelected] receives
/// the chosen callback, or null for Cancel.
class _ActionSheet extends StatelessWidget {
  const _ActionSheet({required this.entries, required this.onSelected});

  final List<MMMenuEntry> entries;
  final ValueChanged<VoidCallback?> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final rows = <Widget?>[
      for (final e in entries)
        switch (e) {
          MMMenuItem() => _ActionSheetRow(
            label: e.label,
            checked: e.checked,
            destructive: e.destructive,
            badge: e.badge,
            detail: e.shortcut,
            disabledReason: e.disabledReason,
            onTap: e.onSelected == null ? null : () => onSelected(e.onSelected),
          ),
          MMMenuHeader(:final label) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: MMSpacing.l, vertical: MMSpacing.m),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
            ),
          ),
          MMMenuDivider() => null,
        },
    ].nonNulls.toList();
    const radius = BorderRadius.all(Radius.circular(14));
    Widget group(Widget child) => Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.surface, borderRadius: radius),
      child: child,
    );
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        minimum: const EdgeInsets.all(MMSpacing.s),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              key: const ValueKey('mm-action-sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: group(
                    SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, row) in rows.indexed) ...[
                            if (i > 0) Container(height: 0.5, color: c.separator),
                            row,
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: MMSpacing.s),
                group(
                  _ActionSheetRow(
                    label: MaterialLocalizations.of(context).cancelButtonLabel,
                    bold: true,
                    onTap: () => onSelected(null),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionSheetRow extends StatelessWidget {
  const _ActionSheetRow({
    required this.label,
    required this.onTap,
    this.checked,
    this.destructive = false,
    this.bold = false,
    this.badge,
    this.detail,
    this.disabledReason,
  });

  final String label;

  /// The menu item's right-aligned secondary text, kept in the sheet.
  final String? detail;
  final String? disabledReason;
  final VoidCallback? onTap;
  final bool? checked;
  final bool destructive;
  final bool bold;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MMInteractive(
      onTap: onTap,
      semanticLabel: label,
      semanticValue: _semanticDetail(detail, onTap == null ? disabledReason : null),
      builder: (context, s) {
        final fg = !s.enabled
            ? c.secondaryLabel
            : destructive
            ? c.critical
            : c.accent;
        return Container(
          height: MMSizes.actionSheetRow,
          color: s.pressed || s.focused ? c.pressed : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: MMSpacing.l),
          child: Row(
            children: [
              SizedBox(width: 20, child: checked ?? false ? Icon(MMIcons.check, size: 16, color: fg) : null),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.mmText.title3.copyWith(
                          color: fg,
                          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (badge != null) ...[const SizedBox(width: 6), badge!],
                  ],
                ),
              ),
              if (detail != null)
                Flexible(
                  child: Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
                  ),
                )
              else
                const SizedBox(width: 20),
            ],
          ),
        );
      },
    );
  }
}
