import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/reader_crop.dart';
import 'package:marginmind/features/workspace/widgets/reader_crop_controls.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';

Future<void> drain(WidgetTester tester) async {
  for (var n = 0; n < 15; n++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    installTestPdfBackend();
    TestPdfRender.produceImages = true;
    TestPdfText.pages = {
      for (var n = 1; n <= 3; n++)
        n: PdfPageRawText(
          'Selected passage',
          List.generate(16, (i) => PdfRect(30 + i * 10, 700 - (i % 3) * 200, 40 + i * 10, 680 - (i % 3) * 200)),
        ),
    };
  });
  tearDown(() {
    TestPdfRender.produceImages = false;
    TestPdfRender.renders.clear();
    TestPdfText.pages = {};
  });
  testWidgets('suggestion dismisses durably; toggle, edit, cancel, Done and undo preserve position', (tester) async {
    final content = InMemoryStudySetContentRepository({
      'demo-1': demoContent().copyWith(documents: [demoContent().documents.first]),
    });
    final container = await pumpApp(tester, renderPdf: true, content: content, size: const Size(1600, 1000));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    final session = container.read(readerCropProvider('demo-1').notifier);
    final pdf = container.read(readerPdfProvider('demo-1'));
    final l = AppLocalizations.of(tester.element(find.byType(ReaderPane)));
    expect(find.byKey(const ValueKey('crop-suggestion')), findsOneWidget);
    expect(find.textContaining('文字可放大'), findsNothing);
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('crop-suggestion')), matching: find.byType(MMIconButton)),
    );
    await drain(tester);
    expect(workspace.content.document('c1')!.cropSuggestionDismissed, true);
    expect(find.byKey(const ValueKey('crop-suggestion')), findsNothing);
    final jump = pdf.jumpToReadingPosition(PdfReadingPosition(page: 2, y: 420));
    await tester.pumpAndSettle();
    await jump;
    final original = pdf.readingPosition!;
    expect(await session.toggle(), true);
    await drain(tester);
    expect(workspace.content.document('c1')!.crop!.enabled, true);
    expect(pdf.readingPosition!.page, original.page);
    expect(pdf.readingPosition!.y, closeTo(original.y, 1));
    final saved = workspace.content.document('c1')!.crop!.toJson();
    await session.adjust();
    await drain(tester);
    expect(find.byKey(const ValueKey('crop-editor-toolbar')), findsOneWidget);
    final handle = find.byKey(const ValueKey('crop-handle-2-0'));
    expect(handle, findsOneWidget);
    await tester.drag(handle, const Offset(50, 0));
    await tester.pumpAndSettle();
    expect(container.read(readerCropProvider('demo-1')).draft!.all.left, greaterThan(16));
    expect(workspace.content.document('c1')!.crop!.toJson(), saved);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await drain(tester);
    expect(container.read(readerCropProvider('demo-1')).editing, false);
    expect(workspace.content.document('c1')!.crop!.toJson(), saved);
    expect(pdf.readingPosition!.page, 2);
    expect(pdf.readingPosition!.y, closeTo(original.y, 1));
    await session.adjust();
    await drain(tester);
    await tester.tap(find.text(l.cropScopeOddEven));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.cropNone));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await drain(tester);
    expect(workspace.content.document('c1')!.crop!.enabled, false);
    await workspace.undo();
    await drain(tester);
    expect(workspace.content.document('c1')!.crop!.toJson(), saved);
    expect(workspace.content.document('c1')!.cropSuggestionDismissed, true);
    await tester.tap(find.byKey(const ValueKey('reader-crop')));
    await tester.pumpAndSettle();
    expect(find.text(l.cropAdjust), findsOneWidget);
    await tester.tap(find.text(l.cropMargins));
    await drain(tester);
    expect(workspace.content.document('c1')!.crop!.enabled, false);
    await settleHud(tester);
    final shortcut = AppShortcuts.toggleCrop;
    await tester.sendKeyDownEvent(shortcut.meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(shortcut.meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft);
    await drain(tester);
    await settleHud(tester);
    expect(workspace.content.document('c1')!.crop!.enabled, true);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
  });
  testWidgets('four handles, keyboard, scopes and hidden annotation warning', (tester) async {
    final fixture = demoContent();
    final content = InMemoryStudySetContentRepository({
      'demo-1': fixture.copyWith(
        annotations: [
          Annotation(
            id: 'warning',
            documentId: 'c1',
            page: 1,
            rects: const [PageRect(10, 700, 100, 680)],
            quote: 'mark',
            colorIndex: 0,
            createdAt: testNow,
          ),
        ],
      ),
    });
    final container = await pumpApp(tester, renderPdf: true, content: content, size: const Size(1600, 1000));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final session = container.read(readerCropProvider('demo-1').notifier);
    final l = AppLocalizations.of(tester.element(find.byType(ReaderPane)));
    await session.adjust();
    await drain(tester);
    session.scope(CropScope.page);
    session.change(1, CropInsets(left: 120));
    await tester.pumpAndSettle();
    expect(find.text(l.cropHiddenAnnotations(1)), findsOneWidget);
    expect(find.text(l.cropCustomPage), findsWidgets);
    for (var edge = 0; edge < 4; edge++) {
      final handle = find.byKey(ValueKey('crop-handle-1-$edge'));
      Focus.of(tester.element(find.descendant(of: handle, matching: find.byType(MouseRegion)).first)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(edge.isEven ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowDown);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(edge.isEven ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }
    await tester.drag(find.byKey(const ValueKey('crop-handle-1-0')), const Offset(2000, 0));
    await tester.pumpAndSettle();
    final draft = container.read(readerCropProvider('demo-1')).draft!;
    expect(600 - draft.forPage(1).left - draft.forPage(1).right, greaterThanOrEqualTo(160));
    await tester.runAsync(session.automatic);
    await drain(tester);
    expect(container.read(readerCropProvider('demo-1')).draft!.mode, CropMode.auto);
    final saving = session.complete();
    session.cancel();
    expect(
      container.read(readerCropProvider('demo-1')).editing,
      true,
      reason: 'a submitted save owns the draft until it settles',
    );
    await saving;
    await drain(tester);
    expect(find.byType(CropPageEditor), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
  });
}
