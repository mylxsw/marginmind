import 'package:flutter/foundation.dart';

/// One entry of a PDF's own table of contents. [page] is 1-based; 0 means the
/// entry has no destination inside the document.
@immutable
class MMPdfOutlineItem {
  const MMPdfOutlineItem({required this.title, required this.page, this.children = const []});

  final String title;
  final int page;
  final List<MMPdfOutlineItem> children;

  bool get isNavigable => page > 0;
}

/// Every item of [roots] in reading order, parents before their children.
Iterable<MMPdfOutlineItem> flattenOutline(List<MMPdfOutlineItem> roots) sync* {
  for (final item in roots) {
    yield item;
    yield* flattenOutline(item.children);
  }
}

/// The section [page] belongs to: of the items starting on or before [page],
/// the one that starts latest (the last in reading order on a tie), or null
/// before the first.
MMPdfOutlineItem? activeOutlineItem(List<MMPdfOutlineItem> roots, int page) {
  MMPdfOutlineItem? active;
  for (final item in flattenOutline(roots)) {
    if (!item.isNavigable || item.page > page) continue;
    if (active == null || item.page >= active.page) active = item;
  }
  return active;
}

/// [target] and the ancestors above it, outermost first; empty when [target]
/// is not part of [roots].
List<MMPdfOutlineItem> outlinePathTo(List<MMPdfOutlineItem> roots, MMPdfOutlineItem target) {
  for (final item in roots) {
    if (identical(item, target)) return [item];
    final below = outlinePathTo(item.children, target);
    if (below.isNotEmpty) return [item, ...below];
  }
  return const [];
}

/// Pages left behind by deliberate jumps (outline, thumbnail, bookmark, page
/// field, first / last page), so "back" returns to where the reader was.
/// Scrolling never records anything.
class PageHistory {
  PageHistory({this.limit = 50});

  final int limit;
  final _stack = <int>[];

  bool get canGoBack => _stack.isNotEmpty;

  /// Remembers [page] unless it is already the latest entry.
  void record(int page) {
    if (_stack.isNotEmpty && _stack.last == page) return;
    _stack.add(page);
    if (_stack.length > limit) _stack.removeAt(0);
  }

  /// The page to return to, or null when there is none.
  int? back() => _stack.isEmpty ? null : _stack.removeLast();

  void clear() => _stack.clear();
}
