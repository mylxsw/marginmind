import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../app/app_commands.dart';
import '../../../shared/l10n.dart';
import '../reader_margin.dart';
import '../workspace_controller.dart';
import 'reader_bookmarks.dart';
import 'reader_outline.dart';

/// Width of the page sidebar inside the source pane.
const readerSidebarWidth = MMSizes.readerSidebarWidth;

/// Page sidebar of the source pane: thumbnails, the PDF's own table of
/// contents, the reader's bookmarks, highlights and margin notes.
class ReaderSidebar extends ConsumerWidget {
  const ReaderSidebar({
    super.key,
    required this.studySetId,
    required this.document,
    required this.pdf,
    this.width = readerSidebarWidth,
  });

  final String studySetId;
  final Document document;
  final MMPdfViewController pdf;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final provider = workspaceProvider(studySetId);
    final controller = ref.read(provider.notifier);
    final mode = ref.watch(provider.select((s) => s.readerPanelMode));
    final content = ref.watch(workspaceContentProvider(studySetId)) ?? StudySetContent.empty;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: c.sidebarOpaque,
        border: Border(right: BorderSide(color: c.separator)),
      ),
      child: ListenableBuilder(
        listenable: pdf,
        builder: (context, _) {
          final shown = mode;
          final tabs = <(ReaderPanelMode, IconData, String, SingleActivator)>[
            (ReaderPanelMode.thumbnails, MMIcons.thumbnails, l.readerThumbnails, AppShortcuts.readerThumbnails),
            (ReaderPanelMode.outline, MMIcons.outline, l.readerOutline, AppShortcuts.readerOutline),
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
                  ReaderPanelMode.outline => ReaderOutline(
                    key: ValueKey(document.id),
                    studySetId: studySetId,
                    document: document,
                    pdf: pdf,
                    outline: content.outlineOn(document.id),
                  ),
                  ReaderPanelMode.bookmarks => ReaderBookmarks(
                    document: document,
                    studySetId: studySetId,
                    pdf: pdf,
                    bookmarks: content.bookmarksOn(document.id),
                  ),
                  ReaderPanelMode.annotations => _Annotations(
                    studySetId: studySetId,
                    pdf: pdf,
                    annotations: content.annotationsOn(document.id),
                    notes: content.marginNotes.where((n) => n.documentId == document.id).toList(),
                  ),
                },
              ),
            ],
          );
        },
      ),
    );
  }
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

// ---- annotations ----------------------------------------------------------------

class _AnnotationEntry {
  const _AnnotationEntry.highlight(Annotation value) : highlight = value, note = null;
  const _AnnotationEntry.note(MarginNote value) : note = value, highlight = null;

  final Annotation? highlight;
  final MarginNote? note;

  String get id => highlight == null ? 'margin-note-${note!.id}' : 'annotation-${highlight!.id}';
  int get page => highlight?.page ?? note!.page;
  int get colorIndex => highlight?.colorIndex ?? note!.colorIndex;
  DateTime get createdAt => highlight?.createdAt ?? note!.createdAt;
  String get text => highlight?.quote ?? note!.text;
}

class _Annotations extends ConsumerWidget {
  const _Annotations({required this.studySetId, required this.pdf, required this.annotations, required this.notes});

  final String studySetId;
  final MMPdfViewController pdf;
  final List<Annotation> annotations;
  final List<MarginNote> notes;

  Future<void> _open(BuildContext context, WidgetRef ref, _AnnotationEntry entry) async {
    final session = ref.read(readerMarginProvider(studySetId).notifier);
    if (!await session.finish() || !context.mounted) return;
    // Saving changes the margin layout. Let it consume that revision before
    // issuing a jump, so its reading-position restoration cannot undo the jump.
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;
    ref.read(workspaceProvider(studySetId).notifier).dismissPending();
    if (entry.note case final note?) {
      // Line notes have no quote rectangles; reveal their original PDF line.
      final rects =
          note.anchor?.pages.first.rects ??
          [PageRect(0, note.lineY!, pdf.pageSize(note.page)?.width ?? 1, note.lineY!)];
      session.show([note]);
      await pdf.jumpToRect(note.page, rects);
    } else {
      await session.close();
      if (!context.mounted) return;
      final first = entry.highlight!.pages.first;
      await pdf.jumpToRect(first.page, first.rects);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final entries =
        [
          for (final annotation in annotations) _AnnotationEntry.highlight(annotation),
          for (final note in notes) _AnnotationEntry.note(note),
        ]..sort((a, b) {
          final byPage = a.page.compareTo(b.page);
          if (byPage != 0) return byPage;
          final byCreated = a.createdAt.compareTo(b.createdAt);
          return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
        });
    if (entries.isEmpty) return _Empty(label: l.noAnnotations);
    final popup = ref.watch(readerMarginProvider(studySetId).select((s) => s.popup));
    return ListView.builder(
      padding: const EdgeInsets.all(MMSizes.sidebarInset),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final color = MMAnnotationColor.fromIndex(entry.colorIndex);
        final label = entry.text.isEmpty ? (entry.note == null ? l.toolArea : l.marginNoteAction) : entry.text;
        final selected = entry.note != null && popup.contains(entry.note!.id);
        return MMInteractive(
          key: ValueKey(entry.id),
          onTap: () => _open(context, ref, entry),
          tooltip: label,
          selected: selected,
          semanticLabel: entry.note == null ? label : '${l.marginNoteAction}: $label',
          semanticValue: l.pageNumber(entry.page),
          builder: (context, s) => Container(
            constraints: BoxConstraints(minHeight: context.mmSidebarRow),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? c.selectedRow : (s.hovered ? c.hover : Colors.transparent),
              borderRadius: BorderRadius.circular(MMRadii.row),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: MMSpacing.s),
                  child: entry.note != null
                      ? Icon(MMIcons.marginNote, size: t.callout.fontSize, color: color.color)
                      : Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: color.color, shape: BoxShape.circle),
                        ),
                ),
                Expanded(
                  child: Text(label, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.callout),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: MMSpacing.xs),
                  child: MMCount(entry.page),
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
