import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'reader_entry_editor.dart';

class ReaderBookmarks extends ConsumerWidget {
  const ReaderBookmarks({
    super.key,
    required this.studySetId,
    required this.document,
    required this.pdf,
    required this.bookmarks,
  });
  final String studySetId;
  final Document document;
  final MMPdfViewController pdf;
  final List<Bookmark> bookmarks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final controller = ref.read(workspaceProvider(studySetId).notifier);
    Future<void> edit([Bookmark? bookmark]) async {
      final value = await showReaderEntryEditor(
        context,
        title: bookmark == null ? l.addBookmark : l.editBookmark,
        initialTitle: bookmark?.title ?? '',
        page: bookmark?.page ?? pdf.currentPage,
        pageCount: document.pageCount,
        occupiedPages: {
          for (final b in bookmarks)
            if (b.id != bookmark?.id) b.page,
        },
      );
      if (value == null) return;
      if (bookmark == null) {
        await controller.addBookmark(document.id, value.page, value.title);
      } else {
        await controller.editBookmark(bookmark.id, value.title, value.page);
      }
    }

    void reorder(int oldIndex, int newIndex) {
      final ids = bookmarks.map((b) => b.id).toList();
      ids.insert(newIndex, ids.removeAt(oldIndex));
      controller.orderBookmarks(document.id, ids);
    }

    void sort(ReaderEntrySort order) {
      final sorted = [...bookmarks]
        ..sort(
          (a, b) => switch (order) {
            ReaderEntrySort.pageAscending => a.page.compareTo(b.page),
            ReaderEntrySort.pageDescending => b.page.compareTo(a.page),
            ReaderEntrySort.title => (a.title.isEmpty ? l.pageNumber(a.page) : a.title).toLowerCase().compareTo(
              (b.title.isEmpty ? l.pageNumber(b.page) : b.title).toLowerCase(),
            ),
          },
        );
      controller.orderBookmarks(document.id, sorted.map((b) => b.id).toList());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReaderEntryHeader(
          title: l.readerBookmarks,
          addLabel: l.addBookmark,
          onAdd: edit,
          onSort: sort,
          canSort: bookmarks.length > 1,
        ),
        Expanded(
          child: bookmarks.isEmpty
              ? Center(
                  child: Text(
                    l.noBookmarks,
                    style: context.mmText.callout.copyWith(color: context.mmColors.secondaryLabel),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.all(MMSizes.sidebarInset),
                  buildDefaultDragHandles: false,
                  itemCount: bookmarks.length,
                  onReorderItem: reorder,
                  proxyDecorator: (child, _, _) =>
                      Material(color: context.mmColors.sidebarOpaque, elevation: 4, child: child),
                  itemBuilder: (context, index) {
                    final bookmark = bookmarks[index];
                    final named = bookmark.title.isNotEmpty;
                    final entries = <MMMenuEntry>[
                      MMMenuItem(l.editBookmark, () => edit(bookmark), icon: MMIcons.editNote),
                      MMMenuItem(l.moveUp, index == 0 ? null : () => reorder(index, index - 1), icon: MMIcons.moveUp),
                      MMMenuItem(
                        l.moveDown,
                        index == bookmarks.length - 1 ? null : () => reorder(index, index + 1),
                        icon: MMIcons.moveDown,
                      ),
                      const MMMenuDivider(),
                      MMMenuItem(
                        l.deleteBookmark,
                        () => controller.removeBookmark(bookmark.id),
                        destructive: true,
                        icon: MMIcons.trash,
                      ),
                    ];
                    return Row(
                      key: ValueKey('bookmark-${bookmark.id}'),
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: Tooltip(
                            message: l.readerDragToMove,
                            child: Padding(
                              key: ValueKey('bookmark-drag-${bookmark.id}'),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              child: Icon(Icons.drag_indicator, size: 14, color: context.mmColors.secondaryLabel),
                            ),
                          ),
                        ),
                        Expanded(
                          child: MMSidebarItem(
                            icon: MMIcons.bookmarkFill,
                            iconColor: context.mmColors.accent,
                            label: named ? bookmark.title : l.pageNumber(bookmark.page),
                            trailing: named ? MMCount(bookmark.page) : null,
                            selected: bookmark.page == pdf.currentPage,
                            onTap: () => pdf.jumpToPage(bookmark.page),
                            onContextMenu: (position) => showMMMenu(context, position: position, entries: entries),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}
