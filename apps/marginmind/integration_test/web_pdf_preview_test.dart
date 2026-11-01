import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/features/workspace/web_conversion.dart';
import 'package:marginmind/features/workspace/web_document.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native PDF save preview renders sharp pages and reaches the final page', (tester) async {
    await DesktopWindow.initialize(
      title: 'Foliarc — PDF Preview Check',
      minimumSize: const Size(900, 650),
      initialSize: const Size(1280, 900),
    );
    await MMPdfEngine.initialize();
    final bytes = (await rootBundle.load('assets/sample/compare-fixture.pdf')).buffer.asUint8List();
    final capture = BrowserDocumentCapture(
      url: Uri.parse('https://example.com/article'),
      title: 'PDF 多页预览检查',
      capturedAt: DateTime(2026, 11, 1),
      html: '<p>正文预览</p>',
      snapshot: '<p>正文预览</p>',
      resources: {},
      pdf: bytes,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('native-preview-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: MMTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: Builder(
              builder: (context) => MMButton(
                label: 'Open',
                onPressed: () => unawaited(
                  showMMSheet<void>(
                    context: context,
                    width: MMSizes.webConversionSheetWidth,
                    builder: (_) => WebConversionSheet(
                      prepare: (mode) => const WebDocumentConverter().prepare(
                        capture,
                        id: 'pdf-preview',
                        title: capture.title,
                        mode: mode,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF'));
    Future<void> ready(Finder page) async {
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final images = tester.widgetList<RawImage>(find.descendant(of: page, matching: find.byType(RawImage)));
        if (images.any((image) => image.image != null)) return;
      }
      fail('PDF page did not render');
    }

    final first = find.byKey(const ValueKey('pdf-data-page-1'));
    await ready(first);
    final preview = find.byType(MMPdfDataPreview);
    void verifyResolution(Finder page) {
      final image = tester.widget<RawImage>(find.descendant(of: page, matching: find.byType(RawImage))).image!;
      final expected = tester.getSize(page).width * tester.view.devicePixelRatio;
      expect(image.width, greaterThanOrEqualTo(expected.floor() - 1));
      debugPrint('[pdf-preview] bitmap=${image.width}x${image.height}, expectedWidth=$expected');
      expect(find.descendant(of: preview, matching: find.byType(RawScrollbar)), findsNothing);
    }

    Future<void> screenshot(String name) async {
      final output = Platform.environment['MM_PDF_PREVIEW_EVIDENCE'];
      if (output == null) return;
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('native-preview-capture')));
      final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('${Directory.systemTemp.path}/$output');
      await directory.create(recursive: true);
      final file = File('${directory.path}/$name.png');
      await file.writeAsBytes(data!.buffer.asUint8List());
      debugPrint('[pdf-preview] screenshot=${file.path}');
      image.dispose();
    }

    verifyResolution(first);
    await screenshot('first-page');
    final scrollable = find.descendant(of: preview, matching: find.byType(Scrollable));
    final last = find.byKey(const ValueKey('pdf-data-page-3'));
    await tester.scrollUntilVisible(last, 400, scrollable: scrollable, maxScrolls: 20);
    await ready(last);
    verifyResolution(last);
    await screenshot('last-page');
    await tester.tap(find.text('Markdown'));
    await tester.pumpAndSettle();
    expect(find.byType(MMPdfDataPreview), findsNothing);
    await tester.tap(find.text('PDF'));
    await ready(first);
    verifyResolution(first);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(WebConversionSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
