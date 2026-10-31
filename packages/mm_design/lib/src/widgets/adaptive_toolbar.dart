import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../tokens/metrics.dart';
import '../theme/mm_theme.dart';
import 'dropdown.dart';

/// Lower priorities move into the menu first. Commands retain one identity
/// regardless of whether they are painted inline or invoked from the menu.
class MMToolbarItem {
  const MMToolbarItem({
    required this.id,
    required this.child,
    required this.menuEntry,
    this.priority = 0,
    this.compactChild,
    this.key,
  });
  final Widget? compactChild;
  final Key? key;
  final String id;
  final Widget child;
  final PopupMenuEntry<VoidCallback> menuEntry;
  final int priority;
}

/// Measures the actual controls in the layout pass, without a trial frame.
class MMAdaptiveToolbar extends StatefulWidget {
  const MMAdaptiveToolbar({
    super.key,
    required this.items,
    required this.menuLabel,
    this.menuIcon,
    this.menuKey,
    this.overflowLabel,
    this.menuBeforeId,
    this.trailingIds = const {},
    this.groups = const [],
    this.menuEntries = const [],
    this.spacing = MMSpacing.s,
    this.groupItemSpacing,
  });
  final List<MMToolbarItem> items;
  final String menuLabel;
  final Widget? menuIcon;
  final Key? menuKey;
  final String? overflowLabel;
  final String? menuBeforeId;
  final Set<String> trailingIds;
  final List<Set<String>> groups;
  final List<PopupMenuEntry<VoidCallback>> menuEntries;
  final double spacing;

  /// Optional spacing within a painted group; group boundaries keep [spacing].
  final double? groupItemSpacing;

  @override
  State<MMAdaptiveToolbar> createState() => _MMAdaptiveToolbarState();
}

