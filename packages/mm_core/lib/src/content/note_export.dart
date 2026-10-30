import 'dart:convert';

import 'note_editor.dart';
import 'note_format.dart';
import 'note_material.dart';
import 'research.dart';
import 'study_note.dart';
import 'study_set_content.dart';

/// Portable targets supported by the pure Dart exporter.
enum NoteExportFormat { markdown, obsidian }

enum NoteExportLanguage { zh, en }

/// How each quote identifies its source.
enum NoteCitationStyle { inline, footnote, none }

/// Shared export switches. Context includes only quotes currently expanded.
class NoteExportOptions {
  const NoteExportOptions({
    this.citations = NoteCitationStyle.inline,
    this.context = true,
    this.ownNotes = true,
    this.aiContent = true,
    this.questions = true,
    this.sources = true,
    this.markAi = true,
    this.tags = const [],
  });
  final NoteCitationStyle citations;
  final bool context, ownNotes, aiContent, questions, sources, markAi;
  final List<String> tags;
}

/// Exported text plus relative destination -> study-set image path. The caller
/// copies these files; the exporter performs no filesystem access.
class NoteExportResult {
  NoteExportResult(this.text, Map<String, String> attachments) : attachments = Map.unmodifiable(attachments);
  final String text;
  final Map<String, String> attachments;
}

/// Resolves live references and produces Markdown or Obsidian without side effects.
class NoteExporter {
  const NoteExporter(this.content, {this.textSource = const NoteTextSource()});
  final StudySetContent content;
  final NoteTextSource textSource;

