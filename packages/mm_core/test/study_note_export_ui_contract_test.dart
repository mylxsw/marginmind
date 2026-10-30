import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'study_notes_test.dart' as fixture;

void main() {
  test('English exports localize fixed labels without translating user text', () {
    final output = NoteExporter(
      fixture.content(),
      textSource: fixture.texts,
    ).export(fixture.note(), language: NoteExportLanguage.en).text;
    expect(output, contains('**My Note**'));
    expect(output, contains('**Context**'));
    expect(output, contains('## Sources'));
    expect(output, contains('Book, p. 1'));
    expect(output, contains('我的心得'));
    expect(output, isNot(contains('**我的批注**')));
  });
  test('text citations use outline titles and never expose storage chapter IDs', () {
    final annotation = Annotation(
      id: 'a',
      documentId: 'd',
      textAnchors: const [TextAnchor('internal-chapter', 0, 5, 'Quote', revision: 'v')],
      quote: 'Quote',
      colorIndex: 0,
      createdAt: fixture.date,
    );
    final content = fixture.content(annotations: [annotation]);
    expect(NoteExporter(content).export(fixture.note()).text, isNot(contains('internal-chapter')));
    final withOutline = content.copyWith(
      documentOutlines: [
        DocumentOutline(
          documentId: 'd',
          items: [
            PdfOutlineEntry(
              id: 'heading',
              title: 'Retrieval Practice',
              position: TextReadingPosition(revision: 'v', chapterId: 'internal-chapter', offset: 0),
            ),
          ],
        ),
      ],
    );
    expect(NoteExporter(withOutline).export(fixture.note()).text, contains('Retrieval Practice'));
  });
  test('Obsidian inline citation is a sanitized aliased page link in the callout title', () {
    final original = fixture.content();
    final c = original.copyWith(documents: [original.documents.single.copyWith(title: r'A/B:C*D?E"F<G>H|I#J^K[L]')]);
    final output = NoteExporter(c).export(fixture.note(), format: NoteExportFormat.obsidian).text;
    expect(output, contains('> [!quote] [[A B C D E F G H I J K L#p1|《A B C D E F G H I J K L》p.1]]'));
    expect(output, contains('- [[A B C D E F G H I J K L]]'));
    expect(output, isNot(contains('> ——')));
    for (final style in [NoteCitationStyle.footnote, NoteCitationStyle.none]) {
      final text = NoteExporter(c)
          .export(
            fixture.note(),
            format: NoteExportFormat.obsidian,
            options: NoteExportOptions(citations: style),
          )
          .text;
      expect(text, contains('> [!quote]\n'));
      expect(text, isNot(contains('> [!quote] [[')));
    }
  });
}
