import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';
import 'reader_crop_test.dart' show drain;

void main() {
  testWidgets('layout buttons retain the PDF page and reading line, including while hidden', (tester) async {
    installTestPdfBackend(pageCount: 20);
    final container = await pumpApp(tester, renderPdf: true, size: const Size(1600, 1000));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final pdf = container.read(readerPdfProvider('demo-1'));
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    final reader = tester.state(find.byType(ReaderPane));
    final jump = pdf.jumpToReadingPosition(PdfReadingPosition(page: 10, y: 420));
    await tester.pumpAndSettle();
    await jump;
    final position = pdf.readingPosition!;
    expect(position.page, 10);
    final toolbar = find.byType(MMToolbar);
    for (var repeat = 0; repeat < 2; repeat++) {
      for (final label in ['Source Only', 'Split', 'Map Only', 'Source Only', 'Map Only', 'Split']) {
        await tester.tap(find.descendant(of: toolbar, matching: find.byTooltip(RegExp('^$label'))));
        await drain(tester);
        expect(tester.state(find.byType(ReaderPane, skipOffstage: false)), same(reader));
        expect(pdf.currentPage, 10, reason: label);
        expect(workspace.activePage, 10, reason: '$label must not save a temporary layout page');
        if (label != 'Map Only') {
          expect(pdf.readingPosition!.page, position.page, reason: label);
          expect(pdf.readingPosition!.y, closeTo(position.y, 1), reason: label);
          expect(pdf.zoom.isFinite && pdf.zoom > 0, isTrue, reason: label);
        }
        expect(tester.takeException(), isNull);
      }
    }
    expect(workspace.content.document('c1')!.lastPage, 10, reason: 'the saved reading page must also survive');
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
  });
}
