import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/workspace/reader_compare.dart';
import 'package:marginmind/features/workspace/reader_ocr.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:marginmind/features/workspace/reader_margin.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';
import 'reader_crop_test.dart' show drain;
import 'reader_ocr_test.dart' show FakeOcr;

StudySetContent compareFixture() => demoContent().copyWith(
  documents: [
    Document(id: 'c1', title: '学习的底层逻辑', fileName: 'a.pdf', pageCount: 3, importedAt: testNow),
    Document(id: 'c2', title: 'Learning and memory.pdf', fileName: 'b.pdf', pageCount: 3, importedAt: testNow),
    Document(id: 'third', title: '第 3 章讲义', fileName: 'c.pdf', pageCount: 3, importedAt: testNow),
  ],
);

class CompareOcr extends FakeOcr {
  @override
  Future<PdfOcrDocument> inspect(String source) async {
    inspections++;
    return PdfOcrDocument(path: source, pageCount: 3, textPages: {1, 2, 3});
  }
}

class FailingCompareRepository extends InMemoryStudySetContentRepository {
  FailingCompareRepository() : super({'demo-1': compareFixture()});
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<StudySetContent> update(String id, StudySetContent Function(StudySetContent) change) async {
    await gate?.future;
    if (fail) throw StateError('Disk unavailable');
    return super.update(id, change);
  }
}

