import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';
import '../reader_crop.dart';
import '../reader_compare.dart';
import '../reader_margin.dart';
import '../workspace_controller.dart';

TextStyle marginNoteTextStyle(BuildContext context, MMReaderStyle style) =>
    context.mmText.body.copyWith(fontSize: 12, height: 1.55, color: style.marginNoteText);

double marginNoteHeight(
  BuildContext context,
  MarginNote note,
  double width,
  MMReaderStyle style, {
  bool editing = false,
}) {
  final text = TextPainter(
    text: TextSpan(text: note.text.isEmpty ? ' ' : note.text, style: marginNoteTextStyle(context, style)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: math.max(1, width - 23));
  final height = math.max(editing ? 37.2 : 18.6, text.height) + 18 + (note.nodeId == null ? 0 : 14);
  text.dispose();
  return height;
}

/// PDF owns coordinates and total extent; interactive cards are viewport siblings.
MMPdfMargin readerMargin(
  BuildContext context,
  WidgetRef ref,
  String studySetId,
  Document doc,
  MMReaderStyle style, {
  bool forceCollapsed = false,
}) {
  final state = ref.watch(readerMarginProvider(studySetId));
  final session = ref.read(readerMarginProvider(studySetId).notifier);
  final notes = session.notes(doc.id);
  final byPage = <int, List<MarginNote>>{};
  for (final note in notes) {
    (byPage[note.page] ??= []).add(note);
  }
  // Only nearby pages are measured. Previously visited pages retain their
  // overflow extent; the PDF reserves it before painting interactive cards.
  final extentCache = <int, double>{};
  double? extentZoom;
  return MMPdfMargin(
    backgroundColor: style.marginFill,
    revision: jsonEncode([
      state.draft?.id,
      MediaQuery.textScalerOf(context).scale(12),
      for (final n in notes) n.toJson(),
    ]),
    requested: state.openDocuments.contains(doc.id),
    forceCollapsed: forceCollapsed,
    extent: (page, original, crop, zoom) {
      if (extentZoom != zoom) {
        extentCache.clear();
        extentZoom = zoom;
      }
      return extentCache.putIfAbsent(page, () {
        final height = original.height - crop.top - crop.bottom;
        final transform = PageViewportTransform(pageSize: original, crop: crop, scale: zoom);
        final placements = layoutMarginNotes(
          byPage[page] ?? [],
          transform: transform,
          height: (n) => marginNoteHeight(context, n, 180 * zoom, style, editing: n.id == state.draft?.id),
        );
        return placements.isEmpty
            ? 0
            : math.max(0, (placements.last.top + placements.last.height + 8 * zoom) / zoom - height);
      });
    },
    builder: (context, viewport) => [
      for (final page in viewport.pages)
        ..._page(context, ref, studySetId, doc, style, page, viewport, byPage[page.page] ?? [], state),
    ],
  );
}

List<Widget> _page(
  BuildContext context,
  WidgetRef ref,
  String studySetId,
  Document doc,
  MMReaderStyle style,
  MMPdfMarginPage page,
  MMPdfMarginViewport viewport,
  List<MarginNote> notes,
  ReaderMarginState state,
) {
  final session = ref.read(readerMarginProvider(studySetId).notifier);
  final scale = viewport.zoom;
  final width = 180 * scale;
  final placements = viewport.expanded
      ? layoutMarginNotes(
          notes,
          transform: page.transform,
          height: (n) => marginNoteHeight(context, n, width, style, editing: state.draft?.id == n.id),
        )
      : <MarginPlacement>[];
  Future<void> edit(MarginNote note) => session.start(doc.id, existing: note);
  final popupNotes = notes.where((n) => state.popup.contains(n.id)).toList();
  final popup = !viewport.expanded && popupNotes.isNotEmpty;
  final anchorY = popup ? marginAnchorY(popupNotes.first, page.transform) : 0.0;
  return [
    if (viewport.expanded)
      Positioned(
        left: page.rect.right,
        top: page.rect.top,
        width: 200 * scale,
        height: page.rect.height + page.extent,
        child: _MarginBlank(
          key: ValueKey('margin-column-${page.page}'),
          style: style,
          onTap: (y) => session.start(
            doc.id,
            page: page.page,
            lineY: page.transform
                .toPdf(Offset(page.rect.right, page.rect.top + y))
                .dy
                .clamp(0, page.transform.pageSize.height),
          ),
        ),
      ),
    for (final note in notes)
      if (note.anchor case final anchor?)
        for (final r in anchor.pages.first.rects)
          (() {
            final rect = page.transform.rect(r).intersect(page.rect);
            if (rect.isEmpty) return const SizedBox.shrink();
            return Positioned.fromRect(
              rect: rect,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => session.hover(note.id),
                onExit: (_) => session.hover(null),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => viewport.expanded ? edit(note) : session.show([note]),
                  child: CustomPaint(painter: _AnchorPainter(style.marginNoteLine, state.hovered == note.id)),
                ),
              ),
            );
          })()
      else
        Positioned(
          left: page.rect.right - 14 * scale,
          top: marginAnchorY(note, page.transform),
          width: 14 * scale,
          height: 4,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => session.hover(note.id),
            onExit: (_) => session.hover(null),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => viewport.expanded ? edit(note) : session.show([note]),
              child: CustomPaint(painter: _AnchorPainter(style.marginNoteLine, state.hovered == note.id)),
            ),
          ),
        ),
    if (viewport.expanded) ...[
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(painter: _ConnectionPainter(placements, page, style.marginNoteLine, state.hovered)),
        ),
      ),
      for (final placement in placements)
        Positioned(
          left: page.rect.right + 10 * scale,
          top: placement.top,
          width: width,
          child: MarginNoteCard(
            key: ValueKey('margin-card-${placement.note.id}'),
            studySetId: studySetId,
            note: placement.note,
            style: style,
          ),
        ),
    ] else ...[
      for (final group in groupMarginMarkers(notes, page.transform))
        Positioned(
          left: page.rect.right - (group.length > 1 ? 42 : 25),
          top: marginAnchorY(group.first, page.transform).clamp(page.rect.top + 4, page.rect.bottom - 18),
          child: Tooltip(
            message: context.l10n.marginNotes,
            child: MouseRegion(
              onEnter: (_) => session.hover(group.first.id),
              onExit: (_) => session.hover(null),
              child: GestureDetector(
                onTap: () => session.show(group),
                child: Container(
                  key: ValueKey('margin-marker-${group.first.id}'),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: style.marginNoteMarker,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(9),
                      topRight: Radius.circular(9),
                      bottomRight: Radius.circular(9),
                      bottomLeft: Radius.circular(3),
                    ),
                    boxShadow: context.mmColors.flat
                        ? null
                        : const [BoxShadow(color: Color(0x2E000000), blurRadius: 3, offset: Offset(0, 1))],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(MMIcons.marginNote, size: 10, color: Color(0xFF3A3A3C)),
                      if (group.length > 1)
                        Text(' ${group.length}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF3A3A3C))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      if (popup)
        Positioned.fill(
          child: MMFloatingToolbarLayout(
            anchor: Rect.fromLTWH(page.rect.right - 25, anchorY, 25, 18),
            child: TapRegion(
              onTapOutside: (_) => session.close(),
              child: MMGlass(
                key: const ValueKey('margin-popover'),
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 280,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: math.max(100, viewport.size.height - 40)),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final note in popupNotes) ...[
                            MarginNoteCard(
                              key: ValueKey('margin-card-${note.id}'),
                              studySetId: studySetId,
                              note: note,
                              style: style,
                            ),
                            const SizedBox(height: 8),
                          ],
                          Consumer(
                            builder: (context, ref, _) {
                              final crop = ref.watch(readerCropProvider(studySetId));
                              final automatic = crop.automatic;
                              final pageWidth = page.transform.pageSize.width;
                              final canExpand = marginFits(
                                viewport.size.width,
                                pageWidth -
                                    (doc.crop?.forPage(page.page).left ?? 0) -
                                    (doc.crop?.forPage(page.page).right ?? 0),
                              );
                              final canCrop =
                                  !canExpand &&
                                  doc.crop?.enabled != true &&
                                  automatic != null &&
                                  marginFits(viewport.size.width, pageWidth - automatic.all.left - automatic.all.right);
                              if (ref.watch(readerCompareProvider(studySetId)) != null ||
                                  crop.editing ||
                                  (!canExpand && !canCrop)) {
                                return const SizedBox.shrink();
                              }
                              return Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  key: const ValueKey('margin-expand'),
                                  onPressed: () async {
                                    if (!await session.finish()) return;
                                    if (canCrop) await ref.read(readerCropProvider(studySetId).notifier).toggle();
                                    session.expand(doc.id);
                                  },
                                  child: Text(canCrop ? context.l10n.cropExpandMargin : context.l10n.expandMargin),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  ];
}

class _MarginBlank extends StatefulWidget {
  const _MarginBlank({super.key, required this.style, required this.onTap});
  final MMReaderStyle style;
  final ValueChanged<double> onTap;
  @override
  State<_MarginBlank> createState() => _MarginBlankState();
}

class _MarginBlankState extends State<_MarginBlank> {
  double? _y;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.text,
    onHover: (e) => setState(() => _y = e.localPosition.dy),
    onExit: (_) => setState(() => _y = null),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (e) => widget.onTap(e.localPosition.dy),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _GuidePainter(widget.style.marginGuide))),
          ),
          if (_y != null)
            Positioned(
              left: 10,
              right: 10,
              top: math.max(0, _y! - 11),
              height: 22,
              child: Text(
                context.l10n.writeMarginNote,
                style: context.mmText.footnote.copyWith(color: widget.style.marginNoteText.withValues(alpha: .6)),
              ),
            ),
        ],
      ),
    ),
  );
}

class MarginNoteCard extends ConsumerStatefulWidget {
  const MarginNoteCard({super.key, required this.studySetId, required this.note, required this.style});
  final String studySetId;
  final MarginNote note;
  final MMReaderStyle style;
  @override
  ConsumerState<MarginNoteCard> createState() => _MarginNoteCardState();
}

class _MarginNoteCardState extends ConsumerState<MarginNoteCard> {
  late final TextEditingController _text = TextEditingController(text: widget.note.text);
  final _focus = FocusNode();
  bool _menuOpen = false;
  bool _wasEditing = false;
  ReaderMarginSession get _session => ref.read(readerMarginProvider(widget.studySetId).notifier);
  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted &&
          !_focus.hasFocus &&
          ref.read(readerMarginProvider(widget.studySetId)).draft?.id == widget.note.id) {
        _session.finish();
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _finishFromKeyboard() async {
    if (!await _session.finish() || !mounted) return;
    // The temporary field leaves the tree after saving. Keep Esc/navigation
    // in the reader instead of dropping focus into the window's root scope.
    Focus.of(context).requestFocus();
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong);
    }
  }

  Future<void> _attach() => _perform(_attachImpl);

  Future<void> _attachImpl() async {
    final id = widget.note.id;
    if (!await _session.finish() || !mounted) return;
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    if (widget.note.nodeId != null) {
      await controller.locateMarginNote(id);
      return;
    }
    final card = await controller.attachMarginNote(id);
    if (!mounted || card == null) return;
    final onlyReader = ref.read(workspaceProvider(widget.studySetId)).layout == MMSplitMode.primary;
    MMHud.show(
      context,
      context.l10n.marginNoteAddedToMap,
      action: onlyReader
          ? (context.l10n.excerptView, () => controller.locateMarginNote(id))
          : (context.l10n.undo, () => controller.undo()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerMarginProvider(widget.studySetId));
    final note = widget.note;
    final editing = state.draft?.id == note.id;
    if (editing && !_wasEditing) {
      // Autofocus does not replace focus already held by the selection toolbar
      // in this scope. Hand it over after the editor joins the focus tree.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(readerMarginProvider(widget.studySetId)).draft?.id == widget.note.id) {
          _focus.requestFocus();
        }
      });
    }
    _wasEditing = editing;
    final hovered = state.hovered == note.id;
    final color = MMAnnotationColor.fromIndex(note.colorIndex);
    final l = context.l10n;
    if (editing && (_text.text != note.text || !_text.selection.isValid)) {
      _text.value = TextEditingValue(
        text: note.text,
        selection: TextSelection.collapsed(offset: note.text.length),
      );
    }
    return TapRegion(
      onTapOutside: (_) {
        if (editing) _session.finish();
      },
      child: MouseRegion(
        onEnter: (_) => _session.hover(note.id),
        onExit: (_) => _session.hover(null),
        child: CallbackShortcuts(
          bindings: {
            if (editing)
              const SingleActivator(LogicalKeyboardKey.escape): _finishFromKeyboard
            else if (state.popup.contains(note.id))
              const SingleActivator(LogicalKeyboardKey.escape): _session.close,
            primaryShortcut(LogicalKeyboardKey.enter): _finishFromKeyboard,
            if (!editing)
              const SingleActivator(LogicalKeyboardKey.enter): () => _session.start(note.documentId, existing: note),
            if (!editing) const SingleActivator(LogicalKeyboardKey.backspace): () => _session.delete(note),
          },
          child: Focus(
            child: GestureDetector(
              onTap: () => _session.start(note.documentId, existing: note),
              child: Container(
                decoration: BoxDecoration(
                  color: widget.style.marginNoteFill(color),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hovered || editing ? color.color : const Color(0x14000000),
                    width: hovered || editing ? 1.5 : .5,
                  ),
                  boxShadow: context.mmColors.flat
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: hovered ? .12 : .06),
                            blurRadius: hovered ? 14 : 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 4,
                      top: 7,
                      bottom: 7,
                      width: 2.5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: color.color, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(11, 7, 9, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (editing)
                            TextField(
                              key: ValueKey('margin-editor-${note.id}'),
                              controller: _text,
                              focusNode: _focus,
                              minLines: 2,
                              maxLines: null,
                              style: marginNoteTextStyle(context, widget.style),
                              decoration: const InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: _session.text,
                              onTapOutside: (_) => _session.finish(),
                              onEditingComplete: _session.finish,
                            )
                          else
                            Text(note.text, style: marginNoteTextStyle(context, widget.style)),
                          if (note.nodeId != null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                height: 14,
                                child: GestureDetector(
                                  onTap: _attach,
                                  child: Icon(MMIcons.mindMap, size: 10, color: context.mmColors.accent),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (hovered || editing || _menuOpen)
                      Positioned(
                        right: 3,
                        top: 3,
                        child: Container(
                          decoration: BoxDecoration(
                            color: context.mmColors.card.withValues(alpha: .92),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  iconSize: 12,
                                  tooltip: note.nodeId == null ? l.addToMapAction : l.locateCard,
                                  onPressed: _attach,
                                  icon: const Icon(MMIcons.mindMap),
                                ),
                              ),
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: PopupMenuButton<Object>(
                                  popUpAnimationStyle: AnimationStyle.noAnimation,
                                  padding: EdgeInsets.zero,
                                  iconSize: 12,
                                  tooltip: l.moreTools,
                                  icon: const Icon(MMIcons.more),
                                  onOpened: () => setState(() => _menuOpen = true),
                                  onCanceled: () => setState(() => _menuOpen = false),
                                  onSelected: (value) => _perform(() async {
                                    setState(() => _menuOpen = false);
                                    if (value is int) await _session.recolor(note, value);
                                    if (value == 'delete') await _session.delete(note);
                                    if (value == 'map') await _attach();
                                    if (value == 'copy') {
                                      await Clipboard.setData(ClipboardData(text: note.text));
                                      if (context.mounted) MMHud.show(context, l.copiedHud);
                                    }
                                  }),
                                  itemBuilder: (_) => [
                                    PopupMenuItem<Object>(
                                      enabled: false,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          for (final c in MMAnnotationColor.values)
                                            MMFloatingToolbarColor(
                                              color: c,
                                              selected: c == color,
                                              tooltip: l.colorName(c),
                                              onPressed: () => Navigator.pop(context, c.index),
                                            ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'map',
                                      child: Text(note.nodeId == null ? l.addToMapAction : l.locateCard),
                                    ),
                                    PopupMenuItem(value: 'copy', child: Text(l.copyAction)),
                                    PopupMenuItem(value: 'delete', child: Text(l.delete)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _dash(Canvas canvas, Offset from, Offset to, Paint paint, {double dash = 3}) {
  final length = (to - from).distance;
  if (length == 0) return;
  final direction = (to - from) / length;
  for (var d = 0.0; d < length; d += dash * 2) {
    canvas.drawLine(from + direction * d, from + direction * math.min(d + dash, length), paint);
  }
}

class _AnchorPainter extends CustomPainter {
  const _AnchorPainter(this.color, this.active);
  final Color color;
  final bool active;
  @override
  void paint(Canvas canvas, Size size) {
    if (active) canvas.drawRect(Offset.zero & size, Paint()..color = Colors.yellow.withValues(alpha: .22));
    _dash(
      canvas,
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      Paint()
        ..color = color
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_AnchorPainter old) => old.active != active || old.color != color;
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) =>
      _dash(canvas, const Offset(0, 14), Offset(0, size.height - 14), Paint()..color = color);
  @override
  bool shouldRepaint(_GuidePainter old) => old.color != color;
}

class _ConnectionPainter extends CustomPainter {
  const _ConnectionPainter(this.placements, this.page, this.color, this.hovered);
  final List<MarginPlacement> placements;
  final MMPdfMarginPage page;
  final Color color;
  final String? hovered;
  @override
  void paint(Canvas canvas, Size size) {
    for (final p in placements) {
      final active = p.note.id == hovered;
      final last = p.note.anchor?.pages.first.rects.last;
      final from = active && last != null
          ? page.transform.rect(last).bottomRight
          : Offset(page.rect.right - 16 * page.transform.scale, p.anchorY);
      final turn = Offset(page.rect.right + 3 * page.transform.scale, from.dy);
      final end = Offset(page.rect.right + 10 * page.transform.scale, p.top + 11);
      final paint = Paint()
        ..color = color.withValues(alpha: active ? 1 : .55)
        ..strokeWidth = active ? 1.4 : 1;
      _dash(canvas, from, turn, paint);
      _dash(canvas, turn, end, paint);
    }
  }

  @override
  bool shouldRepaint(_ConnectionPainter old) => true;
}
