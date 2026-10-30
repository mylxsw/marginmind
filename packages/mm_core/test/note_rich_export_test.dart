import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'study_notes_test.dart' as fixture;

void main() {
  for (final citation in NoteCitationStyle.values) {
    test('HTML golden ${citation.name}', () {
      final document = NoteRichDocument.resolve(
        fixture.content(),
        fixture.note(),
        textSource: fixture.texts,
        options: NoteExportOptions(citations: citation),
      );
      final file = File('test/goldens/study_note_${citation.name}.html');
      if (Platform.environment['UPDATE_GOLDENS'] == '1') file.writeAsStringSync(document.html);
      expect(document.html, file.readAsStringSync());
      expect(document.plainText, contains('我的心得'));
    });
  }
  test('all switches remove private and AI content including questions', () {
    final n = fixture.note().copyWith(
      sections: [
        NoteSection(id: 's', title: 'Section', question: 'SECRET?', blocks: fixture.note().sections.first.blocks),
      ],
    );
    final document = NoteRichDocument.resolve(
      fixture.content(),
      n,
      options: const NoteExportOptions(context: false, ownNotes: false, aiContent: false, sources: false),
    );
    expect(document.html, isNot(contains('我的心得')));
    expect(document.html, isNot(contains('SECRET')));
    expect(
      NoteExporter(fixture.content()).export(n, options: const NoteExportOptions(aiContent: false)).text,
      isNot(contains('SECRET')),
    );
    expect(document.paragraphs.where((p) => p.ai.isNotEmpty), isEmpty);
    expect(
      document.paragraphs.where((p) => p.kind == NoteParagraphKind.source || p.kind == NoteParagraphKind.context),
      isEmpty,
    );
  });
  test('escape user HTML and preserve exact custom highlight color', () {
    final c = fixture.content();
    final a = Annotation(
      id: 'a',
      documentId: 'd',
      page: 1,
      rects: const [PageRect(1, 1, 1, 1)],
      quote: '<script>"A&B"</script>',
      colorIndex: 0x011234ab,
      createdAt: fixture.date,
    );
    final document = NoteRichDocument.resolve(c.copyWith(annotations: [a]), fixture.note());
    expect(document.html, contains('&lt;script&gt;"A&amp;B"&lt;/script&gt;'));
    expect(document.html, contains('#1234AB'));
    expect(document.html, isNot(contains('<script>')));
    expect(noteHighlightHex(-1), '#FFCC00');
    expect(noteHighlightHex(5), '#AF52DE');
    expect(noteHighlightHex(100), '#AF52DE');
  });
  test('missing sources, invalid xrefs and empty notes are safe', () {
    final n = fixture.note().copyWith(
      sections: [
        NoteSection(
          id: 's',
          title: 'S',
          blocks: [
            const QuoteBlock(id: 'q', annotationId: 'missing'),
            const OwnBlock(id: 'o', sourceId: 'missing', source: OwnSource.card),
            const XrefBlock(id: 'x', toSectionId: 'missing', text: 'invalid'),
          ],
        ),
      ],
    );
    final document = NoteRichDocument.resolve(StudySetContent.empty, n, language: NoteExportLanguage.en);
    expect(document.html, contains('Highlight deleted'));
    expect(document.html, isNot(contains('invalid')));
    expect(NoteRichDocument.resolve(StudySetContent.empty, n.copyWith(sections: [])).plainText, n.title);
  });
}
