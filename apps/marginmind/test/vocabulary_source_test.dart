import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/vocabulary/vocabulary_source_flash.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/features/workspace/widgets/reflow_reader.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';
import 'reflow_fixtures.dart';
import 'reader_translation_test.dart' show frames;
import 'vocabulary_screen_test.dart' show word, button;

void main() {
  for (final paged in [false, true]) {
    testWidgets('vocabulary text source paints a temporary flash without persisting annotations, paged=$paged', (
      tester,
    ) async {
      final content = InMemoryStudySetContentRepository();
      final doc = await storeBook(content);
      final vocabulary = InMemoryVocabularyRepository();
      addTearDown(vocabulary.dispose);
      final c = await pumpApp(tester, content: content, vocabulary: vocabulary);
      c.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final workspace = c.read(workspaceProvider('demo-1').notifier);
      workspace.openDocument(doc.id);
      await c.read(settingsProvider.notifier).setReading(doc.format, ReadingSettings(paged: paged));
      await tester.pumpAndSettle();
      final session = c.read(reflowSessionProvider(('demo-1', doc.id)));
      final chapter = session.book!.chapters.first;
      final start = chapter.canonicalText.indexOf('Source anchors');
      final anchor = chapter.anchor(start, start + 'Source anchors'.length, revision: doc.revision!);
      await vocabulary.save([
        word(
          'source',
          contexts: [
            VocabularyContext(
              id: 'text',
              studySetId: 'demo-1',
              documentId: doc.id,
              studySetTitle: 'Learning',
              documentTitle: doc.title,
              sentence: anchor.quote,
              hit: 'Source',
              addedAt: testNow,
              textAnchor: anchor,
            ),
          ],
        ),
      ]);
      c.read(navigationProvider.notifier).showVocabulary(studySetId: 'demo-1');
      await tester.pumpAndSettle();
      await button(tester, 'Back to source');
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<ReflowReaderPainter>();
      expect(painters.any((p) => p.sourceFlash?.quote == 'Source anchors'), isTrue);
      expect(workspace.content.annotations, isEmpty);
      await settleHud(tester);
      expect(c.read(vocabularySourceFlashProvider), isNull);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('initial PDF reveal and flash survive route mounting; later remount preserves new position', (
    tester,
  ) async {
    installTestPdfBackend();
    TestPdfRender.produceImages = true;
    addTearDown(() {
      TestPdfRender.produceImages = false;
      TestPdfRender.renders.clear();
    });
    final vocabulary = InMemoryVocabularyRepository([word('cat')]);
    addTearDown(vocabulary.dispose);
    final c = await pumpApp(tester, renderPdf: true, vocabulary: vocabulary, size: const Size(1600, 1000));
    c.read(navigationProvider.notifier).showVocabulary(studySetId: 'demo-1');
    await tester.pumpAndSettle();
    await button(tester, 'Back to source');
    await frames(tester, count: 3);
    final pdf = tester.widget<MMPdfView>(find.byType(MMPdfView));
    expect(pdf.highlights.any((h) => h.id == 'vocabulary-source-flash'), isTrue);
    expect(pdf.controller.currentPage, 3);
    unawaited(pdf.controller.goToPage(1));
    await frames(tester, count: 3);
    c.read(navigationProvider.notifier).showLibrary();
    await tester.pumpAndSettle();
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await frames(tester);
    final workspace = c.read(workspaceProvider('demo-1').notifier);
    expect(workspace.claimPdfReveal(c.read(workspaceProvider('demo-1')).reveal!.nonce), isFalse);
    await settleHud(tester);
  });
}
