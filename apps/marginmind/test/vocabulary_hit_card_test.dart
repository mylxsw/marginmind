import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/vocabulary/hint_card.dart';
import 'package:marginmind/features/vocabulary/hint_controls.dart';
import 'package:marginmind/features/vocabulary/hint_geometry.dart';
import 'package:marginmind/features/vocabulary/vocabulary_controller.dart';
import 'package:marginmind/features/vocabulary/vocabulary_hints.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';
import 'vocabulary_screen_test.dart' show word;
import 'vocabulary_test.dart' show FailingRepository;

void main() {
  final hit = VocabularyHit('cat', [const Rect.fromLTWH(10, 50, 30, 15)], page: 1);
  testWidgets('failed navigation keeps index; remove and undo preserve vocabulary and details open entry', (
    tester,
  ) async {
    final repo = InMemoryVocabularyRepository([word('cat')]);
    addTearDown(repo.dispose);
    final c = await pumpApp(tester, vocabulary: repo);
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(ReaderPane));
    showVocabularyHit(
      context,
      studySetId: 'demo-1',
      hit: hit,
      occurrences: (_) async => [hit, hit],
      reveal: (_) async => throw StateError('missing'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vocabulary-hit-next')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(VocabularyHitCard), matching: find.text('1 / 2')), findsOneWidget);
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    await settleHud(tester);
    await tester.tap(find.byTooltip('Remove from vocabulary'));
    await tester.pumpAndSettle();
    expect(c.read(vocabularyProvider).value!.entries, isEmpty);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(c.read(vocabularyProvider).value!.entries.single.id, 'cat');
    showVocabularyHit(context, studySetId: 'demo-1', hit: hit, occurrences: (_) async => [hit], reveal: (_) async {});
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details ›'));
    await tester.pumpAndSettle();
    expect(c.read(navigationProvider), isA<VocabularyRoute>());
    expect(find.byType(VocabularyHitCard), findsNothing);
    await settleHud(tester);
  });

  testWidgets('lookup and persistence failures stay recoverable; closing cancels index scan', (tester) async {
    final repo = FailingRepository();
    await repo.save([word('cat')]);
    repo.fail = true;
    addTearDown(repo.dispose);
    final c = await pumpApp(tester, vocabulary: repo);
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(ReaderPane));
    showVocabularyHit(
      context,
      studySetId: 'demo-1',
      hit: hit,
      occurrences: (_) async => throw StateError('index'),
      reveal: (_) async {},
    );
    await tester.pumpAndSettle();
    expect(find.byType(VocabularyHitCard), findsOneWidget);
    await settleHud(tester);
    await tester.tap(find.byTooltip('Mark as known'));
    await tester.pumpAndSettle();
    expect(c.read(vocabularyProvider).value!.entries.single.status, VocabularyStatus.learning);
    expect(find.byType(VocabularyHitCard), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleHud(tester);
    final completion = Completer<List<VocabularyHit>>();
    bool Function()? active;
    showVocabularyHit(
      context,
      studySetId: 'demo-1',
      hit: hit,
      occurrences: (check) {
        active = check;
        return completion.future;
      },
      reveal: (_) async {},
    );
    await tester.pumpAndSettle();
    expect(active!(), true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(active!(), false);
    completion.complete([hit]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('preference write failure shows HUD and preserves the selected mode', (tester) async {
    final c = await pumpApp(tester);
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(ReaderPane));
    await changeVocabularyHint(context, () async => throw StateError('disk'));
    await tester.pumpAndSettle();
    expect(c.read(vocabularyHintProvider).mode, VocabularyHintMode.underline);
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    await settleHud(tester);
  });
}
