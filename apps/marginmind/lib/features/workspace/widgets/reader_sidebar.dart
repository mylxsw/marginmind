import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../app/app_commands.dart';
import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'notices.dart';

/// Width of the page sidebar inside the source pane.
const readerSidebarWidth = 216.0;

/// Page sidebar of the source pane: thumbnails, the PDF's own table of
/// contents, the reader's bookmarks and the document's highlights.
class ReaderSidebar extends ConsumerWidget {
  const ReaderSidebar({super.key, required this.studySetId, required this.document, required this.pdf});

  final String studySetId;
  final Document document;
  final MMPdfViewController pdf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final provider = workspaceProvider(studySetId);
    final controller = ref.read(provider.notifier);
    final mode = ref.watch(provider.select((s) => s.readerPanelMode));
    final content = ref.watch(workspaceContentProvider(studySetId)) ?? StudySetContent.empty;

    return Container(
      width: readerSidebarWidth,
      decoration: BoxDecoration(
        color: c.sidebarOpaque,
        border: Border(right: BorderSide(color: c.separator)),
      ),
      child: ListenableBuilder(
        listenable: pdf,
        builder: (context, _) {
          final hasOutline = pdf.outline.isNotEmpty;
          // A document without contents has no such tab; fall back quietly.
          final shown = mode == ReaderPanelMode.outline && !hasOutline ? ReaderPanelMode.thumbnails : mode;
          final tabs = <(ReaderPanelMode, IconData, String, SingleActivator)>[
            (ReaderPanelMode.thumbnails, MMIcons.thumbnails, l.readerThumbnails, AppShortcuts.readerThumbnails),
            if (hasOutline) (ReaderPanelMode.outline, MMIcons.outline, l.readerOutline, AppShortcuts.readerOutline),
            (ReaderPanelMode.bookmarks, MMIcons.bookmark, l.readerBookmarks, AppShortcuts.readerBookmarks),
            (ReaderPanelMode.annotations, MMIcons.annotations, l.readerAnnotations, AppShortcuts.readerAnnotations),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: MMSpacing.s),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final (value, icon, label, shortcut) in tabs)
                      MMToolbarButton(
                        icon: icon,
                        tooltip: AppShortcuts.tip(label, shortcut),
                        selected: value == shown,
                        onPressed: () => controller.setReaderPanelMode(value),
                      ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: c.separator),
              Expanded(
                child: switch (shown) {
                  ReaderPanelMode.thumbnails => _Thumbnails(pdf: pdf, pageCount: document.pageCount),
                  ReaderPanelMode.outline => _Outline(key: ValueKey(document.id), pdf: pdf),
                  ReaderPanelMode.bookmarks => _Bookmarks(
                    studySetId: studySetId,
                    pdf: pdf,
                    bookmarks: content.bookmarksOn(document.id),
                  ),
                  ReaderPanelMode.annotations => _Annotations(pdf: pdf, annotations: _annotations(content)),
                },
              ),
            ],
          );
        },
      ),
    );
  }

  List<Annotation> _annotations(StudySetContent content) => content.annotationsOn(document.id)
    ..sort((a, b) {
      final byPage = a.page.compareTo(b.page);
      return byPage != 0 ? byPage : a.createdAt.compareTo(b.createdAt);
    });
}

// ---- thumbnails ---------------------------------------------------------------

class _Thumbnails extends StatefulWidget {
  const _Thumbnails({required this.pdf, required this.pageCount});

  final MMPdfViewController pdf;
  final int pageCount;

  @override
  State<_Thumbnails> createState() => _ThumbnailsState();
}

class _ThumbnailsState extends State<_Thumbnails> {
  static const _extent = 184.0;
  static const _thumbWidth = 112.0;
  static const _thumbHeight = 144.0;

  late final ScrollController _scroll;
  int _lastPage = 0;

