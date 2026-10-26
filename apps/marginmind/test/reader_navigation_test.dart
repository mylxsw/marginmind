import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/reader_find_bar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'helpers.dart';
import 'workspace_test.dart' show openFirstSet;

const _chapter2 = MMPdfOutlineItem(title: '第二章', page: 100);
const _section = MMPdfOutlineItem(title: '1.1 记忆', page: 20);
const _chapter1 = MMPdfOutlineItem(title: '第一章', page: 2, children: [_section]);

Future<({ProviderContainer container, WorkspaceController controller, MMPdfViewController pdf})> openReader(
  WidgetTester tester,
) async {
  final container = await openFirstSet(tester);
  final controller = container.read(workspaceProvider('demo-1').notifier);
  controller.openDocument('c1');
  await tester.pumpAndSettle();
  return (container: container, controller: controller, pdf: container.read(readerPdfProvider('demo-1')));
}

Future<void> pressWithControl(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
  bool alt = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
  await tester.sendKeyEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
  await tester.pumpAndSettle();
}

void main() {
  group('workspace state', () {
    Future<(ProviderContainer, WorkspaceController)> create() async {
      final container = ProviderContainer(overrides: await testOverrides());
      addTearDown(container.dispose);
      container.listen(workspaceProvider('demo-1'), (_, _) {});
      await container.read(contentProvider('demo-1').future);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      return (container, controller);
    }

    // A study set opens on the document read last; these need none open.
    void closeAll(ProviderContainer container, WorkspaceController controller) {
      for (final id in [...container.read(workspaceProvider('demo-1')).openDocumentIds]) {
        controller.closeDocument(id);
      }
    }

    test('the page sidebar starts closed on thumbnails and keeps its mode', () async {
      final (container, controller) = await create();
      WorkspaceState state() => container.read(workspaceProvider('demo-1'));
      expect(state().readerPanelVisible, isFalse);
      expect(state().readerPanelMode, ReaderPanelMode.thumbnails);
      controller.toggleReaderPanel();
      expect(state().readerPanelVisible, isTrue);
      controller.setReaderPanelMode(ReaderPanelMode.bookmarks);
      controller.toggleReaderPanel();
      controller.toggleReaderPanel();
      expect(state().readerPanelMode, ReaderPanelMode.bookmarks);
    });

    test('choosing a mode opens the sidebar and brings back the source pane', () async {
      final (container, controller) = await create();
      WorkspaceState state() => container.read(workspaceProvider('demo-1'));
      controller.setLayout(MMSplitMode.secondary);
      controller.showReaderPanel(ReaderPanelMode.annotations);
      expect(state().readerPanelVisible, isTrue);
      expect(state().readerPanelMode, ReaderPanelMode.annotations);
      expect(state().layout, MMSplitMode.split);
      controller.setLayout(MMSplitMode.primary);
      controller.showReaderPanel(ReaderPanelMode.outline);
      expect(state().layout, MMSplitMode.primary);
    });

    test('find needs a document, can be asked again and closes with the document', () async {
      final (container, controller) = await create();
      WorkspaceState state() => container.read(workspaceProvider('demo-1'));
      closeAll(container, controller);
      controller.openFind();
      expect(state().findVisible, isFalse);
      controller.openDocument('c1');
      controller.openFind();
      expect(state().findVisible, isTrue);
      final tick = state().findFocusTick;
      controller.openFind();
      expect(state().findFocusTick, tick + 1);
      controller.openDocument('c1');
      expect(state().findVisible, isTrue, reason: 'same document stays searched');
      controller.openDocument('c2');
      expect(state().findVisible, isFalse);
      controller.openFind();
      controller.closeDocument('c2');
      expect(state().findVisible, isFalse);
      controller.closeFind();
      expect(state().findVisible, isFalse);
    });

    test('bookmarks follow the page being read: add, remove, rename, delete, undo', () async {
      final (container, controller) = await create();
      closeAll(container, controller);
      await controller.toggleBookmark();
      expect(controller.content.bookmarks, isEmpty, reason: 'no document is open');
      controller.openDocument('c1');
      expect(controller.activePage, 1);
      controller.recordPage('c1', 7);
      expect(controller.activePage, 7);
      await controller.toggleBookmark();
      final bookmark = controller.content.bookmarkAt('c1', 7)!;
      await controller.renameBookmark(bookmark.id, '重点');
      expect(controller.content.bookmarkAt('c1', 7)!.title, '重点');
      await controller.toggleBookmark();
      expect(controller.content.bookmarks, isEmpty);
      await controller.undo();
      expect(controller.content.bookmarkAt('c1', 7)!.title, '重点');
      await controller.removeBookmark(bookmark.id);
      expect(controller.content.bookmarks, isEmpty);
    });
  });

  testWidgets('the toolbar toggle opens and closes the page sidebar', (tester) async {
    await openReader(tester);
    expect(find.byIcon(MMIcons.thumbnails), findsNothing);
    await tester.tap(find.byIcon(MMIcons.sidebar).last);
    await tester.pumpAndSettle();
    expect(find.byIcon(MMIcons.thumbnails), findsOneWidget);
    expect(find.byIcon(MMIcons.outline), findsNothing, reason: 'no contents, no tab');
    expect(find.byIcon(MMIcons.bookmark), findsOneWidget);
    expect(find.byIcon(MMIcons.annotations), findsOneWidget);
    await tester.tap(find.byIcon(MMIcons.sidebar).last);
    await tester.pumpAndSettle();
    expect(find.byIcon(MMIcons.thumbnails), findsNothing);
  });

  testWidgets('thumbnails start at the current page and are listed lazily', (tester) async {
    final r = await openReader(tester);
    r.pdf.debugReport(pageCount: 164, page: 24);
    r.controller.showReaderPanel(ReaderPanelMode.thumbnails);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('thumbnail-24')), findsOneWidget);
    expect(find.byKey(const ValueKey('thumbnail-1')), findsNothing);
    expect(find.byKey(const ValueKey('thumbnail-164')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('thumbnail-24')));
    r.pdf.debugReport(page: 100);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('thumbnail-100')), findsOneWidget, reason: 'the list follows the reader');
    r.pdf.debugReport(page: 101);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('thumbnail-101')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('contents: folds, highlights the section being read, and only exists with an outline', (tester) async {
    final r = await openReader(tester);
    r.controller.showReaderPanel(ReaderPanelMode.outline);
    await tester.pumpAndSettle();
    expect(find.byIcon(MMIcons.outline), findsNothing);
    expect(find.byKey(const ValueKey('thumbnail-1')), findsOneWidget, reason: 'falls back to thumbnails');

    r.pdf.debugReport(pageCount: 164, page: 24, outline: [_chapter1, _chapter2]);
    await tester.pumpAndSettle();
    expect(find.byIcon(MMIcons.outline), findsOneWidget);
    expect(find.text('第一章'), findsOneWidget);
    expect(find.text('1.1 记忆'), findsOneWidget);
    FontWeight? weightOf(String title) => tester.widget<Text>(find.text(title)).style?.fontWeight;
    expect(weightOf('1.1 记忆'), FontWeight.w600);
    expect(weightOf('第一章'), FontWeight.w400);

    await tester.tap(find.byIcon(MMIcons.chevronDown).first);
    await tester.pumpAndSettle();
    expect(find.text('1.1 记忆'), findsNothing);
    await tester.tap(find.text('第二章'));
    await tester.tap(find.byIcon(MMIcons.chevronRight).first);
    await tester.pumpAndSettle();
    expect(find.text('1.1 记忆'), findsOneWidget);

    await tester.tap(find.byIcon(MMIcons.chevronDown).first);
    await tester.pumpAndSettle();
    r.pdf.debugReport(page: 150);
    await tester.pumpAndSettle();
    expect(weightOf('第二章'), FontWeight.w600);
    r.pdf.debugReport(page: 21);
    await tester.pumpAndSettle();
    expect(find.text('1.1 记忆'), findsOneWidget, reason: 'the section being read is never hidden');

    r.pdf.debugReport(outline: const []);
    await tester.pumpAndSettle();
    expect(find.byIcon(MMIcons.outline), findsNothing);
    expect(find.byKey(const ValueKey('thumbnail-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entries without a destination are listed but cannot be opened', (tester) async {
    final r = await openReader(tester);
    r.pdf.debugReport(
      pageCount: 164,
      outline: const [
        MMPdfOutlineItem(title: '附录', page: 0),
        _chapter2,
      ],
    );
    r.controller.showReaderPanel(ReaderPanelMode.outline);
    await tester.pumpAndSettle();
    expect(find.text('附录'), findsOneWidget);
    await tester.tap(find.text('附录'));
    await tester.tap(find.text('第二章'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('bookmarks: empty state, add with the shortcut, rename, delete', (tester) async {
    final r = await openReader(tester);
    r.controller.showReaderPanel(ReaderPanelMode.bookmarks);
    await tester.pumpAndSettle();
    expect(find.text('No Bookmarks'), findsOneWidget);

    r.controller.recordPage('c1', 5);
    await tester.pumpAndSettle();
    await pressWithControl(tester, LogicalKeyboardKey.keyD);
    expect(r.controller.content.bookmarkAt('c1', 5), isNotNull);
    expect(find.text('Page 5'), findsOneWidget);
    expect(find.text('No Bookmarks'), findsNothing);

    await tester.tap(find.text('Page 5'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename Bookmark…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(MMSheet), matching: find.byType(TextField)), '遗忘曲线');
    await tester.tap(find.widgetWithText(MMButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('遗忘曲线'), findsOneWidget);
    expect(r.controller.content.bookmarkAt('c1', 5)!.title, '遗忘曲线');

    await tester.tap(find.text('遗忘曲线'));
    await tester.pump();
    await tester.tap(find.text('遗忘曲线'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Bookmark'));
    await tester.pumpAndSettle();
    expect(r.controller.content.bookmarks, isEmpty);
    expect(find.text('No Bookmarks'), findsOneWidget);

    await pressWithControl(tester, LogicalKeyboardKey.keyD);
    await pressWithControl(tester, LogicalKeyboardKey.keyD);
    expect(r.controller.content.bookmarks, isEmpty, reason: 'the second press removes it again');
  });

  testWidgets('bookmarks are per document', (tester) async {
    final r = await openReader(tester);
    r.controller.recordPage('c1', 3);
    await r.controller.toggleBookmark();
    r.controller.showReaderPanel(ReaderPanelMode.bookmarks);
    await tester.pumpAndSettle();
    expect(find.text('Page 3'), findsOneWidget);
    r.controller.openDocument('c2');
    await tester.pumpAndSettle();
    expect(find.text('No Bookmarks'), findsOneWidget);
  });

  testWidgets('annotations list the highlights of this document only', (tester) async {
    final r = await openReader(tester);
    r.controller.showReaderPanel(ReaderPanelMode.annotations);
    await tester.pumpAndSettle();
    expect(find.text('这条先陡后平的曲线，被称为遗忘曲线。'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    await tester.tap(find.text('这条先陡后平的曲线，被称为遗忘曲线。'));
    await tester.pump();
    r.controller.openDocument('c2');
    await tester.pumpAndSettle();
    expect(find.text('No Annotations'), findsOneWidget);
  });

  testWidgets('area highlights are listed by their tool name', (tester) async {
    final r = await openReader(tester);
    r.controller.showReaderPanel(ReaderPanelMode.annotations);
    await r.controller.highlight(
      'c1',
      const MMPdfSelection(page: 2, rects: [PageRect(1, 20, 30, 10)], text: ''),
      MMAnnotationColor.blue,
    );
    await tester.pumpAndSettle();
    expect(find.text('Area Select'), findsOneWidget);
  });

  testWidgets('find bar: opens focused, shows the state of the search, closes with Esc', (tester) async {
    final r = await openReader(tester);
    expect(find.byType(ReaderFindBar), findsNothing);
    r.controller.openFind();
    await tester.pumpAndSettle();
    expect(find.byType(ReaderFindBar), findsOneWidget);
    final field = find.descendant(of: find.byType(ReaderFindBar), matching: find.byType(TextField));
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

    await tester.enterText(field, '曲线');
    await tester.pumpAndSettle();
    expect(r.pdf.searchQuery, '曲线');
    expect(find.text('No Results'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    r.controller.openFind();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ReaderFindBar), findsNothing);
    expect(r.pdf.searchQuery, isEmpty);
  });

  testWidgets('find bar closes with its button and when the document changes', (tester) async {
    final r = await openReader(tester);
    r.controller.openFind();
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(ReaderFindBar), matching: find.byIcon(MMIcons.close)));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderFindBar), findsNothing);
    r.controller.openFind();
    await tester.pumpAndSettle();
    r.controller.openDocument('c2');
    await tester.pumpAndSettle();
    expect(find.byType(ReaderFindBar), findsNothing);
  });

  testWidgets('the page indicator takes a typed page', (tester) async {
    await openReader(tester);
    expect(find.text('1 / 164'), findsOneWidget);
    await tester.tap(find.text('1 / 164'));
    await tester.pumpAndSettle();
    final field = find.byType(MMInlineTextField);
    expect(field, findsOneWidget);
    await tester.enterText(field, '30');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(find.text('1 / 164'), findsOneWidget, reason: 'no PDF renders in tests, so the page does not move');

    await tester.tap(find.text('1 / 164'));
    await tester.pumpAndSettle();
    await tester.enterText(field, 'abc');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(field, findsNothing);

    await tester.tap(find.text('1 / 164'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard: sidebar, find and page commands reach the reader', (tester) async {
    final r = await openReader(tester);
    await pressWithControl(tester, LogicalKeyboardKey.keyS, alt: true);
    expect(r.container.read(workspaceProvider('demo-1')).readerPanelVisible, isTrue);
    await pressWithControl(tester, LogicalKeyboardKey.digit3, alt: true);
    expect(r.container.read(workspaceProvider('demo-1')).readerPanelMode, ReaderPanelMode.bookmarks);
    await pressWithControl(tester, LogicalKeyboardKey.digit4, alt: true);
    expect(r.container.read(workspaceProvider('demo-1')).readerPanelMode, ReaderPanelMode.annotations);
    await pressWithControl(tester, LogicalKeyboardKey.digit1, alt: true);
    expect(r.container.read(workspaceProvider('demo-1')).readerPanelMode, ReaderPanelMode.thumbnails);

    // The keyboard is in the sidebar search until the reader is clicked.
    await pressWithControl(tester, LogicalKeyboardKey.keyF);
    expect(r.container.read(workspaceProvider('demo-1')).findVisible, isFalse);
    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();
    await pressWithControl(tester, LogicalKeyboardKey.keyF);
    expect(r.container.read(workspaceProvider('demo-1')).findVisible, isTrue);
    await pressWithControl(tester, LogicalKeyboardKey.keyG);
    await pressWithControl(tester, LogicalKeyboardKey.keyG, shift: true);
    await pressWithControl(tester, LogicalKeyboardKey.bracketLeft);
    await pressWithControl(tester, LogicalKeyboardKey.arrowUp, alt: true);
    await pressWithControl(tester, LogicalKeyboardKey.arrowDown, alt: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home and End are the reader\'s own keys', (tester) async {
    await openReader(tester);
    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
