import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';

/// Empty selection means the entire document. A null value is invalid input.
class MapSourceRange extends StatefulWidget {
  const MapSourceRange({
    super.key,
    required this.document,
    required this.entries,
    required this.onChanged,
    this.initial = const [],
  });
  final Document document;
  final List<PdfOutlineEntry> entries;
  final List<String> initial;
  final ValueChanged<List<String>?> onChanged;
  @override
  State<MapSourceRange> createState() => _MapSourceRangeState();
}

class _MapSourceRangeState extends State<MapSourceRange> {
  late final _selected = widget.initial.toSet();
  late bool _whole = widget.initial.isEmpty;
  late final _first = TextEditingController(text: widget.initial.firstOrNull?.replaceFirst('page-', '') ?? '1');
  late final _last = TextEditingController(
    text: widget.initial.lastOrNull?.replaceFirst('page-', '') ?? '${widget.document.pageCount}',
  );
  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  void _notify() {
    if (_whole) {
      widget.onChanged([]);
      return;
    }
    if (widget.entries.isNotEmpty) {
      widget.onChanged(_selected.isEmpty ? null : _selected.toList());
      return;
    }
    final first = int.tryParse(_first.text.trim()) ?? 0, last = int.tryParse(_last.text.trim()) ?? 0;
    widget.onChanged(
      first < 1 || last < first || last > widget.document.pageCount
          ? null
          : [for (var p = first; p <= last; p++) 'page-$p'],
    );
  }

  bool _inherited(PdfOutlineEntry entry) => widget.entries.any(
    (parent) =>
        parent.id != entry.id &&
        _selected.contains(parent.id) &&
        OutlineTree.flatten(parent.children).any((child) => child.id == entry.id),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(widget.document.title, style: context.mmText.callout, overflow: TextOverflow.ellipsis),
          ),
          Text(context.l10n.mapGenerateWholeDocument, style: context.mmText.callout),
          const SizedBox(width: MMSpacing.s),
          MMSwitch(
            value: _whole,
            semanticLabel: context.l10n.mapGenerateWholeDocument,
            onChanged: (v) {
              setState(() => _whole = v);
              _notify();
            },
          ),
        ],
      ),
      if (!_whole && widget.entries.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: MMSizes.mapGenerateChapterRow * 4),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entry in widget.entries)
                Container(
                  height: MMSizes.mapGenerateChapterRow,
                  color: context.mmColors.quaternaryFill,
                  padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s),
                  child: Row(
                    children: [
                      MMCheckbox(
                        value: _selected.contains(entry.id) || _inherited(entry),
                        semanticLabel: entry.title,
                        color: context.mmColors.research,
                        onChanged: _inherited(entry)
                            ? null
                            : (v) {
                                setState(() {
                                  if (v) {
                                    _selected.add(entry.id);
                                  } else {
                                    _selected.remove(entry.id);
                                  }
                                });
                                _notify();
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
        ),
      if (!_whole && widget.entries.isEmpty)
        Row(
          children: [
            Expanded(
              child: MMTextField(
                controller: _first,
                semanticLabel: context.l10n.ocrFirstPage,
                onChanged: (_) => _notify(),
              ),
            ),
            const SizedBox(width: MMSpacing.s),
            Expanded(
              child: MMTextField(
                controller: _last,
                semanticLabel: context.l10n.ocrLastPage,
                onChanged: (_) => _notify(),
              ),
            ),
          ],
        ),
    ],
  );
}