  @override
  void initState() {
    super.initState();
    _lastPage = widget.pdf.currentPage;
    _scroll = ScrollController(initialScrollOffset: math.max(0, (_lastPage - 1) * _extent - _extent));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the current page in view when the reader moves through the
  /// document, without fighting a user who scrolls the list by hand.
  void _follow(int page) {
    if (page == _lastPage) return;
    _lastPage = page;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final top = (page - 1) * _extent;
      final position = _scroll.position;
      if (top >= position.pixels && top + _extent <= position.pixels + position.viewportDimension) return;
      _scroll.jumpTo((top - (position.viewportDimension - _extent) / 2).clamp(0, position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final current = widget.pdf.currentPage;
    _follow(current);
    return ListView.builder(
      controller: _scroll,
      itemExtent: _extent,
      itemCount: widget.pageCount,
      itemBuilder: (context, index) {
        final page = index + 1;
        final selected = page == current;
        return MMInteractive(
          key: ValueKey('thumbnail-$page'),
          onTap: () => widget.pdf.jumpToPage(page),
          selected: selected,
          semanticLabel: context.l10n.pageNumber(page),
          builder: (context, s) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(MMRadii.excerpt),
                  border: Border.all(color: selected ? c.accent : Colors.transparent, width: 2),
                  color: s.hovered && !selected ? c.hover : null,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(boxShadow: c.cardShadow),
                  child: MMPdfThumbnail(
                    controller: widget.pdf,
                    page: page,
                    width: _thumbWidth,
                    height: _thumbHeight,
                    backgroundColor: c.page,
                  ),
                ),
              ),
              const SizedBox(height: MMSpacing.xs),
              Text(
                '$page',
                style: t.footnote.copyWith(
                  color: selected ? c.accent : c.secondaryLabel,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---- table of contents ----------------------------------------------------------

class _Outline extends StatefulWidget {
  const _Outline({super.key, required this.pdf});

  final MMPdfViewController pdf;

  @override
  State<_Outline> createState() => _OutlineState();
}

class _OutlineState extends State<_Outline> {
  final _collapsed = <MMPdfOutlineItem>{};
  MMPdfOutlineItem? _lastActive;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final roots = widget.pdf.outline;
    final active = activeOutlineItem(roots, widget.pdf.currentPage);
    if (active != _lastActive) {
      // The section being read must stay visible, whatever was folded.
      _lastActive = active;
      if (active != null) _collapsed.removeAll(outlinePathTo(roots, active).where((i) => i != active));
    }
    final rows = <(MMPdfOutlineItem, int)>[];
    void collect(List<MMPdfOutlineItem> items, int depth) {
      for (final item in items) {
        rows.add((item, depth));
        if (!_collapsed.contains(item)) collect(item.children, depth + 1);
      }
    }

    collect(roots, 0);
    return ListView.builder(
      padding: const EdgeInsets.all(MMSizes.sidebarInset),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final (item, depth) = rows[index];
        final selected = identical(item, active);
        final folded = _collapsed.contains(item);
        return MMInteractive(
          key: ValueKey('outline-$index'),
          onTap: item.isNavigable ? () => widget.pdf.jumpToPage(item.page) : null,
          selected: selected,
          semanticLabel: item.title,
          builder: (context, s) => Container(
            constraints: const BoxConstraints(minHeight: MMSizes.sidebarRow),
            padding: EdgeInsets.fromLTRB(2 + depth * 12.0, 4, 6, 4),
            decoration: BoxDecoration(
              color: selected ? c.selectedRow : (s.hovered ? c.hover : Colors.transparent),
              borderRadius: BorderRadius.circular(MMRadii.row),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 18,
                  height: 20,
                  child: item.children.isEmpty
                      ? null
                      : MMInteractive(
                          onTap: () => setState(() => folded ? _collapsed.remove(item) : _collapsed.add(item)),
                          semanticLabel: folded ? l.expandSection : l.collapseSection,
                          builder: (context, _) => Icon(
                            folded ? MMIcons.chevronRight : MMIcons.chevronDown,
                            size: 10,
                            color: c.secondaryLabel,
                          ),
                        ),
                ),
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: t.callout.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: item.isNavigable ? c.label : c.secondaryLabel,
                    ),
                  ),
                ),
                if (item.isNavigable)
                  Padding(
                    padding: const EdgeInsets.only(left: MMSpacing.xs),
                    child: MMCount(item.page),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---- bookmarks ------------------------------------------------------------------

class _Bookmarks extends ConsumerWidget {
  const _Bookmarks({required this.studySetId, required this.pdf, required this.bookmarks});

  final String studySetId;
  final MMPdfViewController pdf;
  final List<Bookmark> bookmarks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    if (bookmarks.isEmpty) return _Empty(label: l.noBookmarks);
    final controller = ref.read(workspaceProvider(studySetId).notifier);
    return ListView.builder(
      padding: const EdgeInsets.all(MMSizes.sidebarInset),
      itemCount: bookmarks.length,
      itemBuilder: (context, index) {
        final bookmark = bookmarks[index];
        final named = bookmark.title.isNotEmpty;
        return MMSidebarItem(
          key: ValueKey('bookmark-${bookmark.id}'),
          icon: MMIcons.bookmarkFill,
          iconColor: c.accent,
          label: named ? bookmark.title : l.pageNumber(bookmark.page),
          trailing: named ? MMCount(bookmark.page) : null,
          selected: bookmark.page == pdf.currentPage,
          onTap: () => pdf.jumpToPage(bookmark.page),
          onContextMenu: (position) => showMMMenu(
            context,
            position: position,
            entries: [
              MMMenuItem(l.renameBookmark, () async {
                final title = await showRenameSheet(
                  context,
                  title: l.renameBookmark,
                  initial: named ? bookmark.title : l.pageNumber(bookmark.page),
                );
                if (title != null) await controller.renameBookmark(bookmark.id, title);
              }),
              MMMenuItem(l.deleteBookmark, () => controller.removeBookmark(bookmark.id), destructive: true),
            ],
          ),
        );
      },
    );
  }
}

// ---- annotations ----------------------------------------------------------------

class _Annotations extends StatelessWidget {
  const _Annotations({required this.pdf, required this.annotations});

  final MMPdfViewController pdf;
  final List<Annotation> annotations;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    if (annotations.isEmpty) return _Empty(label: l.noAnnotations);
    return ListView.builder(
      padding: const EdgeInsets.all(MMSizes.sidebarInset),
      itemCount: annotations.length,
      itemBuilder: (context, index) {
        final annotation = annotations[index];
        final color = MMAnnotationColor.fromIndex(annotation.colorIndex);
        final first = annotation.pages.first;
        return MMInteractive(
          key: ValueKey('annotation-${annotation.id}'),
          onTap: () => pdf.jumpToRect(first.page, first.rects),
          semanticLabel: annotation.quote.isEmpty ? l.toolArea : annotation.quote,
          builder: (context, s) => Container(
            constraints: const BoxConstraints(minHeight: MMSizes.sidebarRow),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: BoxDecoration(
              color: s.hovered ? c.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(MMRadii.row),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: MMSpacing.s),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: color.color, shape: BoxShape.circle),
                  ),
                ),
                Expanded(
                  child: Text(
                    annotation.quote.isEmpty ? l.toolArea : annotation.quote,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: t.callout,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: MMSpacing.xs),
                  child: MMCount(first.page),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(label, style: context.mmText.callout.copyWith(color: context.mmColors.secondaryLabel)),
  );
}
