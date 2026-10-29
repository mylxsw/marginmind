import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';

class ReaderEntryHeader extends StatelessWidget {
  const ReaderEntryHeader({
    super.key,
    required this.title,
    required this.addLabel,
    required this.onAdd,
    required this.onSort,
    this.canSort = true,
  });
  final String title;
  final String addLabel;
  final VoidCallback onAdd;
  final ValueChanged<ReaderEntrySort> onSort;
  final bool canSort;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: context.mmText.footnote.copyWith(color: context.mmColors.secondaryLabel)),
        ),
        Builder(
          builder: (context) => MMToolbarButton(
            icon: MMIcons.sort,
            tooltip: context.l10n.sortTooltip,
            onPressed: !canSort
                ? null
                : () {
                    final box = context.findRenderObject()! as RenderBox;
                    showMMMenu(
                      context,
                      position: box.localToGlobal(Offset(0, box.size.height)),
                      entries: [
                        MMMenuItem(context.l10n.readerSortPageAscending, () => onSort(ReaderEntrySort.pageAscending)),
                        MMMenuItem(context.l10n.readerSortPageDescending, () => onSort(ReaderEntrySort.pageDescending)),
                        MMMenuItem(context.l10n.readerSortTitle, () => onSort(ReaderEntrySort.title)),
                      ],
                    );
                  },
          ),
        ),
        MMToolbarButton(icon: MMIcons.add, tooltip: addLabel, onPressed: onAdd),
      ],
    ),
  );
}

Future<({String title, int page})?> showReaderEntryEditor(
  BuildContext context, {
  required String title,
  required String initialTitle,
  required int page,
  required int pageCount,
  bool allowNoDestination = false,
  Set<int> occupiedPages = const {},
}) => showMMSheet<({String title, int page})>(
  context: context,
  builder: (_) => _EntryEditor(
    title: title,
    initialTitle: initialTitle,
    page: page,
    pageCount: pageCount,
    allowNoDestination: allowNoDestination,
    occupiedPages: occupiedPages,
  ),
);

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({
    required this.title,
    required this.initialTitle,
    required this.page,
    required this.pageCount,
    required this.allowNoDestination,
    required this.occupiedPages,
  });
  final String title;
  final String initialTitle;
  final int page;
  final int pageCount;
  final bool allowNoDestination;
  final Set<int> occupiedPages;
  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late final _title = TextEditingController(text: widget.initialTitle)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initialTitle.length);
  late final _page = TextEditingController(text: '${widget.page}');
  bool _invalid = false;
  bool _duplicate = false;
  @override
  void dispose() {
    _title.dispose();
    _page.dispose();
    super.dispose();
  }

  void _save() {
    final page = int.tryParse(_page.text);
    if (page == null || page < (widget.allowNoDestination ? 0 : 1) || page > widget.pageCount) {
      setState(() {
        _invalid = true;
        _duplicate = false;
      });
      return;
    }
    if (widget.occupiedPages.contains(page)) {
      setState(() {
        _invalid = false;
        _duplicate = true;
      });
      return;
    }
    Navigator.of(context).pop((title: _title.text.trim(), page: page));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return MMSheet(
      title: widget.title,
      actions: [
        MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
        MMButton(label: l.save, variant: MMButtonVariant.primary, onPressed: _save),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MMFormRow(
            label: l.sheetName,
            child: MMTextField(
              key: const ValueKey('reader-entry-title'),
              controller: _title,
              autofocus: true,
              onSubmitted: (_) => _save(),
            ),
          ),
          const SizedBox(height: 12),
          MMFormRow(
            label: l.pageNumberField,
            child: MMTextField(
              key: const ValueKey('reader-entry-page'),
              controller: _page,
              onSubmitted: (_) => _save(),
            ),
          ),
          if (widget.allowNoDestination)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l.outlineNoDestination, style: context.mmText.footnote),
            ),
          if (_invalid || _duplicate)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _duplicate ? l.bookmarkPageOccupied : l.readerInvalidPage(widget.pageCount),
                style: context.mmText.footnote.copyWith(color: context.mmColors.critical),
              ),
            ),
        ],
      ),
    );
  }
}
