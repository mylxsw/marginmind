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
        quote: '摘录 $i text with several words and lines to measure.',
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
      case CardKind.note:
        final s = measure(card.title, MMTypography.body.copyWith(height: 19 / 13), 186).size;
        return Size(s.width + 48, s.height + 16);
      case CardKind.image:
      case CardKind.excerpt:
        final quote = content.annotation(card.annotationId ?? '')?.quote ?? '';
        final lines = math.min(4, measure(quote, MMTypography.readingExcerpt, 174).lines);
        return Size(240, (11 + 17 + 6 + (lines * 20 + 12) + 6 + 14 + 11 + 2).toDouble());
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
    expect(environment(colors: MMTheme.dark()), same(original));
    expect(cache.measurementCount, count + 4);
    count = cache.measurementCount;
    final scaled = environment(scaler: TextScaler.linear(1.5));
    expect(scaled.rects['c0']!.height, greaterThan(original.rects['c0']!.height));
    expect(scaled.rects['c1']!.height, greaterThan(original.rects['c1']!.height));
    expect(cache.measurementCount, count + 4);
    count = cache.measurementCount;
    environment(locale: const Locale('zh'));
    expect(cache.measurementCount, count + 4);
    count = cache.measurementCount;
    environment(direction: TextDirection.rtl);
    expect(cache.measurementCount, count + 4);
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
    expect(cache.measurementCount, 620);
    expect(cache.layoutCount, greaterThan(100));
  });
}
