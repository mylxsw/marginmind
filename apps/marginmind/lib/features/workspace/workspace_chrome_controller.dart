import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mm_design/mm_design.dart';

/// Transient state owned by one workspace, never persisted with the document.
class WorkspaceChromeController extends ChangeNotifier {
  /// Called only for reading gestures, before checking transient holds.
  VoidCallback? onReadingScroll;
  bool _visible = true;
  bool get visible => _visible;
  final Set<Object> _holds = {};
  double _distance = 0;
  Object? _geometry, _document;
  bool _scheduled = false, _disposed = false;
  void _changed() {
    if (_disposed || _scheduled) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      _scheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void reveal() {
    _distance = 0;
    if (_visible) return;
    _visible = true;
    _changed();
  }

  void hold(Object reason, {bool reveal = true}) {
    _holds.add(reason);
    if (reveal) this.reveal();
  }

  void release(Object reason) {
    if (_holds.remove(reason)) _distance = 0;
  }

  void reset(Object documentKey) {
    if (_document == documentKey) return;
    _document = documentKey;
    _geometry = null;
    reveal();
  }

  void onUserScroll(double delta, {required bool atStart, required Object geometryKey}) {
    if (_geometry != geometryKey) {
      _geometry = geometryKey;
      _distance = 0;
    }
    if (!delta.isFinite) return;
    if (delta != 0) onReadingScroll?.call();
    if (_holds.isNotEmpty) return;
    if (atStart) return reveal();
    if (delta == 0) return;
    if (delta.sign != _distance.sign) _distance = 0;
    _distance += delta;
    if (_distance <= -MMMotion.chromeRevealDistance) reveal();
    if (_visible && _distance >= MMMotion.chromeHideDistance) {
      _visible = false;
      _distance = 0;
      _changed();
    }
  }
}

class WorkspaceChromeScope extends InheritedNotifier<WorkspaceChromeController> {
  const WorkspaceChromeScope({super.key, required WorkspaceChromeController controller, required super.child})
    : super(notifier: controller);
  static WorkspaceChromeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceChromeScope>()?.notifier;
}

/// Keeps layout stable while removing hidden controls from every input tree.
class WorkspaceChromeBar extends StatefulWidget {
  const WorkspaceChromeBar({super.key, required this.child, this.bottom = false});
  final Widget child;
  final bool bottom;
  @override
  State<WorkspaceChromeBar> createState() => _WorkspaceChromeBarState();
}

class _WorkspaceChromeBarState extends State<WorkspaceChromeBar> {
  WorkspaceChromeController? _controller;
  @override
  void dispose() {
    _controller?.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = WorkspaceChromeScope.maybeOf(context);
    _controller = controller;
    final visible = controller?.visible ?? true;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final shown = visible && !(widget.bottom && keyboard);
    return Focus(
      onFocusChange: (focused) {
        if (focused) {
          controller?.hold(this);
        } else {
          controller?.release(this);
        }
      },
      child: IgnorePointer(
        ignoring: !shown,
        child: ExcludeFocus(
          excluding: !shown,
          child: ExcludeSemantics(
            excluding: !shown,
            child: ClipRect(
              child: AnimatedSlide(
                offset: shown ? Offset.zero : Offset(0, widget.bottom ? 1 : -1),
                duration: MMAppearance.duration(context, MMMotion.layout),
                curve: MMMotion.layoutCurve,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Only the primary vertical scrollable contributes; nested code blocks and
/// programmatic jumps do not masquerade as reading gestures.
class WorkspaceReadingScroll extends StatefulWidget {
  const WorkspaceReadingScroll({super.key, required this.child});
  final Widget child;
  @override
  State<WorkspaceReadingScroll> createState() => _WorkspaceReadingScrollState();
}

class _WorkspaceReadingScrollState extends State<WorkspaceReadingScroll> {
  bool _user = false;
  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
    onNotification: (event) {
      if (event.depth != 0 || event.metrics.axis != Axis.vertical) return false;
      if (event is ScrollStartNotification) _user = event.dragDetails != null;
      if (event is ScrollUpdateNotification && _user && event.metrics.maxScrollExtent > event.metrics.minScrollExtent) {
        WorkspaceChromeScope.maybeOf(context)?.onUserScroll(
          event.scrollDelta ?? 0,
          atStart: event.metrics.pixels <= event.metrics.minScrollExtent,
          geometryKey: (event.metrics.viewportDimension, event.metrics.maxScrollExtent),
        );
      }
      if (event is ScrollEndNotification) _user = false;
      return false;
    },
    child: widget.child,
  );
}
