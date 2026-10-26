import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_core/mm_core.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';

import 'package:marginmind/features/workspace/reader_ocr.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';

class FakeOcr implements PdfOcrService {
  @override
  bool supported = true;
  bool failInspect = false;
  bool failCancel = false;
  int inspections = 0;
  int starts = 0;
  String? cancelledId;
  (int, int, PdfOcrLanguage)? request;
  void Function(int, int)? progress;
  Completer<({PdfOcrDocument document, bool cancelled})> result = Completer();
  PdfOcrDocument document = const PdfOcrDocument(path: '/a.pdf', pageCount: 164, textPages: {2});
  @override
  Future<PdfOcrDocument> inspect(String source) async {
    inspections++;
    if (failInspect) throw StateError('read');
    return document;
  }

  @override
  Future<void> cancel(String id) async {
    if (failCancel) throw StateError('cancel');
    cancelledId = id;
  }

  @override
  Future<({PdfOcrDocument document, bool cancelled})> recognize(
    String source, {
    required String id,
    required int first,
    required int last,
    required PdfOcrLanguage language,
    required void Function(int done, int total) onProgress,
  }) {
    starts++;
    request = (first, last, language);
    progress = onProgress;
    return result.future;
  }
}

void main() {
  late FakeOcr service;
  late ProviderContainer container;
  final provider = readerOcrProvider('/a.pdf');
  setUp(() {
    service = FakeOcr();
    container = ProviderContainer(overrides: [pdfOcrServiceProvider.overrideWithValue(service)]);
  });
  tearDown(() => container.dispose());

  test('inspect is cached, unsupported is hidden, read errors can retry', () async {
    final controller = container.read(provider.notifier);
    service.failInspect = true;
    await controller.inspect();
    expect(container.read(provider).failed, isTrue);
    service.failInspect = false;
    await controller.inspect();
    await controller.inspect();
    expect(service.inspections, 2);
    expect(container.read(provider).document, service.document);
    service.supported = false;
    await container.read(readerOcrProvider('/unsupported.pdf').notifier).inspect();
    expect(service.inspections, 2);
  });

  test('range validation, progress, duplicate start, cancel and partial copy', () async {
    final controller = container.read(provider.notifier);
    await controller.inspect();
    await controller.recognize(0, 1, PdfOcrLanguage.chineseEnglish);
    await controller.recognize(2, 1, PdfOcrLanguage.chineseEnglish);
    await controller.recognize(1, 165, PdfOcrLanguage.chineseEnglish);
    expect(service.starts, 0);
    final task = controller.recognize(1, 164, PdfOcrLanguage.chineseEnglish);
    await controller.recognize(1, 1, PdfOcrLanguage.english);
    expect(service.starts, 1);
    service.progress!(12, 164);
    expect(container.read(provider).done, 12);
    service.failCancel = true;
    await controller.cancel();
    expect(container.read(provider).running, isTrue);
    expect(container.read(provider).cancelling, isFalse);
    service.failCancel = false;
    await controller.cancel();
    await controller.cancel();
    expect(container.read(provider).cancelling, isTrue);
    expect(service.cancelledId, startsWith('ocr-'));
    service.progress!(13, 164);
    expect(container.read(provider).cancelling, isTrue);
    const copy = PdfOcrDocument(path: '/a.ocr.pdf', pageCount: 164, textPages: {1, 2}, hasCopy: true);
    service.result.complete((document: copy, cancelled: true));
    await task;
    expect(container.read(provider).document, same(copy));
    expect(container.read(provider).cancelled, isTrue);
    expect(container.read(provider).revision, 1);
    expect(container.read(provider).running, isFalse);
    await controller.cancel();
  });

  test('failure preserves original and disposal cancels without publishing', () async {
    final controller = container.read(provider.notifier);
    await controller.inspect();
    final task = controller.recognize(1, 1, PdfOcrLanguage.english);
    service.result.completeError(StateError('recognition'));
    await task;
    expect(container.read(provider).failed, isTrue);
    expect(container.read(provider).document, service.document);
    service.result = Completer();
    final next = controller.recognize(1, 1, PdfOcrLanguage.english);
    container.invalidate(provider);
    await Future<void>.delayed(Duration.zero);
    expect(service.cancelledId, isNotNull);
    service.progress!(1, 1);
    service.result.complete((document: service.document, cancelled: true));
    await next;
  });

  testWidgets('scan prompt, range validation, languages, progress and partial completion', (tester) async {
    service = FakeOcr();
    final app = await pumpApp(
      tester,
      prefs: {'settings.language': 'zh'},
      overrides: [pdfOcrServiceProvider.overrideWithValue(service)],
    );
    app.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    expect(find.text('本页文字尚不能选择'), findsOneWidget);
    await tester.tap(find.text('识别文字…'));
    await tester.pumpAndSettle();
    expect(tester.widget<MMSheet>(find.byType(MMSheet)).title, '识别文字');
    await tester.tap(find.text('页码范围'));
    await tester.pumpAndSettle();
    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(fields.evaluate().length - 2), '0');
    await tester.pump();
    expect(find.text('请输入 1 至 164 内的页码范围'), findsOneWidget);
    expect(tester.widget<MMButton>(find.widgetWithText(MMButton, '开始识别')).onPressed, isNull);
    await tester.enterText(fields.at(fields.evaluate().length - 2), '1');
    await tester.pump();
    await tester.tap(find.text('当前页'));
    await tester.pump();
    await tester.tap(find.text('仅英文'));
    await tester.pump();
    await tester.tap(find.text('开始识别'));
    await tester.pumpAndSettle();
    expect(service.request, (1, 1, PdfOcrLanguage.english));
    service.progress!(0, 1);
    await tester.pump();
    expect(find.text('识别文字 0/1'), findsOneWidget);
    await tester.tap(find.byTooltip('取消'));
    await tester.pump();
    expect(service.cancelledId, isNotNull);
    service.result.complete((
      document: const PdfOcrDocument(path: '/a.ocr.pdf', pageCount: 164, textPages: {1, 2}, hasCopy: true),
      cancelled: false,
    ));
    await tester.pumpAndSettle();
    expect(find.text('已识别 · 可选字和搜索'), findsNothing);
    expect(find.text('本页文字尚不能选择'), findsNothing);
    expect(find.text('识别文字…'), findsNothing);
    expect(find.text('已识别'), findsOneWidget);
    // A later unrecognized page still offers OCR.
    app.read(workspaceProvider('demo-1').notifier).recordPage('c1', 3);
    await tester.pumpAndSettle();
    expect(find.text('本页文字尚不能选择'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('copy reload clears stale selection and repeats an existing search', (tester) async {
    service = FakeOcr();
    installTestPdfBackend();
    final app = await pumpApp(tester, renderPdf: true, overrides: [pdfOcrServiceProvider.overrideWithValue(service)]);
    app.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final workspace = app.read(workspaceProvider('demo-1').notifier);
    final pdf = app.read(readerPdfProvider('demo-1'));
    for (var i = 0; i < 100 && !pdf.isReady; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(pdf.isReady, isTrue);
    pdf.search('Selected');
    await tester.pumpAndSettle();
    await workspace.onSelectionCommitted(
      'c1',
      const MMPdfSelection(page: 1, rects: [PageRect(1, 2, 30, 10)], text: 'Selected'),
    );
    final source = workspace.filePath(workspace.content.document('c1')!);
    final job = app.read(readerOcrProvider(source).notifier).recognize(1, 1, PdfOcrLanguage.english);
    service.result.complete((
      document: const PdfOcrDocument(path: '/a.ocr.pdf', pageCount: 164, textPages: {1, 2}, hasCopy: true),
      cancelled: false,
    ));
    await job;
    await tester.pumpAndSettle();
    for (var i = 0; i < 100 && (!pdf.isReady || pdf.matchCount == 0); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(pdf.isReady, isTrue);
    expect(pdf.searchQuery, 'Selected');
    expect(pdf.matchCount, greaterThan(0));
    expect(app.read(workspaceProvider('demo-1')).pending, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('ordinary text pages hide the prompt and options can be cancelled', (tester) async {
    service = FakeOcr();
    service.document = const PdfOcrDocument(path: '/a.pdf', pageCount: 164, textPages: {1});
    final app = await pumpApp(
      tester,
      prefs: {'settings.language': 'zh'},
      overrides: [pdfOcrServiceProvider.overrideWithValue(service)],
    );
    app.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    expect(find.text('识别文字…'), findsNothing);
    app.read(workspaceProvider('demo-1').notifier).recordPage('c1', 3);
    await tester.pumpAndSettle();
    await tester.tap(find.text('识别文字…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MMButton, '取消'));
    await tester.pumpAndSettle();
    expect(service.starts, 0);
    await tester.pump(const Duration(seconds: 1));
  });
}
