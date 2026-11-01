import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'reader_entry_editor.dart';

class _OutlineDrag {
  const _OutlineDrag(this.documentId, this.id);
  final String documentId;
  final String id;
}

class ReaderOutline extends ConsumerStatefulWidget {
  const ReaderOutline({
    super.key,
    required this.studySetId,
    required this.document,
    required this.pdf,
    required this.outline,
  });
  final String studySetId;
  final Document document;
  final MMPdfViewController pdf;
  final DocumentOutline? outline;
  @override
  ConsumerState<ReaderOutline> createState() => _ReaderOutlineState();
}

class _ReaderOutlineState extends ConsumerState<ReaderOutline> {
  final _collapsed = <String>{};
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  List<MMPdfOutlineItem>? _source;
  List<PdfOutlineEntry> _original = const [];
  int? _lastPage;
  String? _dropId;
  OutlineDrop? _drop;
  Offset? _pointer;
  Timer? _autoScroll;
  Timer? _expand;

  List<PdfOutlineEntry> get _roots {
    if (!identical(_source, widget.pdf.outline)) {
      _source = widget.pdf.outline;
      List<PdfOutlineEntry> convert(List<MMPdfOutlineItem> entries, String prefix) => [
        for (final (index, item) in entries.indexed)
          PdfOutlineEntry(
            id: 'pdf-$prefix$index',
            title: item.title,
            page: item.page,
            children: convert(item.children, '$prefix$index/'),
          ),
      ];
      _original = convert(_source!, '');
    }
    return widget.outline?.items ?? _original;
  }

  WorkspaceController get _controller => ref.read(workspaceProvider(widget.studySetId).notifier);
  Future<void> _edit(List<PdfOutlineEntry> Function(List<PdfOutlineEntry>) change) =>
      _controller.editDocumentOutline(widget.document.id, _original, change);

  @override
  void dispose() {
    _autoScroll?.cancel();
    _expand?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _add({PdfOutlineEntry? target, bool child = false}) async {
    final l = context.l10n;
    final value = await showReaderEntryEditor(
      context,
      title: child ? l.addOutlineChild : l.addOutlineEntry,
      initialTitle: '',
      page: widget.pdf.currentPage,
      pageCount: widget.document.pageCount,
      allowNoDestination: true,
    );
    if (value == null || !mounted) return;
    final entry = PdfOutlineEntry(
      id: newId(),
      title: value.title.isEmpty ? (value.page == 0 ? l.readerOutline : l.pageNumber(value.page)) : value.title,
      page: value.page,
    );
    if (child) setState(() => _collapsed.remove(target!.id));
    await _edit(
      (roots) =>
          OutlineTree.insert(roots, entry, targetId: target?.id, drop: child ? OutlineDrop.inside : OutlineDrop.after),
    );
  }

  Future<void> _rename(PdfOutlineEntry entry) async {
    final value = await showReaderEntryEditor(
      context,
      title: context.l10n.editOutlineEntry,
      initialTitle: entry.title,
      page: entry.page,
      pageCount: widget.document.pageCount,
      allowNoDestination: true,
    );
    if (value == null || !mounted) return;
    final title = value.title.isEmpty
        ? (value.page == 0 ? context.l10n.readerOutline : context.l10n.pageNumber(value.page))
        : value.title;
    await _edit((roots) => OutlineTree.update(roots, entry.id, (e) => e.copyWith(title: title, page: value.page)));
  }

  void _shift(PdfOutlineEntry entry, List<PdfOutlineEntry> siblings, int delta) {
    final index = siblings.indexWhere((e) => e.id == entry.id) + delta;
    if (index < 0 || index >= siblings.length) return;
    _edit(
      (roots) =>
          OutlineTree.move(roots, entry.id, siblings[index].id, delta < 0 ? OutlineDrop.before : OutlineDrop.after),
    );
  }

  void _stopDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _expand?.cancel();
    _expand = null;
    if (mounted) {
      setState(() {
        _dropId = null;
        _drop = null;
        _pointer = null;
      });
    }
  }

