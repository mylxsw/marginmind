import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

export '../../assistant/widgets/expansion_widgets.dart' show MapGhostNode, MapGhostNodeState;

/// Skeleton node displayed during the chapter reading phase.
class MapSkeletonNode extends StatefulWidget {
  const MapSkeletonNode({super.key, required this.title, this.isCurrent = false});

  final String title;
  final bool isCurrent;

  @override
  State<MapSkeletonNode> createState() => _MapSkeletonNodeState();
}

class _MapSkeletonNodeState extends State<MapSkeletonNode> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: MMMotion.breathe);
    _opacity = Tween<double>(
      begin: 1.0,
      end: 0.4,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(MapSkeletonNode old) {
    super.didUpdateWidget(old);
    if (widget.isCurrent != old.isCurrent) {
      _update();
    }
  }

  void _update() {
    if (widget.isCurrent && !MMAppearance.reduceMotionOf(context)) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller.stop();
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final reduceMotion = MMAppearance.reduceMotionOf(context);

    Widget box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(MMRadii.row)),
      child: Text(
        widget.title,
        style: t.headline.copyWith(color: c.secondaryLabel, fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );

    if (widget.isCurrent && !reduceMotion) {
      box = AnimatedBuilder(
        animation: _opacity,
        builder: (context, child) => Opacity(opacity: _opacity.value, child: child),
        child: box,
      );
    }

    return ExcludeSemantics(child: box);
  }
}