  NoteExportResult export(
    StudyNote note, {
    NoteExportFormat format = NoteExportFormat.markdown,
    NoteExportLanguage language = NoteExportLanguage.zh,
    NoteExportOptions options = const NoteExportOptions(),
  }) {
    final en = language == NoteExportLanguage.en;
    String label(String zh, String english) => en ? english : zh;
    String wikiTitle(String title) =>
        title.replaceAll(RegExp(r'[\\/:*?"<>|#^\[\]\x00-\x1f]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final obsidian = format == NoteExportFormat.obsidian;
    final out = StringBuffer(), footnotes = <String>[], sources = <String>{};
    final attachments = <String, String>{};
    String line(String s) => s.replaceAll(RegExp(r'[\r\n]+'), ' ');
    String escape(String s) => s.replaceAllMapped(RegExp(r'[\\`*_{}\[\]<>#]'), (m) => '\\${m[0]}');
    String ai(NoteOrigin origin) => options.markAi && (origin == NoteOrigin.ai || origin == NoteOrigin.mixed)
        ? (origin == NoteOrigin.mixed ? label('AI · 已改', 'AI · Edited') : label('AI 整理', 'AI'))
        : '';
    bool visible(StudyNoteBlock b) => options.aiContent || (b.origin != NoteOrigin.ai && b.origin != NoteOrigin.mixed);
    void prose(String value, {String? callout, String? label}) {
      if (obsidian && callout != null) {
        out.writeln('> [!$callout]${label == null || label.isEmpty ? '' : ' ${line(label)}'}');
        for (final l in value.split('\n')) {
          out.writeln('> $l');
        }
      } else {
        if (label != null && label.isNotEmpty) out.writeln('**${escape(label)}**');
        out.writeln(value);
      }
      out.writeln();
    }

    String citation(ResolvedNoteSource source) {
      final a = source.annotation;
      final title = line(source.documentTitle ?? label('未知来源', 'Unknown source'));
      final page = a != null && !a.isText ? a.page : null;
      final location = page == null
          ? (a == null ? '' : const NoteMaterialCollector().sectionTitle(content, a) ?? '')
          : 'p.$page';
      final status = switch (source.status) {
        NoteSourceStatus.available => '',
        NoteSourceStatus.annotationDeleted => label('（划线已删除）', ' (Highlight deleted)'),
        NoteSourceStatus.documentRemoved => label('（原文已移除）', ' (Source removed)'),
        NoteSourceStatus.missing => label('（划线已删除）', ' (Highlight deleted)'),
      };
      if (obsidian && page != null && source.status == NoteSourceStatus.available) {
        final target = wikiTitle(title);
        return '[[$target#p$page|${label('《$target》p.$page', '$target, p. $page')}]]';
      }
      return en
          ? '${escape(title)}${page == null ? (location.isEmpty ? '' : ', ${escape(location)}') : ', p. $page'}$status'
          : '《${escape(title)}》${location.isEmpty ? '' : ' ${escape(location)}'}$status';
    }

    if (obsidian) {
      final titles = <String>{
        for (final s in note.sections)
          for (final b in s.blocks)
            if (b is QuoteBlock)
              resolveNoteSource(content, b.annotationId).documentTitle ?? label('未知来源', 'Unknown source'),
      };
      out.writeln('---');
      out.writeln('title: ${jsonEncode(note.title)}');
      out.writeln('source: ${jsonEncode(titles.toList())}');
      out.writeln('tags: ${jsonEncode(options.tags)}');
      out.writeln('created: ${jsonEncode(note.createdAt.toIso8601String())}');
      out.writeln('---\n');
    }
    out.writeln('# ${escape(line(note.title))}\n');
    if (!obsidian) {
      final highlights = {
        for (final s in note.sections)
          for (final b in s.blocks)
            if (b is QuoteBlock) b.annotationId,
      };
      final documents = {for (final id in highlights) resolveNoteSource(content, id).annotation?.documentId}
        ..remove(null);
      final date = note.organizedAt.toIso8601String().split('T').first;
      out.writeln(
        label(
          '${documents.length} 份文档 · ${highlights.length} 条划线 · 整理于 $date',
          '${documents.length} documents · ${highlights.length} highlights · organized $date',
        ),
      );
      out.writeln();
    }
    final sectionAnchors = {for (final (i, s) in note.sections.indexed) s.id: 'section-${i + 1}'};
    var quoteIndex = 0;
    for (final section in note.sections) {
      out.writeln('<a id="${sectionAnchors[section.id]}"></a>');
      out.writeln('## ${escape(line(section.title))}\n');
      final answers = <String>[];
      for (final block in section.blocks) {
        if (block is OwnBlock && !options.ownNotes) continue;
        if (!visible(block)) continue;
        switch (block) {
          case QuoteBlock():
            final resolved = resolveNoteSource(content, block.annotationId);
            final annotation = resolved.annotation;
            final quote = annotation?.quote ?? label('划线已删除', 'Highlight deleted');
            answers.add(quote);
            final source = citation(resolved);
            sources.add(
              obsidian && resolved.documentTitle != null ? '[[${wikiTitle(resolved.documentTitle!)}]]' : source,
            );
            if (obsidian) out.writeln('> [!quote]${options.citations == NoteCitationStyle.inline ? ' $source' : ''}');
            for (final l in quote.split('\n')) {
              out.writeln('> $l');
            }
            switch (options.citations) {
              case NoteCitationStyle.inline:
                if (!obsidian) out.writeln('> ${label('——', '—')} $source');
              case NoteCitationStyle.footnote:
                final id = 'h${++quoteIndex}';
                out.writeln('> [^$id]');
                footnotes.add('[^$id]: $source');
              case NoteCitationStyle.none:
                break;
            }
            out.writeln();
            if (options.context &&
                block.contextOpen &&
                annotation != null &&
                resolved.status == NoteSourceStatus.available) {
              final ctx = const NoteMaterialCollector().contextFor(
                content,
                annotation,
                note.settings.contextSentences,
                text: textSource,
              );
              if (ctx.noText) {
                prose(label('无原文文本', 'No source text'));
              } else if (!ctx.unresolved && (ctx.before.isNotEmpty || ctx.after.isNotEmpty)) {
                prose(
                  [ctx.before, ctx.after].where((s) => s.isNotEmpty).join('\n'),
                  callout: 'info',
                  label: label('上下文', 'Context'),
                );
              }
            }
          case OwnBlock():
            String? value;
            switch (block.source) {
              case OwnSource.marginNote:
                value = content.marginNotes.where((n) => n.id == block.sourceId).firstOrNull?.text;
              case OwnSource.card:
                final card = content.card(block.sourceId);
                if (card != null) {
                  value = [
                    notePlainText(card.title, card.textFormat),
                    notePlainText(card.body, card.textFormat),
                  ].where((s) => s.isNotEmpty).join('\n');
                }
              case OwnSource.researchNote:
                value = content.researchNote(block.sourceId)?.body;
              case OwnSource.image:
                final path = content.card(block.sourceId)?.imageFileName;
                if (path != null) {
                  final destination = 'attachments/${path.split('/').last}';
                  attachments[destination] = path;
                  value = obsidian ? '![[${destination.replaceAll(']', '_')}]]' : '![](${Uri.encodeFull(destination)})';
                }
            }
            if (value != null) {
              prose(
                value,
                callout: 'note',
                label: ai(block.origin).isEmpty ? label('我的批注', 'My Note') : ai(block.origin),
              );
            }
          case TextBlock():
            final value = block.kind == TextKind.action ? '- [ ] ${block.text}' : block.text;
            prose(
              value,
              callout: options.markAi && ai(block.origin).isNotEmpty ? 'abstract' : null,
              label: ai(block.origin),
            );
          case PointsBlock():
            prose(
              block.items.map((s) => '- ${s.replaceAll('\n', '\n  ')}').join('\n'),
              callout: options.markAi && ai(block.origin).isNotEmpty ? 'abstract' : null,
              label: ai(block.origin),
            );
          case XrefBlock():
            final target = sectionAnchors[block.toSectionId];
            if (target != null) prose('[${escape(line(block.text))}](#$target)', label: ai(block.origin));
        }
      }
      if (options.questions && section.question?.trim().isNotEmpty == true) {
        if (obsidian) {
          out.writeln('${section.question}\n?\n${answers.join('\n\n')}\n');
        } else {
          prose(
            section.question!,
            label:
                '${label('复习题', 'Review Questions')}${ai(section.questionOrigin).isEmpty ? '' : ' · ${ai(section.questionOrigin)}'}',
          );
        }
      }
    }
    if (footnotes.isNotEmpty) out.writeln('${footnotes.join('\n')}\n');
    if (options.sources && sources.isNotEmpty) {
      out.writeln('## ${label('出处', 'Sources')}\n');
      for (final source in sources) {
        out.writeln('- $source');
      }
      out.writeln();
    }
    return NoteExportResult('${out.toString().trimRight()}\n', attachments);
  }
}
