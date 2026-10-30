import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../shared/l10n.dart';

enum NoteShareScope { quote, section, summary }

/// Apply scope before resolving references. Unselected quotes and their private
/// notes are never included in the rendering tree or footer count.
StudyNote selectSharedNote(StudyNote note, NoteShareScope scope, int sectionIndex, int quoteIndex) {
  final sections = scope == NoteShareScope.summary
      ? note.sections
      : note.sections.isEmpty
      ? <NoteSection>[]
      : [note.sections[sectionIndex.clamp(0, note.sections.length - 1)]];
  return note.copyWith(
    sections: [
      for (final section in sections)
        section.copyWith(
          blocks: () {
            var quotes = 0, selected = false;
            final blocks = <StudyNoteBlock>[];
            for (final block in section.blocks) {
              if (block is QuoteBlock) {
                selected = switch (scope) {
                  NoteShareScope.quote => quotes == quoteIndex,
                  NoteShareScope.section => quotes < 4,
                  NoteShareScope.summary => quotes < 2,
                };
                quotes++;
                if (selected) blocks.add(block);
              } else if (block is OwnBlock) {
                if (selected) blocks.add(block);
              } else if (scope != NoteShareScope.quote && block is TextBlock && block.kind == TextKind.summary) {
                blocks.add(block);
              }
            }
            return blocks;
          }(),
        ),
    ],
  );
}

class NoteShareCard extends StatelessWidget {
  const NoteShareCard({super.key, required this.document, required this.theme, required this.scope});
  final NoteRichDocument document;
  final MMShareCardTheme theme;
  final NoteShareScope scope;
  @override
  Widget build(BuildContext context) {
    final color = theme.foreground;
    final quotes = document.paragraphs.where((p) => p.kind == NoteParagraphKind.quote).length;
    Widget text(String value, TextStyle style, {double opacity = 1}) => Text(
      value,
      style: style.copyWith(color: color.withValues(alpha: opacity)),
    );
    return Container(
      width: MMShareCardStyle.width,
      padding: const EdgeInsets.all(MMShareCardStyle.padding),
      decoration: BoxDecoration(color: theme.background, borderRadius: BorderRadius.circular(MMShareCardStyle.radius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (scope == NoteShareScope.quote)
            text('“', MMShareCardStyle.quotationMark, opacity: .25)
          else ...[
            text(
              [context.l10n.noteReading, document.sourceTitles.join(' × ')].where((s) => s.isNotEmpty).join(' · '),
              MMShareCardStyle.caption,
              opacity: .55,
            ),
            const SizedBox(height: MMSpacing.s),
            text(document.title, MMShareCardStyle.title),
            const SizedBox(height: MMSpacing.m),
          ],
          for (final p in document.paragraphs)
            if (p.kind != NoteParagraphKind.title &&
                (scope != NoteShareScope.quote || p.kind != NoteParagraphKind.heading))
              Padding(
                padding: const EdgeInsets.only(bottom: MMSpacing.m),
                child: switch (p.kind) {
                  NoteParagraphKind.quote => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.only(left: MMSpacing.m),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: color.withValues(alpha: .25), width: MMShareCardStyle.quoteBar),
                          ),
                        ),
                        child: text(
                          p.text,
                          scope == NoteShareScope.quote ? MMShareCardStyle.quote : MMShareCardStyle.excerpt,
                        ),
                      ),
                      const SizedBox(height: MMSpacing.s),
                      text(p.citation ?? '', MMShareCardStyle.caption, opacity: .5),
                    ],
                  ),
                  NoteParagraphKind.own => Container(
                    padding: const EdgeInsets.all(MMSpacing.s),
                    decoration: BoxDecoration(
                      color: MMShareCardStyle.annotation.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(MMRadii.card),
                    ),
                    child: text(p.text, MMShareCardStyle.body),
                  ),
                  NoteParagraphKind.heading => text(p.text, MMShareCardStyle.section),
                  _ => text('${p.ai.isEmpty ? '' : '${p.ai} · '}${p.text}', MMShareCardStyle.body, opacity: .85),
                },
              ),
          Divider(color: color.withValues(alpha: .25), thickness: MMShareCardStyle.rule),
          const SizedBox(height: MMSpacing.s),
          Row(
            children: [
              Icon(MMIcons.studyNote, size: MMShareCardStyle.icon, color: color.withValues(alpha: .55)),
              const SizedBox(width: MMSpacing.xs),
              Expanded(child: text(context.l10n.noteShareFooter, MMShareCardStyle.caption, opacity: .55)),
              if (scope != NoteShareScope.quote)
                text(context.l10n.noteSharedCount(quotes), MMShareCardStyle.caption, opacity: .55),
            ],
          ),
        ],
      ),
    );
  }
}

/// Capture exactly the preview at 2×. Explicit limits avoid GPU exhaustion;
/// images are disposed even if encoding fails.
Future<Uint8List> captureNoteCard(RenderRepaintBoundary boundary) async {
  final size = boundary.size;
  if (size.width * 2 > 16384 || size.height * 2 > 16384 || size.width * size.height * 4 > 32000000) {
    throw StateError('Share image exceeds raster budget');
  }
  final image = await boundary.toImage(pixelRatio: 2);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Empty share image');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}
