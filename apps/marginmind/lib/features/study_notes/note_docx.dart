import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:mm_core/mm_core.dart';

/// Small, editable OOXML package. Relationships and content types are explicit,
/// including native footnotes and Word's built-in Quote paragraph style.
class NoteDocx {
  static const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  static const _r = 'http://schemas.openxmlformats.org/package/2006/relationships';
  static String _e(String value) => value
      .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  static String _run(String text) =>
      text.split('\n').map((s) => '<w:r><w:t xml:space="preserve">${_e(s)}</w:t></w:r>').join('<w:r><w:br/></w:r>');

  static Map<String, String> parts(NoteRichDocument document) {
    final body = StringBuffer(), notes = StringBuffer();
    var index = 0;
    for (final p in document.paragraphs) {
      final style = switch (p.kind) {
        NoteParagraphKind.title => 'Title',
        NoteParagraphKind.heading => 'Heading1',
        NoteParagraphKind.quote => 'Quote',
        _ => 'Normal',
      };
      body.write('<w:p><w:pPr><w:pStyle w:val="$style"/>');
      if (p.kind == NoteParagraphKind.own) body.write('<w:shd w:val="clear" w:fill="FFF3C4"/>');
      if (p.kind == NoteParagraphKind.quote) {
        body.write(
          '<w:pBdr><w:left w:val="single" w:sz="18" w:space="8" w:color="${noteHighlightHex(p.colorIndex).substring(1)}"/></w:pBdr>',
        );
      }
      body.write('</w:pPr>');
      if (p.ai.isNotEmpty) body.write(_run('${p.ai}: '));
      body.write(
        _run(
          '${p.kind == NoteParagraphKind.point
              ? '• '
              : p.kind == NoteParagraphKind.action
              ? '☐ '
              : ''}${p.text}',
        ),
      );
      if (p.kind == NoteParagraphKind.quote) {
        if (document.citations == NoteCitationStyle.inline) body.write(_run('\n— ${p.citation ?? ''}'));
        if (document.citations == NoteCitationStyle.footnote) {
          index++;
          body.write(
            '<w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:footnoteReference w:id="$index"/></w:r>',
          );
          notes.write(
            '<w:footnote w:id="$index"><w:p><w:pPr><w:pStyle w:val="FootnoteText"/></w:pPr><w:r><w:footnoteRef/></w:r>${_run(' ${p.citation ?? ''}')}</w:p></w:footnote>',
          );
        }
      }
      body.write('</w:p>');
    }
    String rel(String id, String type, String target) =>
        '<Relationship Id="$id" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/$type" Target="$target"/>';
    return {
      '[Content_Types].xml':
          '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>${{'/word/document.xml': 'document.main', '/word/styles.xml': 'styles', '/word/footnotes.xml': 'footnotes'}.entries.map((e) => '<Override PartName="${e.key}" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.${e.value}+xml"/>').join()}</Types>',
      '_rels/.rels': '<Relationships xmlns="$_r">${rel('rId1', 'officeDocument', 'word/document.xml')}</Relationships>',
      'word/_rels/document.xml.rels':
          '<Relationships xmlns="$_r">${rel('rId1', 'styles', 'styles.xml')}${rel('rId2', 'footnotes', 'footnotes.xml')}</Relationships>',
      'word/document.xml':
          '<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="$_w"><w:body>$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/></w:sectPr></w:body></w:document>',
      'word/styles.xml':
          '<w:styles xmlns:w="$_w"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="PingFang SC"/><w:sz w:val="22"/><w:lang w:val="en-US" w:eastAsia="zh-CN"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="360" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style><w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="36"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="240" w:right="240"/></w:pPr><w:rPr><w:rFonts w:ascii="Songti SC" w:hAnsi="Songti SC" w:eastAsia="Songti SC"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="FootnoteText"><w:name w:val="footnote text"/><w:basedOn w:val="Normal"/><w:rPr><w:sz w:val="18"/></w:rPr></w:style><w:style w:type="character" w:styleId="FootnoteReference"><w:name w:val="footnote reference"/><w:rPr><w:vertAlign w:val="superscript"/></w:rPr></w:style></w:styles>',
      'word/footnotes.xml':
          '<w:footnotes xmlns:w="$_w"><w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote><w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>$notes</w:footnotes>',
    };
  }

  static Uint8List encode(NoteRichDocument document) {
    final archive = Archive();
    for (final entry in parts(document).entries) {
      final data = utf8.encode(entry.value);
      archive.addFile(ArchiveFile(entry.key, data.length, data));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}
