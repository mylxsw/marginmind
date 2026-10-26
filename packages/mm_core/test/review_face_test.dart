import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  var seq = 0;
  final e = StudySetEditor(newId: () => 'id-${seq++}', now: () => DateTime.utc(2026, 10, 26));
  const rect = PageRect(10, 20, 30, 10);
  const page = 'Cells divide. Mitosis has four phases, and each is short. The next step is meiosis. Last sentence.';

  // Root > Biology > Cells > excerpt, in document "Book" page 4.
  (StudySetContent, Card) excerpt({String quote = 'Mitosis has four phases, and each is short.', String title = ''}) {
    final (c, doc) = e.addDocument(StudySetContent.empty, title: 'Book', fileName: 'b.pdf', pageCount: 9);
    final (c1, bio) = e.addTopic(c, title: 'Biology');
    final (c2, cells) = e.addTopic(c1, title: ' Cells ', parentId: bio.id);
    final (c3, card) = e.createExcerpt(
      c2,
      documentId: doc.id,
      page: 4,
      rects: const [rect],
      quote: quote,
      colorIndex: 0,
      parentId: cells.id,
    );
    final named = title.isEmpty ? c3 : e.rename(c3, card.id, title);
    return (named, named.card(card.id)!);
  }

  group('excerptContext', () {
    test('keeps the sentence and one on each side, split at the excerpt', () {
      final r = excerptContext(page, 'four phases')!;
      expect(r.before, 'Cells divide. Mitosis has ');
      expect(r.after, ', and each is short. The next step is meiosis.');
    });

    test('an excerpt that is a whole sentence adds only its neighbours', () {
      final r = excerptContext(page, 'Mitosis has four phases, and each is short.')!;
      expect(r.before, 'Cells divide. ');
      expect(r.after, ' The next step is meiosis.');
    });

    test('at the page edges there is nothing more to add', () {
      expect(excerptContext(page, 'Cells divide.')!.before, '');
      expect(excerptContext(page, 'Last sentence.')!.after, '');
      expect(excerptContext('Only one', 'one')!.before, 'Only ');
    });

    test('folds line wraps and CJK sentence ends', () {
      final r = excerptContext('第一句。细胞\n分裂 很快。第三句。', '细胞 分裂')!;
      expect(r.before, '第一句。');
      expect(r.after, ' 很快。第三句。');
    });

    test('matches Chinese broken across lines against a quote joined without spaces', () {
      final r = excerptContext('第一句。细胞分\n裂的过程\n很快。第三句。', '细胞分裂的过程很快。')!;
      expect(r.before, '第一句。');
      expect(r.after, '第三句。');
    });

    test('matches English broken across lines and hyphenated words', () {
      const text = 'Cells divide. Mitosis has\nfour inter-\nnational phases. Last one.';
      final r = excerptContext(text, 'has four international phases.')!;
      expect(r.before, 'Cells divide. Mitosis ');
      expect(r.after, ' Last one.');
    });

    test('matches mixed Chinese and English', () {
      final r = excerptContext('前文。DNA 复制发\n生在 S 期。后文。', 'DNA 复制发生在 S 期')!;
      expect(r.before, '前文。');
      expect(r.after, '。后文。');
    });

    test('still matches quotes saved with a space between Chinese characters', () {
      expect(excerptContext('细胞分\n裂很快。', '细胞 分裂'), isNull);
      expect(excerptContext('细胞\n分裂 很快。', '细胞 分裂'), isNotNull);
    });

    test('treats paragraph breaks and full-width marks as sentence boundaries', () {
      final r = excerptContext('标题\n\n什么是细胞？细胞是基本单位！它很小', '基本单位')!;
      expect(r.before, '什么是细胞？细胞是');
      expect(r.after, '！它很小');
    });

    test('picks the occurrence closest to the highlight', () {
      const text = '甲说。重复的话。乙说。丙说。丁说。重复的话。戊说。';
      expect(excerptContext(text, '重复的话', near: 0)!.before, '甲说。');
      expect(excerptContext(text, '重复的话', near: 1)!.before, '丁说。');
      expect(excerptContext(text, '重复的话')!.before, '甲说。');
    });

    test('returns null when the quote is missing or blank', () {
      expect(excerptContext(page, 'absent'), isNull);
      expect(excerptContext(page, '  '), isNull);
    });
  });

  group('excerpt cards', () {
    test('cloze front: path without the root, context, mask as long as the quote', () {
      final (c, card) = excerpt();
      final face = buildReviewFace(card, c, rootTitle: 'Root', pageText: page);
      expect(face.front.prompt, ReviewPrompt.cloze);
      expect(face.front.path, ['Biology', 'Cells']);
      expect(face.front.before, 'Cells divide. ');
      expect(face.front.after, ' The next step is meiosis.');
      expect(face.front.maskLength, 'Mitosis has four phases, and each is short.'.length);
      expect(face.back.quote, 'Mitosis has four phases, and each is short.');
      expect(face.back.source, ReviewSource(documentId: c.documents.single.id, documentTitle: 'Book', page: 4));
      expect(face.back.notes, isEmpty);
      expect(needsPageText(card, c), isTrue);
    });

    test('a repeated quote is told apart by where it was highlighted', () {
      const repeated = '开头。重复的话。中间一。中间二。结尾。重复的话。收尾。';
      final (c, card) = excerpt(quote: '重复的话');
      expect(buildReviewFace(card, c, pageText: repeated).front.before, '开头。');
      // The rect's top is 20: near the top of a 22-high page, near the bottom of a 2000-high one.
      expect(buildReviewFace(card, c, pageText: repeated, pageHeight: 22).front.after, '。中间一。');
      expect(buildReviewFace(card, c, pageText: repeated, pageHeight: 2000).front.after, '。收尾。');
      expect(buildReviewFace(card, c, pageText: repeated, pageHeight: 0).front.before, '开头。');
    });

    test('the user title is the prompt, path kept', () {
      final (c, card) = excerpt(title: 'What are the phases?');
      final face = buildReviewFace(card, c, pageText: page);
      expect(face.front.prompt, ReviewPrompt.title);
      expect(face.front.title, 'What are the phases?');
      expect(face.front.path, ['Biology', 'Cells']);
      expect(face.back.quote, startsWith('Mitosis'));
      expect(needsPageText(card, c), isFalse);
    });

    test('no readable context falls back to the page thumbnail with the area covered', () {
      final (c, card) = excerpt();
      for (final text in [null, 'unrelated text']) {
        final face = buildReviewFace(card, c, pageText: text);
        expect(face.front.prompt, ReviewPrompt.page);
        expect(face.front.page, 4);
        expect(face.front.areas, [rect]);
      }
    });

    test('child notes show on the back in map order; empty and non-notes are skipped', () {
      var (c, card) = excerpt();
      final (c1, n1) = e.addNote(c, text: 'First note', parentId: card.id);
      final (c2, _) = e.addNote(c1, text: '  ', parentId: card.id);
      final (c3, _) = e.addTopic(c2, title: 'A topic', parentId: card.id);
      final (c4, _) = e.addNote(c3, text: 'Second note', parentId: card.id);
      expect(n1.kind, CardKind.note);
      final face = buildReviewFace(card, c4, pageText: page);
      expect(face.back.notes, ['First note', 'Second note']);
    });

    test('mapId selects the branch path', () {
      final (c, card) = excerpt();
      final (withMap, map) = e.addMap(c, title: 'Other');
      final other = StudySetEditor(newId: () => 'id-${seq++}', now: () => DateTime.utc(2026), mapId: map.id);
      final placed = other.placeCard(withMap, card.id);
      expect(buildReviewFace(card, placed, mapId: map.id, pageText: page).front.path, isEmpty);
    });
  });

  group('image cards', () {
    (StudySetContent, Card) image({bool titled = false}) {
      final (c, doc) = e.addDocument(StudySetContent.empty, title: 'Scan', fileName: 's.pdf', pageCount: 3);
      final (c1, topic) = e.addTopic(c, title: 'Figures');
      final (c2, card) = e.createAreaExcerpt(
        c1,
        documentId: doc.id,
        page: 2,
        rect: rect,
        imageFileName: 'images/a.png',
        colorIndex: 0,
        parentId: topic.id,
      );
      final named = titled ? e.rename(c2, card.id, 'Which figure?') : c2;
      return (named, named.card(card.id)!);
    }

    test('untitled: thumbnail of the page with the area covered; picture on the back', () {
      final (c, card) = image();
      final face = buildReviewFace(card, c, pageText: 'ignored');
      expect(face.front.prompt, ReviewPrompt.page);
      expect(face.front.page, 2);
      expect(face.front.areas, [rect]);
      expect(face.front.path, ['Figures']);
      expect(face.back.imageFileName, 'images/a.png');
      expect(face.back.quote, isEmpty);
      expect(face.back.source!.documentTitle, 'Scan');
      expect(needsPageText(card, c), isFalse);
    });

    test('titled: the title is the prompt', () {
      final (c, card) = image(titled: true);
      final face = buildReviewFace(card, c);
      expect(face.front.prompt, ReviewPrompt.title);
      expect(face.front.title, 'Which figure?');
      expect(face.back.imageFileName, 'images/a.png');
    });
  });

  group('note cards', () {
    test('front is the path plus the parent title; back is the note', () {
      var (c, card) = excerpt(title: 'Phases?');
      final (c1, note) = e.addNote(c, text: 'Prophase first', parentId: card.id);
      final face = buildReviewFace(note, c1);
      expect(face.front.prompt, ReviewPrompt.title);
      expect(face.front.title, 'Phases?');
      expect(face.front.path, ['Biology', 'Cells', 'Phases?']);
      expect(face.back.notes, ['Prophase first']);
      expect(face.back.source, isNull);
    });

    test('an untitled excerpt parent is described by its quote', () {
      final (c, card) = excerpt();
      final (c1, note) = e.addNote(c, text: 'Remember', parentId: card.id);
      expect(buildReviewFace(note, c1).front.title, startsWith('Mitosis has'));
    });

    test('a note under the root uses the root title; with none there is no prompt', () {
      final (c, note) = e.addNote(StudySetContent.empty, text: 'Loose');
      final withRoot = buildReviewFace(note, c, rootTitle: ' Set ');
      expect(withRoot.front.prompt, ReviewPrompt.title);
      expect(withRoot.front.title, 'Set');
      expect(withRoot.front.path, isEmpty);
      expect(buildReviewFace(note, c).front.prompt, ReviewPrompt.none);
    });

    test("a note's own child notes follow it", () {
      final (c, note) = e.addNote(StudySetContent.empty, text: 'Parent note');
      final (c1, _) = e.addNote(c, text: 'Child', parentId: note.id);
      expect(buildReviewFace(note, c1).back.notes, ['Parent note', 'Child']);
    });
  });

  test('a card without an annotation has no front but still answers', () {
    final topic = Card(id: 'x', kind: CardKind.excerpt, createdAt: DateTime.utc(2026));
    final face = buildReviewFace(topic, StudySetContent(cards: [topic]));
    expect(face.front.prompt, ReviewPrompt.none);
    expect(face.front.path, isEmpty);
    expect(face, buildReviewFace(topic, StudySetContent(cards: [topic])));
    expect(face.hashCode, buildReviewFace(topic, StudySetContent(cards: [topic])).hashCode);
  });
}
