import '../../study_notes/note_setup_sheet.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../app/app_commands.dart';
import '../../../settings/app_settings.dart';
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
      width: math.max(0, width - MMSpacing.m),
      margin: const EdgeInsets.all(MMSpacing.m / 2),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.sidebarOpaque,
        borderRadius: BorderRadius.circular(MMRadii.sidebar),
        border: Border.all(color: c.border, width: MMSizes.hairline),
      ),
      child: ListenableBuilder(
        listenable: pdf,
        builder: (context, _) {
          final shown = mode;
          final tabs = <(ReaderPanelMode, IconData, String, SingleActivator)>[
            if (document.contentManifest == null)
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
                child: LayoutBuilder(
                  builder: (context, bounds) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: bounds.maxWidth),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final (value, icon, label, shortcut) in tabs)
                            MMToolbarButton(
                              icon: icon,
                              tooltip: AppShortcuts.tip(label, shortcut),
                              selected: value == shown,
                              onPressed: controller.canShowReaderPanel(value)
                                  ? () => controller.setReaderPanelMode(value)
                                  : null,
                            ),
                        ],
                      ),
                    ),
                  ),
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
                    document: document,
                    studySetId: studySetId,
                    pdf: pdf,
                    annotations: content.annotationsOn(document.id),
                    notes: content.marginNotes.where((n) => n.documentId == document.id).toList(),
                    ink: content.inkStrokes.where((s) => s.documentId == document.id && s.textAnchor == null).toList(),
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
  const _AnnotationEntry.highlight(Annotation value) : highlight = value, note = null, ink = const [];
  const _AnnotationEntry.note(MarginNote value) : note = value, highlight = null, ink = const [];
  const _AnnotationEntry.ink(this.ink) : highlight = null, note = null;

  final Annotation? highlight;
  final MarginNote? note;
  final List<InkStroke> ink;

  String get id => ink.isNotEmpty
      ? 'ink-page-$page'
      : highlight == null
      ? 'margin-note-${note!.id}'
      : 'annotation-${highlight!.id}';
  int get page => ink.isNotEmpty ? ink.first.page : (highlight?.isText == true ? 0 : highlight?.page ?? note!.page);
  bool get needsReview => highlight?.needsReview ?? false;
  DateTime get createdAt => highlight?.createdAt ?? note?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
}

class _Annotations extends ConsumerWidget {
  const _Annotations({
    required this.document,
    required this.studySetId,
    required this.pdf,
    required this.annotations,
    required this.notes,
    required this.ink,
  });

  final Document document;

  final String studySetId;
  final MMPdfViewController pdf;
  final List<Annotation> annotations;
  final List<MarginNote> notes;
  final List<InkStroke> ink;

