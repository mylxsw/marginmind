import '../../../app/providers.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../shared/l10n.dart';
import '../reader_crop.dart';
import '../workspace_controller.dart';

class CropControls extends ConsumerWidget {
  const CropControls({super.key, required this.studySetId, required this.document, this.documentScoped = false});
  final String studySetId;
  final Document document;
  final bool documentScoped;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = documentScoped
        ? readerDocumentCropProvider((studySetId, document.id))
        : readerCropProvider(studySetId);
    final state = ref.watch(provider);
    final session = ref.read(provider.notifier);
    final l = context.l10n, c = context.mmColors;
    if (!state.editing) {
      final crop = state.automatic?.all;
      if (document.crop?.enabled == true ||
          document.cropSuggestionDismissed ||
          crop == null ||
          crop.left + crop.right <= 100) {
        return const SizedBox.shrink();
      }
      return MMGlass(
        key: const ValueKey('crop-suggestion'),
        padding: const EdgeInsets.all(MMSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MMToolbarButton(
              compact: true,
              icon: MMIcons.crop,
              label: l.cropMargins,
              tooltip: l.cropMargins,
              onPressed: state.busy
                  ? null
                  : () => toggleReaderCrop(context, ref, studySetId, documentId: documentScoped ? document.id : null),
            ),
            MMToolbarButton(
              compact: true,
              icon: MMIcons.close,
              tooltip: l.closePanel,
              onPressed: () => ref.read(workspaceProvider(studySetId).notifier).dismissCropSuggestion(document.id),
            ),
          ],
        ),
      );
    }
    final content = ref.watch(workspaceContentProvider(studySetId)) ?? StudySetContent.empty;
    final pdf = ref.read(documentPdfProvider((studySetId, document.id)));
    final marks = <List<AnnotationPage>>[
      for (final a in content.annotations.where((a) => a.documentId == document.id && !a.isText)) a.pages,
      for (final stroke in content.inkStrokes.where((s) => s.documentId == document.id))
        [AnnotationPage(page: stroke.page, rects: cropInkBounds(stroke))],
      for (final n in content.marginNotes.where((n) => n.documentId == document.id))
        if (n.anchor != null)
          n.anchor!.pages
        else if (pdf.pageSize(n.page) case final size?)
          [
            AnnotationPage(page: n.page, rects: [PageRect(size.width / 2, n.lineY!, size.width / 2, n.lineY!)]),
          ],
    ];
    final hidden = marks
        .where(
          (mark) => mark.any((page) {
            final size = pdf.pageSize(page.page);
            if (size == null) return false;
            final crop = state.draft!.forPage(page.page);
            return page.rects.any(
              (r) =>
                  r.left < crop.left ||
                  r.right > size.width - crop.right ||
                  r.top > size.height - crop.top ||
                  r.bottom < crop.bottom,
            );
          }),
        )
        .length;
    final draft = state.draft!;
    final uncropped = [
      draft.all,
      ?draft.odd,
      ...draft.pages.values,
    ].every((insets) => insets.left + insets.right + insets.top + insets.bottom == 0);
    Widget button(String label, VoidCallback? onPressed, {bool selected = false}) => MMToolbarButton(
      compact: true,
      icon: null,
      label: label,
      tooltip: label,
      selected: selected,
      onPressed: onPressed,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MMGlass(
          key: const ValueKey('crop-editor-toolbar'),
          padding: const EdgeInsets.all(MMSpacing.xs),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: MMSpacing.s,
            runSpacing: MMSpacing.xs,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                runSpacing: MMSpacing.xs,
                children: [
                  for (final (scope, label) in [
                    (CropScope.all, l.cropScopeAll),
                    (CropScope.oddEven, l.cropScopeOddEven),
                    (CropScope.page, l.cropScopePage),
                  ])
                    button(label, state.busy ? null : () => session.scope(scope), selected: draft.scope == scope),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  button(
                    l.cropAuto,
                    state.busy ? null : session.automatic,
                    selected: !uncropped && draft.mode == CropMode.auto,
                  ),
                  button(l.cropNone, state.busy ? null : session.none, selected: uncropped),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  button(l.cancel, state.busy ? null : session.cancel),
                  button(
                    l.done,
                    state.busy
                        ? null
                        : () => completeReaderCrop(
                            context,
                            ref,
                            studySetId,
                            documentId: documentScoped ? document.id : null,
                          ),
                    selected: true,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              decoration: BoxDecoration(
                color: c.caution.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber, size: 12, color: c.caution),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      l.cropHiddenAnnotations(hidden),
                      style: context.mmText.footnote.copyWith(color: c.caution),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Full-page overlay; edits are measured in original PDF points.
class CropPageEditor extends StatelessWidget {
  const CropPageEditor({
    super.key,
    required this.page,
    required this.size,
    required this.crop,
    required this.groupMinimum,
    required this.onChanged,
  });
  final int page;
  final Size size, groupMinimum;
  final DocumentCrop crop;
  final ValueChanged<CropInsets> onChanged;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = constraints.maxWidth / size.width;
      final insets = crop.forPage(page);
      final frame = Rect.fromLTRB(
        insets.left * scale,
        insets.top * scale,
        (size.width - insets.right) * scale,
        (size.height - insets.bottom) * scale,
      );
      final label = switch (crop.scope) {
        CropScope.all => null,
        CropScope.oddEven => page.isOdd ? context.l10n.cropOddPages : context.l10n.cropEvenPages,
        CropScope.page => crop.pages.containsKey(page) ? context.l10n.cropCustomPage : null,
      };
      void move(int edge, double delta) {
        final values = [insets.left, insets.top, insets.right, insets.bottom];
        final dimension = edge.isEven ? groupMinimum.width : groupMinimum.height;
        final minimum = math.min(dimension, edge.isEven ? 160.0 : 200.0);
        final max = math.max(0.0, dimension - minimum - values[(edge + 2) % 4]);
        values[edge] = (values[edge] + delta).roundToDouble().clamp(0.0, max);
        onChanged(CropInsets(left: values[0], top: values[1], right: values[2], bottom: values[3]));
      }

      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _CropMask(frame, context.mmColors.accent))),
          ),
          if (label != null)
            Positioned(
              left: 6,
              top: 6,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  child: Text(label, style: context.mmText.footnote.copyWith(fontSize: 10, color: Colors.white)),
                ),
              ),
            ),
          for (var edge = 0; edge < 4; edge++)
            Positioned.fromRect(
              rect: Rect.fromCenter(
                center: switch (edge) {
                  0 => frame.centerLeft,
                  1 => frame.topCenter,
                  2 => frame.centerRight,
                  _ => frame.bottomCenter,
                },
                width: edge.isEven ? 22 : 44,
                height: edge.isEven ? 44 : 22,
              ),
              child: _CropHandle(
                key: ValueKey('crop-handle-$page-$edge'),
                horizontal: edge.isEven,
                onMove: (delta) => move(edge, delta * (edge < 2 ? 1 : -1)),
                onDrag: (delta) => move(edge, (edge.isEven ? delta.dx : delta.dy) / scale * (edge < 2 ? 1 : -1)),
              ),
            ),
        ],
      );
    },
  );
}

