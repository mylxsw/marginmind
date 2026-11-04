import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/widgets/reader_sidebar_tab_bar.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'reader_crop_test.dart' show drain;
import 'reflow_fixtures.dart';

void main() {
  testWidgets('empty outline, bookmarks and annotations start directly with tabs', (tester) async {
    final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final chapter = const EpubParser().parseHtml('main', '<h1>Empty index document</h1><p>Text without chapters.</p>');
    final doc = await storeBook(
      repo,
      book: Book(
        'Empty index document',
        [chapter],
        {},
        [],
        toc: [BookTocEntry('document-heading', 'Empty index document', 'main', 0)],
      ),
    );
    final container = await pumpApp(
      tester,
      size: const Size(393, 852),
      content: repo,
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final owner = container.read(workspaceProvider('demo-1').notifier);
    owner.openDocument(doc.id);
    await drain(tester);
    owner.showReaderPanel(ReaderPanelMode.outline);
    await drain(tester);
    final frame = find.byKey(const ValueKey('phone-document-navigation'));
    final l = tester.element(frame).l10n;
    for (final (mode, message) in [
      (ReaderPanelMode.outline, l.readerNoOutline),
      (ReaderPanelMode.bookmarks, l.noBookmarks),
      (ReaderPanelMode.annotations, l.noAnnotations),
    ]) {
      owner.setReaderPanelMode(mode);
      await drain(tester);
      expect(find.descendant(of: frame, matching: find.text(doc.title)), findsNothing);
      expect(find.descendant(of: frame, matching: find.text(message)), findsOneWidget);
      expect(find.descendant(of: frame, matching: find.text(l.readerBookmarks)), findsOneWidget);
      expect(tester.getTopLeft(find.byType(ReaderSidebarTabBar)).dy, tester.getTopLeft(frame).dy);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('reflow navigation closes once after locating, and stays closed after async jump', (tester) async {
    final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final chapter = const EpubParser().parseHtml('main', '<h1>First</h1><p>Read and return to the source.</p>');
    final doc = await storeBook(
      repo,
      book: Book(
        'Navigation',
        [chapter],
        {},
        [],
        toc: [
          BookTocEntry('first', 'Go to chapter', 'main', 0, [
            BookTocEntry('child', 'A long nested chapter title that must remain on one line on a phone', 'main', 4),
          ]),
        ],
      ),
    );
    final container = await pumpApp(
      tester,
      size: const Size(393, 852),
      content: repo,
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final owner = container.read(workspaceProvider('demo-1').notifier);
    owner.openDocument(doc.id);
    await drain(tester);
    owner.showReaderPanel(ReaderPanelMode.outline);
    await drain(tester);
    final frame = find.byKey(const ValueKey('phone-document-navigation'));
    expect(tester.getSize(frame).width, 393 - MMSizes.phoneSheetPadding * 2);
    expect(tester.getRect(frame).left, greaterThanOrEqualTo(MMSizes.phoneSheetPadding));
    expect(tester.getSize(frame).height, greaterThan(852 * .85));
    expect(find.descendant(of: frame, matching: find.byType(ReaderSidebarTab)), findsNWidgets(3));
    expect(find.descendant(of: frame, matching: find.text('Navigation')), findsNothing);
    expect(tester.getTopLeft(find.byType(ReaderSidebarTabBar)).dy, tester.getTopLeft(frame).dy);
    final parentTitle = find.text('Go to chapter').hitTestable();
    final childTitle = find.text('A long nested chapter title that must remain on one line on a phone').hitTestable();
    expect(tester.widget<Text>(childTitle).maxLines, 1);
    expect(tester.getTopLeft(childTitle).dx - tester.getTopLeft(parentTitle).dx, MMReaderNavigationLayout.indent);
    for (final id in ['first', 'child']) {
      final row = find.byKey(ValueKey('reader-outline-$id'));
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
      expect(find.descendant(of: row, matching: find.byIcon(MMIcons.check)), findsNothing);
      for (final text in tester.widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))) {
        expect(text.style!.fontWeight, anyOf(isNull, FontWeight.w400));
      }
      final interaction = tester.widget<MMInteractive>(find.descendant(of: row, matching: find.byType(MMInteractive)));
      expect(interaction.selected, false);
    }
    final tabSizes = tester
        .widgetList<ReaderSidebarTab>(find.byType(ReaderSidebarTab))
        .map((tab) => tester.getSize(find.byWidget(tab)).width)
        .toList();
    expect(tabSizes.every((width) => (width - tabSizes.first).abs() < .01), true);
    await tester.ensureVisible(find.text('Bookmarks'));
    await drain(tester);
    await tester.tap(find.text('Bookmarks').hitTestable());
    await drain(tester);
    expect(container.read(workspaceProvider('demo-1')).readerPanelMode, ReaderPanelMode.bookmarks);
    expect(frame, findsOneWidget);
    expect(find.descendant(of: frame, matching: find.text('Bookmarks')), findsOneWidget);
    await tester.ensureVisible(find.text('Table of Contents'));
    await drain(tester);
    await tester.tap(find.text('Table of Contents').hitTestable());
    await drain(tester);
    tester.view.physicalSize = const Size(320, 740);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await drain(tester);
    expect(tester.widget<Text>(childTitle).maxLines, 1);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Go to chapter').hitTestable());
    await drain(tester);
    expect(container.read(workspaceProvider('demo-1')).readerPanelVisible, false);
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(workspaceProvider('demo-1')).readerPanelVisible, false);
    expect(frame, findsNothing);
    owner.showReaderPanel(ReaderPanelMode.bookmarks);
    await drain(tester);
    expect(find.descendant(of: frame, matching: find.byIcon(MMIcons.close)), findsNothing);
    await tester.fling(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, 400), 1200);
    await drain(tester);
    expect(container.read(workspaceProvider('demo-1')).readerPanelVisible, false);
    expect(tester.takeException(), isNull);
  });
}
