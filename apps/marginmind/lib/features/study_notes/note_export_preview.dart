import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'note_pdf.dart';

/// The PDF preview draws the same paginated vector commands sent to the encoder.
class NotePdfPreview extends StatelessWidget {
  const NotePdfPreview({super.key, required this.document});
  final NoteRichDocument document;
  @override
  Widget build(BuildContext context) {
    final pages = NotePdf.scene(document)['pages'] as List<List<Map<String, Object?>>>;
    return Column(
      children: [
        for (final page in pages)
          Padding(
            padding: const EdgeInsets.only(bottom: MMSpacing.m),
            child: AspectRatio(
              aspectRatio: NotePdf.width / NotePdf.height,
              child: CustomPaint(painter: _Page(page)),
            ),
          ),
      ],
    );
  }
}

class _Page extends CustomPainter {
  _Page(this.commands);
  final List<Map<String, Object?>> commands;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / NotePdf.width);
    canvas.drawRect(const Rect.fromLTWH(0, 0, NotePdf.width, NotePdf.height), Paint()..color = Colors.white);
    for (final c in commands) {
      final color = Color(c['color'] as int);
      if (c['type'] == 'box') {
        final r = c['rect'] as List<double>;
        canvas.drawRect(Rect.fromLTWH(r[0], r[1], r[2], r[3]), Paint()..color = color);
      } else if (c['type'] == 'text') {
        final painter = TextPainter(
          text: TextSpan(
            text: c['text'] as String,
            style: TextStyle(
              fontSize: c['fontSize'] as double,
              fontFamily: c['serif'] == true ? 'Songti SC' : null,
              fontWeight: c['bold'] == true ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(c['x'] as double, c['y'] as double));
        painter.dispose();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Page oldDelegate) => commands != oldDelegate.commands;
}

class NoteRichPreview extends StatelessWidget {
  const NoteRichPreview({super.key, required this.document});
  final NoteRichDocument document;
  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    var index = 0;
    final notes = <String>[];
    Widget paragraph(NoteParagraph p) {
      String citation = '';
      if (p.kind == NoteParagraphKind.quote) {
        if (document.citations == NoteCitationStyle.inline) citation = '\n— ${p.citation}';
        if (document.citations == NoteCitationStyle.footnote) {
          citation = ' [${++index}]';
          notes.add('[$index] ${p.citation}');
        }
      }
      final style = switch (p.kind) {
        NoteParagraphKind.title => context.mmText.title2,
        NoteParagraphKind.heading => context.mmText.headline,
        NoteParagraphKind.quote => MMTypography.readingExcerpt,
        _ => context.mmText.body,
      };
      return Container(
        margin: const EdgeInsets.only(bottom: MMSpacing.m),
        padding: const EdgeInsets.all(MMSpacing.s),
        decoration: BoxDecoration(
          color: p.kind == NoteParagraphKind.own ? MMAnnotationColor.yellow.cardTint : null,
          border: p.kind == NoteParagraphKind.quote
              ? Border(
                  left: BorderSide(
                    color: MMAnnotationColor.fromIndex(p.colorIndex).color,
                    width: MMNoteLayout.quoteBar,
                  ),
                )
              : null,
        ),
        child: SelectableText(
          '${p.ai.isEmpty ? '' : '${p.ai} · '}${p.kind == NoteParagraphKind.point
              ? '• '
              : p.kind == NoteParagraphKind.action
              ? '☐ '
              : ''}${p.text}$citation',
          style: style.copyWith(color: c.label),
        ),
      );
    }

    final children = document.paragraphs.map(paragraph).toList();
    if (notes.isNotEmpty) {
      children.add(SelectableText(notes.join('\n'), style: context.mmText.footnote.copyWith(color: c.secondaryLabel)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}