class _CropHandle extends StatefulWidget {
  const _CropHandle({super.key, required this.horizontal, required this.onMove, required this.onDrag});
  final bool horizontal;
  final ValueChanged<double> onMove;
  final ValueChanged<Offset> onDrag;
  @override
  State<_CropHandle> createState() => _CropHandleState();
}

class _CropHandleState extends State<_CropHandle> {
  bool focused = false;
  Offset _dragDelta = Offset.zero;
  ValueChanged<Offset>? _dragMove;
  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (v) => setState(() => focused = v),
    onKeyEvent: (_, event) {
      if (event is KeyUpEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      final direction = widget.horizontal
          ? (key == LogicalKeyboardKey.arrowLeft
                ? -1
                : key == LogicalKeyboardKey.arrowRight
                ? 1
                : 0)
          : (key == LogicalKeyboardKey.arrowUp
                ? -1
                : key == LogicalKeyboardKey.arrowDown
                ? 1
                : 0);
      if (direction == 0) return KeyEventResult.ignored;
      widget.onMove(direction * (HardwareKeyboard.instance.isShiftPressed ? 10 : 1).toDouble());
      return KeyEventResult.handled;
    },
    child: MouseRegion(
      cursor: widget.horizontal ? SystemMouseCursors.resizeLeftRight : SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          _dragDelta = Offset.zero;
          _dragMove = widget.onDrag;
        },
        onPanUpdate: (d) {
          _dragDelta += d.delta;
          _dragMove?.call(_dragDelta);
        },
        onPanEnd: (_) => _dragMove = null,
        onPanCancel: () => _dragMove = null,
        child: Center(
          child: Container(
            width: widget.horizontal ? 6 : 28,
            height: widget.horizontal ? 28 : 6,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: context.mmColors.accent, width: focused ? 2.5 : 1.5),
              boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 3, offset: Offset(0, 1))],
            ),
          ),
        ),
      ),
    ),
  );
}

class _CropMask extends CustomPainter {
  const _CropMask(this.frame, this.color);
  final Rect frame;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(frame),
      Paint()..color = Colors.black.withValues(alpha: .34),
    );
    canvas.drawRect(
      frame.deflate(.75),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_CropMask oldDelegate) => frame != oldDelegate.frame || color != oldDelegate.color;
}
