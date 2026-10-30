import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/vocabulary/hint_card.dart';
import 'package:marginmind/features/vocabulary/vocabulary_controller.dart';
import 'package:marginmind/features/vocabulary/vocabulary_hints.dart';
import 'package:marginmind/features/vocabulary/vocabulary_source_flash.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';
import 'reader_crop_test.dart' show drain;
import 'vocabulary_screen_test.dart' show word;

void main() {
  testWidgets('PDF hints load neighbors, map text, repaint modes, navigate and ignore exports', (tester) async {
    installTestPdfBackend(pageCount: 12);
    final vocabulary = InMemoryVocabularyRepository([
      word('selected'),
      word('passage', status: VocabularyStatus.known),
    ]);
    addTearDown(vocabulary.dispose);
    final content = StudySetEditor(
      newId: () => 'pdf',
      now: () => testNow,
    ).addDocument(StudySetContent.empty, title: 'Document', fileName: 'hints.pdf', pageCount: 12).$1;
    final documentId = content.documents.single.id;
    final repository = InMemoryStudySetContentRepository({'demo-1': content});
    final c = await pumpApp(
      tester,
      vocabulary: vocabulary,
      content: repository,
      renderPdf: true,
      size: const Size(1600, 1000),
    );
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final pdf = c.read(readerPdfProvider('demo-1'));
    final hints = c.read(vocabularyHintProvider.notifier);
    List<MMPdfHighlight> highlights() => tester
        .widget<MMPdfView>(find.byType(MMPdfView))
        .highlights
        .where((h) => h.id.startsWith('vocabulary:'))
        .toList();
    expect(pdf.isReady, true);
    expect((await pdf.translationPage(1))!.text, 'Selected passage');
    expect(await pdf.translationPage(0), isNull);
    expect(await pdf.translationPage(20), isNull);
    expect(pdf.visiblePages(), isNotEmpty);
    expect(highlights().length, lessThanOrEqualTo(pdf.visiblePages(neighbors: true).length));
    expect(highlights(), isNotEmpty);
    expect(highlights().first.lineStyle, AnnotationLineStyle.dotted);
    expect(highlights().first.color, Colors.transparent);
    expect(highlights().first.rects.first, const PageRect(30, 700, 110, 680));
    await hints.setMode(VocabularyHintMode.off);
    c.read(vocabularyAddedFlashProvider.notifier).show('selected');
    await tester.pump();
    await tester.pump();
    expect(highlights(), isNotEmpty);
    expect(highlights().every((h) => h.underline == null && h.color == MMColors.light.vocabularyTint), true);
    await tester.pump(MMMotion.flash);
    await drain(tester);
    expect(highlights(), isEmpty);
    await hints.setMode(VocabularyHintMode.gloss);
    await drain(tester);
    expect(highlights().every((h) => h.gloss == '猫'), true);
    expect(find.text('猫'), findsWidgets);
    final first = highlights().first;
    final view = tester.widget<MMPdfView>(find.byType(MMPdfView));
    view.onHighlightTap!(first.id, const Rect.fromLTWH(100, 150, 80, 20));
    await drain(tester);
    expect(find.byType(VocabularyHitCard), findsOneWidget);
    expect(find.descendant(of: find.byType(VocabularyHitCard), matching: find.text('1 / 12')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('vocabulary-hit-next')));
    await drain(tester);
    expect(find.descendant(of: find.byType(VocabularyHitCard), matching: find.text('2 / 12')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('vocabulary-hit-previous')));
    await drain(tester);
    expect(find.descendant(of: find.byType(VocabularyHitCard), matching: find.text('1 / 12')), findsOneWidget);
    await tester.tap(find.byTooltip('Mark as known'));
    await drain(tester);
    expect(c.read(vocabularyProvider).value!.entries.first.status, VocabularyStatus.known);
    expect(highlights(), isEmpty);
    await hints.setShowKnown(true);
    await drain(tester);
    expect(highlights().every((h) => h.underline == MMColors.light.secondaryLabel), true);
    c.read(vocabularyAddedFlashProvider.notifier).show('selected');
    await tester.pump();
    expect(highlights().any((h) => h.color == MMColors.light.vocabularyTint), true);
    final jump = pdf.jumpToReadingPosition(PdfReadingPosition(page: 10, y: 500));
    await drain(tester);
    await jump;
    await drain(tester);
    expect(highlights().every((h) => pdf.visiblePages(neighbors: true).contains(h.page)), true);
    expect(highlights().every((h) => h.page >= 8), true);
    await hints.setDocumentHidden(documentId, true);
    await drain(tester);
    expect(highlights(), isEmpty);
    await hints.setDocumentHidden(documentId, false);
    await drain(tester);
    expect(highlights(), isNotEmpty);
    expect(c.read(workspaceProvider('demo-1').notifier).content.annotations, isEmpty);
    await settleHud(tester);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
    expect(await pdf.translationPage(1), isNull);
    expect(pdf.visiblePages(), isEmpty);
  });
}
