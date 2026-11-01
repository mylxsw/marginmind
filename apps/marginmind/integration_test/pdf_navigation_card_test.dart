import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/widgets/reader_sidebar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';

import '../test/assistant_support.dart' show pumpFor;
import '../test/helpers.dart';

/// Real PDF rendering with an isolated in-memory library; no user data writes.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('inset PDF navigator and centred title retain navigation and resizing', (tester) async {
    await DesktopWindow.initialize(title: 'Foliarc · PDF navigation QA', minimumSize: MMSizes.windowMinSize);
    final temp = Directory.systemTemp.createTempSync('foliarc-pdf-card-');
    addTearDown(() => temp.deleteSync(recursive: true));
    debugPrint('PDF_CARD_QA: loading sample');
    final bytes = await tester.runAsync(() => rootBundle.load('assets/sample/sample.pdf'));
    final file = File('${temp.path}/遗忘曲线与间隔重复.pdf')..writeAsBytesSync(bytes!.buffer.asUint8List());
    final repository = _PdfCardRepository(file.path);
    debugPrint('PDF_CARD_QA: opening workspace');
    final container = await pumpApp(
      tester,
      size: const Size(1280, 820),
      prefs: {'settings.appearance': 'dark'},
      renderPdf: true,
      content: repository,
      settle: false,
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await pumpFor(tester, 15);
    final owner = container.read(workspaceProvider('demo-1').notifier);
    debugPrint('PDF_CARD_QA: importing PDF');
    await tester.runAsync(() => owner.importDocuments([(path: file.path, name: '遗忘曲线与间隔重复.pdf')]));
    await pumpFor(tester, 30);
    final document = owner.content.documents.last;
    final pdf = container.read(readerPdfProvider('demo-1'));
    for (var i = 0; i < 80 && pdf.pageCount == 0; i++) {
      await pumpFor(tester, 4);
    }
    debugPrint('PDF_CARD_QA: PDF ready');
    expect(pdf.pageCount, 2);
    for (final (page, text) in [(1, '内容，却不能保证在'), (2, '任意一句话，它会被高亮'), (2, '上角的箭头，可以回到原文中')]) {
      await owner.excerpt(
        document.id,
        MMPdfSelection(page: page, rects: const [PageRect(80, 280, 190, 16)], text: text),
        MMAnnotationColor.green,
      );
    }
    owner.showReaderPanel(ReaderPanelMode.annotations);
    await pumpFor(tester, 15);

    void checkTitle() {
      final header = tester.getRect(find.byKey(const ValueKey('workspace-tab-row')));
      final title = tester.getRect(find.byKey(const ValueKey('workspace-tab-documentMap')));
      expect(title.center.dx, closeTo(header.center.dx, 1));
    }

    void checkCard() {
      final sidebar = find.byType(ReaderSidebar);
      final card = find.descendant(of: sidebar, matching: find.byType(DecoratedBox)).first;
      final outer = tester.getRect(sidebar);
      final inner = tester.getRect(card);
      expect(inner.left - outer.left, closeTo(MMSpacing.m, .1));
      expect(outer.bottom - inner.bottom, closeTo(MMSpacing.m, .1));
      final icons = find.descendant(of: sidebar, matching: find.byType(MMToolbarButton));
      final first = tester.getRect(icons.first);
      final last = tester.getRect(icons.at(3));
      expect((first.left + last.right) / 2, closeTo(inner.center.dx, 1));
    }

    Future<void> shot(String name) async {
      const server = String.fromEnvironment('PDF_CARD_SHOT_SERVER');
      if (server.isEmpty) return;
      debugPrint('PDF_CARD_QA: capturing $name');
      await pumpFor(tester, 8);
      final view = tester.binding.renderViews.first;
      final image = (await tester.runAsync(
        () => (view.debugLayer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 2),
      ))!;
      final png = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
      image.dispose();
      await tester.runAsync(() async {
        final client = HttpClient();
        try {
          final request = await client.postUrl(Uri.parse('$server/capture/$name'));
          request.headers.contentType = ContentType('image', 'png');
          request.contentLength = png!.lengthInBytes;
          request.add(png.buffer.asUint8List());
          final response = await request.close();
          expect(response.statusCode, 200);
          await response.drain<void>();
        } finally {
          client.close(force: true);
        }
      });
    }

    checkTitle();
    checkCard();
    await shot('annotations-dark');
    final resize = find.byKey(const ValueKey('reader-sidebar-resize'));
    final originalWidth = tester.getSize(find.byType(ReaderSidebar)).width;
    await tester.drag(resize, const Offset(40, 0));
    await pumpFor(tester, 8);
    expect(tester.getSize(find.byType(ReaderSidebar)).width, greaterThan(originalWidth));
    checkCard();
    await container.read(settingsProvider.notifier).setReaderSidebarWidth(readerSidebarWidth);
    await owner.addBookmark(document.id, 1, '记忆是怎样流失的');
    await owner.addBookmark(document.id, 2, '主动提取');
    owner.showReaderPanel(ReaderPanelMode.bookmarks);
    await pumpFor(tester, 8);
    final entry = find.descendant(of: find.byType(ReaderSidebar), matching: find.text('主动提取'));
    await tester.tap(entry);
    await pumpFor(tester, 15);
    expect(pdf.currentPage, 2);
    checkTitle();
    await shot('bookmarks-dark');
    await owner.editDocumentOutline(
      document.id,
      const [],
      (_) => const [
        PdfOutlineEntry(
          id: 'one',
          title: '第二章 遗忘曲线与间隔重复',
          page: 1,
          children: [
            PdfOutlineEntry(id: 'memory', title: '记忆是怎样流失的', page: 1),
            PdfOutlineEntry(id: 'spacing', title: '间隔重复', page: 1),
            PdfOutlineEntry(id: 'retrieval', title: '主动提取', page: 2),
          ],
        ),
      ],
    );
    owner.showReaderPanel(ReaderPanelMode.outline);
    await container.read(settingsProvider.notifier).setAppearance(AppearancePreference.light);
    await pumpFor(tester, 12);
    checkCard();
    await shot('outline-light');
    tester.view.physicalSize = const Size(900, 820);
    await pumpFor(tester, 12);
    checkTitle();
    checkCard();
    await shot('narrow-light');
    expect(tester.takeException(), isNull);
  });
}

class _PdfCardRepository extends InMemoryStudySetContentRepository {
  _PdfCardRepository(this.samplePath) : super({'demo-1': StudySetContent.empty});
  final String samplePath;

  @override
  String resolveFile(String studySetId, String fileName) => samplePath;
}
