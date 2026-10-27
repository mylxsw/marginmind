import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/review/review_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:marginmind/features/review/review_screen.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
  const rect = PageRect(10, 100, 200, 88);
  const front = ReviewFront(path: ['Biology', 'Cells'], prompt: ReviewPrompt.none);
  const source = ReviewSource(documentId: 'd', documentTitle: 'Book', page: 4);

  Future<void> pump(WidgetTester tester, ReviewFace face, {bool revealed = false, VoidCallback? onReveal}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: MMTheme.light(),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReviewCardView(face: face, revealed: revealed, onRevealSource: onReveal ?? () {}),
            ),
          ),
        ),
      );

  testWidgets('cloze front: path, context around a mask sized to the excerpt', (tester) async {
    for (final (length, width) in [(2, 36.0), (20, 180.0), (400, 360.0)]) {
      await pump(
        tester,
        ReviewFace(
          front: ReviewFront(
            path: const ['Biology', 'Cells'],
            prompt: ReviewPrompt.cloze,
            before: 'Cells divide. Mitosis has ',
            after: ' phases.',
            maskLength: length,
          ),
          back: const ReviewBack(quote: 'four', source: source),
        ),
      );
      expect(find.text('Biology  ›  Cells'), findsOneWidget);
      expect(find.textContaining('Mitosis has', findRichText: true), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('cloze-mask'))), Size(width, 20));
      expect(find.text('Book · Page 4'), findsNothing);
    }
  });

  testWidgets('title front stays above the answer, which shows quote, notes and source', (tester) async {
    var revealed = 0;
    final face = ReviewFace(
      front: const ReviewFront(path: ['Biology'], prompt: ReviewPrompt.title, title: 'What are the phases?'),
      back: const ReviewBack(
        quote: 'Four phases.',
        notes: [ReviewNote('First note'), ReviewNote('Second note')],
        source: source,
      ),
    );
    await pump(tester, face);
    expect(find.text('What are the phases?'), findsOneWidget);
    expect(find.text('Four phases.'), findsNothing);

    await pump(tester, face, revealed: true, onReveal: () => revealed++);
    expect(find.text('What are the phases?'), findsOneWidget);
    expect(find.text('Four phases.'), findsOneWidget);
    expect(find.text('First note'), findsOneWidget);
    expect(find.text('Second note'), findsOneWidget);
    expect(find.textContaining('Book ·'), findsOneWidget);
    await tester.tap(find.byType(MMButton));
    expect(revealed, 1);
  });

  testWidgets('back of a cloze card replaces the masked context with the full excerpt', (tester) async {
    await pump(
      tester,
      const ReviewFace(
        front: ReviewFront(path: [], prompt: ReviewPrompt.cloze, before: 'Before ', after: ' after', maskLength: 3),
        back: ReviewBack(quote: 'the quote', source: source),
      ),
      revealed: true,
    );
    expect(find.text('the quote'), findsOneWidget);
    expect(find.byKey(const ValueKey('cloze-mask')), findsNothing);
  });

  testWidgets('note card: no quote block and no source; none front draws only the path', (tester) async {
    await pump(
      tester,
      const ReviewFace(
        front: front,
        back: ReviewBack(notes: [ReviewNote('Only the note')]),
      ),
      revealed: true,
    );
    expect(find.text('Only the note'), findsOneWidget);
    expect(find.byType(MMButton), findsNothing);
    await pump(
      tester,
      const ReviewFace(
        front: ReviewFront(path: [], prompt: ReviewPrompt.none),
        back: ReviewBack(),
      ),
    );
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('page front: a blank page without a file, a preview with one', (tester) async {
    const face = ReviewFace(
      front: ReviewFront(path: [], prompt: ReviewPrompt.page, page: 4, areas: [rect]),
      back: ReviewBack(source: source),
    );
    await pump(tester, face);
    expect(find.byKey(const ValueKey('page-prompt')), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: ReviewCardView(face: face, revealed: false, pagePath: 'missing.pdf', onRevealSource: () {}),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('page-prompt')), findsOneWidget);
    // Back of the same card: the page prompt is gone.
    await pump(tester, face, revealed: true);
    expect(find.byKey(const ValueKey('page-prompt')), findsNothing);
  });

  testWidgets('rating preview uses persisted memory and the injected FSRS parameters', (tester) async {
    final review = ReviewState(
      cardId: 'a',
      due: testNow,
      intervalDays: 1,
      ease: 2.5,
      reps: 3,
      lapses: 0,
      lastReviewedAt: testNow,
    );
    const memory = MemoryState(cardId: 'a', stability: 50, difficulty: 5, phase: MemoryPhase.review);
    final content = StudySetContent(
      cards: [Card(id: 'a', kind: CardKind.note, title: 'Answer', createdAt: testNow)],
      nodes: const [MapNode(cardId: 'a', order: 0)],
      reviews: [review],
      memoryStates: const [memory],
    );
    final repo = InMemoryStudySetContentRepository({'demo-1': content});
    final parameters = FsrsParameters(maximumInterval: 7);
    final editor = StudySetEditor(newId: () => 'log', now: () => testNow, fsrsParameters: parameters);
    final overrides = await testOverrides(content: repo, prefs: {'locale': 'en'});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...overrides, editorProvider.overrideWithValue(editor)],
        child: MaterialApp(
          theme: MMTheme.light(),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const ReviewScreen(studySetId: 'demo-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Answer'));
    await tester.pumpAndSettle();
    expect(find.text('7 days'), findsNWidgets(3));
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();
    final saved = await repo.load('demo-1');
    expect(saved.reviewOf('a')!.intervalDays, 7);
    expect(saved.memoryOf('a')!.stability, 50);
    expect(saved.reviewLogs.single.intervalAfter, 7);
  });

  group('excerptPageTextProvider', () {
    Future<PageContent?> read(WidgetTester tester, {required bool render, String cardId = 'c5'}) async {
      final container = ProviderContainer(overrides: await testOverrides(renderPdf: render));
      addTearDown(container.dispose);
      container.listen(contentProvider('demo-1'), (_, _) {});
      await container.read(contentProvider('demo-1').future);
      final sub = container.listen(excerptPageTextProvider((studySetId: 'demo-1', cardId: cardId)), (_, _) {});
      addTearDown(sub.close);
      return container.read(excerptPageTextProvider((studySetId: 'demo-1', cardId: cardId)).future);
    }

    testWidgets('is empty when PDFs are not rendered, the card is missing, or the file is unreadable', (tester) async {
      await tester.runAsync(() async {
        expect(await read(tester, render: false), isNull);
        expect(await read(tester, render: true, cardId: 'nope'), isNull);
        expect(await read(tester, render: true), isNull);
      });
    });
  });
}
