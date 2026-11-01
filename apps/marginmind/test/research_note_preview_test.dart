import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
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
  setUp(installTestPdfBackend);
  for (final dismissal in ['escape', 'outside', 'document', 'open']) {
    testWidgets('hover does not open a note; clicking supports $dismissal dismissal', (tester) async {
      final container = await pumpApp(tester, renderPdf: true, size: const Size(1600, 1000));
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await drain(tester);
      final provider = workspaceProvider('demo-1');
      final workspace = container.read(provider.notifier);
      await workspace.saveResearchNote(
        ResearchNote(
          id: 'hover-note',
          title: 'Saved note',
          question: 'Why?',
          body: 'Existing note body',
          createdAt: testNow,
          updatedAt: testNow,
        ),
        source: PdfTarget(
          documentId: 'c1',
          pages: const [
            AnnotationPage(page: 1, rects: [PageRect(30, 700, 150, 680)]),
          ],
          quote: 'Source',
        ),
      );
      final pdf = container.read(readerPdfProvider('demo-1'));
      final jump = pdf.jumpToPage(1);
      await tester.pumpAndSettle();
      await jump;
      await drain(tester);
      final marker = find.byKey(ValueKey('pdf-marker-${noteMarkId(workspace.content.noteAttachments.single.id)}'));
      final popover = find.byKey(const ValueKey('research-note-popover'));
      // Establish the reader's keyboard focus, then hover without clicking.
      Focus.of(tester.element(find.byType(ReaderPane))).requestFocus();
      await tester.pump();
      final focus = FocusManager.instance.primaryFocus;
      final state = container.read(provider);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(tester.getCenter(marker));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(popover, findsNothing);
      expect(container.read(provider), same(state), reason: 'hover must not change workspace state');
      expect(FocusManager.instance.primaryFocus, same(focus));
      await mouse.down(tester.getCenter(marker));
      await mouse.up();
      expect(container.read(provider).pending, isA<PendingResearchNote>());
      await tester.pump();
      expect(popover, findsOneWidget);
      expect(find.text('Existing note body'), findsOneWidget);
      await mouse.moveTo(const Offset(1, 1));
      await tester.pump(const Duration(seconds: 1));
      expect(popover, findsOneWidget, reason: 'moving away must not dismiss a clicked note');
      switch (dismissal) {
        case 'escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
        case 'outside':
          await tester.tapAt(const Offset(500, 700));
          await tester.pump();
        case 'open':
          await tester.tap(find.byKey(const ValueKey('popover-open-note')));
          await tester.pumpAndSettle();
          expect(find.text('Existing note body'), findsWidgets);
        case 'document':
          workspace.openDocument('c2');
          await tester.pump();
      }
      expect(popover, findsNothing);
      if (dismissal != 'document' && dismissal != 'open') {
        await mouse.moveTo(tester.getCenter(marker));
        await tester.pump(const Duration(seconds: 1));
        expect(popover, findsNothing, reason: 'hover must not reopen a dismissed note');
      }
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      await drain(tester);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('click pins a note immediately and its actions still open the note', (tester) async {
    final container = await pumpApp(tester, renderPdf: true, size: const Size(1600, 1000));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    await workspace.saveResearchNote(
      ResearchNote(
        id: 'click-note',
        title: 'Click note',
        question: 'Why?',
        body: 'Click body',
        createdAt: testNow,
        updatedAt: testNow,
      ),
      source: PdfTarget(
        documentId: 'c1',
        pages: const [
          AnnotationPage(page: 1, rects: [PageRect(30, 700, 150, 680)]),
        ],
        quote: 'Source',
      ),
    );
    final jump = container.read(readerPdfProvider('demo-1')).jumpToPage(1);
    await tester.pumpAndSettle();
    await jump;
    await drain(tester);
    final marker = find.byKey(ValueKey('pdf-marker-${noteMarkId(workspace.content.noteAttachments.single.id)}'));
    await tester.tap(marker, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(find.byKey(const ValueKey('research-note-popover')), findsOneWidget);
    expect(container.read(workspaceProvider('demo-1')).pending, isA<PendingResearchNote>());
    await tester.pump(MMMotion.hoverExit * 2);
    expect(find.byKey(const ValueKey('research-note-popover')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('research-note-popover')), findsNothing);
    expect(container.read(workspaceProvider('demo-1')).pending, isNull);
    await tester.tap(marker, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('popover-open-note')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('research-note-popover')), findsNothing);
    expect(find.text('Click body'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
    expect(tester.takeException(), isNull);
  });
}
