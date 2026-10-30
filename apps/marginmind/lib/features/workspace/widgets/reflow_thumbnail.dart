import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_reflow/mm_reflow.dart';

import '../../../shared/l10n.dart';
import '../reflow_document.dart';
import '../reflow_session.dart';

/// Fixed EPUB page previews borrow no resources from the main viewport. ListView
/// disposes offscreen sessions, releasing paragraphs before their image handles.
class ReflowThumbnail extends StatefulWidget {
  const ReflowThumbnail({
    super.key,
    required this.book,
    required this.chapterId,
    required this.page,
    required this.selected,
    required this.style,
    required this.onTap,
  });
  final ReflowDocument book;
  final String chapterId;
  final int page;
  final bool selected;
  final MMReaderStyle style;
  final VoidCallback onTap;
  @override
  State<ReflowThumbnail> createState() => _ReflowThumbnailState();
}

class _ReflowThumbnailState extends State<ReflowThumbnail> {
  late final session = ReflowSession(
    () async => widget.book,
    onPosition: (_) {},
    maxImagePixels: (MMReaderLayout.thumbnailWidth * MMReaderLayout.thumbnailHeight * 4).ceil(),
  );
  LayoutSpec get spec => LayoutSpec(
    width: MMReaderLayout.thumbnailWidth,
    pageHeight: MMReaderLayout.thumbnailHeight,
    padding: EdgeInsets.zero,
    readerStyle: widget.style,
  );
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await session.initialize();
    if (!mounted) return;
    await session.jump(widget.book.position(widget.chapterId, 0), remember: false);
    if (mounted) await session.configure(spec);
  }

  @override
  void didUpdateWidget(ReflowThumbnail old) {
    super.didUpdateWidget(old);
    if (old.style != widget.style) session.configure(spec);
  }

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MMInteractive(
    onTap: widget.onTap,
    selected: widget.selected,
    semanticLabel: context.l10n.pageNumber(widget.page),
    builder: (context, interaction) => Padding(
      padding: const EdgeInsets.all(MMSpacing.m),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: widget.style.paperColor,
              border: Border.all(
                color: widget.selected ? context.mmColors.accent : context.mmColors.separator,
                width: widget.selected ? MMSpacing.xxs : MMSizes.readerProgressTrack,
              ),
            ),
            child: SizedBox(
              width: MMReaderLayout.thumbnailWidth,
              height: MMReaderLayout.thumbnailHeight,
              child: ListenableBuilder(
                listenable: session,
                builder: (context, _) => session.ready
                    ? CustomPaint(painter: _ThumbnailPainter(session.layout!))
                    : Icon(MMIcons.document, color: context.mmColors.secondaryLabel),
              ),
            ),
          ),
          const SizedBox(height: MMSpacing.xs),
          Text('${widget.page}', style: context.mmText.footnote),
        ],
      ),
    ),
  );
}

class _ThumbnailPainter extends CustomPainter {
  const _ThumbnailPainter(this.layout);
  final ChapterLayout layout;
  @override
  void paint(Canvas canvas, Size size) {
    if (!layout.isDisposed) layout.paint(canvas, page: 0);
  }

  @override
  bool shouldRepaint(_ThumbnailPainter old) => old.layout != layout;
}
