import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';

/// List view: Finder-style table with zebra rows and sortable headers.
class StudySetList extends StatelessWidget {
  const StudySetList({
    super.key,
    required this.sets,
    required this.folders,
    required this.sort,
    required this.selectedId,
    required this.now,
    required this.onSort,
    required this.onSelect,
    required this.onOpen,
    this.onContextMenu,
  });

  /// Right click on a row (study set id, global pointer position).
  final void Function(String id, Offset position)? onContextMenu;
  final List<StudySet> sets;
  final List<Folder> folders;
  final LibrarySort sort;
  final String? selectedId;
  final DateTime now;
  final ValueChanged<LibrarySort> onSort;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onOpen;

  static const _flex = [24, 10, 6, 6, 6, 10];

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;

    Widget header(String label, {LibrarySort? sortKey, bool numeric = false}) {
      final active = sortKey != null && sortKey == sort;
      final text = Text(
        label + (active ? (sortKey == LibrarySort.title ? ' ⌃' : ' ⌄') : ''),
        textAlign: numeric ? TextAlign.right : TextAlign.left,
        style: t.subheadline.copyWith(
          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          color: active ? c.label : c.secondaryLabel,
        ),
      );
      if (sortKey == null) return text;
      return MMInteractive(onTap: () => onSort(sortKey), semanticLabel: label, builder: (_, _) => text);
    }

    Widget row(List<Widget> cells) => Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(flex: _flex[i], child: cells[i]),
        ],
      ],
    );

    String folderName(String? id) => folders.where((f) => f.id == id).firstOrNull?.name ?? l.libraryUnfiled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.separator, width: 0.5)),
          ),
          child: row([
            header(l.columnName, sortKey: LibrarySort.title),
            header(l.columnFolder),
            header(l.columnDocuments, numeric: true),
            header(l.columnCards, sortKey: LibrarySort.cardCount, numeric: true),
            header(l.columnDue, numeric: true),
            header(l.columnLastOpened, sortKey: LibrarySort.recent),
          ]),
        ),
        for (var i = 0; i < sets.length; i++)
          _Row(
            set: sets[i],
            striped: i.isOdd,
            selected: sets[i].id == selectedId,
            onSelect: () => onSelect(sets[i].id),
            onOpen: () => onOpen(sets[i].id),
            onContextMenu: onContextMenu == null ? null : (position) => onContextMenu!(sets[i].id, position),
            builder: (fg) {
              final secondary = t.body.copyWith(
                color: fg ?? c.secondaryLabel,
                fontFeatures: const [FontFeature.tabularFigures()],
              );
              return row([
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: MMAnnotationColor.fromIndex(sets[i].colorIndex).color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        sets[i].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.body.copyWith(color: fg),
                      ),
                    ),
                    if (sets[i].starred) ...[
                      const SizedBox(width: 6),
                      const Icon(MMIcons.starFill, size: 10, color: Color(0xFFFFCC00)),
                    ],
                  ],
                ),
                Text(folderName(sets[i].folderId), style: secondary, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${sets[i].documentCount}', style: secondary, textAlign: TextAlign.right),
                Text('${sets[i].cardCount}', style: secondary, textAlign: TextAlign.right),
                Text(sets[i].dueCount == 0 ? '—' : '${sets[i].dueCount}', style: secondary, textAlign: TextAlign.right),
                Text(l.relativeTime(sets[i].lastOpenedAt, now), style: secondary, maxLines: 1),
              ]);
            },
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.set,
    required this.striped,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onContextMenu,
    required this.builder,
  });

  final ValueChanged<Offset>? onContextMenu;

  final StudySet set;
  final bool striped;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onOpen;

  /// Builds the cells; receives the foreground override for selected rows.
  final Widget Function(Color? foreground) builder;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MMContextMenuRegion(
      onSecondaryTapUp: onContextMenu == null
          ? null
          : (d) {
              onSelect();
              onContextMenu!(d.globalPosition);
            },
      child: _interactive(context, c),
    );
  }

  Widget _interactive(BuildContext context, MMColors c) {
    return MMInteractive(
      onTapDown: onSelect,
      onDoubleTap: onOpen,
      selected: selected,
      builder: (context, s) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? c.accentFill
              : s.hovered
              ? c.hover
              : striped
              ? c.quaternaryFill.withValues(alpha: 0.35)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MMRadii.row),
        ),
        child: builder(selected ? c.onAccent : null),
      ),
    );
  }
}
