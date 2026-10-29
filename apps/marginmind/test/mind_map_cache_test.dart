import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/l10n/generated/app_localizations_en.dart';
import 'package:marginmind/l10n/generated/app_localizations_zh.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_layout/mm_layout.dart';

final now = DateTime(2026);
final english = AppLocalizationsEn();
final theme = MMTheme.light();

StudySetContent fixture([int count = 499]) => StudySetContent(
  cards: [
    for (var i = 0; i < count; i++)
      Card(
        id: 'c$i',
        kind: CardKind.values[i % 3],
        title: 'Node $i 中文',
        annotationId: i % 3 == 1 ? 'a$i' : null,
        createdAt: now,
      ),
  ],
  nodes: [
    for (var i = 0; i < count; i++)
      MapNode(cardId: 'c$i', parentId: i < 10 ? null : 'c${(i - 10) ~/ 10}', order: i.toDouble()),
  ],
  annotations: [
    for (var i = 1; i < count; i += 3)
      Annotation(
        id: 'a$i',
        documentId: 'd',
        page: i + 1,
        rects: const [],
        // Short enough to show whole (see the clipping test).
        quote: '摘录 $i text with words.',
        colorIndex: i % 6,
        createdAt: now,
      ),
  ],
  documents: [Document(id: 'd', title: 'Source', fileName: 'a.pdf', pageCount: 500, importedAt: now)],
);

TreeLayoutResult update(MindMapRenderCache cache, StudySetContent content, {String title = 'Root'}) =>
    cache.update(content: content, rootTitle: title, localizations: english, theme: theme);

