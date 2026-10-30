import 'dart:convert';

import 'note_editor.dart';
import 'note_export.dart';
import 'note_format.dart';
import 'note_material.dart';
import 'research.dart';
import 'study_note.dart';
import 'study_set_content.dart';

/// Resolved, filtered paragraphs shared by HTML, print and image exports.
/// No raw markup or live references escape this snapshot.
enum NoteParagraphKind { title, heading, quote, own, text, point, action, question, context, source }

class NoteParagraph {
  const NoteParagraph(
    this.kind,
    this.text, {
    this.citation,
    this.shareCitation,
    this.colorIndex = 0,
    this.ai = '',
    this.target,
  });
  final NoteParagraphKind kind;
  final String text, ai;
  final String? citation, target;
  final String? shareCitation;
  final int colorIndex;
}

class NoteRichDocument {
  NoteRichDocument(this.title, this.paragraphs, this.citations, {this.sourceTitles = const []});
  final String title;
  final List<String> sourceTitles;
  final List<NoteParagraph> paragraphs;
  final NoteCitationStyle citations;

  factory NoteRichDocument.resolve(
    StudySetContent content,
    StudyNote note, {
    NoteExportOptions options = const NoteExportOptions(),
    NoteExportLanguage language = NoteExportLanguage.zh,
    NoteTextSource textSource = const NoteTextSource(),
  }) {
    final en = language == NoteExportLanguage.en;
    String label(String zh, String english) => en ? english : zh;
    String mark(NoteOrigin origin) => !options.markAi || origin == NoteOrigin.user
        ? ''
        : origin == NoteOrigin.mixed
        ? label('AI · 已改', 'AI · Edited')
        : 'AI';
    final out = <NoteParagraph>[NoteParagraph(NoteParagraphKind.title, note.title)];
    final sources = <String>{}, titles = <String>{};
    final anchors = {for (final (i, s) in note.sections.indexed) s.id: 'section-${i + 1}'};
    for (final section in note.sections) {
      out.add(NoteParagraph(NoteParagraphKind.heading, section.title, target: anchors[section.id]));
      for (final block in section.blocks) {
        if (!options.aiContent && block.origin != NoteOrigin.user) continue;
        final ai = mark(block.origin);
        switch (block) {
          case QuoteBlock():
            final source = resolveNoteSource(content, block.annotationId);
            final a = source.annotation;
            final title = source.documentTitle ?? label('未知来源', 'Unknown source');
            final location = a == null
                ? ''
                : a.isText
                ? const NoteMaterialCollector().sectionTitle(content, a) ?? ''
                : a.pages.map((p) => 'p.${p.page}').join(', ');
            final status = switch (source.status) {
              NoteSourceStatus.available => '',
              NoteSourceStatus.documentRemoved => label('（原文已移除）', ' (Source removed)'),
              _ => label('（划线已删除）', ' (Highlight deleted)'),
            };
            final citation = '${en ? title : '《$title》'}${location.isEmpty ? '' : ' $location'}$status';
            sources.add(citation);
            titles.add(title);
            out.add(
              NoteParagraph(
                NoteParagraphKind.quote,
                a?.quote ?? label('划线已删除', 'Highlight deleted'),
                citation: citation,
                shareCitation: '$title${location.isEmpty ? '' : ' · $location'}$status',
                colorIndex: a?.colorIndex ?? 0,
              ),
            );
            if (options.context && block.contextOpen && a != null && source.status == NoteSourceStatus.available) {
              final ctx = const NoteMaterialCollector().contextFor(
                content,
                a,
                note.settings.contextSentences,
                text: textSource,
              );
              final value = ctx.noText
                  ? label('无原文文本', 'No source text')
                  : ctx.unresolved
                  ? ''
                  : [ctx.before, ctx.after].where((s) => s.isNotEmpty).join('\n');
              if (value.isNotEmpty) out.add(NoteParagraph(NoteParagraphKind.context, value));
            }
          case OwnBlock():
            if (!options.ownNotes) continue;
            final card = content.card(block.sourceId);
            final value = switch (block.source) {
              OwnSource.marginNote => content.marginNotes.where((n) => n.id == block.sourceId).firstOrNull?.text,
              OwnSource.card =>
                card == null
                    ? null
                    : [
                        notePlainText(card.title, card.textFormat),
                        notePlainText(card.body, card.textFormat),
                      ].where((s) => s.isNotEmpty).join('\n'),
              OwnSource.researchNote => content.researchNote(block.sourceId)?.body,
              OwnSource.image => null,
            };
            if (value != null && value.isNotEmpty) out.add(NoteParagraph(NoteParagraphKind.own, value, ai: ai));
          case TextBlock():
            out.add(
              NoteParagraph(
                block.kind == TextKind.action ? NoteParagraphKind.action : NoteParagraphKind.text,
                block.text,
                ai: ai,
              ),
            );
          case PointsBlock():
            out.addAll(block.items.map((s) => NoteParagraph(NoteParagraphKind.point, s, ai: ai)));
          case XrefBlock():
            if (anchors[block.toSectionId] case final target?) {
              out.add(NoteParagraph(NoteParagraphKind.text, block.text, ai: ai, target: target));
            }
        }
      }
      if (options.questions &&
          (options.aiContent || section.questionOrigin == NoteOrigin.user) &&
          section.question?.trim().isNotEmpty == true) {
        out.add(
          NoteParagraph(
            NoteParagraphKind.question,
            '${label('复习题', 'Review Question')}: ${section.question}',
            ai: mark(section.questionOrigin),
          ),
        );
      }
    }
    if (options.sources && sources.isNotEmpty) {
      out.add(NoteParagraph(NoteParagraphKind.heading, label('出处', 'Sources')));
      out.addAll(sources.map((s) => NoteParagraph(NoteParagraphKind.source, s)));
    }
    return NoteRichDocument(
      note.title,
      List.unmodifiable(out),
      options.citations,
      sourceTitles: List.unmodifiable(titles),
    );
  }