  void _scrollWhileDragging(DragUpdateDetails details) {
    _pointer = details.globalPosition;
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 40), (_) {
      final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || _pointer == null || !_scroll.hasClients) return;
      final y = box.globalToLocal(_pointer!).dy;
      final delta = y < 36
          ? -12.0
          : y > box.size.height - 36
          ? 12.0
          : 0.0;
      if (delta != 0) _scroll.jumpTo((_scroll.offset + delta).clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  OutlineDrop _placement(BuildContext context, Offset pointer) {
    final box = context.findRenderObject()! as RenderBox;
    final fraction = box.globalToLocal(pointer).dy / box.size.height;
    return fraction < 0.25
        ? OutlineDrop.before
        : fraction > 0.75
        ? OutlineDrop.after
        : OutlineDrop.inside;
  }

  void _hover(String id, OutlineDrop drop) {
    if (_dropId == id && _drop == drop) return;
    _expand?.cancel();
    setState(() {
      _dropId = id;
      _drop = drop;
    });
    if (drop == OutlineDrop.inside && _collapsed.contains(id)) {
      _expand = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _collapsed.remove(id));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final roots = _roots;
    PdfOutlineEntry? active;
    for (final entry in OutlineTree.flatten(roots)) {
      if (entry.page > 0 && entry.page <= widget.pdf.currentPage && (active == null || entry.page >= active.page)) {
        active = entry;
      }
    }
    if (_lastPage != widget.pdf.currentPage) {
      _lastPage = widget.pdf.currentPage;
      bool reveal(List<PdfOutlineEntry> entries) {
        for (final entry in entries) {
          if (entry.id == active?.id) return true;
          if (reveal(entry.children)) {
            _collapsed.remove(entry.id);
            return true;
          }
        }
        return false;
      }

      reveal(roots);
    }
    final rows = <(PdfOutlineEntry, int, List<PdfOutlineEntry>)>[];
    void collect(List<PdfOutlineEntry> entries, int depth) {
      for (final entry in entries) {
        rows.add((entry, depth, entries));
        if (!_collapsed.contains(entry.id)) collect(entry.children, depth + 1);
      }
    }

    collect(roots, 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReaderEntryHeader(
          title: l.readerOutline,
          addLabel: l.addOutlineEntry,
          onAdd: _add,
          canSort: rows.length > 1,
          onSort: (order) => _edit((roots) => OutlineTree.sort(roots, order)),
        ),
        Expanded(
          child: SizedBox(
            key: _viewport,
            child: roots.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l.noOutlineEntries,
                        textAlign: TextAlign.center,
                        style: context.mmText.callout.copyWith(color: c.secondaryLabel),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(MMSizes.sidebarInset),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final (entry, depth, siblings) = rows[index];
                      final selected = entry.id == active?.id;
                      final folded = _collapsed.contains(entry.id);
                      final siblingIndex = siblings.indexWhere((e) => e.id == entry.id);
                      final menu = <MMMenuEntry>[
                        MMMenuItem(l.editOutlineEntry, () => _rename(entry), icon: MMIcons.editNote),
                        MMMenuItem(l.addOutlineEntry, () => _add(target: entry), icon: MMIcons.addTopic),
                        MMMenuItem(l.addOutlineChild, () => _add(target: entry, child: true), icon: MMIcons.syncToMap),
                        const MMMenuDivider(),
                        MMMenuItem(
                          l.moveUp,
                          siblingIndex == 0 ? null : () => _shift(entry, siblings, -1),
                          icon: MMIcons.moveUp,
                        ),
                        MMMenuItem(
                          l.moveDown,
                          siblingIndex == siblings.length - 1 ? null : () => _shift(entry, siblings, 1),
                          icon: MMIcons.moveDown,
                        ),
                        const MMMenuDivider(),
                        MMMenuItem(
                          entry.children.isEmpty ? l.deleteOutlineEntry : l.deleteOutlineBranch,
                          () => _edit((roots) => OutlineTree.remove(roots, entry.id)),
                          destructive: true,
                          icon: MMIcons.trash,
                        ),
                      ];
                      final row = MMContextMenuRegion(
                        longPressEnabled: false,
                        onSecondaryTapUp: (details) =>
                            showMMMenu(context, position: details.globalPosition, entries: menu),
                        child: MMInteractive(
                          tooltip: '${entry.title}\n${l.outlineDragHint}',
                          onTap: entry.page > 0 ? () => widget.pdf.jumpToPage(entry.page) : () {},
                          selected: selected,
                          builder: (context, state) => Container(
                            constraints: BoxConstraints(minHeight: context.mmSidebarRow),
                            padding: EdgeInsets.fromLTRB(2 + math.min(depth, 6) * 12.0, 2, 2, 2),
                            decoration: BoxDecoration(
                              color: _dropId == entry.id && _drop == OutlineDrop.inside
                                  ? c.accentTint
                                  : selected
                                  ? c.selectedRow
                                  : state.hovered
                                  ? c.hover
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(MMRadii.row),
                            ),
                            foregroundDecoration: _dropId == entry.id && _drop != OutlineDrop.inside
                                ? BoxDecoration(
                                    border: Border(
                                      top: BorderSide(
                                        color: _drop == OutlineDrop.before ? c.accent : Colors.transparent,
                                        width: 2,
                                      ),
                                      bottom: BorderSide(
                                        color: _drop == OutlineDrop.after ? c.accent : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  )
                                : null,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 20,
                                  child: entry.children.isEmpty
                                      ? null
                                      : MMInteractive(
                                          key: ValueKey('outline-fold-${entry.id}'),
                                          semanticLabel: folded ? l.expandSection : l.collapseSection,
                                          onTap: () => setState(
                                            () => folded ? _collapsed.remove(entry.id) : _collapsed.add(entry.id),
                                          ),
                                          builder: (context, _) => Icon(
                                            folded ? MMIcons.chevronRight : MMIcons.chevronDown,
                                            size: 10,
                                            color: c.secondaryLabel,
                                          ),
                                        ),
                                ),
                                Expanded(
                                  child: Tooltip(
                                    message: entry.title,
                                    child: Text(
                                      entry.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.mmText.callout.copyWith(
                                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                        color: entry.page > 0 ? c.label : c.secondaryLabel,
                                      ),
                                    ),
                                  ),
                                ),
                                if (entry.page > 0)
                                  Padding(padding: const EdgeInsets.only(left: 4), child: MMCount(entry.page)),
                                Builder(
                                  builder: (context) => MMToolbarButton(
                                    icon: MMIcons.more,
                                    tooltip: l.readerEntryActions,
                                    onPressed: () {
                                      final box = context.findRenderObject()! as RenderBox;
                                      showMMMenu(
                                        context,
                                        position: box.localToGlobal(Offset(0, box.size.height)),
                                        entries: menu,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                      return Builder(
                        key: ValueKey('outline-${entry.id}'),
                        builder: (context) => DragTarget<_OutlineDrag>(
                          onWillAcceptWithDetails: (details) =>
                              details.data.documentId == widget.document.id &&
                              OutlineTree.canMove(roots, details.data.id, entry.id),
                          onMove: (details) => _hover(entry.id, _placement(context, details.offset)),
                          onLeave: (_) {
                            if (_dropId == entry.id) {
                              _expand?.cancel();
                              setState(() {
                                _dropId = null;
                                _drop = null;
                              });
                            }
                          },
                          onAcceptWithDetails: (details) {
                            final drop = _placement(context, details.offset);
                            _edit((roots) => OutlineTree.move(roots, details.data.id, entry.id, drop));
                            setState(() => _collapsed.remove(entry.id));
                            _stopDrag();
                          },
                          builder: (context, _, _) {
                            final feedback = Material(
                              color: c.sidebarOpaque,
                              elevation: 4,
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 220,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    entry.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.mmText.callout,
                                  ),
                                ),
                              ),
                            );
                            if (MMInput.of(context).touchPlatform) {
                              return LongPressDraggable<_OutlineDrag>(
                                data: _OutlineDrag(widget.document.id, entry.id),
                                feedback: feedback,
                                dragAnchorStrategy: pointerDragAnchorStrategy,
                                onDragUpdate: _scrollWhileDragging,
                                onDragEnd: (_) => _stopDrag(),
                                childWhenDragging: Opacity(opacity: 0.35, child: row),
                                child: row,
                              );
                            }
                            return Draggable<_OutlineDrag>(
                              data: _OutlineDrag(widget.document.id, entry.id),
                              feedback: feedback,
                              dragAnchorStrategy: pointerDragAnchorStrategy,
                              onDragUpdate: _scrollWhileDragging,
                              onDragEnd: (_) => _stopDrag(),
                              childWhenDragging: Opacity(opacity: 0.35, child: row),
                              child: row,
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
