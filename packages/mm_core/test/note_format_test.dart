import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  const md = TextFormat.markdown;
  const plain = TextFormat.plain;

  List<NoteSpan> spans(String line) => NoteDocument.parse(line, md).blocks.single.spans;

  group('parse', () {
    test('a plain note is never read as Markdown', () {
      final doc = NoteDocument.parse('**not bold**\n- not a list\n1. nor this', plain);
      expect(doc.blocks.map((b) => b.kind), everyElement(NoteBlockKind.paragraph));
      expect(doc.toPlainText(), '**not bold**\n- not a list\n1. nor this');
      expect(doc.hasFormatting, isFalse);
      expect(notePlainText('*a*', plain), '*a*');
    });

    test('bold, italic and both', () {
      expect(spans('a **b** c'), const [NoteSpan('a '), NoteSpan('b', bold: true), NoteSpan(' c')]);
      expect(spans('*i*'), const [NoteSpan('i', italic: true)]);
      expect(spans('***x***'), const [NoteSpan('x', bold: true, italic: true)]);
      expect(spans('**b *bi* b**'), const [
        NoteSpan('b ', bold: true),
        NoteSpan('bi', bold: true, italic: true),
        NoteSpan(' b', bold: true),
      ]);
    });

    test('unmatched or spaced stars stay text', () {
      expect(spans('2 * 3 * 4'), const [NoteSpan('2 * 3 * 4')]);
      expect(spans('**open'), const [NoteSpan('**open')]);
      expect(spans('a*b'), const [NoteSpan('a*b')]);
      expect(spans('****'), const [NoteSpan('****')]);
      expect(spans('***a**'), const [NoteSpan('*'), NoteSpan('a', bold: true)]);
    });

    test('escapes are literal', () {
      expect(spans(r'\*not\* \\ \-'), const [NoteSpan(r'*not* \ -')]);
      expect(spans(r'a\b'), const [NoteSpan(r'a\b')]);
    });

    test('list items and plain text', () {
      final doc = NoteDocument.parse('Intro\n- one **1**\n12. twelve\n-not\n1.not', md);
      expect(doc.blocks.map((b) => b.kind), [
        NoteBlockKind.paragraph,
        NoteBlockKind.bullet,
        NoteBlockKind.ordered,
        NoteBlockKind.paragraph,
        NoteBlockKind.paragraph,
      ]);
      expect(doc.blocks[2].number, 12);
      expect(doc.blocks[1].text, 'one 1');
      expect(doc.toPlainText(), 'Intro\n• one 1\n12. twelve\n-not\n1.not');
      expect(doc.hasFormatting, isTrue);
      expect(NoteDocument.parse('just text', md).hasFormatting, isFalse);
    });

    test('empty lines are empty paragraphs', () {
      final doc = NoteDocument.parse('a\n\nb', md);
      expect(doc.blocks, hasLength(3));
      expect(doc.blocks[1].spans, isEmpty);
    });

    test('values compare by content', () {
      expect(const NoteSpan('a', bold: true), const NoteSpan('a', bold: true));
      expect(const NoteSpan('a').hashCode, const NoteSpan('a').hashCode);
      expect(const NoteSpan('a', italic: true).toString(), contains('i'));
      expect(const NoteSourceRun(0, 1, marker: true), const NoteSourceRun(0, 1, marker: true));
      expect(const NoteSourceRun(0, 1).hashCode, const NoteSourceRun(0, 1).hashCode);
      expect(const NoteSourceRun(0, 1, marker: true, bold: true, italic: true).toString(), contains('marker'));
    });
  });

  group('source runs', () {
    test('mark the markup and style the text', () {
      expect(noteSourceRuns('- **b** x'), const [
        NoteSourceRun(0, 2, marker: true),
        NoteSourceRun(2, 4, marker: true),
        NoteSourceRun(4, 5, bold: true),
        NoteSourceRun(5, 7, marker: true),
        NoteSourceRun(7, 9),
      ]);
    });

    test('cover every line with offsets past the line breaks', () {
      final runs = noteSourceRuns('a\n\\*b');
      expect(runs, const [NoteSourceRun(0, 1), NoteSourceRun(2, 3, marker: true), NoteSourceRun(3, 5)]);
    });
  });

  group('escape', () {
    for (final text in [
      '*a* and **b**',
      '- dash line\n1. number line\n10. ten',
      r'back\slash \* \\',
      'plain -text 3.5',
      '',
      '-',
    ]) {
      test('round trips "$text"', () {
        final escaped = escapeNoteMarkdown(text).text;
        expect(NoteDocument.parse(escaped, md).toPlainText(), text);
      });
    }

    test('maps offsets past inserted backslashes', () {
      final e = escapeNoteMarkdown('a*b');
      expect(e.text, r'a\*b');
      expect(e.offsets(0), 0);
      expect(e.offsets(1), 1);
      expect(e.offsets(2), 3);
      expect(e.offsets(3), 4);
    });
  });

  group('formatting commands', () {
    NoteEditValue v(String text, int start, [int? end, TextFormat format = md]) =>
        NoteEditValue(text, start, end ?? start, format);

    test('the first format turns a plain note into escaped Markdown', () {
      final r = NoteFormatting.toggleBold(v('a*b c', 4, 5, plain));
      expect(r, v(r'a\*b **c**', 7, 8));
      expect(NoteDocument.parse(r.text, md).blocks.single.spans, const [NoteSpan('a*b '), NoteSpan('c', bold: true)]);
      expect(NoteFormatting.ensureMarkdown(r), same(r));
    });

    test('bold and italic wrap the selection and unwrap it again', () {
      final bold = NoteFormatting.toggleBold(v('one two', 4, 7));
      expect(bold, v('one **two**', 6, 9));
      expect(NoteFormatting.toggleBold(bold), v('one two', 4, 7));
      // Selecting the markers too also unwraps.
      expect(NoteFormatting.toggleBold(v('one **two**', 4, 11)), v('one two', 4, 7));
      final italic = NoteFormatting.toggleItalic(v('one two', 0, 3));
      expect(italic, v('*one* two', 1, 4));
      expect(NoteFormatting.toggleItalic(italic), v('one two', 0, 3));
      // Italic inside bold: both styles.
      expect(NoteFormatting.toggleItalic(bold).text, 'one ***two***');
      expect(NoteFormatting.toggleBold(v('***x***', 3, 4)), v('*x*', 1, 2));
      // Escaped stars beside the markers are text, not markup.
      final escaped = NoteFormatting.toggleBold(v(r'a \*b\*', 0, 7));
      expect(escaped.text, r'**a \*b\***');
      final both = NoteFormatting.toggleItalic(escaped);
      expect(both.text, r'***a \*b\****');
      expect(NoteFormatting.toggleBold(NoteFormatting.toggleItalic(both)), v(r'a \*b\*', 0, 7));
    });

    test('an empty selection inserts a pair, a second toggle takes it away', () {
      final r = NoteFormatting.toggleBold(v('ab', 1));
      expect(r, v('a****b', 3));
      expect(NoteFormatting.toggleBold(r), v('ab', 1));
      expect(NoteFormatting.toggleItalic(v('', 0)), v('**', 1));
    });

    test('several lines are styled one by one, outside list prefixes and spaces', () {
      final r = NoteFormatting.toggleBold(v('- one \n- two', 0, 12));
      expect(r.text, '- **one** \n- **two**');
      expect(r.start, 4);
      expect(r.end, r.text.length - 2);
      expect(NoteFormatting.toggleBold(r).text, '- one \n- two');
      // Only blank or prefix text selected: nothing to style.
      expect(NoteFormatting.toggleBold(v('-   ', 0, 4)), v('-   ', 0, 4));
    });

    test('lists toggle on the selected lines and renumber', () {
      expect(NoteFormatting.toggleBullets(v('a\nb', 0, 3)), v('- a\n- b', 2, 7));
      expect(NoteFormatting.toggleBullets(v('- a\n- b', 0, 7)), v('a\nb', 0, 3));
      expect(NoteFormatting.toggleNumbers(v('- a\nb', 0, 5)), v('1. a\n2. b', 3, 9));
      expect(NoteFormatting.toggleNumbers(v('1. a', 3)), v('a', 0));
      // The caret keeps its column; a selection ending at a line start leaves that line.
      expect(NoteFormatting.toggleBullets(v('ab\ncd', 1)), v('- ab\ncd', 3));
      expect(NoteFormatting.toggleBullets(v('ab\ncd', 0, 3)).text, '- ab\ncd');
      // A plain note is escaped first.
      expect(NoteFormatting.toggleBullets(v('*x', 0, 0, plain)), v(r'- \*x', 2));
    });

    test('typing "- " or "1. " at a line start of a plain note starts a list', () {
      final before = v('a*\n-', 4, 4, plain);
      final after = v('a*\n- ', 5, 5, plain);
      expect(NoteFormatting.autoList(before, after), v('a\\*\n- ', 6));
      expect(NoteFormatting.autoList(v('2', 1, 1, plain), v('2.', 2, 2, plain)), isNull);
      expect(NoteFormatting.autoList(v('12.', 3, 3, plain), v('12. ', 4, 4, plain)), v('12. ', 4));
      expect(NoteFormatting.autoList(v('-x', 1, 1, plain), v('- x', 2, 2, plain)), v('- x', 2));
      // Not at a line start, not a single typed space, or already Markdown.
      expect(NoteFormatting.autoList(v('a-', 2, 2, plain), v('a- ', 3, 3, plain)), isNull);
      expect(NoteFormatting.autoList(v('', 0, 0, plain), v('- ', 2, 2, plain)), isNull);
      expect(NoteFormatting.autoList(v('-', 1, 1, plain), v('-x', 2, 2, plain)), isNull);
      expect(NoteFormatting.autoList(v('-', 1, 1, md), v('- ', 2, 2, md)), isNull);
      expect(NoteFormatting.autoList(v('-', 1, 1, plain), v('- ', 0, 2, plain)), isNull);
      expect(NoteFormatting.autoList(v('-y', 1, 1, plain), v('- x', 2, 2, plain)), isNull);
    });

    test('a line break continues a list, and ends it in an empty item', () {
      expect(NoteFormatting.continueList(v('- a', 3), v('- a\n', 4)), v('- a\n- ', 6));
      expect(NoteFormatting.continueList(v('9. a\nb', 4), v('9. a\n\nb', 5)), v('9. a\n10. \nb', 9));
      expect(NoteFormatting.continueList(v('- a\n- ', 6), v('- a\n- \n', 7)), v('- a\n', 4));
      // Plain lines, a caret inside the prefix, or anything but one typed break.
      expect(NoteFormatting.continueList(v('a', 1), v('a\n', 2)), isNull);
      expect(NoteFormatting.continueList(v('- a', 1), v('-\n a', 2)), isNull);
      expect(NoteFormatting.continueList(v('- a', 3), v('- ab', 4)), isNull);
      expect(NoteFormatting.continueList(v('- a', 3, 3, plain), v('- a\n', 4, 4, plain)), isNull);
      expect(NoteFormatting.continueList(v('- a', 0, 3), v('\n', 1)), isNull);
    });

    test('values compare by content', () {
      expect(v('a', 0), NoteEditValue.collapsed('a', 0, md));
      expect(v('a', 0).hashCode, NoteEditValue.collapsed('a', 0, md).hashCode);
      expect(v('a', 0).toString(), contains('markdown'));
    });
  });

  group('export and review', () {
    var seq = 0;
    final e = StudySetEditor(newId: () => 'id-${seq++}', now: () => DateTime.utc(2026, 10, 26));

    StudySetContent withNote(String text, TextFormat format) {
      final (c, topic) = e.addTopic(StudySetContent.empty, title: 'Topic');
      final (c1, note) = e.addNote(c, text: text, parentId: topic.id);
      return e.setCardTextFormat(c1, note.id, format);
    }

    test('Markdown keeps a formatted note as written, OPML strips it', () {
      final c = withNote('**Key** point\nsecond line\n- one\n- two\n\nafter', md);
      final markdown = MapExporter(c, rootTitle: 'Root').markdown();
      expect(
        markdown,
        contains(
          '  - **Key** point\\\n'
          '    second line\n'
          '    - one\n'
          '    - two\n'
          '\n'
          '    after\n',
        ),
      );
      final opml = MapExporter(c, rootTitle: 'Root').opml();
      expect(opml, contains('text="Key point&#10;second line&#10;• one&#10;• two&#10;&#10;after"'));
    });

    test('a plain note exports as before, stars and all', () {
      final c = withNote('2 * 3 *', plain);
      expect(MapExporter(c, rootTitle: 'Root').markdown(), contains('  - 2 * 3 *\n'));
      expect(MapExporter(c, rootTitle: 'Root').opml(), contains('text="2 * 3 *"'));
    });

    test('relations name a formatted note by its text', () {
      final c = withNote('**Bold** note', md);
      final topic = c.cards.firstWhere((x) => x.kind == CardKind.topic);
      final note = c.cards.firstWhere((x) => x.kind == CardKind.note);
      final (c1, _) = e.addRelation(c, topic.id, note.id);
      expect(MapExporter(c1, rootTitle: 'Root').markdown(), contains('- Topic → Bold note'));
    });

    test('review keeps each note with its format; prompts and paths use plain text', () {
      final (c, parent) = e.addNote(StudySetContent.empty, text: '**Why** it works');
      final c1 = e.setCardTextFormat(c, parent.id, md);
      final (c2, child) = e.addNote(c1, text: '*child*', parentId: parent.id);
      final c3 = e.setCardTextFormat(c2, child.id, md);
      final (c4, grandchild) = e.addNote(c3, text: 'leaf', parentId: child.id);
      expect(buildReviewFace(c3.card(parent.id)!, c3).back.notes, const [
        ReviewNote('**Why** it works', md),
        ReviewNote('*child*', md),
      ]);
      final face = buildReviewFace(c4.card(child.id)!, c4);
      expect(face.front.title, 'Why it works');
      expect(buildReviewFace(grandchild, c4).front.path, ['Why it works', 'child']);
      expect(const ReviewNote('a').toString(), contains('plain'));
      expect(const ReviewNote('a').hashCode, const ReviewNote('a', plain).hashCode);
    });
  });
}