class _MMAdaptiveToolbarState extends State<MMAdaptiveToolbar> {
  final _hidden = <String>{};
  final _compacted = <String>{};
  double? _width;
  bool _open = false;
  final _menuFocus = FocusNode();
  NavigatorState? _navigator;
  @override
  void dispose() {
    if (_open) {
      final navigator = _navigator;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator?.mounted == true) navigator!.popUntil((route) => route.settings.name != 'mm-dropdown');
      });
    }
    _menuFocus.dispose();
    super.dispose();
  }

  void _restoreMenuFocus() {
    final descendants = _menuFocus.descendants.where((node) => node.canRequestFocus && !node.skipTraversal);
    (descendants.isEmpty ? _menuFocus : descendants.first).requestFocus();
  }

  void _reconcileFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focus = FocusManager.instance.primaryFocus;
      if (focus != null &&
          [focus, ...focus.ancestors].any((node) => _hidden.any((id) => node.debugLabel == 'toolbar-item:$id'))) {
        _restoreMenuFocus();
      } else if (focus != null) {
        for (final node in [focus, ...focus.ancestors]) {
          final label = node.debugLabel;
          if (label == null || !label.startsWith('toolbar-variant:') || !label.endsWith(':full')) continue;
          final id = label.substring('toolbar-variant:'.length, label.length - ':full'.length);
          if (!_compacted.contains(id)) continue;
          final candidates = node.parent?.descendants.where(
            (other) => other.debugLabel == 'toolbar-variant:$id:compact',
          );
          if (candidates?.isNotEmpty == true) {
            final targets = candidates!.first.descendants.where(
              (target) => target.canRequestFocus && !target.skipTraversal,
            );
            if (targets.isNotEmpty) targets.first.requestFocus();
          }
          break;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_width != null && _width != constraints.maxWidth && _open) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _open) {
            Navigator.of(context).popUntil((route) => route.settings.name != 'mm-dropdown');
            _restoreMenuFocus();
          }
        });
      }
      _navigator = Navigator.of(context);
      _width = constraints.maxWidth;
      return FocusTraversalGroup(
        policy: _VisibleToolbarTraversal(_hidden, _compacted),
        child: _ToolbarLayout(
          ids: [for (final item in widget.items) item.id],
          priorities: [for (final item in widget.items) item.priority],
          hidden: _hidden,
          compacted: _compacted,
          spacing: widget.spacing,
          groupItemSpacing: widget.groupItemSpacing,
          menuBeforeId: widget.menuBeforeId,
          trailingIds: widget.trailingIds,
          groups: widget.groups,
          groupColor: context.mmColors.quaternaryFill,
          onLayout: _reconcileFocus,
          children: [
            for (final item in widget.items)
              Focus(
                key: item.key,
                debugLabel: 'toolbar-item:${item.id}',
                skipTraversal: true,
                child: item.compactChild == null
                    ? item.child
                    : _ToolbarVariant(
                        children: [
                          Focus(debugLabel: 'toolbar-variant:${item.id}:full', skipTraversal: true, child: item.child),
                          Focus(
                            debugLabel: 'toolbar-variant:${item.id}:compact',
                            skipTraversal: true,
                            child: item.compactChild!,
                          ),
                        ],
                      ),
              ),
            Focus(
              focusNode: _menuFocus,
              skipTraversal: true,
              child: MMDropdownButton<VoidCallback>(
                key: widget.menuKey,
                onOpened: () => _open = true,
                onClosed: () => _open = false,
                tooltip: widget.menuLabel,
                icon: widget.menuIcon,
                width: MMSizes.readerZoomMenuWidth,
                itemBuilder: (_) => [
                  if (_hidden.isNotEmpty && widget.overflowLabel != null)
                    MMDropdownHeader<VoidCallback>(widget.overflowLabel!),
                  for (final item in widget.items)
                    if (_hidden.contains(item.id)) item.menuEntry,
                  if (_hidden.isNotEmpty && widget.overflowLabel != null && widget.menuEntries.isNotEmpty)
                    const PopupMenuDivider(),
                  ...widget.menuEntries,
                ],
                onSelected: (command) => command(),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _VisibleToolbarTraversal extends WidgetOrderTraversalPolicy {
  _VisibleToolbarTraversal(this.hidden, this.compacted);
  final Set<String> hidden, compacted;
  @override
  Iterable<FocusNode> sortDescendants(Iterable<FocusNode> descendants, FocusNode currentNode) => super
      .sortDescendants(descendants, currentNode)
      .where(
        (node) => ![node, ...node.ancestors].any(
          (ancestor) =>
              hidden.any((id) => ancestor.debugLabel == 'toolbar-item:$id') ||
              (ancestor.debugLabel?.startsWith('toolbar-variant:') == true &&
                  (ancestor.debugLabel!.endsWith(':full')
                      ? compacted.contains(ancestor.debugLabel!.split(':')[1])
                      : !compacted.contains(ancestor.debugLabel!.split(':')[1]))),
        ),
      );
}

class _ToolbarLayout extends MultiChildRenderObjectWidget {
  const _ToolbarLayout({
    required this.ids,
    required this.priorities,
    required this.hidden,
    required this.compacted,
    required this.spacing,
    required this.groupItemSpacing,
    required this.menuBeforeId,
    required this.trailingIds,
    required this.groups,
    required this.groupColor,
    required this.onLayout,
    required super.children,
  });
  final List<String> ids;
  final List<int> priorities;
  final Set<String> hidden, compacted;
  final double spacing;
  final double? groupItemSpacing;
  final String? menuBeforeId;
  final Set<String> trailingIds;
  final List<Set<String>> groups;
  final Color groupColor;
  final VoidCallback onLayout;
  @override
  RenderObject createRenderObject(BuildContext context) => _ToolbarBox(
    ids,
    priorities,
    hidden,
    compacted,
    spacing,
    groupItemSpacing,
    menuBeforeId,
    trailingIds,
    groups,
    groupColor,
    onLayout,
  );
  @override
  void updateRenderObject(BuildContext context, _ToolbarBox renderObject) {
    renderObject
      ..ids = ids
      ..priorities = priorities
      ..spacing = spacing
      ..groupItemSpacing = groupItemSpacing
      ..menuBeforeId = menuBeforeId
      ..trailingIds = trailingIds
      ..groups = groups
      ..groupColor = groupColor
      ..onLayout = onLayout
      ..markNeedsLayout();
  }
}

class _ToolbarData extends ContainerBoxParentData<RenderBox> {
  bool visible = true;
}

class _ToolbarBox extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _ToolbarData>, RenderBoxContainerDefaultsMixin<RenderBox, _ToolbarData> {
  _ToolbarBox(
    this.ids,
    this.priorities,
    this.hidden,
    this.compacted,
    this.spacing,
    this.groupItemSpacing,
    this.menuBeforeId,
    this.trailingIds,
    this.groups,
    this.groupColor,
    this.onLayout,
  );
  Set<String> trailingIds;
  List<Set<String>> groups;
  Color groupColor;
  VoidCallback onLayout;
  String? menuBeforeId;
  List<String> ids;
  List<int> priorities;
  final Set<String> hidden, compacted;
  double spacing;
  double? groupItemSpacing;

  @override
  void setupParentData(RenderBox child) {
    child.parentData = _ToolbarData();
  }

  @override
  void performLayout() {
    final controls = getChildrenAsList();
    final menu = controls.last;
    final loose = BoxConstraints(maxHeight: constraints.maxHeight);
    compacted.clear();
    for (final child in controls) {
      child.layout(
        identical(child, menu)
            ? BoxConstraints(maxWidth: constraints.maxWidth, maxHeight: constraints.maxHeight)
            : loose,
        parentUsesSize: true,
      );
    }
    hidden.clear();
    final visible = List.filled(ids.length, true);
    final before = ids.indexOf(menuBeforeId ?? '');
    final indices = [
      for (var i = 0; i < ids.length; i++)
        if (i != before) i,
    ];
    if (before < 0) {
      indices.add(ids.length);
    } else {
      indices.insert(before, ids.length);
      indices.insert(before + 1, before);
    }
    double gap(int a, int b) =>
        groupItemSpacing != null &&
            a < ids.length &&
            b < ids.length &&
            groups.any((group) => group.contains(ids[a]) && group.contains(ids[b]))
        ? groupItemSpacing!
        : spacing;
    List<int> visibleIndices() => [
      for (final i in indices)
        if (i == ids.length || visible[i]) i,
    ];
    double measuredWidth(List<int> shown) {
      var result = 0.0;
      for (var position = 0; position < shown.length; position++) {
        if (position > 0) result += gap(shown[position - 1], shown[position]);
        result += controls[shown[position]].size.width;
      }
      return result;
    }

    var width = measuredWidth(visibleIndices());
    final order = List.generate(ids.length, (i) => i)..sort((a, b) => priorities[a].compareTo(priorities[b]));
    // Remove labels before moving any command out of the toolbar.
    for (final i in order) {
      if (width <= constraints.maxWidth) break;
      final variant = _variantOf(controls[i]);
      if (variant == null) continue;
      final previous = controls[i].size.width;
      controls[i].layout(loose.tighten(width: variant.compactWidth), parentUsesSize: true);
      width -= previous - controls[i].size.width;
      compacted.add(ids[i]);
    }
    for (final i in order) {
      if (width <= constraints.maxWidth) break;
      visible[i] = false;
      hidden.add(ids[i]);
      width = measuredWidth(visibleIndices());
    }
    size = constraints.constrain(
      Size(width, controls.fold<double>(0, (h, c) => h > c.size.height ? h : c.size.height)),
    );
    var x = 0.0;
    final shown = visibleIndices();
    var alignedTrailing = false;
    for (var position = 0; position < shown.length; position++) {
      final i = shown[position];
      if (position > 0) x += gap(shown[position - 1], i);
      if (!alignedTrailing &&
          ((i < ids.length && trailingIds.contains(ids[i])) || (i == ids.length && trailingIds.contains(':menu')))) {
        x = (size.width - measuredWidth(shown.sublist(position))).clamp(x, size.width);
        alignedTrailing = true;
      }
      final child = controls[i];
      final data = child.parentData! as _ToolbarData;
      data.offset = Offset(x, (size.height - child.size.height) / 2);
      x += child.size.width;
    }
    for (var i = 0; i < controls.length; i++) {
      (controls[i].parentData! as _ToolbarData).visible = i == ids.length || visible[i];
    }
    markNeedsSemanticsUpdate();
    onLayout();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final children = getChildrenAsList();
    for (final group in groups) {
      Rect? bounds;
      for (var i = 0; i < ids.length; i++) {
        final data = children[i].parentData! as _ToolbarData;
        if (data.visible && group.contains(ids[i])) {
          final rect = data.offset & children[i].size;
          bounds = bounds?.expandToInclude(rect) ?? rect;
        }
      }
      if (bounds != null) {
        final rect = Rect.fromCenter(
          center: bounds.center + offset,
          width: bounds.width + 6,
          height: MMSizes.toolbarGroupHeight,
        );
        context.canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(MMRadii.capsule)),
          Paint()..color = groupColor,
        );
      }
    }
    for (final child in children) {
      final data = child.parentData! as _ToolbarData;
      if (data.visible) context.paintChild(child, offset + data.offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in getChildrenAsList().reversed) {
      final data = child.parentData! as _ToolbarData;
      if (data.visible &&
          result.addWithPaintOffset(
            offset: data.offset,
            position: position,
            hitTest: (result, position) => child.hitTest(result, position: position),
          )) {
        return true;
      }
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (final child in getChildrenAsList()) {
      if ((child.parentData! as _ToolbarData).visible) visitor(child);
    }
  }

  @override
  bool paintsChild(RenderBox child) => (child.parentData! as _ToolbarData).visible;
}

class _ToolbarVariant extends MultiChildRenderObjectWidget {
  const _ToolbarVariant({required super.children});
  @override
  RenderObject createRenderObject(BuildContext context) => _ToolbarVariantBox();
}

_ToolbarVariantBox? _variantOf(RenderObject object) {
  if (object is _ToolbarVariantBox) return object;
  _ToolbarVariantBox? result;
  object.visitChildren((child) {
    result ??= _variantOf(child);
  });
  return result;
}

class _ToolbarVariantBox extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _ToolbarData>, RenderBoxContainerDefaultsMixin<RenderBox, _ToolbarData> {
  bool _compact = false;
  double compactWidth = 0;
  RenderBox get active => _compact ? lastChild! : firstChild!;
  @override
  void setupParentData(RenderBox child) {
    child.parentData = _ToolbarData();
  }

  @override
  void performLayout() {
    for (final child in getChildrenAsList()) {
      child.layout(BoxConstraints(maxHeight: constraints.maxHeight), parentUsesSize: true);
    }
    compactWidth = lastChild!.size.width;
    _compact = firstChild!.size.width > constraints.maxWidth;
    size = constraints.constrain(active.size);
    markNeedsSemanticsUpdate();
  }

  @override
  void paint(PaintingContext context, Offset offset) => context.paintChild(active, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      active.hitTest(result, position: position);
  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) => visitor(active);
  @override
  bool paintsChild(RenderBox child) => identical(child, active);
}
