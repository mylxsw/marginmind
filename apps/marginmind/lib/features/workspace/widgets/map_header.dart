import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:mm_design/mm_design.dart';

enum MapPaneSlot { canvas, header }

class MapHeaderGeometry {
  double toolbarTopInset = 60;
}

/// Measure the floating header before laying out the canvas, while painting
/// it afterward. The canvas receives the actual clearance in the same frame.
class MapPaneHeaderLayout extends MultiChildLayoutDelegate {
  MapPaneHeaderLayout(this.geometry, {required this.top, this.merged = false});
  final bool merged;
  final MapHeaderGeometry geometry;
  final double top;

  @override
  void performLayout(Size size) {
    final header = layoutChild(
      MapPaneSlot.header,
      BoxConstraints(
        maxWidth: math.max(0, size.width - (merged ? 0 : MMSpacing.m * 2)),
        maxHeight: math.max(0, size.height - top),
      ),
    );
    positionChild(MapPaneSlot.header, Offset(merged ? 0 : MMSpacing.m, top));
    geometry.toolbarTopInset = top + header.height + (merged ? 0 : MMSpacing.s);
    // Changing the reserved height also invalidates the canvas LayoutBuilder
    // when only a header child reflows (for example after a font loads).
    layoutChild(
      MapPaneSlot.canvas,
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        minHeight: math.min(size.height, geometry.toolbarTopInset),
        maxHeight: size.height,
      ),
    );
    positionChild(MapPaneSlot.canvas, Offset.zero);
  }

  @override
  bool shouldRelayout(MapPaneHeaderLayout old) => true;
}

/// Uses measured control widths, including localization and text scaling.
/// The title yields space first; commands wrap only when the controls don't fit.
class MapHeader extends MultiChildRenderObjectWidget {
  MapHeader({super.key, required Widget title, required Widget controls, Widget? commands})
    : hasCommands = commands != null,
      super(children: [title, commands ?? const SizedBox.shrink(), controls]);

  final bool hasCommands;

  @override
  RenderObject createRenderObject(BuildContext context) => _MapHeaderBox(hasCommands);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _MapHeaderBox).hasCommands = hasCommands;
  }
}

class _MapHeaderBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MultiChildLayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MultiChildLayoutParentData> {
  _MapHeaderBox(this._hasCommands);
  bool _hasCommands;
  set hasCommands(bool value) {
    if (value == _hasCommands) return;
    _hasCommands = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MultiChildLayoutParentData) child.parentData = MultiChildLayoutParentData();
  }

  void _place(RenderBox child, double x, double y) {
    (child.parentData! as MultiChildLayoutParentData).offset = Offset(x, y);
  }

  @override
  void performLayout() {
    final title = firstChild!;
    final commands = childAfter(title)!;
    final controls = childAfter(commands)!;
    final width = constraints.maxWidth;
    final loose = BoxConstraints(maxWidth: width, maxHeight: constraints.maxHeight);
    commands.layout(loose, parentUsesSize: true);
    controls.layout(loose, parentUsesSize: true);
    final minimumTitle = math.min(title.getMaxIntrinsicWidth(double.infinity), MMSizes.toolbarButton.width * 2);
    final inline = !_hasCommands || minimumTitle + commands.size.width + controls.size.width + MMSpacing.s * 2 <= width;
    if (inline) {
      final commandX = !_hasCommands
          ? width - controls.size.width
          : ((width - commands.size.width) / 2).clamp(
              minimumTitle + MMSpacing.s,
              width - controls.size.width - MMSpacing.s - commands.size.width,
            );
      title.layout(
        BoxConstraints(maxWidth: math.max(0, commandX - MMSpacing.s), maxHeight: constraints.maxHeight),
        parentUsesSize: true,
      );
      final height = math.max(title.size.height, math.max(commands.size.height, controls.size.height));
      _place(title, 0, (height - title.size.height) / 2);
      _place(commands, commandX, (height - commands.size.height) / 2);
      _place(controls, width - controls.size.width, (height - controls.size.height) / 2);
      size = constraints.constrain(Size(width, height));
      return;
    }

    final titleBesideControls = minimumTitle + MMSpacing.s + controls.size.width <= width;
    final compact = constraints.maxHeight < (controls.size.height + commands.size.height) * 2 + MMSpacing.xxxl * 2;
    final showTitle = titleBesideControls || !compact;
    title.layout(
      BoxConstraints(
        maxWidth: showTitle ? (titleBesideControls ? width - controls.size.width - MMSpacing.s : width) : 0,
        maxHeight: showTitle ? constraints.maxHeight : 0,
      ),
      parentUsesSize: true,
    );
    final titleRow = !titleBesideControls && showTitle ? title.size.height + MMSpacing.xs : 0.0;
    final firstRow = titleRow + math.max(titleBesideControls ? title.size.height : 0, controls.size.height);
    _place(title, 0, titleBesideControls ? (firstRow - title.size.height) / 2 : 0);
    _place(controls, width - controls.size.width, titleRow + (firstRow - titleRow - controls.size.height) / 2);
    _place(commands, (width - commands.size.width) / 2, firstRow + MMSpacing.s);
    size = constraints.constrain(Size(width, firstRow + MMSpacing.s + commands.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