void main() {
  testWidgets('workspace document menu switches the primary comparison document by ID', (tester) async {
    installTestPdfBackend();
    final container = await pumpApp(
      tester,
      renderPdf: true,
      size: const Size(1600, 1000),
      content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}),
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    await container.read(readerCompareProvider('demo-1').notifier).select('c2', readerWidth: 1600);
    await drain(tester);
    await tester.tap(find.byKey(const ValueKey('reader-documents')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 3 章讲义').last);
    await drain(tester);
    final pair = container.read(readerCompareProvider('demo-1'))!;
    expect(pair.leftDocumentId, 'third');
    expect((pair.right as PdfCompareTarget).documentId, 'c2');
    expect(container.read(workspaceProvider('demo-1')).activeDocumentId, 'third');
    expect(tester.takeException(), isNull);
  });

  setUp(() {
    installTestPdfBackend();
    TestPdfRender.produceImages = true;
    TestPdfText.pages = {
      for (var n = 1; n <= 3; n++)
        n: PdfPageRawText('Selected passage', List.generate(16, (i) => PdfRect(130 + i * 10, 700, 140 + i * 10, 680))),
    };
  });
  tearDown(() {
    TestPdfRender.produceImages = false;
    TestPdfRender.renders.clear();
    TestPdfText.pages = {};
  });
  test('alignment sorted, coincident replaced, crossings rejected, pair reversible', () {
    final map = ReadingAlignment(leftHeights: [800, 600], rightHeights: [900, 700, 500]);
    AlignPoint p(int l, double y, int r, double ry) => AlignPoint(
      left: PdfReadingPosition(page: l, y: y),
      right: PdfReadingPosition(page: r, y: ry),
    );
    final a = p(1, 400, 2, 500), b = p(2, 300, 3, 250);
    expect(insertCompareAlignment(map, [b], a), [a, b]);
    final replaced = insertCompareAlignment(map, [a, b], p(1, 400, 2, 450));
    expect(replaced.length, 2);
    expect(replaced.first.right.y, 450);
    expect(insertCompareAlignment(map, [a, b], p(1, 600, 3, 100)), hasLength(1));
    expect(compareLanguage('学习的底层逻辑'), 'zh');
    expect(compareLanguage('Learning and memory'), 'en');
    expect(compareLanguage('123'), isNull);
    final pair = ComparePair(
      id: 'pair',
      leftDocumentId: 'a',
      right: PdfCompareTarget('b'),
      alignPoints: [a, b],
      sync: false,
    );
    expect(reverseComparePair(reverseComparePair(pair)).toJson(), pair.toJson());
  });
  testWidgets('enter, sync, swap, exit restore and saved pair reuse', (tester) async {
    final repository = InMemoryStudySetContentRepository({'demo-1': compareFixture()});
    final container = await pumpApp(
      tester,
      renderPdf: true,
      content: repository,
      size: const Size(1600, 1000),
      overrides: [
        compareDocumentInfoProvider(('demo-1', 'c1')).overrideWith((ref) async => (language: 'zh', hasText: true)),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    final session = container.read(readerCompareProvider('demo-1').notifier);
    workspace.toggleReaderPanel();
    await drain(tester);
    await tapReaderCommand(tester, find.byKey(const ValueKey('reader-compare')));
    await tester.pumpAndSettle();
    expect(find.text('Suggested'), findsNWidgets(2));
    await tester.tap(find.text('Learning and memory.pdf').last);
    await drain(tester);
    expect(find.byKey(const ValueKey('reader-compare-view')), findsOneWidget);
    final state = container.read(workspaceProvider('demo-1'));
    expect(state.sidebarVisible, false);
    expect(state.readerPanelVisible, false);
    expect(state.layout, MMSplitMode.primary);
    final left = session.pdf('c1'), right = session.pdf('c2');
    expect(left.isReady && right.isReady, true);
    await tester.tap(find.byKey(const ValueKey('reader-more')));
    await tester.pumpAndSettle();
    expect(tester.widget<MenuItemButton>(find.byKey(const ValueKey('reader-margin'))).onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('compare-sync')));
    await drain(tester);
    expect(container.read(readerCompareProvider('demo-1'))!.sync, false);
    Future<void> jump(MMPdfViewController pdf, int page, double y) async {
      final moving = pdf.jumpToReadingPosition(PdfReadingPosition(page: page, y: y));
      await tester.pumpAndSettle();
      await moving;
      await drain(tester);
    }

    await jump(left, 2, 450);
    await jump(right, 2, 250);
    final l = left.readingPosition!, r = right.readingPosition!;
    await tester.tap(find.byKey(const ValueKey('compare-sync')));
    await drain(tester);
    final pair = container.read(readerCompareProvider('demo-1'))!;
    expect(pair.sync, true);
    expect(left.readingPosition!.y, closeTo(l.y, 1));
    expect(right.readingPosition!.y, closeTo(r.y, 1));
    expect((await repository.load('demo-1')).comparePairs.single.toJson(), pair.toJson());
    await tester.tap(find.byKey(const ValueKey('compare-swap')));
    await drain(tester);
    expect(container.read(readerCompareProvider('demo-1'))!.leftDocumentId, 'c2');
    expect(right.readingPosition!.page, r.page);
    expect(right.readingPosition!.y, closeTo(r.y, 1));
    expect(left.readingPosition!.y, closeTo(l.y, 1));
    await tester.tap(find.byKey(const ValueKey('compare-right-document')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await drain(tester);
    expect(container.read(readerCompareProvider('demo-1')), isNotNull);
    await tester.tap(find.byKey(const ValueKey('compare-exit')));
    await drain(tester);
    final restored = container.read(workspaceProvider('demo-1'));
    expect(restored.layout, MMSplitMode.split);
    expect(restored.sidebarVisible, true);
    expect(restored.readerPanelVisible, true);
    expect(container.read(readerCompareProvider('demo-1')), isNull);
    await session.select('c1', readerWidth: 600);
    await drain(tester);
    expect(container.read(readerCompareProvider('demo-1'))!.id, pair.id);
    expect(container.read(readerCompareProvider('demo-1'))!.sync, true);
    await tester.tap(find.byKey(const ValueKey('reader-compare-view')), warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await drain(tester);
    expect(container.read(readerCompareProvider('demo-1')), isNull);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('each column writes to its own PDF; comments are markers; crop independently', (tester) async {
    final repository = InMemoryStudySetContentRepository({'demo-1': compareFixture()});
    final ocr = CompareOcr();
    final container = await pumpApp(
      tester,
      renderPdf: true,
      content: repository,
      size: const Size(1800, 1100),
      overrides: [pdfOcrServiceProvider.overrideWithValue(ocr)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    final session = container.read(readerCompareProvider('demo-1').notifier);
    await session.select('c2', readerWidth: 700);
    await drain(tester);
    expect(ocr.inspections, 2);
    for (final id in ['c1', 'c2']) {
      const selection = MMPdfSelection(
        text: 'Selected passage',
        page: 1,
        rects: [PageRect(140, 700, 250, 680)],
        viewportRect: Rect.fromLTWH(100, 160, 180, 20),
      );
      final view = tester
          .widgetList<MMPdfView>(find.byType(MMPdfView))
          .firstWhere((v) => identical(v.controller, session.pdf(id)));
      // A real selection gives the reader focus before the temporary editor.
      await tester.tap(find.byWidgetPredicate((w) => identical(w, view)));
      await drain(tester);
      view.onSelectionCommitted!(selection);
      await drain(tester);
      await tester.tap(find.byKey(const ValueKey('selection-margin-note')));
      await drain(tester);
      final margin = container.read(readerMarginProvider('demo-1').notifier);
      final draft = container.read(readerMarginProvider('demo-1')).draft!;
      expect(draft.documentId, id);
      await tester.enterText(find.byKey(ValueKey('margin-editor-${draft.id}')), 'Comment for $id');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await drain(tester);
      expect(container.read(readerCompareProvider('demo-1')), isNotNull);
      expect(workspace.content.marginNotes.last.documentId, id);
      expect(find.byKey(ValueKey('margin-marker-${draft.id}')), findsOneWidget);
      expect(find.byKey(const ValueKey('margin-expand')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await drain(tester);
      expect(container.read(readerCompareProvider('demo-1')), isNotNull);
      expect(container.read(readerMarginProvider('demo-1')).popup, isEmpty);
      await margin.close();
      await drain(tester);
      await workspace.excerpt(id, selection, MMAnnotationColor.yellow);
      await workspace.highlight(id, selection, MMAnnotationColor.blue);
      await drain(tester);
      expect(workspace.content.annotations.where((a) => a.documentId == id), isNotEmpty);
    }
    expect(find.byKey(const ValueKey('crop-suggestion')), findsNWidgets(2));
    await tester.tap(find.text('Crop Margins').last);
    await drain(tester);
    expect(workspace.content.document('c2')!.crop!.enabled, true);
    expect(workspace.content.document('c1')!.crop?.enabled, isNot(true));
    await tester.tap(find.text('Crop Margins').first);
    await drain(tester);
    expect(workspace.content.document('c1')!.crop!.enabled, true);
    expect(find.byKey(const ValueKey('crop-suggestion')), findsNothing);
    session.exit();
    await drain(tester);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('bidirectional sync settles, user takeover and resize keep original coordinates', (tester) async {
    final repository = InMemoryStudySetContentRepository({'demo-1': compareFixture()});
    final container = await pumpApp(tester, renderPdf: true, content: repository, size: const Size(1800, 1100));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final session = container.read(readerCompareProvider('demo-1').notifier);
    await session.select('c2', readerWidth: 700);
    await drain(tester);
    Future<void> move(int side, int page, double y) async {
      session.userInput(side);
      final jump = session.pdf(side == 0 ? 'c1' : 'c2').jumpToReadingPosition(PdfReadingPosition(page: page, y: y));
      await tester.pumpAndSettle();
      await jump;
      await drain(tester);
    }

    final leftView = find.byWidgetPredicate((w) => w is MMPdfView && identical(w.controller, session.pdf('c1')));
    final a = session.pdf('c1'), b = session.pdf('c2');
    Future<void> equalMovement(Future<void> Function() gesture) async {
      final left = a.scrollPosition!.offset, right = b.scrollPosition!.offset;
      await gesture();
      expect(b.scrollPosition!.offset - right, closeTo(a.scrollPosition!.offset - left, .01));
    }

    await equalMovement(() async {
      await tester.sendEventToBinding(
        PointerScrollEvent(position: tester.getCenter(leftView), scrollDelta: const Offset(0, 180)),
      );
      await drain(tester);
    });
    await equalMovement(() => move(0, 2, 500));
    await equalMovement(() => move(1, 2, 250));
    await equalMovement(() async {
      await tester.drag(leftView, const Offset(0, 60), kind: PointerDeviceKind.touch);
      await drain(tester);
    });
    final rightBeforeResize = b.readingPosition!;
    final stable = session.pdf('c1').readingPosition!.toJson();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(session.pdf('c1').readingPosition!.toJson(), stable);
    await session.toggleSync();
    await drain(tester);
    await move(0, 2, 400);
    final before = session.pdf('c1').readingPosition!;
    tester.view.physicalSize = const Size(1500, 900);
    await drain(tester);
    expect(session.pdf('c1').readingPosition!.page, before.page);
    expect(session.pdf('c1').readingPosition!.y, closeTo(before.y, 1));
    expect(session.pdf('c2').readingPosition!.y, closeTo(rightBeforeResize.y, 1));
    session.exit();
    await drain(tester);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wheel sync in both directions and realignment with 2 versus 291 pages', (tester) async {
    installTestPdfBackend(documents: {'a.pdf': (pages: 2, height: 800), 'b.pdf': (pages: 291, height: 900)});
    final fixture = compareFixture();
    final repository = InMemoryStudySetContentRepository({
      'demo-1': fixture.copyWith(
        documents: [
          Document(id: 'c1', title: '学习的底层逻辑', fileName: 'a.pdf', pageCount: 2, importedAt: testNow),
          Document(id: 'c2', title: 'Learning and memory.pdf', fileName: 'b.pdf', pageCount: 291, importedAt: testNow),
        ],
      ),
    });
    final container = await pumpApp(tester, renderPdf: true, content: repository, size: const Size(1800, 1100));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final session = container.read(readerCompareProvider('demo-1').notifier);
    await session.select('c2', readerWidth: 700);
    await drain(tester);
    final left = session.pdf('c1'), right = session.pdf('c2');
    Future<void> wheel(int side, double delta) async {
      final pdf = side == 0 ? left : right;
      final view = find.byWidgetPredicate((w) => w is MMPdfView && identical(w.controller, pdf));
      await tester.sendEventToBinding(
        PointerScrollEvent(position: tester.getCenter(view), scrollDelta: Offset(0, delta)),
      );
      await drain(tester);
    }

    Future<void> equalWheel(int side, double delta) async {
      final a = left.scrollPosition!.offset, b = right.scrollPosition!.offset;
      await wheel(side, delta);
      final leftDelta = left.scrollPosition!.offset - a, rightDelta = right.scrollPosition!.offset - b;
      expect(side == 0 ? leftDelta : rightDelta, delta > 0 ? greaterThan(0) : lessThan(0));
      expect(rightDelta, closeTo(leftDelta, .01));
    }

    await equalWheel(0, 160);
    expect(right.readingPosition!.page, 1); // A short PDF no longer races through a long PDF.
    await equalWheel(1, 200);
    await equalWheel(0, -80);
    // Different zoom and cropping must still move the same screen distance.
    await container
        .read(workspaceProvider('demo-1').notifier)
        .setDocumentCrop('c2', DocumentCrop(all: CropInsets(left: 24, top: 36, right: 60, bottom: 80)));
    await drain(tester);
    final zooming = right.setWidthZoom(1.5);
    await tester.pumpAndSettle();
    await zooming;
    await drain(tester);
    await equalWheel(0, 120);
    await equalWheel(1, -60);
    await session.toggleSync();
    await drain(tester);
    Future<void> jump(MMPdfViewController pdf, int page, double y) async {
      final moving = pdf.jumpToReadingPosition(PdfReadingPosition(page: page, y: y));
      await tester.pumpAndSettle();
      await moving;
      await drain(tester);
    }

    await jump(left, 1, 400);
    await jump(right, 40, 500);
    final first = session.align();
    await drain(tester);
    expect(await first, true);
    await session.toggleSync();
    await drain(tester);
    // A later source position aligned to an earlier target contradicts the old anchor.
    await jump(left, 2, 400);
    await jump(right, 30, 500);
    final realign = session.align();
    await drain(tester);
    expect(await realign, true);
    final pair = container.read(readerCompareProvider('demo-1'))!;
    expect(pair.alignPoints, hasLength(1));
    expect(pair.alignPoints.single.right.page, 30);
    await equalWheel(0, -40);
    expect((await repository.load('demo-1')).comparePairs.single.toJson(), pair.toJson());
    final undo = container.read(workspaceProvider('demo-1').notifier).undo();
    await drain(tester);
    await undo;
    expect(container.read(readerCompareProvider('demo-1'))!.alignPoints.single.right.page, 40);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clamped endpoints stay still, never echo to the driver and resume on reversal', (tester) async {
    installTestPdfBackend(documents: {'a.pdf': (pages: 2, height: 800), 'b.pdf': (pages: 291, height: 900)});
    final fixture = compareFixture();
    final content = InMemoryStudySetContentRepository({
      'demo-1': fixture.copyWith(
        documents: [
          Document(id: 'c1', title: 'Short source', fileName: 'a.pdf', pageCount: 2, importedAt: testNow),
          Document(
            id: 'c2',
            title: 'Long target',
            fileName: 'b.pdf',
            pageCount: 291,
            lastPage: 200,
            importedAt: testNow,
          ),
        ],
      ),
    });
    final container = await pumpApp(tester, renderPdf: true, content: content, size: const Size(1800, 1100));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final session = container.read(readerCompareProvider('demo-1').notifier);
    final original = session.pdf('c1').readingPosition!;
    await session.select('c2', readerWidth: 700);
    await drain(tester);
    final short = session.pdf('c1'), long = session.pdf('c2');
    expect(short.readingPosition!.page, original.page);
    expect(short.readingPosition!.y, closeTo(original.y, 1));
    expect(long.readingPosition!.page, 200);
    final controls = tester.getRect(find.byKey(const ValueKey('compare-floating-controls')));
    final frame = tester.getRect(find.byKey(const ValueKey('reader-compare-view')));
    expect(frame.bottom - controls.bottom, closeTo(MMSizes.readerCompareBottomGap + MMSpacing.xxs, .01));
    expect(controls.width, MMSizes.readerCompareControl);
    expect(controls.height, MMSizes.readerCompareControl);
    Future<void> move(int page, double y) async {
      session.userInput(1);
      final moving = long.jumpToReadingPosition(PdfReadingPosition(page: page, y: y));
      await tester.pumpAndSettle();
      await moving;
      await drain(tester);
    }

    Future<void> stable() async {
      final a = short.readingPosition!.toJson(), b = long.readingPosition!.toJson();
      for (var i = 0; i < 12; i++) {
        session.changed(0); // A late callback from the clamped, driven pane.
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(short.readingPosition!.toJson(), a);
      expect(long.readingPosition!.toJson(), b);
    }

    await move(280, 400);
    final atEnd = short.readingPosition!.toJson();
    final source = long.readingPosition!.toJson();
    await stable();
    expect(long.readingPosition!.toJson(), source);
    await move(288, 400);
    expect(short.readingPosition!.toJson(), atEnd);
    await stable();
    final a = short.scrollPosition!.offset, b = long.scrollPosition!.offset;
    session.userInput(1);
    await long.scrollByScreenDistance(-80);
    await drain(tester);
    expect(short.scrollPosition!.offset - a, closeTo(-80, .01));
    expect(long.scrollPosition!.offset - b, closeTo(-80, .01));
    await stable();
    await move(1, 900);
    final atStart = short.scrollPosition!.offset;
    await stable();
    // Keep moving towards the top while the short PDF is already clamped.
    await move(1, 900);
    expect(short.scrollPosition!.offset, atStart);
    session.userInput(1);
    await long.scrollByScreenDistance(80);
    await drain(tester);
    expect(short.scrollPosition!.offset - atStart, closeTo(80, .01));
    await stable();
    expect(container.read(readerCompareProvider('demo-1'))!.sync, true);
    expect(container.read(readerCompareProvider('demo-1'))!.alignPoints, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single document menu imports to the right and exits from menu', (tester) async {
    final fixture = compareFixture();
    final repository = InMemoryStudySetContentRepository({
      'demo-1': fixture.copyWith(documents: [fixture.documents.first]),
    });
    var picks = <({String path, String name})>[];
    final container = await pumpApp(
      tester,
      content: repository,
      pdfPicker: (_) async => picks,
      overrides: [assistantDefaultModelProvider.overrideWithValue(null)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await tapReaderCommand(tester, find.byKey(const ValueKey('reader-compare')));
    await tester.pumpAndSettle();
    expect(find.textContaining('AI Translate into'), findsNothing);
    expect(find.text('Suggested'), findsNothing);
    final importItem = find.text('Import Document…');
    await tester.tap(importItem);
    await tester.pumpAndSettle();
    expect(container.read(readerCompareProvider('demo-1')), isNull);
    final directory = await tester.runAsync(() => Directory.systemTemp.createTemp('mm_compare_import'));
    addTearDown(() => directory!.delete(recursive: true));
    final source = File('${directory!.path}/imported.pdf');
    await tester.runAsync(() => source.writeAsString('%PDF-1.7'));
    picks = [(path: source.path, name: 'Imported English.pdf')];
    await tapReaderCommand(tester, find.byKey(const ValueKey('reader-compare')));
    await tester.pumpAndSettle();
    await tester.tap(importItem);
    await drain(tester);
    final pair = container.read(readerCompareProvider('demo-1'))!;
    expect(pair.leftDocumentId, 'c1');
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    expect(workspace.content.documents.length, 2);
    expect((pair.right as PdfCompareTarget).documentId, workspace.content.documents.last.id);
    await tapReaderCommand(tester, find.byKey(const ValueKey('reader-compare')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exit Side by Side'));
    await tester.pumpAndSettle();
    expect(container.read(readerCompareProvider('demo-1')), isNull);
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow tablet disables document choices; compact phone hides the entry', (tester) async {
    final container = await pumpApp(
      tester,
      size: const Size(820, 1100),
      overrides: [touchPlatformProvider.overrideWithValue(true)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await tapReaderCommand(tester, find.byKey(const ValueKey('reader-compare')));
    await tester.pumpAndSettle();
    expect(find.text('Window too narrow'), findsOneWidget);
    final item = tester.widget<MenuItemButton>(find.byKey(const ValueKey('compare-document-c2')));
    expect(item.onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-compare')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('write failures restore sync and keep unsaved comments through swap and exit', (tester) async {
    final repository = FailingCompareRepository();
    final container = await pumpApp(tester, content: repository);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final session = container.read(readerCompareProvider('demo-1').notifier);
    await session.select('c2', readerWidth: 600);
    await tester.pumpAndSettle();
    repository.fail = true;
    await expectLater(session.toggleSync(), throwsStateError);
    expect(container.read(readerCompareProvider('demo-1'))!.sync, true);
    container.read(workspaceProvider('demo-1').notifier).openDocument('third');
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).activeDocumentId, 'c1');
    expect(container.read(readerCompareProvider('demo-1'))!.leftDocumentId, 'c1');
    final margin = container.read(readerMarginProvider('demo-1').notifier);
    await margin.start('c1', page: 1, lineY: 400);
    margin.text('Unsaved');
    await session.swap();
    await session.exit();
    await tester.pumpAndSettle();
    expect(container.read(readerCompareProvider('demo-1'))!.leftDocumentId, 'c1');
    expect(container.read(readerMarginProvider('demo-1')).draft!.text, 'Unsaved');
    repository.fail = false;
    await session.exit();
    await tester.pumpAndSettle();
    expect(container.read(readerCompareProvider('demo-1')), isNull);
    expect((await repository.load('demo-1')).marginNotes.single.text, 'Unsaved');
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exiting during a slow document switch cancels its late completion', (tester) async {
    final repository = FailingCompareRepository();
    final container = await pumpApp(tester, content: repository);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final session = container.read(readerCompareProvider('demo-1').notifier);
    await session.select('c2', readerWidth: 600);
    await tester.pumpAndSettle();
    repository.gate = Completer<void>();
    final switching = session.select('third');
    await tester.pump();
    await session.exit();
    repository.gate!.complete();
    await switching;
    await tester.pumpAndSettle();
    expect(container.read(readerCompareProvider('demo-1')), isNull);
    expect(container.read(workspaceProvider('demo-1')).sidebarVisible, true);
    expect(container.read(workspaceProvider('demo-1')).layout, MMSplitMode.split);
  });

  testWidgets('wide source keeps map, switch either header, deletion restores layout', (tester) async {
    final repository = InMemoryStudySetContentRepository({'demo-1': compareFixture()});
    final container = await pumpApp(tester, content: repository, size: const Size(2400, 1100));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    final session = container.read(readerCompareProvider('demo-1').notifier);
    expect(await session.select('missing'), false);
    expect(await session.select('c1'), false);
    expect(await session.select('c2', readerWidth: 1000), false);
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).layout, MMSplitMode.split);
    await session.select('third', left: true);
    await tester.pumpAndSettle();
    expect(container.read(readerCompareProvider('demo-1'))!.leftDocumentId, 'third');
    await session.select('third');
    await tester.pumpAndSettle();
    expect(container.read(readerCompareProvider('demo-1'))!.leftDocumentId, 'c2');
    await workspace.removeDocument('third');
    await tester.pumpAndSettle();
    expect(container.read(readerCompareProvider('demo-1')), isNull);
    expect(container.read(workspaceProvider('demo-1')).sidebarVisible, true);
    expect(await session.align(), false);
    await session.toggleSync();
    session.swap();
    session.exit();
    await session.select('c1', readerWidth: 600);
    await tester.pumpAndSettle();
    for (final id in [...container.read(workspaceProvider('demo-1')).openDocumentIds]) {
      workspace.closeDocument(id);
    }
    await tester.pumpAndSettle();
    expect(container.read(readerCompareProvider('demo-1')), isNull);
    expect(container.read(workspaceProvider('demo-1')).sidebarVisible, true);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
