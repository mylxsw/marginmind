import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:mm_core/mm_core.dart';
import 'package:mm_reflow/mm_reflow.dart';

import '../reflow_document.dart';
import '../reflow_session.dart';

/// Bidirectional lazy chapter list. The current source chapter is the sliver
/// center, so restoring a faraway position never lays out every earlier chapter.
class ReflowScrollReader extends StatefulWidget {
  const ReflowScrollReader({
    super.key,
    required this.book,
    required this.position,
    required this.spec,
    required this.controller,
    required this.surface,
    required this.onPosition,
    required this.onReady,
    this.selectionChapter,
    this.onPreviewPosition,
  });
  final ReflowDocument book;
  final TextReadingPosition position;
  final LayoutSpec spec;
  final ScrollController controller;
  final Widget Function(ChapterLayout) surface;
  final void Function(TextReadingPosition, double) onPosition;
  final VoidCallback onReady;
  final String? selectionChapter;
  final void Function(TextReadingPosition, double)? onPreviewPosition;
  @override
  State<ReflowScrollReader> createState() => ReflowScrollReaderState();
}

class ReflowScrollReaderState extends State<ReflowScrollReader> {
  bool _userScroll = false, _observeQueued = false;
  final _viewport = GlobalKey();
  final _center = GlobalKey();
  final _keys = <String, GlobalKey<_ScrollChapterState>>{};
  late final int _index = widget.book.chapters.indexWhere((c) => c.id == widget.position.chapterId);
  ({ChapterLayout layout, Offset local})? hitTest(Offset global) {
    for (final key in _keys.values) {
      final state = key.currentState;
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (state?.session.ready != true || box == null || !box.attached) continue;
      final point = box.globalToLocal(global);
      if ((Offset.zero & box.size).contains(point)) {
        final layout = state!.session.layout!;
        return (layout: layout, local: point - Offset((box.size.width - layout.spec.width) / 2, 0));
      }
    }
    return null;
  }

  void recordPosition() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _observe();
  });
  void _observe({bool persist = true}) {
    final viewport = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null) return;
    final origin = viewport.localToGlobal(Offset.zero).dy;
    final visible = <(_ScrollChapterState, double)>[];
    for (final key in _keys.values) {
      final state = key.currentState;
      if (state?.session.ready != true) continue;
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy - origin;
      if (top + box.size.height > 0 && top < viewport.size.height) visible.add((state!, top));
    }
    if (visible.isEmpty) return;
    visible.sort((a, b) => a.$2.compareTo(b.$2));
    final (state, y) = visible.first;
    final top = math.max(0.0, -y);
    final anchor = state.session.layout!.capture(top).position;
    final position = widget.book.position(anchor.chapterId, anchor.start);
    if (persist) {
      widget.onPosition(position, top);
    } else {
      widget.onPreviewPosition?.call(position, top);
    }
  }

  Widget chapter(int index) {
    final c = widget.book.chapters[index];
    return _ScrollChapter(
      key: _keys.putIfAbsent(c.id, () => GlobalKey<_ScrollChapterState>()),
      book: widget.book,
      chapterId: c.id,
      spec: widget.spec,
      surface: widget.surface,
      keepAlive: c.id == widget.selectionChapter,
      offset: index == _index ? widget.position.offset : 0,
      onReady: index == _index ? widget.onReady : () {},
    );
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
    onNotification: (notification) {
      if (notification is UserScrollNotification && notification.direction != ScrollDirection.idle) _userScroll = true;
      if (notification is ScrollStartNotification && notification.dragDetails != null) _userScroll = true;
      if (notification is ScrollUpdateNotification && _userScroll && !_observeQueued) {
        _observeQueued = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _observeQueued = false;
          if (mounted) _observe(persist: false);
        });
      }
      if (notification is ScrollEndNotification && _userScroll) {
        _userScroll = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _observe();
        });
      }
      return false;
    },
    child: CustomScrollView(
      key: _viewport,
      controller: widget.controller,
      center: _center,
      slivers: [
        SliverList(delegate: SliverChildBuilderDelegate((_, i) => chapter(_index - i - 1), childCount: _index)),
        SliverList(
          key: _center,
          delegate: SliverChildBuilderDelegate(
            (_, i) => chapter(_index + i),
            childCount: widget.book.chapters.length - _index,
          ),
        ),
      ],
    ),
  );
}

class _ScrollChapter extends StatefulWidget {
  const _ScrollChapter({
    super.key,
    required this.book,
    required this.chapterId,
    required this.spec,
    required this.surface,
    required this.offset,
    required this.onReady,
    required this.keepAlive,
  });
  final ReflowDocument book;
  final String chapterId;
  final LayoutSpec spec;
  final int offset;
  final bool keepAlive;
  final Widget Function(ChapterLayout) surface;
  final VoidCallback onReady;
  @override
  State<_ScrollChapter> createState() => _ScrollChapterState();
}

class _ScrollChapterState extends State<_ScrollChapter> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;
  @override
  void didUpdateWidget(_ScrollChapter old) {
    super.didUpdateWidget(old);
    if (old.keepAlive != widget.keepAlive) updateKeepAlive();
  }

  late final session = ReflowSession(() async => widget.book, onPosition: (_) {});
  @override
  void initState() {
    super.initState();
    _layout();
  }

  Future<void> _layout() async {
    await session.initialize();
    if (!mounted) return;
    await session.jump(widget.book.position(widget.chapterId, widget.offset), remember: false);
    await session.configure(widget.spec);
    if (mounted) {
      setState(() {});
      widget.onReady();
    }
  }

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return session.layout == null
        ? SizedBox(height: widget.spec.pageHeight)
        : Center(child: widget.surface(session.layout!));
  }
}