  String get plainText {
    var index = 0;
    final footnotes = <String>[];
    final lines = <String>[];
    for (final p in paragraphs) {
      lines.add(
        '${p.ai.isEmpty ? '' : '${p.ai}: '}${p.kind == NoteParagraphKind.point
            ? '• '
            : p.kind == NoteParagraphKind.action
            ? '☐ '
            : ''}${p.text}',
      );
      if (p.kind == NoteParagraphKind.quote && p.citation != null) {
        if (citations == NoteCitationStyle.inline) lines.add('— ${p.citation}');
        if (citations == NoteCitationStyle.footnote) {
          lines.add('[${++index}]');
          footnotes.add('[$index] ${p.citation}');
        }
      }
    }
    return [...lines, ...footnotes].join('\n\n');
  }

  String get html {
    const escape = HtmlEscape(HtmlEscapeMode.element);
    String e(String s) => escape.convert(s).replaceAll('\n', '<br>');
    final out = StringBuffer(
      '<!DOCTYPE html>\n<html><head><meta charset="utf-8"><title>${e(title)}</title></head><body>\n',
    );
    final footnotes = <String>[];
    var index = 0;
    var listOpen = false;
    for (final p in paragraphs) {
      if (listOpen && p.kind != NoteParagraphKind.point) {
        out.writeln('</ul>');
        listOpen = false;
      }
      final text = '${p.ai.isEmpty ? '' : '<strong>${e(p.ai)}</strong> '}${e(p.text)}';
      switch (p.kind) {
        case NoteParagraphKind.title:
          out.writeln('<h1>$text</h1>');
        case NoteParagraphKind.heading:
          out.writeln('<h2${p.target == null ? '' : ' id="${p.target}"'}>$text</h2>');
        case NoteParagraphKind.quote:
          out.write(
            '<blockquote style="font-family:Songti SC,SimSun,serif;border-left:3px solid ${noteHighlightHex(p.colorIndex)};padding-left:12px"><p>$text</p>',
          );
          if (citations == NoteCitationStyle.inline) out.write('<cite>${e(p.citation ?? '')}</cite>');
          if (citations == NoteCitationStyle.footnote) {
            index++;
            out.write('<sup><a href="#footnote-$index">$index</a></sup>');
            footnotes.add('<li id="footnote-$index">${e(p.citation ?? '')}</li>');
          }
          out.writeln('</blockquote>');
        case NoteParagraphKind.own:
          out.writeln('<p style="background-color:#FFF3C4;padding:8px">$text</p>');
        case NoteParagraphKind.point:
          if (!listOpen) out.writeln('<ul>');
          listOpen = true;
          out.writeln('<li>$text</li>');
        case NoteParagraphKind.action:
          out.writeln('<p>☐ $text</p>');
        default:
          out.writeln('<p>${p.target == null ? text : '<a href="#${p.target}">$text</a>'}</p>');
      }
    }
    if (listOpen) out.writeln('</ul>');
    if (footnotes.isNotEmpty) out.writeln('<ol class="footnotes">${footnotes.join()}</ol>');
    out.writeln('</body></html>');
    return out.toString();
  }
}

/// Fixed export colors, independent of the system appearance.
String noteHighlightHex(int index) {
  if (index >= 0x01000000 && index <= 0x01ffffff) {
    return '#${(index & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
  return const ['#FFCC00', '#34C759', '#007AFF', '#FF2D55', '#FF9500', '#AF52DE'][index.clamp(0, 5)];
}
