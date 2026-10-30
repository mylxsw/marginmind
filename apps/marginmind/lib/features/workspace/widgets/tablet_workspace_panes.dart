import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';

enum _Slot { content, panel, handle }

/// Keeps both panes mounted while the companion opens, resizes or rotates.
/// Unlike a modal drawer, the document always remains interactive.
class TabletWorkspacePanes extends StatelessWidget {
  const TabletWorkspacePanes({
    super.key,
    required this.content,
    required this.panel,
    required this.axis,
    required this.extent,
    required this.onResize,
  });

  final Widget content;
  final Widget? panel;
  final Axis axis;
  final double extent;
  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final chrome = MMChromeInsets.of(context);
    return CustomMultiChildLayout(
      delegate: _TabletPanesLayout(axis: axis, extent: extent, top: chrome.top, bottom: chrome.bottom),
      children: [
        LayoutId(
          id: _Slot.content,
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            identifier: 'tablet-workspace-content',
            child: content,
          ),
        ),
        if (panel != null) ...[
          LayoutId(
            id: _Slot.handle,
            child: Semantics(
              label: context.l10n.resizeCompanionPanel,
              onIncrease: axis == Axis.vertical ? () => onResize(44) : null,
              onDecrease: axis == Axis.vertical ? () => onResize(-44) : null,
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('tablet-panel-resize'),
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: axis == Axis.vertical ? (d) => onResize(-d.delta.dy) : null,
                child: Center(
                  child: Container(
                    width: axis == Axis.vertical ? 36 : 1,
                    height: axis == Axis.vertical ? 4 : double.infinity,
                    decoration: BoxDecoration(color: c.separator, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
            ),
          ),
          LayoutId(
            id: _Slot.panel,
            child: MMChromeInsets.remove(
              context,
              removeTop: true,
              removeBottom: true,
              child: Container(
                key: const ValueKey('tablet-workspace-panel'),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: c.windowBackground,
                  borderRadius: BorderRadius.circular(MMRadii.sidebar),
                  border: Border.all(color: c.separator, width: .5),
                ),
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  identifier: 'tablet-workspace-panel',
                  child: panel,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TabletPanesLayout extends MultiChildLayoutDelegate {
  _TabletPanesLayout({required this.axis, required this.extent, required this.top, required this.bottom});
  final Axis axis;
  final double extent, top, bottom;

  @override
  void performLayout(Size size) {
    final open = hasChild(_Slot.panel);
    final vertical = axis == Axis.vertical;
    final available = vertical ? size.height - top - bottom : size.width;
    final panel = open ? extent.clamp(0.0, (available - 44).clamp(0.0, double.infinity)) : 0.0;
    final handle = open ? 44.0 : 0.0;
    layoutChild(
      _Slot.content,
      BoxConstraints.tight(
        Size(
          vertical ? size.width : (size.width - panel - handle).clamp(0.0, double.infinity),
          vertical ? (size.height - panel - handle).clamp(0.0, double.infinity) : size.height,
        ),
      ),
    );
    positionChild(_Slot.content, Offset.zero);
    if (!open) return;
    layoutChild(
      _Slot.panel,
      BoxConstraints.tight(
        Size(
          vertical ? size.width - 16 : panel,
          vertical ? panel : (size.height - top - bottom - 16).clamp(0.0, double.infinity),
        ),
      ),
    );
    positionChild(
      _Slot.panel,
      vertical ? Offset(8, size.height - bottom - panel) : Offset(size.width - panel, top + 8),
    );
    layoutChild(
      _Slot.handle,
      BoxConstraints.tight(
        Size(
          vertical ? size.width : handle,
          vertical ? handle : (size.height - top - bottom).clamp(0.0, double.infinity),
        ),
      ),
    );
    positionChild(
      _Slot.handle,
      vertical ? Offset(0, size.height - bottom - panel - handle) : Offset(size.width - panel - handle, top),
    );
  }

  @override
  bool shouldRelayout(_TabletPanesLayout old) =>
      axis != old.axis || extent != old.extent || top != old.top || bottom != old.bottom;
}
