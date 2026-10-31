import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';

/// Empty means whole document; null means no valid range.
Set<String> mapSelectedChapters(List<PdfOutlineEntry> entries, List<String>? selection) {
  if (selection == null) return {};
  if (selection.isEmpty) return entries.map((e) => e.id).toSet();
  return {
    for (final entry in entries.where((e) => selection.contains(e.id)))
      ...OutlineTree.flatten([entry]).map((e) => e.id),
  };
}

Set<int> mapSelectedPages(Document document, List<PdfOutlineEntry> entries, List<String>? selection) {
  if (selection == null) return {};
  if (selection.isEmpty) return {for (var p = 1; p <= document.pageCount; p++) p};
  if (selection.every((id) => RegExp(r'^page-[1-9][0-9]*$').hasMatch(id))) {
    return {
      for (final id in selection)
        if (int.tryParse(id.substring(5)) case final int page)
          if (page >= 1 && page <= document.pageCount) page,
    };
  }
  int start(PdfOutlineEntry entry) {
    if (entry.page > 0) return entry.page;
    return entry.children.map(start).where((p) => p > 0).firstOrNull ?? 0;
  }

  final ordered = entries.where((e) => start(e) > 0).toList()
    ..sort((a, b) {
      final order = start(a).compareTo(start(b));
      return order == 0 ? entries.indexOf(a).compareTo(entries.indexOf(b)) : order;
    });
  final selected = mapSelectedChapters(entries, selection);
  return {
    for (var i = 0; i < ordered.length; i++)
      if (selected.contains(ordered[i].id))
        for (
          var p = start(ordered[i]);
          p <= document.pageCount && p < (i + 1 < ordered.length ? start(ordered[i + 1]) : document.pageCount + 1);
          p++
        )
          p,
  };
}

/// Expanded content lives immediately below its document row; the row owns its toggle.
class MapSourceRange extends StatefulWidget {
  const MapSourceRange({
    super.key,
    required this.document,
    required this.entries,
    required this.selection,
    required this.onChanged,
  });
  final Document document;
  final List<PdfOutlineEntry> entries;
  final List<String>? selection;
  final ValueChanged<List<String>?> onChanged;
  @override
  State<MapSourceRange> createState() => _MapSourceRangeState();
}

class _MapSourceRangeState extends State<MapSourceRange> {
  late final _first = TextEditingController(text: widget.selection?.firstOrNull?.replaceFirst('page-', '') ?? '1');
  late final _last = TextEditingController(
    text: widget.selection?.lastOrNull?.replaceFirst('page-', '') ?? '${widget.document.pageCount}',
  );
  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  void _pagesChanged(String _) {
    final first = int.tryParse(_first.text.trim()) ?? 0, last = int.tryParse(_last.text.trim()) ?? 0;
    widget.onChanged(
      first < 1 || last < first || last > widget.document.pageCount
          ? null
          : first == 1 && last == widget.document.pageCount
          ? []
          : [for (var p = first; p <= last; p++) 'page-$p'],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: MMSizes.mapGenerateRangeInset, bottom: MMSpacing.s),
        child: Row(
          children: [
            SizedBox(
              width: MMSizes.mapGeneratePageFieldWidth,
              child: MMTextField(
                controller: _first,
                semanticLabel: context.l10n.ocrFirstPage,
                onChanged: _pagesChanged,
              ),
            ),
            const SizedBox(width: MMSpacing.s),
            SizedBox(
              width: MMSizes.mapGeneratePageFieldWidth,
              child: MMTextField(controller: _last, semanticLabel: context.l10n.ocrLastPage, onChanged: _pagesChanged),
            ),
          ],
        ),
      );
    }
    final selected = mapSelectedChapters(widget.entries, widget.selection);
    final rowHeight = context.mmTouchPlatform ? MMSizes.touchTarget : MMSizes.mapGenerateChapterRow;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: rowHeight * 4),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final entry in widget.entries)
            Container(
              height: rowHeight,
              color: context.mmColors.quaternaryFill,
              padding: const EdgeInsets.only(left: MMSizes.mapGenerateRangeInset, right: MMSpacing.s),
              child: Row(
                children: [
                  MMCheckbox(
                    value: selected.contains(entry.id),
                    semanticLabel: entry.title,
                    color: context.mmColors.research,
                    onChanged: (checked) {
                      final next = {...selected};
                      final descendants = OutlineTree.flatten([entry]).map((e) => e.id).toSet();
                      if (checked) {
                        next.addAll(descendants);
                      } else {
                        next.removeAll(descendants);
                        next.removeWhere(
                          (id) => widget.entries.any(
                            (parent) =>
                                parent.id == id &&
                                OutlineTree.flatten(parent.children).any((child) => child.id == entry.id),
                          ),
                        );
                      }
                      widget.onChanged(
                        next.isEmpty
                            ? null
                            : next.length == widget.entries.length
                            ? []
                            : next.toList(),
                      );
                    },
                  ),
                  const SizedBox(width: MMSpacing.s),
                  Expanded(child: Text(entry.title, style: context.mmText.body)),
                  if (entry.position is! TextReadingPosition && entry.page > 0)
                    Text(
                      context.l10n.notePage(entry.page),
                      style: context.mmText.footnote.copyWith(color: context.mmColors.secondaryLabel),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
