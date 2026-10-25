import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  late StudySetEditor editor;
  late DateTime now;
  var n = 0;
  setUp(() {
    n = 0;
    now = DateTime(2026, 10, 25, 9);
    editor = StudySetEditor(newId: () => 'id${++n}', now: () => now);
  });

  const rects = [PageRect(10, 100, 200, 88)];

  (StudySetContent, Document) withDoc([StudySetContent c = StudySetContent.empty]) =>
      editor.addDocument(c, title: 'Book', fileName: 'documents/a.pdf', pageCount: 10);

  group('map editing', () {
    test('move places a node at an index among its new siblings', () {
      var c = StudySetContent.empty;
      final (c1, a) = editor.addTopic(c, title: 'A');
      final (c2, b) = editor.addTopic(c1, title: 'B');
      final (c3, x) = editor.addTopic(c2, title: 'X');
      c = editor.move(c3, x.id, null, index: 0);
      expect([for (final n in c.childrenOf(null)) n.cardId], [x.id, a.id, b.id]);
      c = editor.move(c, x.id, null, index: 2);
      expect([for (final n in c.childrenOf(null)) n.cardId], [a.id, b.id, x.id]);
      c = editor.move(c, x.id, null, index: 1);
      expect([for (final n in c.childrenOf(null)) n.cardId], [a.id, x.id, b.id]);
      c = editor.move(c, a.id, x.id);
      expect(c.node(a.id)!.parentId, x.id);
      // Not under its own descendant.
      expect(editor.move(c, x.id, a.id), same(c));
    });

    test('shift reorders among siblings and stops at the ends', () {
      var c = StudySetContent.empty;
      final (c1, a) = editor.addTopic(c, title: 'A');
      final (c2, b) = editor.addTopic(c1, title: 'B');
      c = editor.shift(c2, b.id, -1);
      expect([for (final n in c.childrenOf(null)) n.cardId], [b.id, a.id]);
      expect(editor.shift(c, b.id, -1), same(c));
    });

    test('collapsed survives a JSON round trip', () {
      final (c1, a) = editor.addTopic(StudySetContent.empty, title: 'A');
      final c = editor.setCollapsed(c1, a.id, collapsed: true);
      final back = StudySetContent.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, Object?>);
      expect(back.node(a.id)!.collapsed, isTrue);
    });

    test('removeDocument drops its highlights and excerpt cards', () {
      final (c0, doc) = withDoc();
      final (c1, other) = editor.addDocument(c0, title: 'Other', fileName: 'documents/b.pdf', pageCount: 2);
      final (c2, card) = editor.createExcerpt(c1, documentId: doc.id, page: 1, rects: rects, quote: 'q', colorIndex: 0);
      final (c3, keep) = editor.createExcerpt(
        c2,
        documentId: other.id,
        page: 1,
        rects: rects,
        quote: 'k',
        colorIndex: 0,
      );
      final c = editor.removeDocument(c3, doc.id);
      expect(c.documents.map((d) => d.id), [other.id]);
      expect(c.card(card.id), isNull);
      expect(c.card(keep.id), isNotNull);
      expect(c.annotations, hasLength(1));
    });

    test('restore keeps review history and reading position from the present', () {
      final (c0, doc) = withDoc();
      final (before, topic) = editor.addTopic(c0, title: 'T');
      final (excerpted, card) = editor.createExcerpt(
        before,
        documentId: doc.id,
        page: 1,
        rects: rects,
        quote: 'q',
        colorIndex: 0,
      );
      final current = editor.rate(editor.setLastPage(excerpted, doc.id, 7), card.id, Rating.good);
      final restored = StudySetEditor.restore(before, current);
      expect(restored.card(card.id), isNull);
      expect(restored.card(topic.id), isNotNull);
      expect(restored.document(doc.id)!.lastPage, 7);
      expect(restored.reviews, hasLength(1));
    });
  });

  group('review', () {
    test('scheduler grows intervals and resets on again', () {
      var s = ReviewScheduler.rate('c', null, Rating.good, now);
      expect(s.intervalDays, 1);
      expect(s.due, now.add(const Duration(days: 1)));
      s = ReviewScheduler.rate('c', s, Rating.good, now);
      expect(s.intervalDays, 3);
      s = ReviewScheduler.rate('c', s, Rating.good, now);
      expect(s.intervalDays, closeTo(7.5, 0.001));
      s = ReviewScheduler.rate('c', s, Rating.again, now);
      expect(s.intervalDays, 0);
      expect(s.lapses, 1);
      expect(s.due, now.add(ReviewScheduler.relearnDelay));
      expect(s.ease, closeTo(2.3, 0.001));
      expect(ReviewScheduler.rate('c', null, Rating.easy, now).intervalDays, 4);
    });

    test('queue has due cards first, then new ones, never topics', () {
      final (c0, doc) = withDoc();
      final (c1, _) = editor.addTopic(c0, title: 'T');
      final (c2, first) = editor.createExcerpt(
        c1,
        documentId: doc.id,
        page: 1,
        rects: rects,
        quote: 'a',
        colorIndex: 0,
      );
      final (c3, second) = editor.addNote(c2, text: 'note');
      final (c4, _) = editor.addNote(c3, text: '  ');
      var c = c4;
      expect(c.reviewQueue(now).map((x) => x.id), [first.id, second.id]);

      c = editor.rate(c, first.id, Rating.good);
      expect(c.reviewQueue(now).map((x) => x.id), [second.id]);
      final tomorrow = now.add(const Duration(days: 1, minutes: 1));
      expect(c.reviewQueue(tomorrow).map((x) => x.id), [first.id, second.id]);
      expect(c.dueCount(tomorrow), 2);
    });

    test('reviews survive a JSON round trip', () {
      final (c0, a) = editor.addNote(StudySetContent.empty, text: 'n');
      final c = editor.rate(c0, a.id, Rating.hard);
      final back = StudySetContent.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, Object?>);
      expect(back.reviewOf(a.id)!.due, c.reviewOf(a.id)!.due);
      expect(back.reviewOf(a.id)!.ease, c.reviewOf(a.id)!.ease);
    });
  });

  group('search, path and export', () {
    late StudySetContent c;
    late Card excerpt;
    setUp(() {
      final (c0, doc) = withDoc();
      final (c1, topic) = editor.addTopic(c0, title: 'Memory & <Forgetting>');
      final (c2, card) = editor.createExcerpt(
        c1,
        documentId: doc.id,
        page: 3,
        rects: rects,
        quote: 'The forgetting\ncurve',
        colorIndex: 0,
        parentId: topic.id,
      );
      final (c3, _) = editor.addNote(c2, text: 'Review "often"', parentId: card.id);
      c = c3;
      excerpt = card;
    });

    test('search matches titles and quotes in map order', () {
      expect(c.search('FORGET').map((x) => x.kind), [CardKind.topic, CardKind.excerpt]);
      expect(c.search('often').single.kind, CardKind.note);
      expect(c.search('  '), isEmpty);
    });

    test('pathOf lists ancestors root first', () {
      expect(c.pathOf(excerpt.id), ['Memory & <Forgetting>']);
    });

    test('markdown nests topics, excerpts and notes', () {
      final md = MapExporter(c, rootTitle: 'Set').markdown();
      expect(
        md,
        '# Set\n\n'
        '- **Memory & <Forgetting>**\n'
        '  - “The forgetting curve” *(Book, p. 3)*\n'
        '    - Review "often"\n',
      );
    });

    test('opml escapes text and keeps quotes as notes', () {
      final xml = MapExporter(c, rootTitle: 'Set').opml();
      expect(xml, contains('<outline text="Memory &amp; &lt;Forgetting&gt;">'));
      expect(xml, contains('text="The forgetting&#10;curve" _note="Book, p. 3">'));
      expect(xml, contains('text="Review &quot;often&quot;"/>'));
    });
  });
}