// Pre-cache implementation as an independent geometry oracle. Retains the
// original scans and TextPainter calls, so indexing/caching cannot mask drift.
TreeLayoutResult legacyLayout(StudySetContent content, {String title = 'Root'}) {
  ({Size size, int lines}) measure(String text, TextStyle style, double width) {
    final p = TextPainter(
      text: TextSpan(text: text.isEmpty ? ' ' : text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    final result = (
      size: Size(p.width.ceilToDouble(), p.height.ceilToDouble()),
      lines: math.max(1, p.computeLineMetrics().length),
    );
    p.dispose();
    return result;
  }

  Size cardSize(Card card) {
    switch (card.kind) {
      case CardKind.topic:
        final s = measure(card.title, MMTypography.headline, 192).size;
        return Size(s.width + 32, s.height + 18);
      case CardKind.research:
      case CardKind.note:
        final s = measure(card.title, MMTypography.body.copyWith(height: 19 / 13), 186).size;
        return Size(s.width + 48, s.height + 16);
      case CardKind.image:
      case CardKind.excerpt:
        final quote = content.annotation(card.annotationId ?? '')?.quote ?? '';
        final lines = math.min(4, measure(quote, MMTypography.readingExcerpt, 174).lines);
        // No title row without a title; the source is not on the card.
        final title = card.title.isEmpty ? 0 : 17 + 6;
        return Size(240, (11 + title + (lines * 20 + 12) + 11 + 2).toDouble());
    }
  }

  LayoutNode build(String id, Size size) {
    var children = content.childrenOf(id == rootNodeId ? null : id);
    if (id != rootNodeId && (content.node(id)?.collapsed ?? false)) children = [];
    return LayoutNode(
      id: id,
      width: size.width,
      height: size.height,
      children: [
        for (final node in children)
          if (content.card(node.cardId) case final card?) build(card.id, cardSize(card)),
      ],
    );
  }

  return const TreeLayout(
    levelGap: 56,
    siblingGap: 14,
    padding: 72,
    balanced: true,
  ).layout(build(rootNodeId, Size(measure(title, MMTypography.title3, 360).size.width + 40, 42)));
}

void expectSameGeometry(TreeLayoutResult a, TreeLayoutResult b) {
  expect(a.width, b.width);
  expect(a.height, b.height);
  expect(
    [for (final e in a.rects.entries) (e.key, e.value.left, e.value.top, e.value.width, e.value.height)],
    [for (final e in b.rects.entries) (e.key, e.value.left, e.value.top, e.value.width, e.value.height)],
  );
  expect([for (final e in a.edges) (e.parentId, e.childId)], [for (final e in b.edges) (e.parentId, e.childId)]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('legacy summaries without a card distinguish stored labels from active drafts', () {
    final cache = MindMapRenderCache();
    final content = fixture(2).copyWith(
      summaries: const [MapSummary(id: 's', fromId: 'c0', toId: 'c1', label: 'Legacy summary')],
    );
    final stored = update(cache, content);
    expect(stored.summaries['s']!.label.width, greaterThan(0));
    expect(update(cache, content), same(stored));
    final empty = content.copyWith(summaries: [content.summaries.single.copyWith(label: '')]);
    expect(update(cache, empty).summaries['s']!.label.width, 0);
    final editing = cache.update(
      content: empty,
      rootTitle: 'Root',
      localizations: english,
      theme: theme,
      markDraft: ('s', ''),
    );
    expect(editing.summaries['s']!.label.width, greaterThan(0));
    expect(update(cache, empty).summaries['s']!.label.width, 0);
  });
  test('500 mixed nodes preserve every original rectangle and edge', () {
    final content = fixture();
    final cached = update(MindMapRenderCache(), content);
    expect(cached.rects, hasLength(500));
    expectSameGeometry(cached, legacyLayout(content));
  });
  test('unchanged content, read position and annotation color reuse layout and measurements', () {
    final cache = MindMapRenderCache();
    final content = fixture(30);
    final first = update(cache, content);
    final measured = cache.measurementCount;
    expect(update(cache, content), same(first));
    final metadata = content.copyWith(
      documents: [content.documents.first.copyWith(lastPage: 12, title: 'Renamed source')],
      annotations: [for (final a in content.annotations) a.copyWith(colorIndex: 5)],
    );
    expect(update(cache, metadata), same(first));
    expect(cache.measurementCount, measured);
    expect(cache.layoutCount, 1);
  });
  test('one text change measures once, reflows correctly; undo uses cached text', () {
    final cache = MindMapRenderCache();
    final content = fixture();
    update(cache, content);
    final measured = cache.measurementCount;
    final changed = content.copyWith(
      cards: [
        content.cards.first.copyWith(title: 'A much longer topic that wraps across several lines'),
        ...content.cards.skip(1),
      ],
    );
    expectSameGeometry(update(cache, changed), legacyLayout(changed));
    expect(cache.measurementCount, measured + 1);
    expect(cache.layoutCount, 2);
    expectSameGeometry(update(cache, content), legacyLayout(content));
    expect(cache.measurementCount, measured + 1);
  });
  test('move, reorder, fold, unfold, remove and missing cards preserve legacy layout', () {
    final cache = MindMapRenderCache();
    final content = fixture(40);
    update(cache, content);
    for (final nodes in [
      [for (final n in content.nodes) n.cardId == 'c1' ? n.copyWith(parentId: 'c0') : n],
      [for (final n in content.nodes) n.cardId == 'c0' ? n.copyWith(order: 100) : n],
      [for (final n in content.nodes) n.cardId == 'c0' ? n.copyWith(collapsed: true) : n],
      content.nodes,
      content.nodes.where((n) => n.cardId != 'c0').toList(),
      [...content.nodes, const MapNode(cardId: 'missing', order: 1000)],
    ]) {
      final changed = content.copyWith(nodes: nodes);
      expectSameGeometry(update(cache, changed), legacyLayout(changed));
    }
  });
  test('root title, empty text and excerpts without annotations are measured', () {
    final cache = MindMapRenderCache();
    final content = fixture(3).copyWith(
      annotations: [],
      cards: [
        Card(id: 'c0', kind: CardKind.topic, createdAt: now),
        Card(id: 'c1', kind: CardKind.excerpt, createdAt: now),
        Card(id: 'c2', kind: CardKind.note, createdAt: now),
      ],
    );
    expectSameGeometry(update(cache, content, title: ''), legacyLayout(content, title: english.appName));
    expectSameGeometry(update(cache, content, title: 'New root title'), legacyLayout(content, title: 'New root title'));
  });
  test('theme, scale, locale and direction invalidate measurements', () {
    final cache = MindMapRenderCache();
    final content = fixture(3);
    final original = update(cache, content);
    var count = cache.measurementCount;
    TreeLayoutResult environment({
      ThemeData? colors,
      TextScaler scaler = TextScaler.noScaling,
      Locale locale = const Locale('en'),
      TextDirection direction = TextDirection.ltr,
    }) => cache.update(
      content: content,
      rootTitle: 'Root',
      localizations: locale.languageCode == 'zh' ? AppLocalizationsZh() : english,
      theme: colors ?? theme,
      textScaler: scaler,
      locale: locale,
      textDirection: direction,
    );
    // Root, topic, note, the excerpt's quote and its title (one line or more).
    expect(environment(colors: MMTheme.dark()), same(original));
    expect(cache.measurementCount, count + 5);
    count = cache.measurementCount;
    final scaled = environment(scaler: TextScaler.linear(1.5));
    expect(scaled.rects['c0']!.height, greaterThan(original.rects['c0']!.height));
    expect(scaled.rects['c1']!.height, greaterThan(original.rects['c1']!.height));
    expect(cache.measurementCount, count + 5);
    count = cache.measurementCount;
    environment(locale: const Locale('zh'));
    expect(cache.measurementCount, count + 5);
    count = cache.measurementCount;
    environment(direction: TextDirection.rtl);
    expect(cache.measurementCount, count + 5);
  });
  test('the inherited text style is measured with and invalidates measurements', () {
    // Rendered titles inherit the ambient style (on macOS: the system font and
    // letter spacing); measuring without it made titles wrap as drawn.
    final cache = MindMapRenderCache();
    final content = fixture(3);
    final plain = update(cache, content);
    final count = cache.measurementCount;
    final spaced = cache.update(
      content: content,
      rootTitle: 'Root',
      localizations: english,
      theme: theme,
      baseStyle: const TextStyle(letterSpacing: 2),
    );
    expect(cache.measurementCount, count + 5);
    expect(spaced.rects['c0']!.width, greaterThan(plain.rects['c0']!.width));
  });

  test('same text shares measurements only when style and width match', () {
    final cache = MindMapRenderCache();
    final content = fixture(4).copyWith(
      cards: [
        for (var i = 0; i < 4; i++)
          Card(id: 'c$i', kind: i == 3 ? CardKind.note : CardKind.topic, title: 'Same', createdAt: now),
      ],
    );
    update(cache, content);
    expect(cache.measurementCount, 3); // root, headline, note body
    expect(cache.cachedMeasurementCount, 3);
  });
  test('equal-size title changes update text without relayout', () {
    final cache = MindMapRenderCache();
    final content = fixture(1).copyWith(
      cards: [Card(id: 'c0', kind: CardKind.topic, title: 'abc', createdAt: now)],
    );
    final first = update(cache, content);
    // The test font is fixed-width, so these have identical dimensions.
    final changed = content.copyWith(cards: [content.cards.first.copyWith(title: 'def')]);
    expect(update(cache, changed), same(first));
    expect(cache.layoutCount, 1);
    expect(cache.measurementCount, 3);
  });
  test('measurement cache is bounded during long editing sessions', () {
    final cache = MindMapRenderCache();
    for (var i = 0; i < MindMapRenderCache.measurementCapacity + 5; i++) {
      update(cache, StudySetContent.empty, title: 'Version $i');
    }
    expect(cache.cachedMeasurementCount, MindMapRenderCache.measurementCapacity);
    final count = cache.measurementCount;
    update(cache, StudySetContent.empty, title: 'Version 0');
    expect(cache.measurementCount, count + 1);
  });
  test('excerpts: a title row only with a title or while typing one; long quotes are cut once', () {
    final cache = MindMapRenderCache();
    final long = 'word ' * 80;
    final content = fixture(0).copyWith(
      annotations: [
        Annotation(id: 'a', documentId: 'd', page: 1, rects: const [], quote: long, colorIndex: 0, createdAt: now),
      ],
      cards: [Card(id: 'e', kind: CardKind.excerpt, annotationId: 'a', createdAt: now)],
      nodes: const [MapNode(cardId: 'e', order: 0)],
    );
    // Four lines of quote and the "show full text" row; no title row, no source row.
    const cut = 11 + (4 * 20 + 12) + 4 + 14 + 11 + 2;
    expect(update(cache, content).rects['e']!.height, cut);
    final measured = cache.measurementCount;
    expect(update(cache, content.copyWith(nodes: [...content.nodes])).rects['e']!.height, cut);
    expect(cache.measurementCount, measured, reason: 'the cut quote is cached');
    final typing = cache.update(
      content: content,
      rootTitle: 'Root',
      localizations: english,
      theme: theme,
      draft: ('e', ''),
    );
    expect(
      typing.rects['e']!.height,
      11 + (4 * 20 + 12) + 11 + 2 + 17 + 6,
      reason: 'the title field opens even while empty; while typing the card shows its preview',
    );
    final titled = content.copyWith(cards: [content.cards.single.copyWith(title: 'Title')]);
    expect(update(cache, titled).rects['e']!.height, cut + 17 + 6);
  });

  group('C01 full text', () {
    TreeLayoutResult expand(MindMapRenderCache cache, StudySetContent content, Set<String> expanded) =>
        cache.update(content: content, rootTitle: 'Root', localizations: english, theme: theme, expanded: expanded);

    StudySetContent excerpt({required String quote, String title = ''}) => fixture(0).copyWith(
      annotations: [
        Annotation(id: 'a', documentId: 'd', page: 1, rects: const [], quote: quote, colorIndex: 0, createdAt: now),
      ],
      cards: [Card(id: 'e', kind: CardKind.excerpt, title: title, annotationId: 'a', createdAt: now)],
      nodes: const [MapNode(cardId: 'e', order: 0)],
    );

    int lines(String text, TextStyle style, double width) {
      final p = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
      final n = p.computeLineMetrics().length;
      p.dispose();
      return n;
    }

    test('the expanded set is part of the key: the card grows and shrinks back from cache', () {
      final cache = MindMapRenderCache();
      final long = 'word ' * 80;
      final content = excerpt(quote: long);
      final cut = expand(cache, content, const {});
      expect(expand(cache, content, const {}), same(cut));
      final layouts = cache.layoutCount;
      final open = expand(cache, content, {'e'});
      expect(open, isNot(same(cut)), reason: 'a new expanded set is measured again');
      expect(cache.layoutCount, layouts + 1);
      final all = lines(long, MMTypography.readingExcerpt, 174);
      expect(all, greaterThan(4));
      expect(open.rects['e']!.height, 11 + (all * 20 + 12) + 4 + 14 + 11 + 2);
      // An equal set (another instance) changes nothing.
      expect(expand(cache, content, {'e'}), same(open));
      final measured = cache.measurementCount;
      final back = expand(cache, content, const {});
      expect(back.rects['e']!.height, cut.rects['e']!.height);
      expect(expand(cache, content, {'e'}).rects['e']!.height, open.rects['e']!.height);
      expect(cache.measurementCount, measured, reason: 'both texts stay measured');
    });

    test('a long title is cut to one line and shown whole when expanded', () {
      final cache = MindMapRenderCache();
      final title = 'title ' * 12;
      final content = excerpt(quote: 'short', title: title);
      final titleLines = lines(title, MMTypography.headline.copyWith(height: 17 / 13), 174);
      expect(titleLines, greaterThan(1));
      final cut = expand(cache, content, const {}).rects['e']!.height;
      expect(cut, 11 + (17 + 6) + (20 + 12) + 4 + 14 + 11 + 2, reason: 'a cut title offers the full text');
      final open = expand(cache, content, {'e'}).rects['e']!.height;
      expect(open, 11 + (titleLines * 17 + 6) + (20 + 12) + 4 + 14 + 11 + 2);
    });

    test('short cards have nothing to expand; editing shows the preview', () {
      final cache = MindMapRenderCache();
      final short = excerpt(quote: 'short');
      final plain = expand(cache, short, const {}).rects['e']!.height;
      expect(plain, 11 + (20 + 12) + 11 + 2);
      expect(expand(cache, short, {'e'}).rects['e']!.height, plain, reason: 'nothing is cut, nothing to show');
      final long = excerpt(quote: 'word ' * 80);
      final typing = cache.update(
        content: long,
        rootTitle: 'Root',
        localizations: english,
        theme: theme,
        draft: ('e', ''),
        expanded: {'e'},
      );
      expect(typing.rects['e']!.height, 11 + 17 + 6 + (4 * 20 + 12) + 11 + 2);
    });
  });

  test('500 nodes: single text edit + measurement + reflow p95 below 16 ms', () {
    final content = fixture();
    final cache = MindMapRenderCache();
    update(cache, content);
    final times = <int>[];
    for (var i = 0; i < 120; i++) {
      final edited = content.copyWith(
        cards: [
          content.cards.first.copyWith(title: i.isEven ? 'Edit $i' : 'Edit $i ${'word ' * 20}'),
          ...content.cards.skip(1),
        ],
      );
      final timer = Stopwatch()..start();
      final result = update(cache, edited);
      timer.stop();
      expect(result.rects.length, 500);
      if (i >= 20) times.add(timer.elapsedMicroseconds);
    }
    times.sort();
    // ignore: avoid_print
    print('500-node edit/reflow: median=${times[49]}us p95=${times[94]}us (limit 16000us)');
    expect(times[94], lessThan(16000));
    // Each titled excerpt's title is also measured once, to know whether it is cut.
    expect(cache.measurementCount, 786);
    expect(cache.layoutCount, greaterThan(100));
  });
}
