import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/workspace/widgets/phone_reader_controls.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';
import 'reader_crop_test.dart' show drain;

void main() {
  testWidgets('phone page capsule follows touch scrolling without using the page slider', (tester) async {
    installTestPdfBackend(pageCount: 67);
    final container = await pumpApp(
      tester,
      renderPdf: true,
      size: const Size(393, 852),
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final view = find.byType(MMPdfView);
    final pdf = tester.widget<MMPdfView>(view).controller;
    expect(pdf.isReady, true);
    expect(tester.widget<PhoneReaderControls>(find.byType(PhoneReaderControls)).page, 1);
    final jump = pdf.scrubToPage(37);
    await tester.pumpAndSettle();
    await jump;
    await tester.pumpAndSettle();
    expect(pdf.currentPage, 37);
    final origin = tester.getCenter(view);
    final finger = await tester.startGesture(origin);
    for (var i = 0; i < 15; i++) {
      await finger.moveBy(const Offset(0, -50));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await finger.up();
    await tester.pumpAndSettle();
    expect(pdf.readingPosition!.page, greaterThan(37), reason: 'The document must have moved to a later page');
    expect(pdf.currentPage, greaterThan(37), reason: 'Touch scrolling must report a new current page');
    expect(container.read(readingPagesProvider('demo-1'))['c1'], pdf.currentPage);
    expect(tester.widget<PhoneReaderControls>(find.byType(PhoneReaderControls)).page, pdf.currentPage);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
  });
}
