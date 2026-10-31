import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../shared/l10n.dart';
import '../phone_reader_controls_controller.dart';
import '../workspace_chrome_controller.dart';
import '../workspace_controller.dart';
import 'annotation_palette.dart';

class PhoneReaderWorkspaceScope extends StatelessWidget {
  const PhoneReaderWorkspaceScope({super.key, required this.controls, required this.chrome, required this.child});
  final PhoneReaderControlsController controls;
  final WorkspaceChromeController chrome;
  final Widget child;
  @override
  Widget build(BuildContext context) => PhoneReaderControlsScope(
    controller: controls,
    safeBottom: MediaQuery.paddingOf(context).bottom,
    child: WorkspaceChromeScope(controller: chrome, child: child),
  );
}

/// Shared by the source and mind-map pages. Content scrolls beneath the fade.
class PhoneReaderTopControls extends StatelessWidget {
  const PhoneReaderTopControls({
    super.key,
    required this.leading,
    required this.mode,
    required this.onMode,
    required this.trailing,
  });
  final Widget leading, trailing;
  final MMSplitMode mode;
  final ValueChanged<MMSplitMode> onMode;

  @override
  Widget build(BuildContext context) {
    final visible = WorkspaceChromeScope.maybeOf(context)?.visible ?? true;
    final c = context.mmColors, l = context.l10n;
    return Stack(
      children: [
        IgnorePointer(
          child: AnimatedContainer(
            key: const ValueKey('phone-reader-edge'),
            duration: MMAppearance.duration(context, MMMotion.layout),
            height: visible ? MMPhoneReaderLayout.edge : MMPhoneReaderLayout.immersiveEdge,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [c.windowBackground, c.windowBackground.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
        WorkspaceChromeBar(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MMPhoneReaderLayout.inset,
              vertical: MMPhoneReaderLayout.top,
            ),
            child: Row(
              children: [
                _glass(leading),
                const SizedBox(width: MMPhoneReaderLayout.gap),
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: MMPhoneReaderLayout.modeWidth,
                      child: _glass(
                        LayoutBuilder(
                          builder: (context, constraints) => Stack(
                            children: [
                              AnimatedAlign(
                                key: const ValueKey('phone-reader-lens'),
                                alignment: mode == MMSplitMode.secondary ? Alignment.centerRight : Alignment.centerLeft,
                                duration: MMAppearance.duration(context, MMMotion.layout),
                                curve: MMMotion.layoutCurve,
                                child: Padding(
                                  padding: const EdgeInsets.all(MMSpacing.xs),
                                  child: Container(
                                    width: constraints.maxWidth / 2 - MMSpacing.xs,
                                    height: MMSizes.phoneTopControl - MMSpacing.s,
                                    decoration: BoxDecoration(
                                      color: c.fill,
                                      borderRadius: BorderRadius.circular(MMRadii.capsule),
                                    ),
                                  ),
                                ),
                              ),
                              Row(
                                key: const ValueKey('workspace-pane-switch'),
                                children: [
                                  for (final (value, label) in [
                                    (MMSplitMode.primary, l.phoneReaderReading),
                                    (MMSplitMode.secondary, l.paneMap),
                                  ])
                                    Expanded(
                                      child: MMInteractive(
                                        semanticLabel: label,
                                        selected: mode == value,
                                        onTap: () => onMode(value),
                                        builder: (context, _) => SizedBox(
                                          height: MMSizes.phoneTopControl,
                                          child: Center(
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xs),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    value == MMSplitMode.primary ? MMIcons.ebook : MMIcons.network,
                                                    size: MMSpacing.l,
                                                    color: mode == value ? c.label : c.secondaryLabel,
                                                  ),
                                                  const SizedBox(width: MMSpacing.xs),
                                                  Flexible(
                                                    child: Text(
                                                      label,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: context.mmText.headline.copyWith(
                                                        color: mode == value ? c.label : c.secondaryLabel,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: MMPhoneReaderLayout.gap),
                _glass(trailing),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Widget _glass(Widget child, {double radius = MMSizes.phoneTopControl / 2}) => MMFlatSurface(
  enabled: false,
  child: MMLiquidGlass(
    phoneStyle: MMPhoneGlass.regular,
    borderRadius: BorderRadius.circular(radius),
    // Menus opened by these controls must capture the workspace's flat surface.
    child: MMFlatSurface(child: child),
  ),
);

IconData phoneReaderToolIcon(AnnotationTool tool) => switch (tool) {
  AnnotationTool.select => MMReaderIcons.select,
  AnnotationTool.highlight => MMIcons.highlight,
  AnnotationTool.underline => MMReaderIcons.underline,
  AnnotationTool.ink => MMReaderIcons.pen,
  AnnotationTool.area => MMReaderIcons.area,
};

/// The renderer supplies navigation; annotation commands use the existing workspace.
class PhoneReaderControls extends ConsumerStatefulWidget {
  const PhoneReaderControls({
    super.key,
    required this.studySetId,
    required this.page,
    required this.pageCount,
    required this.chapter,
    required this.onJump,
    this.progress,
    this.onProgress,
  });
  final String studySetId, chapter;
  final int page, pageCount;
  final ValueChanged<int> onJump;
  final double? progress;
  final ValueChanged<double>? onProgress;

  @override
  ConsumerState<PhoneReaderControls> createState() => _PhoneReaderControlsState();
}

class _PhoneReaderControlsState extends ConsumerState<PhoneReaderControls> {
  double? _dragX;

  @override
  Widget build(BuildContext context) {
    final slots = PhoneReaderControlsScope.maybeOf(context);
    if (slots == null || MediaQuery.viewInsetsOf(context).bottom > 0) return const SizedBox.shrink();
    final state = ref.watch(workspaceProvider(widget.studySetId));
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final l = context.l10n, c = context.mmColors;
    final count = math.max(1, widget.pageCount), page = widget.page.clamp(1, math.max(1, widget.pageCount)).toInt();
    final tool = state.tool;
    final color = switch (tool) {
      AnnotationTool.ink => state.inkColor.color,
      AnnotationTool.underline => state.underlineColor.color,
      _ => state.color.color,
    };
    Widget button(
      String id,
      IconData icon,
      String label,
      VoidCallback? action, {
      bool selected = false,
      Color? dot,
      bool tintSelected = true,
      bool filled = false,
    }) => MMInteractive(
      key: ValueKey('phone-reader-$id'),
      semanticLabel: label,
      tooltip: label,
      selected: selected,
      onTap: action,
      builder: (context, s) => Container(
        width: MMSizes.touchTarget,
        height: MMSizes.touchTarget,
        decoration: BoxDecoration(
          color: (selected && tintSelected) || s.focused
              ? c.accentTint
              : s.pressed || filled
              ? c.fill
              : null,
          borderRadius: BorderRadius.circular(MMSizes.touchTarget / 2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              icon,
              size: MMSizes.phoneTopControl / 2,
              color: action == null
                  ? c.secondaryLabel
                  : selected
                  ? c.accent
                  : c.label,
            ),
            if (dot != null)
              Positioned(right: MMSpacing.s, bottom: MMSpacing.s, child: _dot(dot, MMPhoneReaderLayout.dot)),
          ],
        ),
      ),
    );
    Widget content;
    switch (slots.slot) {
      case PhoneReaderSlot.page:
        content = Center(
          child: MMInteractive(
            key: const ValueKey('phone-reader-page'),
            semanticLabel: l.goToPage,
            semanticValue: l.pageOf(page, count),
            onTap: () {
              slots.openScrub();
              WorkspaceChromeScope.maybeOf(context)?.reveal();
            },
            builder: (context, _) => SizedBox(
              height: MMSizes.touchTarget,
              child: Center(
                child: _glass(
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: MMPhoneReaderLayout.inset),
                    child: SizedBox(
                      height: MMSizes.phonePageCapsuleHeight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: MMPhoneReaderLayout.progress,
                            child: CircularProgressIndicator(
                              value: widget.progress ?? page / count,
                              strokeWidth: MMSpacing.xxs,
                              color: c.accent,
                              backgroundColor: c.fill,
                            ),
                          ),
                          const SizedBox(width: MMSpacing.s),
                          Text(
                            l.pageOf(page, count),
                            style: context.mmText.callout.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                        ],
                      ),
                    ),
                  ),
                  radius: MMRadii.capsule,
                ),
              ),
            ),
          ),
        );
      case PhoneReaderSlot.scrub:
        content = _glass(
          Semantics(
            onDismiss: slots.closeScrub,
            child: CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.escape): slots.closeScrub},
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: MMPhoneReaderLayout.scrubHeight),
                child: Padding(
                  key: const ValueKey('phone-reader-scrub'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: MMPhoneReaderLayout.scrubInset,
                    vertical: MMSpacing.xs,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.chapter,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.mmText.callout,
                            ),
                          ),
                          Text(l.pageOf(page, count), style: context.mmText.footnote),
                        ],
                      ),
                      SizedBox(
                        height: MMSizes.touchTarget,
                        child: Slider(
                          key: const ValueKey('phone-reader-slider'),
                          min: widget.onProgress == null ? 1 : 0,
                          max: widget.onProgress == null ? math.max(2, count).toDouble() : 1,
                          value: widget.onProgress == null ? page.toDouble() : (widget.progress ?? 0).clamp(0, 1),
                          semanticFormatterCallback: (v) => widget.onProgress == null
                              ? l.pageOf(v.round(), count)
                              : l.phoneReaderPercent((v * 100).round()),
                          padding: EdgeInsets.zero,
                          onChangeStart: count > 1 || widget.onProgress != null
                              ? (_) => slots.setScrubbing(true)
                              : null,
                          onChanged: widget.onProgress ?? (count > 1 ? (v) => widget.onJump(v.round()) : null),
                          onChangeEnd: count > 1 || widget.onProgress != null ? (_) => slots.setScrubbing(false) : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          radius: MMRadii.phoneReaderToolbar,
        );
      case PhoneReaderSlot.orb:
        content = LayoutBuilder(
          builder: (context, constraints) {
            final maxX = math.max(0.0, constraints.maxWidth - MMSizes.phoneToolOrb);
            final x = (_dragX ?? (slots.dockRight ? maxX : 0.0)).clamp(0.0, maxX);
            return SizedBox(
              height: MMSizes.phoneToolOrb,
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: _dragX == null ? MMAppearance.duration(context, MMMotion.layout) : Duration.zero,
                    curve: MMMotion.layoutCurve,
                    left: x,
                    child: GestureDetector(
                      onHorizontalDragStart: (_) => setState(() => _dragX = x),
                      onHorizontalDragUpdate: (event) =>
                          setState(() => _dragX = (_dragX! + event.delta.dx).clamp(0.0, maxX)),
                      onHorizontalDragEnd: (_) {
                        slots.dock(right: _dragX! >= maxX / 2);
                        setState(() => _dragX = null);
                      },
                      onHorizontalDragCancel: () => setState(() => _dragX = null),
                      child: _glass(
                        MMInteractive(
                          key: const ValueKey('phone-reader-orb'),
                          semanticLabel: l.phoneReaderTools,
                          semanticValue: _toolLabel(context, tool),
                          onTap: slots.openTools,
                          builder: (context, s) => Container(
                            width: MMSizes.phoneToolOrb,
                            height: MMSizes.phoneToolOrb,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: tool != AnnotationTool.select || s.focused ? Border.all(color: c.accent) : null,
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  phoneReaderToolIcon(tool),
                                  color: tool == AnnotationTool.select ? c.label : c.accent,
                                  size: MMSizes.phoneTopControl / 2,
                                ),
                                if (tool != AnnotationTool.select)
                                  Positioned(
                                    right: MMSpacing.s,
                                    bottom: MMSpacing.s,
                                    child: _dot(color, MMPhoneReaderLayout.orbDot),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        radius: MMSizes.phoneToolOrb / 2,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      case PhoneReaderSlot.tools:
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: slots.dockRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if ([AnnotationTool.highlight, AnnotationTool.underline, AnnotationTool.ink].contains(tool)) ...[
              _glass(
                Padding(
                  key: const ValueKey('phone-reader-colors'),
                  padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xs),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: slots.dockRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (tool == AnnotationTool.ink)
                              for (final value in MMInkColor.values)
                                MMFloatingToolbarSwatch(
                                  color: value.color,
                                  tooltip: l.inkColorName(value),
                                  selected: state.inkTool != MMPdfInkTool.eraser && value == state.inkColor,
                                  onPressed: () {
                                    slots.colorChanged();
                                    controller.setInkColor(value);
                                  },
                                )
                            else
                              for (final value in MMAnnotationColor.values)
                                MMFloatingToolbarSwatch(
                                  color: value.color,
                                  tooltip: l.colorName(value),
                                  selected:
                                      value == (tool == AnnotationTool.underline ? state.underlineColor : state.color),
                                  onPressed: () {
                                    slots.colorChanged();
                                    tool == AnnotationTool.underline
                                        ? controller.styleUnderline(color: value)
                                        : controller.setColor(value);
                                  },
                                ),
                          ],
                        ),
                      ),
                      if (tool == AnnotationTool.ink)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final width in MMInkWidth.values)
                                MMFloatingToolbarStrokeWidth(
                                  key: ValueKey('phone-reader-width-${width.name}'),
                                  width: width.points,
                                  tooltip: l.inkWidthName(width),
                                  selected: state.inkTool != MMPdfInkTool.eraser && state.inkWidth == width,
                                  onPressed: () {
                                    slots.colorChanged();
                                    controller.setInkWidth(width);
                                  },
                                ),
                              const MMToolbarDivider(),
                              for (final (value, icon, label) in [
                                (MMPdfInkTool.freehand, MMIcons.inkFreehand, l.inkFreehand),
                                (MMPdfInkTool.ellipse, MMIcons.inkEllipse, l.inkEllipse),
                                (MMPdfInkTool.arrow, MMIcons.inkArrow, l.inkArrow),
                                (MMPdfInkTool.eraser, MMIcons.inkEraser, l.inkEraser),
                              ])
                                button('ink-${value.name}', icon, label, () {
                                  slots.colorChanged();
                                  controller.setInkTool(value);
                                }, selected: state.inkTool == value),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: MMPhoneReaderLayout.gap),
            ],
            _glass(
              SizedBox(
                height: MMSizes.phoneToolBarHeight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    key: const ValueKey('phone-reader-tools'),
                    padding: const EdgeInsets.symmetric(horizontal: MMPhoneReaderLayout.toolInset),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final value in [
                          AnnotationTool.select,
                          AnnotationTool.highlight,
                          AnnotationTool.underline,
                          AnnotationTool.ink,
                          AnnotationTool.area,
                        ])
                          button(
                            'tool-${value.name}',
                            phoneReaderToolIcon(value),
                            _toolLabel(context, value),
                            controller.canUseTool(value)
                                ? () {
                                    final next = tool == value && value != AnnotationTool.select
                                        ? AnnotationTool.select
                                        : value;
                                    controller.setTool(next);
                                    slots.selectTool(selection: next == AnnotationTool.select);
                                  }
                                : null,
                            selected: tool == value,
                            dot: switch (value) {
                              AnnotationTool.highlight => state.color.color,
                              AnnotationTool.underline => state.underlineColor.color,
                              AnnotationTool.ink => state.inkColor.color,
                              _ => null,
                            },
                          ),
                        const MMToolbarDivider(),
                        button(
                          'sync',
                          MMIcons.link,
                          state.syncToMap ? l.syncToMapOn : l.syncToMapOff,
                          controller.activeCapabilities.excerpt ? controller.toggleSyncToMap : null,
                          selected: state.syncToMap,
                          tintSelected: false,
                        ),
                        button(
                          'collapse',
                          MMIcons.chevronDown,
                          l.phoneReaderCollapse,
                          slots.collapseTools,
                          filled: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              radius: MMRadii.phoneReaderToolbar,
            ),
          ],
        );
    }
    if (slots.slot == PhoneReaderSlot.tools) {
      content = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: MMAppearance.duration(context, MMMotion.layout),
        curve: MMMotion.layoutCurve,
        builder: (context, value, child) => ClipPath(clipper: _ToolReveal(value, slots.dockRight), child: child),
        child: content,
      );
    }
    return TapRegion(
      groupId: annotationTapGroup(widget.studySetId),
      child: FocusTraversalGroup(
        child: Padding(
          padding: EdgeInsets.only(
            left: MMSpacing.m,
            right: MMSpacing.m,
            bottom: math.max(0, MMPhoneReaderLayout.bottom - PhoneReaderControlsScope.safeBottomOf(context)),
          ),
          child: content,
        ),
      ),
    );
  }
}

Widget _dot(Color color, double size) => Container(
  width: size,
  height: size,
  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
);

String _toolLabel(BuildContext context, AnnotationTool tool) => switch (tool) {
  AnnotationTool.select => context.l10n.toolSelect,
  AnnotationTool.highlight => context.l10n.toolHighlight,
  AnnotationTool.underline => context.l10n.toolUnderline,
  AnnotationTool.ink => context.l10n.toolPen,
  AnnotationTool.area => context.l10n.toolArea,
};

class _ToolReveal extends CustomClipper<Path> {
  const _ToolReveal(this.value, this.right);
  final double value;
  final bool right;
  @override
  Path getClip(Size size) {
    final width = MMSizes.phoneToolOrb + (size.width - MMSizes.phoneToolOrb) * value;
    return Path()..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(right ? size.width - width : 0, 0, width, size.height),
        const Radius.circular(MMRadii.phoneReaderToolbar),
      ),
    );
  }

  @override
  bool shouldReclip(_ToolReveal old) => old.value != value || old.right != right;
}
