import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

import 'support/pdf_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    installTestPdfBackend();
    TestPdfOutline.nodes = [];
  });

  Future<MMPdfViewController> open(WidgetTester tester, {void Function(int, int)? onPageChanged}) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Expanded(
              child: MMPdfView(filePath: 'reader.pdf', controller: controller, onPageChanged: onPageChanged),
            ),
            ListenableBuilder(
              listenable: controller,
              builder: (_, _) => Row(
                children: [
                  for (var page = 1; page <= controller.pageCount; page++)
                    MMPdfThumbnail(controller: controller, page: page, width: 20, height: 28),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    for (var i = 0; i < 100 && !controller.isReady; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(controller.isReady, isTrue);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    return controller;
  }

  testWidgets('reports page count, current page and an empty outline', (tester) async {
    final controller = await open(tester);
    expect(controller.pageCount, 3);
    expect(controller.currentPage, 1);
    expect(controller.outline, isEmpty);
    expect(find.byType(MMPdfThumbnail), findsNWidgets(3));
    expect(find.byType(PdfPageView), findsNWidgets(3));
  });

  testWidgets('reads the outline into pages and children', (tester) async {
    TestPdfOutline.nodes = [
      PdfOutlineNode(
        title: ' Chapter ',
        dest: const PdfDest(2, PdfDestCommand.fit, null),
        children: [const PdfOutlineNode(title: 'Section', dest: PdfDest(3, PdfDestCommand.fit, null), children: [])],
      ),
      const PdfOutlineNode(title: 'Loose', dest: null, children: []),
    ];
    final controller = await open(tester);
    expect(controller.outline.map((i) => (i.title, i.page)), [('Chapter', 2), ('Loose', 0)]);
    expect(controller.outline.first.children.single.page, 3);
  });

  testWidgets('jumps move the page, are clamped, and back returns', (tester) async {
    final pages = <int>[];
    final controller = await open(tester, onPageChanged: (page, _) => pages.add(page));
    expect(controller.canGoBack, isFalse);
    var notified = 0;
    controller.addListener(() => notified++);

    await controller.jumpToPage(3);
    await tester.pumpAndSettle();
    expect(controller.currentPage, 3);
    expect(controller.canGoBack, isTrue);
    expect(notified, greaterThan(0));

    await controller.jumpToPage(3);
    await controller.jumpToPage(99);
    await tester.pumpAndSettle();
    expect(controller.currentPage, 3, reason: 'jumping to where you are does nothing; 99 clamps to the last page');

    await controller.firstPage();
    await tester.pumpAndSettle();
    expect(controller.currentPage, 1);
    await controller.lastPage();
    await tester.pumpAndSettle();
    expect(controller.currentPage, 3);

    await controller.goBack();
    await tester.pumpAndSettle();
    expect(controller.currentPage, 1);
    await controller.goBack();
    await tester.pumpAndSettle();
    expect(controller.currentPage, 3);
    await controller.goBack();
    await tester.pumpAndSettle();
    expect(controller.currentPage, 1);
    expect(controller.canGoBack, isFalse);
    expect(pages, contains(3));
  });

  testWidgets('jumping to a rectangle records the origin', (tester) async {
    final controller = await open(tester);
    await controller.jumpToRect(2, const []);
    await tester.pumpAndSettle();
    expect(controller.currentPage, 2);
    await controller.goBack();
    await tester.pumpAndSettle();
    expect(controller.currentPage, 1);
  });

  testWidgets('searches the whole document, steps through hits and clears', (tester) async {
    final controller = await open(tester);
    controller.search('passage');
    for (var i = 0; i < 50 && (controller.isSearching || controller.matchCount < 3); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(controller.searchQuery, 'passage');
    expect(controller.matchCount, 3);
    expect(controller.matchIndex, 0);

    await tester.runAsync(controller.nextMatch);
    await tester.pumpAndSettle();
    expect(controller.matchIndex, 1);
    await tester.runAsync(controller.previousMatch);
    await tester.pumpAndSettle();
    expect(controller.matchIndex, 0);

    controller.search('absent phrase');
    for (var i = 0; i < 50 && controller.isSearching; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(controller.matchCount, 0);
    expect(controller.matchIndex, isNull);
    await controller.nextMatch();
    await controller.previousMatch();

    controller.clearSearch();
    await tester.pump();
    expect(controller.searchQuery, isEmpty);
    expect(controller.matchCount, 0);
  });

  testWidgets('a controller without a view ignores every command', (tester) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    await controller.jumpToPage(2);
    await controller.firstPage();
    await controller.goBack();
    await controller.jumpToRect(1, const []);
    controller.search('x');
    await controller.nextMatch();
    expect(controller.isReady, isFalse);
    expect(controller.pageCount, 0);
    await tester.pumpWidget(
      MaterialApp(home: MMPdfThumbnail(controller: controller, page: 1, width: 10, height: 10)),
    );
    expect(find.byType(PdfPageView), findsNothing);
  });

  testWidgets('swapping the document resets what the controller knows', (tester) async {
    final controller = await open(tester);
    await controller.jumpToPage(2);
    await tester.pumpAndSettle();
    expect(controller.canGoBack, isTrue);
    await tester.pumpWidget(
      MaterialApp(home: MMPdfView(key: const ValueKey('other'), filePath: 'other.pdf', controller: controller)),
    );
    await tester.pump();
    expect(controller.canGoBack, isFalse);
    expect(controller.currentPage, 1);
    expect(controller.matchCount, 0);
  });
}