  Future<void> _open(BuildContext context, WidgetRef ref, _AnnotationEntry entry) async {
    final session = ref.read(readerMarginProvider(studySetId).notifier);
    if (!await session.finish() || !context.mounted) return;
    // Saving changes the margin layout. Let it consume that revision before
    // issuing a jump, so its reading-position restoration cannot undo the jump.
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;
    final controller = ref.read(workspaceProvider(studySetId).notifier);
    controller.dismissPending();
    if (entry.needsReview || entry.highlight?.isText == true) {
      await session.close();
      if (!context.mounted) return;
      final annotation = entry.highlight!;
      if (annotation.isText) {
        final anchors = entry.needsReview
            ? [
                TextAnchor(
                  document.origin == null ? annotation.textAnchors.first.chapterId : 'main',
                  0,
                  0,
                  '',
                  revision: document.revision!,
                ),
              ]
            : annotation.textAnchors;
        await controller.revealAnchor(
          SourceAnchor(
            target: TextTarget(documentId: document.id, textAnchors: anchors),
          ),
        );
      } else {
        // A removed PDF passage has no usable rectangles. Use its chapter's
        // first page, falling back to the document start when there is no TOC.
        await pdf.jumpToPage(_chapter(entry, controller).page.clamp(1, math.max(1, document.pageCount)));
      }
      if (entry.needsReview && context.mounted) {
        MMHud.show(context, context.l10n.annotationNotFound, icon: MMIcons.warning);
      }
    } else if (entry.ink.isNotEmpty) {
      await session.close();
      if (!context.mounted) return;
      await pdf.jumpToPage(entry.page);
    } else if (entry.note case final note?) {
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

  ({String title, int page}) _chapter(_AnnotationEntry entry, WorkspaceController controller) {
    if (entry.highlight?.isText == true) return (title: document.title, page: 0);
    final custom = controller.content.outlineOn(document.id);
    final locations = custom == null
        ? flattenOutline(pdf.outline).map((e) => (title: e.title, page: e.page))
        : OutlineTree.flatten(custom.items)
              .where((e) => e.position is! TextReadingPosition)
              .map((e) => (title: e.title, page: e.page));
    var chapter = (title: document.title, page: 1);
    for (final location in locations) {
      if (location.page > 0 && location.page <= entry.page && location.page >= chapter.page) chapter = location;
    }
    return chapter;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final colors = ref.watch(workspaceProvider(studySetId).select((s) => s.annotationColors));
    final visibleAnnotations = annotations.where((a) => a.colorIndex > 5 || colors.contains(a.colorIndex)).toList();
    final inkPages = <int, List<InkStroke>>{};
    for (final stroke in ink) {
      (inkPages[stroke.page] ??= []).add(stroke);
    }
    final entries =
        [
          for (final annotation in visibleAnnotations) _AnnotationEntry.highlight(annotation),
          for (final note in notes.where((n) => n.anchor?.textAnchors.isEmpty ?? true)) _AnnotationEntry.note(note),
          for (final strokes in inkPages.values) _AnnotationEntry.ink(strokes),
        ]..sort((a, b) {
          if (a.needsReview != b.needsReview) return a.needsReview ? -1 : 1;
          final byPage = a.page.compareTo(b.page);
          if (byPage != 0) return byPage;
          final byCreated = a.createdAt.compareTo(b.createdAt);
          return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
        });
    if (annotations.isEmpty && entries.isEmpty) return _Empty(label: l.noAnnotations);
    final reviewCount = entries.where((e) => e.needsReview).length;
    final owner = ref.read(workspaceProvider(studySetId).notifier);
    final betaEnabled = ref.watch(settingsProvider.select((s) => s.betaFeaturesEnabled));
    final selectedIds = ref.watch(workspaceProvider(studySetId).select((s) => s.selectedAnnotationIds));
    final eligible = visibleAnnotations.where((a) => a.quote.trim().isNotEmpty).map((a) => a.id).toSet();
    final allSelected = eligible.isNotEmpty && eligible.every(selectedIds.contains);
    final popup = ref.watch(readerMarginProvider(studySetId).select((s) => s.popup));
    return Column(
      children: [
        const SizedBox(height: MMSpacing.s),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: MMSpacing.xs,
          children: [
            for (var i = 0; i < 6; i++)
              MMInteractive(
                key: ValueKey('annotation-color-$i'),
                tooltip: l.colorName(MMAnnotationColor.fromIndex(i)),
                onTap: () => owner.toggleAnnotationColor(i),
                builder: (_, _) => Padding(
                  padding: const EdgeInsets.all(MMSpacing.xs),
                  child: Opacity(
                    opacity: colors.contains(i) ? 1 : .35,
                    child: Container(
                      width: MMSizes.noteColorDot,
                      height: MMSizes.noteColorDot,
                      decoration: BoxDecoration(color: MMAnnotationColor.fromIndex(i).color, shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
            if (betaEnabled)
              MMButton(
                key: const ValueKey('annotations-select-all'),
                label: allSelected ? l.noteDeselectAll : l.noteSelectAll,
                onPressed: () => owner.selectAnnotations(
                  allSelected ? selectedIds.difference(eligible) : {...selectedIds, ...eligible},
                ),
              ),
          ],
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(MMSizes.sidebarInset),
            itemCount: entries.length + (reviewCount > 0 ? 2 : 0),
            itemBuilder: (context, index) {
              if (reviewCount > 0) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: MMSpacing.s),
                    child: Row(
                      children: [
                        Icon(MMIcons.warning, color: c.caution, size: t.subheadline.fontSize),
                        const SizedBox(width: MMSpacing.s),
                        Text(l.annotationsNeedReview(reviewCount), style: t.subheadline.copyWith(color: c.caution)),
                      ],
                    ),
                  );
                }
                if (index == reviewCount + 1) return Divider(height: MMSpacing.m, thickness: 0.5, color: c.separator);
                index -= index <= reviewCount ? 1 : 2;
              }
              final entry = entries[index];
              final chapter = _chapter(entry, ref.read(workspaceProvider(studySetId).notifier));
              final isInk = entry.ink.isNotEmpty;
              final color = isInk
                  ? c.secondaryLabel
                  : MMAnnotationColor.fromIndex(entry.highlight?.colorIndex ?? entry.note!.colorIndex).color;
              final text = entry.highlight?.quote ?? entry.note?.text ?? '';
              final label = isInk
                  ? l.inkAnnotations
                  : (text.isEmpty ? (entry.note == null ? l.toolArea : l.marginNoteAction) : text);
              final selected = entry.highlight != null
                  ? betaEnabled && selectedIds.contains(entry.highlight!.id)
                  : entry.note != null && popup.contains(entry.note!.id);
              final row = MMInteractive(
                key: ValueKey(entry.id),
                onTap: () => betaEnabled && !entry.needsReview && entry.highlight?.quote.trim().isNotEmpty == true
                    ? owner.selectAnnotation(entry.highlight!.id, !selected)
                    : _open(context, ref, entry),
                // A tooltip's own long-press recognizer would consume the Delete menu.
                tooltip: entry.needsReview ? null : label,
                selected: selected,
                semanticLabel: entry.note == null ? label : '${l.marginNoteAction}: $label',
                semanticValue: entry.page > 0 ? l.pageNumber(entry.page) : document.title,
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
                      if (betaEnabled && entry.highlight?.quote.trim().isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: MMSpacing.xs, right: MMSpacing.s),
                          child: MMCheckbox(
                            key: ValueKey('annotation-check-${entry.highlight!.id}'),
                            value: selected,
                            semanticLabel: label,
                            onChanged: (v) => owner.selectAnnotation(entry.highlight!.id, v),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: MMSpacing.s),
                        child: isInk || entry.note != null
                            ? Icon(
                                isInk ? MMIcons.inkAnnotations : MMIcons.marginNote,
                                size: t.callout.fontSize,
                                color: color,
                              )
                            : Container(width: 3, height: context.mmSidebarRow, color: color),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: !isInk && entry.note == null ? MMTypography.readingExcerpt : t.callout,
                            ),
                            if (isInk)
                              Text(
                                l.inkStrokeCount(entry.ink.length),
                                style: t.footnote.copyWith(color: c.secondaryLabel),
                              ),
                            if (entry.needsReview || entry.highlight?.isText == true)
                              MMInteractive(
                                key: ValueKey('annotation-source-${entry.highlight!.id}'),
                                semanticLabel: l.revealSource,
                                onTap: () => _open(context, ref, entry),
                                builder: (_, _) => Text(
                                  chapter.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.footnote.copyWith(color: entry.needsReview ? c.caution : c.accent),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (entry.page > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: MMSpacing.xs),
                          child: MMInteractive(
                            key: ValueKey('annotation-source-${entry.id}'),
                            semanticLabel: l.revealSource,
                            onTap: () => _open(context, ref, entry),
                            builder: (_, _) => MMCount(entry.page),
                          ),
                        ),
                    ],
                  ),
                ),
              );
              return !entry.needsReview
                  ? row
                  : MMContextMenuRegion(
                      onSecondaryTapUp: (details) => showMMMenu(
                        context,
                        position: details.globalPosition,
                        entries: [
                          MMMenuItem(
                            l.delete,
                            () => ref.read(workspaceProvider(studySetId).notifier).deleteHighlight(entry.highlight!.id),
                            destructive: true,
                            icon: MMIcons.trash,
                          ),
                        ],
                      ),
                      child: row,
                    );
            },
          ),
        ),
        if (betaEnabled && selectedIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(MMSpacing.s),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: MMSpacing.s,
              runSpacing: MMSpacing.s,
              children: [
                Text(l.noteSelectedCount(selectedIds.length), style: t.footnote),
                MMButton(
                  key: const ValueKey('annotations-organize'),
                  label: l.organizeSelection,
                  variant: MMButtonVariant.primary,
                  onPressed: () => showNoteSetupSheet(context, ref, studySetId),
                ),
              ],
            ),
          ),
      ],
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
