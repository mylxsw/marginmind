/// Renders the demo map in each structure, light and dark, with a palette
/// per structure, and the style popover, to PNGs with real fonts. Skipped
/// unless MM_SCREENSHOTS names an output directory and MM_FONT a CJK font:
///
///   MM_SCREENSHOTS=shots MM_FONT=~/.fonts/NotoSansSC.otf \
///     flutter test test/map_style_screenshots_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/annotation_palette.dart';
import 'package:marginmind/features/workspace/widgets/map_selection_bar.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

final _out = Platform.environment['MM_SCREENSHOTS'];
final _font = Platform.environment['MM_FONT'];

Future<void> _loadFonts() async {
  final bytes = ByteData.sublistView(await File(_font!).readAsBytes());
  for (final family in [
    '.AppleSystemUIFont',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
    'Roboto',
    'PingFang SC',
    'Songti SC',
    'SF Mono',
  ]) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  final pub = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
  final icons = Directory('$pub/hosted/pub.dev')
      .listSync()
      .whereType<Directory>()
      .lastWhere((d) => d.path.contains('cupertino_icons-'));
  await (FontLoader(
        'packages/cupertino_icons/CupertinoIcons',
      )..addFont(Future.value(ByteData.sublistView(File('${icons.path}/assets/CupertinoIcons.ttf').readAsBytesSync()))))
      .load();
}

Future<void> _save(WidgetTester tester, String name) async {
  final image = (await tester.runAsync(() {
    final view = tester.binding.renderViews.first;
    return (view.debugLayer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 2);
  }))!;
  final png = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  await tester.runAsync(() => File('$_out/$name.png').writeAsBytes(png.buffer.asUint8List()));
}

final _now = DateTime(2026);

/// Four branches of topics and excerpts, with a summary.
StudySetContent _sample() {
  final topics = {
    't1': (null, '检索练习'),
    't1a': ('t1', '小测验'),
    't1b': ('t1', '自由回忆'),
    't2': (null, '间隔练习'),
    't3': (null, '交错练习'),
    't3a': ('t3', '混合题型'),
    't3b': ('t3', '对比辨析'),
    't4': (null, '常见误区'),
    'm1': ('t4', '反复重读'),
    'm2': ('t4', '考前突击'),
  };
  final quotes = {'e1': ('t1', '提取本身就是一种学习，每回想一次，记忆就更牢一些。'), 'e2': ('t2', '把练习分散在几天里，比集中在一次完成记得更久。')};
  final order = <String?, int>{};
  double next(String? parent) => (order[parent] = (order[parent] ?? -1) + 1).toDouble();
  return StudySetContent(
    documents: [Document(id: 'd', title: '认知天性', fileName: 'a.pdf', pageCount: 300, importedAt: _now)],
    annotations: [
      for (final (i, e) in quotes.entries.indexed)
        Annotation(
          id: 'a${e.key}',
          documentId: 'd',
          page: 12 + i * 30,
          rects: const [],
          quote: e.value.$2,
          colorIndex: i,
          createdAt: _now,
        ),
    ],
    cards: [
      for (final e in topics.entries) Card(id: e.key, kind: CardKind.topic, title: e.value.$2, createdAt: _now),
      for (final e in quotes.keys) Card(id: e, kind: CardKind.excerpt, annotationId: 'a$e', createdAt: _now),
    ],
    nodes: [
      for (final e in topics.entries) MapNode(cardId: e.key, parentId: e.value.$1, order: next(e.value.$1)),
      for (final e in quotes.entries) MapNode(cardId: e.key, parentId: e.value.$1, order: next(e.value.$1)),
    ],
    summaries: const [MapSummary(id: 's', parentId: 't4', fromId: 'm1', toId: 'm2', label: '低效')],
  );
}

