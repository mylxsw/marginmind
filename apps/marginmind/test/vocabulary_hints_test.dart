import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/vocabulary/hint_card.dart';
import 'package:marginmind/features/vocabulary/hint_controls.dart';
import 'package:marginmind/features/vocabulary/hint_geometry.dart';
import 'package:marginmind/features/vocabulary/hint_painter.dart';
import 'package:marginmind/features/vocabulary/vocabulary_controller.dart';
import 'package:marginmind/features/vocabulary/vocabulary_hints.dart';
import 'package:marginmind/features/vocabulary/vocabulary_source_flash.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/widgets/reflow_tools.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_reflow/mm_reflow.dart';

import 'helpers.dart';
import 'reflow_fixtures.dart';
import 'vocabulary_screen_test.dart' show word;
import 'vocabulary_screenshots.dart';

void main() {
  test('PDF UTF16 offsets map to separate lines and preserve original coordinates', () {
    final page = TranslationPage(3, '😀cat cat\ncat', [
      const PageRect(0, 100, 0, 100),
      const PageRect(0, 100, 0, 100),
      for (var i = 0; i < 7; i++) PageRect(10.0 + i * 8, 100, 18.0 + i * 8, 88),
      const PageRect(0, 80, 0, 80),
      for (var i = 0; i < 3; i++) PageRect(10.0 + i * 8, 80, 18.0 + i * 8, 68),
    ]);
    final hits = vocabularyPdfHits(page, VocabularyMatcher([word('cat')]).match(page.text));
    expect(hits.length, 3);
    expect(hits.first.pdfRects.single, const PageRect(10, 100, 34, 88));
    expect(hits.last.pdfRects.single, const PageRect(10, 80, 34, 68));
    expect(hits.last.page, 3);
    expect(vocabularyPdfRects(page, 0, 2), isEmpty);
    expect(vocabularyPdfRects(TranslationPage(1, 'abc', []), 0, 3), isEmpty);
    expect(vocabularyGlossSpace(const Rect.fromLTRB(10, 50, 35, 65), [const Rect.fromLTRB(0, 20, 100, 35)]), 15);
    expect(vocabularyGlossSpace(const Rect.fromLTRB(10, 50, 35, 65), [const Rect.fromLTRB(0, 45, 100, 55)]), 0);
  });

  test('reflow mapping uses source anchors, skips distant pieces, filters known and stale layout', () {
    final c = const EpubParser().parseHtml('c', '<p>cat cat</p>${'<p>dog text</p>' * 100}');
    final layout = ChapterLayout.layout(c, const LayoutSpec(width: 200, pageHeight: 180));
    final cache = VocabularyMatchCache();
    final entries = [word('cat'), word('dog', status: VocabularyStatus.known)];
    var hits = vocabularyReflowHits(layout, cache, entries, 1, top: 0, bottom: 150);
    expect(hits.map((h) => h.anchor!.quote), ['cat', 'cat']);
    expect(hits.first.rects, layout.boxes(hits.first.anchor!).map((b) => b.rect));
    hits = vocabularyReflowHits(layout, cache, entries, 1, page: 0, showKnown: true);
    expect(hits.any((h) => h.entryId == 'dog'), true);
    expect(hits.length, lessThan(102));
    final far = vocabularyReflowHits(layout, cache, entries, 1, page: layout.pages.length - 1, showKnown: true);
    expect(far.every((h) => h.entryId == 'dog'), true);
    layout.dispose();
    expect(vocabularyReflowHits(layout, cache, entries, 1), isEmpty);
  });

  for (final dark in [false, true]) {
    for (final capture in [false, true]) {
      testWidgets(
        'hint paint and hit card ${dark ? 'dark' : 'light'} ${capture ? 'screenshot' : 'structure and colors'}',
        skip: capture && !vocabularyScreenshotsEnabled,
        (tester) async {
          if (capture) await tester.runAsync(loadVocabularyScreenshotFonts);
          final repository = InMemoryVocabularyRepository([word('cat').copyWith(note: 'Remember this word')]);
          addTearDown(repository.dispose);
          final overrides = await testOverrides(vocabulary: repository);
          final container = ProviderContainer(overrides: overrides);
          addTearDown(container.dispose);
          await container.read(vocabularyProvider.future);
          final hit = VocabularyHit('cat', [const Rect.fromLTWH(20, 60, 50, 18)], page: 1);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: MMTheme.light(),
                darkTheme: MMTheme.dark(),
                themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(
                  body: Center(
                    child: RepaintBoundary(
                      key: const ValueKey('hints-preview'),
                      child: Container(
                        width: 360,
                        height: 330,
                        color: (dark ? MMTheme.dark() : MMTheme.light()).scaffoldBackgroundColor,
                        child: Builder(
                          builder: (context) => Column(
                            children: [
                              SizedBox(
                                width: 300,
                                height: 100,
                                child: CustomPaint(
                                  painter: VocabularyHintPainter(
                                    hits: [
                                      hit,
                                      VocabularyHit('known', [const Rect.fromLTWH(100, 60, 50, 18)]),
                                    ],
                                    entries: {
                                      'cat': word('cat'),
                                      'known': word('known', status: VocabularyStatus.known),
                                    },
                                    color: context.mmColors.vocabulary,
                                    knownColor: context.mmColors.secondaryLabel,
                                    tint: context.mmColors.vocabularyTint,
                                    glossStyle: context.mmText.footnote,
                                    lines: const [Rect.fromLTWH(0, 10, 280, 20)],
                                    gloss: true,
                                    flashEntry: 'cat',
                                  ),
                                ),
                              ),
                              VocabularyHitCard(
                                studySetId: 'demo-1',
                                hit: hit,
                                occurrences: (active) async => [hit, hit],
                                reveal: (_) async {},
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (capture) {
            await saveVocabularyHintScreenshot(
              tester,
              'hints-${dark ? 'dark' : 'light'}',
              find.byKey(const ValueKey('hints-preview')),
            );
          } else {
            final colors = tester.element(find.byType(VocabularyHitCard)).mmColors;
            expect(colors.brightness, dark ? Brightness.dark : Brightness.light);
            final paint = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is VocabularyHintPainter);
            final painter = tester.widget<CustomPaint>(paint).painter! as VocabularyHintPainter;
            expect(painter.color, colors.vocabulary);
            expect(painter.knownColor, colors.secondaryLabel);
            expect(painter.tint, colors.vocabularyTint);
            expect(
              (Canvas canvas) => painter.paint(canvas, const Size(300, 100)),
              paints
                ..rect(color: colors.vocabularyTint)
                ..circle(color: colors.vocabulary)
                ..paragraph()
                ..circle(color: colors.secondaryLabel)
                ..paragraph(),
            );
            final card = find.byType(VocabularyHitCard);
            for (final text in [
              'cat',
              '/kæt/  /kæt/',
              'n.  a small animal',
              'Remember this word',
              '1 / 2',
              'Details ›',
            ]) {
              expect(find.descendant(of: card, matching: find.text(text)), findsOneWidget);
            }
            final status = find.descendant(of: card, matching: find.text('Learning'));
            expect(tester.widget<Text>(status).style?.color, colors.vocabulary);
            final badge = tester.widget<Container>(find.ancestor(of: status, matching: find.byType(Container)).first);
            expect((badge.decoration! as BoxDecoration).color, colors.vocabularyTint);
            for (final key in ['vocabulary-hit-previous', 'vocabulary-hit-next']) {
              expect(tester.widget<MMIconButton>(find.byKey(ValueKey(key))).onPressed, isNotNull);
            }
            expect(find.byTooltip('Mark as known'), findsOneWidget);
            expect(find.byTooltip('Remove from vocabulary'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          // Keep the original container alive until this replacement widget is gone.
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('reflow hint toggle, shortcut, hidden document, known, modes and drag priority', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(repo);
    final vocabulary = InMemoryVocabularyRepository([
      word('source'),
      word('paragraph', status: VocabularyStatus.known),
    ]);
    addTearDown(vocabulary.dispose);
    final c = await pumpApp(tester, content: repo, vocabulary: vocabulary);
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final owner = c.read(workspaceProvider('demo-1').notifier);
    owner.openDocument(doc.id);
    await tester.pumpAndSettle();
    final hints = c.read(vocabularyHintProvider.notifier);
    final session = c.read(reflowSessionProvider(('demo-1', doc.id)));
    final surface = find.byKey(const ValueKey('reflow-surface'));
    VocabularyHintPainter paint() =>
        tester.widget<CustomPaint>(find.byKey(const ValueKey('vocabulary-hints-surface')).first).painter!
            as VocabularyHintPainter;
    expect(paint().hits.length, greaterThan(0));
    expect(paint().hits.every((h) => h.entryId == 'source'), true);
    final capture = tester.renderObject<ReflowCaptureBoundary>(
      find.descendant(
        of: find.byType(ReflowAreaCapture),
        matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_CaptureBoundary'),
      ),
    );
    final normal = (await tester.runAsync(() => capture.toImage(pixelRatio: 1)))!;
    final exported = (await tester.runAsync(() => capture.capture(Offset.zero & capture.size, 1)))!;
    Future<int> teal(ui.Image image) async {
      final bytes = (await tester.runAsync(() => image.toByteData()))!.buffer.asUint8List();
      var found = 0;
      for (var i = 0; i < bytes.length; i += 4) {
        if (bytes[i + 1] > bytes[i] + 30 && bytes[i + 2] > bytes[i] + 30) found++;
      }
      return found;
    }

    expect(await teal(normal), greaterThan(0));
    expect(await teal(exported), 0);
    normal.dispose();
    exported.dispose();
    final hit = paint().hits.first;
    final point = tester.getTopLeft(surface) + hit.rects.first.center;
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(find.byType(VocabularyHitCard), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('vocabulary-hit-next')));
    await tester.pumpAndSettle();
    expect(find.textContaining(' / '), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(VocabularyHitCard), findsNothing);
    await session.jump(session.book!.start);
    await tester.pumpAndSettle();
    final dragHit = paint().hits.first;
    final dragAt = tester.getTopLeft(surface) + dragHit.rects.first.centerLeft + const Offset(1, 0);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(dragAt);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(30, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(VocabularyHitCard), findsNothing);
    expect(c.read(workspaceProvider('demo-1')).pending, isA<PendingSelection>());
    owner.dismissPending();
    await hints.setMode(VocabularyHintMode.gloss);
    await tester.pumpAndSettle();
    expect(paint().gloss, true);
    await tester.tap(find.byKey(const ValueKey('vocabulary-hint-toggle')));
    await tester.pumpAndSettle();
    expect(paint().hits, isEmpty);
    await tester.tap(find.byKey(const ValueKey('vocabulary-hint-toggle')));
    await tester.pumpAndSettle();
    expect(paint().gloss, true);
    await hints.setDocumentHidden(doc.id, true);
    await tester.pumpAndSettle();
    expect(paint().hits, isEmpty);
    await tester.tap(find.byKey(const ValueKey('vocabulary-hint-toggle')));
    await tester.pumpAndSettle();
    expect(c.read(vocabularyHintProvider).hiddenDocuments, isEmpty);
    await hints.setShowKnown(true);
    await tester.pumpAndSettle();
    expect(paint().hits.any((h) => h.entryId == 'paragraph'), true);
    final modifier = AppShortcuts.vocabularyHints.meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
    expect(c.read(vocabularyHintProvider).mode, VocabularyHintMode.off);
    c.read(vocabularyAddedFlashProvider.notifier).show('source');
    await tester.pump();
    expect(paint().flashOnly, true);
    expect(paint().hits.every((h) => h.entryId == 'source'), true);
    expect(paint().hits, isNotEmpty);
    await tester.pump(MMMotion.flash);
    expect(paint().hits, isEmpty);
    expect(owner.content.annotations, isEmpty);
    expect(owner.content.cards, isEmpty);
    await settleHud(tester);
  });

  testWidgets('Aa settings persist changes and added flash expires', (tester) async {
    final c = await pumpApp(tester);
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(ReaderPane));
    showDialog<void>(
      context: context,
      builder: (_) => const Dialog(
        child: SizedBox(width: 340, child: VocabularyHintSettings(documentId: 'c1')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meaning'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vocabulary-hint-hidden')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vocabulary-hint-known')));
    await tester.pumpAndSettle();
    final prefs = c.read(sharedPreferencesProvider);
    expect(prefs.getString('vocabulary.hintMode'), 'gloss');
    expect(prefs.getBool('vocabulary.showKnown'), true);
    expect(prefs.getStringList('vocabulary.hiddenDocuments'), ['c1']);
    c.invalidate(vocabularyHintProvider);
    expect(c.read(vocabularyHintProvider).modeFor('c1'), VocabularyHintMode.off);
    expect(c.read(vocabularyHintProvider).modeFor('other'), VocabularyHintMode.gloss);
    c.read(vocabularyAddedFlashProvider.notifier).show('cat');
    expect(c.read(vocabularyAddedFlashProvider), 'cat');
    c.read(vocabularyAddedFlashProvider.notifier).show('dog');
    await tester.pump(MMMotion.flash);
    expect(c.read(vocabularyAddedFlashProvider), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('gloss painter conservatively falls back without room, clips labels and tolerates missing entries', () async {
    Future<int> ink(bool gloss, List<Rect> lines, {bool flashOnly = false}) async {
      final recorder = ui.PictureRecorder();
      final painter = VocabularyHintPainter(
        hits: [
          VocabularyHit('cat', [const Rect.fromLTWH(15, 30, 45, 18)]),
          const VocabularyHit('missing', []),
        ],
        entries: {'cat': word('cat')},
        color: Colors.teal,
        knownColor: Colors.grey,
        tint: Colors.teal,
        glossStyle: const TextStyle(fontSize: 10),
        gloss: gloss,
        flashOnly: flashOnly,
        flashEntry: flashOnly ? 'cat' : null,
        lines: lines,
      );
      painter.paint(Canvas(recorder), const Size(100, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = (await image.toByteData())!;
      var alpha = 0;
      for (var y = 0; y < 29; y++) {
        for (var x = 0; x < 100; x++) {
          alpha += bytes.getUint8((y * 100 + x) * 4 + 3);
        }
      }
      image.dispose();
      picture.dispose();
      return alpha;
    }

    expect(await ink(false, []), 0);
    expect(await ink(true, [], flashOnly: true), 0);
    expect(await ink(true, [const Rect.fromLTWH(0, 10, 100, 18)]), 0);
    expect(await ink(true, []), greaterThan(0));
  });
}
