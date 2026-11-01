import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/app/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/reader_sidebar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'reader_navigation_test.dart' show openReader;
import 'helpers.dart';

Finder sidebar(Finder child) => find.descendant(of: find.byType(ReaderSidebar), matching: child);
Future<void> action(WidgetTester tester, String entry, String label) async {
  await tester.tap(sidebar(find.text(entry)), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> form(WidgetTester tester, String title, String page) async {
  await tester.enterText(
    find.descendant(of: find.byKey(const ValueKey('reader-entry-title')), matching: find.byType(TextField)),
    title,
  );
  await tester.enterText(
    find.descendant(of: find.byKey(const ValueKey('reader-entry-page')), matching: find.byType(TextField)),
    page,
  );
  await tester.tap(find.widgetWithText(MMButton, 'Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('touch outline and bookmark entries open menus on long press without more buttons', (tester) async {
    final container = await pumpApp(tester, overrides: [touchPlatformProvider.overrideWithValue(true)]);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final owner = container.read(workspaceProvider('demo-1').notifier);
    owner.openDocument('c1');
    await tester.pumpAndSettle();
    container
        .read(readerPdfProvider('demo-1'))
        .debugReport(pageCount: 164, outline: const [MMPdfOutlineItem(title: 'Touch chapter', page: 2)]);
    owner.showReaderPanel(ReaderPanelMode.outline);
    await tester.pumpAndSettle();
    expect(sidebar(find.byIcon(MMIcons.more)), findsNothing);
    await tester.longPress(sidebar(find.text('Touch chapter')));
    await tester.pumpAndSettle();
    expect(find.text('Edit Outline Entry…'), findsOneWidget);
    await tester.tap(find.text('Edit Outline Entry…'));
    await tester.pumpAndSettle();
    await form(tester, 'Renamed chapter', '2');
    expect(owner.content.outlineOn('c1')!.items.single.title, 'Renamed chapter');
    await owner.addBookmark('c1', 2, 'Touch bookmark');
    owner.showReaderPanel(ReaderPanelMode.bookmarks);
    await tester.pumpAndSettle();
    expect(sidebar(find.byIcon(MMIcons.more)), findsNothing);
    await tester.longPress(sidebar(find.text('Touch bookmark')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Bookmark'));
    await tester.pumpAndSettle();
    expect(owner.content.bookmarksOn('c1'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('personal bookmarks: add, validate page, edit, reorder by mouse, sort, undo', (tester) async {
    final r = await openReader(tester);
    r.controller.showReaderPanel(ReaderPanelMode.bookmarks);
    await tester.pumpAndSettle();
    await tester.tap(sidebar(find.byTooltip('Add Bookmark')));
    await tester.pumpAndSettle();
    await form(tester, 'First', '999');
    expect(find.byType(MMSheet), findsOneWidget);
    expect(find.text('Enter a valid page number up to 164.'), findsOneWidget);
    await form(tester, 'First', '2');
    expect(r.controller.content.bookmarkAt('c1', 2)!.title, 'First');
    await tester.tap(sidebar(find.byTooltip('Add Bookmark')));
    await tester.pumpAndSettle();
    await form(tester, 'Second', '2');
    expect(find.text('This page already has a bookmark.'), findsOneWidget);
    await form(tester, 'Second', '8');
    await action(tester, 'First', 'Edit Bookmark…');
    await form(tester, 'Edited', '3');
    expect(r.controller.content.bookmarkAt('c1', 2), isNull);
    expect(r.controller.content.bookmarkAt('c1', 3)!.title, 'Edited');
    final first = r.controller.content.bookmarksOn('c1').first;
    final handle = find.byKey(ValueKey('bookmark-drag-${first.id}'));
    final target = tester.getBottomLeft(sidebar(find.text('Second'))).dy + 20;
    final start = tester.getCenter(handle);
    final gesture = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(Offset(start.dx, target));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 5));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(r.controller.content.bookmarksOn('c1').map((b) => b.title), ['Second', 'Edited']);
    await tester.tap(sidebar(find.byTooltip('Sort order')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page Number: Ascending'));
    await tester.pumpAndSettle();
    expect(r.controller.content.bookmarksOn('c1').map((b) => b.page), [3, 8]);
    await r.controller.undo();
    await tester.pumpAndSettle();
    expect(r.controller.content.bookmarksOn('c1').map((b) => b.page), [8, 3]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('outline: add on an empty PDF, add child, edit title and destination, delete tree, undo', (tester) async {
    final r = await openReader(tester);
    r.controller.showReaderPanel(ReaderPanelMode.outline);
    await tester.pumpAndSettle();
    await tester.tap(sidebar(find.byTooltip('Add Outline Entry…')));
    await tester.pumpAndSettle();
    await form(tester, 'Chapter', '4');
    expect(r.controller.content.outlineOn('c1')!.items.single.title, 'Chapter');
    await action(tester, 'Chapter', 'Add Subentry…');
    await form(tester, 'Section', '6');
    expect(r.controller.content.outlineOn('c1')!.items.single.children.single.title, 'Section');
    await action(tester, 'Section', 'Edit Outline Entry…');
    await form(tester, 'New section', '7');
    expect(r.controller.content.outlineOn('c1')!.items.single.children.single.page, 7);
    await action(tester, 'Chapter', 'Delete Entry and Subentries');
    expect(r.controller.content.outlineOn('c1')!.items, isEmpty);
    expect(sidebar(find.byTooltip('Add Outline Entry…')), findsOneWidget);
    await r.controller.undo();
    await tester.pumpAndSettle();
    expect(find.text('New section'), findsOneWidget);
    r.controller.openDocument('c2');
    await tester.pumpAndSettle();
    expect(find.text('New section'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('outline: mouse drag reorders whole subtree, nests, and rejects cycles', (tester) async {
    final r = await openReader(tester);
    r.pdf.debugReport(
      pageCount: 164,
      outline: const [
        MMPdfOutlineItem(
          title: 'Chapter A',
          page: 2,
          children: [MMPdfOutlineItem(title: 'Child A', page: 3)],
        ),
        MMPdfOutlineItem(title: 'Chapter B', page: 8),
      ],
    );
    r.controller.showReaderPanel(ReaderPanelMode.outline);
    await tester.pumpAndSettle();
    Future<void> drag(String from, String to, double fraction) async {
      final start = tester.getCenter(sidebar(find.text(from)));
      final target = tester.getRect(
        find.ancestor(of: sidebar(find.text(to)), matching: find.byType(MMContextMenuRegion)).first,
      );
      final gesture = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump();
      await gesture.moveTo(Offset(start.dx, target.top + target.height * fraction));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await drag('Chapter A', 'Chapter B', 0.9);
    expect(r.controller.content.outlineOn('c1')!.items.map((e) => e.title), ['Chapter B', 'Chapter A']);
    expect(r.controller.content.outlineOn('c1')!.items.last.children.single.title, 'Child A');
    await drag('Chapter B', 'Child A', 0.5);
    expect(r.controller.content.outlineOn('c1')!.items.single.children.single.children.single.title, 'Chapter B');
    await drag('Chapter A', 'Chapter B', 0.5);
    expect(r.controller.content.outlineOn('c1')!.items.single.title, 'Chapter A');
    await r.controller.undo();
    await tester.pumpAndSettle();
    expect(r.controller.content.outlineOn('c1')!.items.length, 2);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('export management sidebar in ${dark ? 'dark' : 'light'} appearance', (tester) async {
      final out = Platform.environment['MM_BOOKMARK_SHOTS']!;
      final latin = File('/System/Library/Fonts/SFNS.ttf').readAsBytesSync();
      final cjk = File('/System/Library/Fonts/STHeiti Light.ttc').readAsBytesSync();
      for (final family in ['.AppleSystemUIFont', 'CupertinoSystemText', 'CupertinoSystemDisplay', 'Roboto']) {
        await (FontLoader(family)
              ..addFont(Future.value(ByteData.sublistView(latin)))
              ..addFont(Future.value(ByteData.sublistView(cjk))))
            .load();
      }
      await (FontLoader('PingFang SC')..addFont(Future.value(ByteData.sublistView(cjk)))).load();
      final pub = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
      final icons = Directory('$pub/hosted/pub.dev')
          .listSync()
          .whereType<Directory>()
          .lastWhere((d) => d.path.contains('cupertino_icons-'));
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            Future.value(ByteData.sublistView(File('${icons.path}/assets/CupertinoIcons.ttf').readAsBytesSync())),
          ))
          .load();
      final sdk = Platform.resolvedExecutable.split('/bin/cache/').first;
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(
              ByteData.sublistView(
                File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync(),
              ),
            ),
          ))
          .load();

      final container = await pumpApp(
        tester,
        prefs: {'settings.appearance': dark ? 'dark' : 'light', 'settings.language': 'zh'},
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final controller = container.read(workspaceProvider('demo-1').notifier);
      controller.openDocument('c1');
      await tester.pumpAndSettle();
      final pdf = container.read(readerPdfProvider('demo-1'));
      pdf.debugReport(
        pageCount: 164,
        page: 25,
        outline: const [
          MMPdfOutlineItem(title: '推荐序 企业数字化转型', page: 9),
          MMPdfOutlineItem(
            title: '绪论 回归本质：何谓数字化转型',
            page: 17,
            children: [
              MMPdfOutlineItem(title: '数字化企业的定义及特征', page: 18),
              MMPdfOutlineItem(title: '为何向华为学习数字化转型', page: 25),
              MMPdfOutlineItem(title: '华为数字化转型：钻石模型', page: 32),
            ],
          ),
          MMPdfOutlineItem(
            title: '上篇 华为数字化转型之道',
            page: 45,
            children: [
              MMPdfOutlineItem(title: '第1章 战略力', page: 45),
              MMPdfOutlineItem(title: '第2章 数字领导力', page: 72),
            ],
          ),
        ],
      );
      controller.showReaderPanel(ReaderPanelMode.outline);
      await tester.pumpAndSettle();
      Future<void> save(String name, {Rect? bounds}) async {
        final view = tester.binding.renderViews.first;
        final image = (await tester.runAsync(
          () => (view.debugLayer! as OffsetLayer).toImage(bounds ?? Offset.zero & view.size, pixelRatio: 2),
        ))!;
        final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
        await tester.runAsync(() => File('$out/$name.png').writeAsBytes(bytes.buffer.asUint8List()));
        image.dispose();
      }

      final theme = dark ? 'dark' : 'light';
      await save('outline-$theme', bounds: tester.getRect(find.byType(ReaderSidebar)));
      await controller.addBookmark('c1', 18, '数字化企业的定义');
      await controller.addBookmark('c1', 25, '为什么学习华为');
      await controller.addBookmark('c1', 45, '战略力');
      controller.showReaderPanel(ReaderPanelMode.bookmarks);
      await tester.pumpAndSettle();
      await save('bookmarks-$theme', bounds: tester.getRect(find.byType(ReaderSidebar)));
      await tester.tap(sidebar(find.byTooltip('添加书签')));
      await tester.pumpAndSettle();
      await save('editor-$theme');
      expect(tester.takeException(), isNull);
    }, skip: Platform.environment['MM_BOOKMARK_SHOTS'] == null);
  }
}