void main() {
  final skip = _out == null || _font == null;
  setUpAll(() async {
    if (skip) return;
    Directory(_out!).createSync(recursive: true);
    await _loadFonts();
  });

  const styles = [
    (MapStructure.mind, MapPalette.rainbow),
    (MapStructure.logic, MapPalette.fresh),
    (MapStructure.brace, MapPalette.warm),
    (MapStructure.tree, MapPalette.ink),
  ];
  for (final dark in [false, true]) {
    testWidgets('node color toolbars ${dark ? 'dark' : 'light'}', skip: skip, (tester) async {
      final container = await pumpApp(
        tester,
        content: InMemoryStudySetContentRepository({'demo-1': _sample()}),
        size: const Size(1600, 900),
        prefs: {if (dark) 'settings.appearance': 'dark'},
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final controller = container.read(workspaceProvider('demo-1').notifier);
      controller.setLayout(MMSplitMode.secondary);
      controller.selectCards(['e1', 'e2']);
      await tester.pumpAndSettle();
      await _save(tester, 'node-colors-collapsed-${dark ? 'dark' : 'light'}');
      await tester.tap(find.byKey(const ValueKey('node-bar-color')), kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await _save(tester, 'node-colors-palette-${dark ? 'dark' : 'light'}');
      await tester.tap(find.byType(AnnotationMoreColorsButton), kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await _save(tester, 'node-colors-custom-${dark ? 'dark' : 'light'}');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleHud(tester);
    });
    testWidgets('narrow pane frosted toolbar ${dark ? 'dark' : 'light'}', skip: skip, (tester) async {
      tester.view.physicalSize = const Size(632, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: await testOverrides(content: InMemoryStudySetContentRepository({'demo-1': _sample()})),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? MMTheme.dark() : MMTheme.light(),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: MapPane(studySetId: 'demo-1')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(MapPane)));
      final controller = container.read(workspaceProvider('demo-1').notifier);
      controller.selectCard('e1');
      await tester.pumpAndSettle();
      expect(find.byType(MapCommandBar), findsNothing);
      final bar = tester.getRect(find.byKey(const ValueKey('map-view-glass')));
      expect(bar.center.dy, tester.getCenter(find.byKey(const ValueKey('map-style-button'))).dy);
      final excerpt = tester.getRect(find.byKey(const ValueKey('e1')));
      controller.selectCard(null);
      await tester.pumpAndSettle();
      final transform = tester.widget<MindMapCanvas>(find.byType(MindMapCanvas)).transformation;
      final delta = bar.center - excerpt.center;
      transform.value = transform.value.clone()
        ..setTranslationRaw(transform.value.storage[12] + delta.dx, transform.value.storage[13] + delta.dy, 0);
      await tester.pumpAndSettle();
      await _save(tester, 'narrow-toolbar-${dark ? 'dark' : 'light'}');
      await settleHud(tester);
    });
    testWidgets('new topic toolbars ${dark ? 'dark' : 'light'}', skip: skip, (tester) async {
      final container = await pumpApp(
        tester,
        content: InMemoryStudySetContentRepository({'demo-1': _sample()}),
        size: const Size(1600, 900),
        prefs: {if (dark) 'settings.appearance': 'dark'},
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final controller = container.read(workspaceProvider('demo-1').notifier);
      controller.setLayout(MMSplitMode.secondary);
      controller.selectCard('t1');
      await tester.pumpAndSettle();
      await controller.addTopicAndEdit('新主题', asChild: true);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(MMInlineTextField), '建立检索练习清单');
      await tester.pumpAndSettle();
      await _save(tester, 'new-topic-${dark ? 'dark' : 'light'}');
      await controller.cancelEditing();
      await settleHud(tester);
    });
    for (final (structure, palette) in styles) {
      testWidgets('${structure.name} ${palette.name} ${dark ? 'dark' : 'light'}', skip: skip, (tester) async {
        final container = await pumpApp(
          tester,
          content: InMemoryStudySetContentRepository({'demo-1': _sample()}),
          size: const Size(1600, 900),
          prefs: {if (dark) 'settings.appearance': 'dark'},
        );
        container.read(navigationProvider.notifier).openStudySet('demo-1');
        await tester.pumpAndSettle();
        final controller = container.read(workspaceProvider('demo-1').notifier);
        controller.setLayout(MMSplitMode.secondary);
        await controller.setMapStructure(structure);
        await controller.setMapPalette(palette);
        await tester.pumpAndSettle();
        // Shows the style popover, which fits the whole map beside it.
        await toggleMapStyle(tester);
        await tester.pumpAndSettle();
        await _save(tester, '${structure.name}-${palette.name}-${dark ? 'dark' : 'light'}');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settleHud(tester);
      });
    }
  }
}
