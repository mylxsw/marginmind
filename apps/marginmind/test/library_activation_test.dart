import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/library/library_controller.dart';
import 'package:marginmind/features/library/widgets/study_set_card.dart';
import 'package:marginmind/features/library/widgets/study_set_cover.dart';
import 'package:marginmind/settings/system_appearance.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';

void main() {
  for (final mode in LibraryViewMode.values) {
    testWidgets('$mode opens with a fast 10ms mouse double click', (tester) async {
      final container = await pumpApp(tester);
      container.read(libraryViewProvider.notifier).setViewMode(mode);
      await tester.pumpAndSettle();
      final title = find.text('交互设计原则笔记').last;
      await tester.tap(title, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(title, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(container.read(navigationProvider), isA<WorkspaceRoute>());
    });

    testWidgets('$mode opens with a 400ms mouse double click using the system interval', (tester) async {
      final container = await pumpApp(tester, overrides: [systemAppearanceProvider.overrideWith(_MacAppearance.new)]);
      container.read(libraryViewProvider.notifier).setViewMode(mode);
      await tester.pumpAndSettle();
      final title = find.text('交互设计原则笔记').last;
      await tester.tap(title, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(libraryViewProvider).selectedId, isNotNull);
      await tester.tap(title, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(container.read(navigationProvider), isA<WorkspaceRoute>());
    });
  }

  testWidgets('clicking the star does not open the study set', (tester) async {
    final container = await pumpApp(tester);
    final card = find.byType(StudySetCard).first;
    final id = tester.widget<StudySetCard>(card).set.id;
    final starred = container.read(studySetsProvider).value!.singleWhere((s) => s.id == id).starred;
    final star = find.descendant(of: card, matching: find.byIcon(MMIcons.starFill));
    await tester.tap(star, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(container.read(studySetsProvider).value!.singleWhere((s) => s.id == id).starred, !starred);
    expect(container.read(navigationProvider), isA<LibraryRoute>());
  });

  for (final region in ['cover', 'title', 'metadata', 'padding', 'bottom']) {
    for (final held in [0, 120]) {
      testWidgets('mouse double click opens from $region (held ${held}ms)', (tester) async {
        final container = await pumpApp(tester);
        final card = find.byType(StudySetCard).first;
        final set = tester.widget<StudySetCard>(card).set;
        final rect = tester.getRect(card);
        final point = switch (region) {
          'cover' => tester.getCenter(find.descendant(of: card, matching: find.byType(StudySetCover))),
          'title' => tester.getCenter(find.descendant(of: card, matching: find.text(set.title))),
          'metadata' => Offset(rect.center.dx, rect.bottom - 17),
          'padding' => rect.topLeft + const Offset(2, 2),
          _ => rect.bottomCenter - const Offset(0, 2),
        };
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: point);
        await tester.pump();
        await mouse.down(point);
        await tester.pump(Duration(milliseconds: held));
        await mouse.up();
        await tester.pump(const Duration(milliseconds: 80));
        final second = await tester.startGesture(point + const Offset(1, 1), kind: PointerDeviceKind.mouse);
        await tester.pump(Duration(milliseconds: held));
        await second.up();
        await tester.pumpAndSettle();
        expect(container.read(navigationProvider), isA<WorkspaceRoute>());
        expect((container.read(navigationProvider) as WorkspaceRoute).studySetId, set.id);
        expect(tester.takeException(), isNull);
        await second.removePointer();
      });
    }
  }

  testWidgets('single mouse click selects immediately and blank area clears selection', (tester) async {
    final container = await pumpApp(tester);
    final card = find.byType(StudySetCard).first;
    final id = tester.widget<StudySetCard>(card).set.id;
    await tester.tap(card, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(container.read(libraryViewProvider).selectedId, id);
    expect(container.read(navigationProvider), isA<LibraryRoute>());
    await tester.tapAt(const Offset(1100, 780), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(container.read(libraryViewProvider).selectedId, isNull);
  });

  test('opening does not wait for the recent-open timestamp to reach disk', () async {
    final repo = _SlowOpenRepository();
    final container = ProviderContainer(overrides: [studySetRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    final opening = container.read(libraryViewProvider.notifier).open('demo-1');
    final route = container.read(navigationProvider);
    // Complete the disk operation even if the assertion below fails.
    repo.pending.single.complete();
    await opening;
    expect(route, isA<WorkspaceRoute>());
  });

  test('a failed timestamp write still opens the study set', () async {
    final repo = _SlowOpenRepository();
    final container = ProviderContainer(overrides: [studySetRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    final opening = container.read(libraryViewProvider.notifier).open('demo-1');
    repo.pending.single.completeError(StateError('Disk unavailable'));
    await expectLater(opening, completes);
    expect(container.read(navigationProvider), isA<WorkspaceRoute>());
  });

  test('an old timestamp write cannot reopen a set after returning home', () async {
    final repo = _SlowOpenRepository();
    final container = ProviderContainer(overrides: [studySetRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    final opening = container.read(libraryViewProvider.notifier).open('demo-1');
    container.read(navigationProvider.notifier).showLibrary();
    repo.pending.single.complete();
    await opening;
    expect(container.read(navigationProvider), isA<LibraryRoute>());
  });
}

class _SlowOpenRepository extends InMemoryStudySetRepository {
  _SlowOpenRepository() : super(sets: DemoLibrary.studySets(testNow), clock: () => testNow);

  final pending = <Completer<void>>[];

  @override
  Future<void> markOpened(String id) {
    final operation = Completer<void>();
    pending.add(operation);
    return operation.future;
  }
}

class _MacAppearance extends SystemAppearanceController {
  @override
  SystemAppearance build() => const SystemAppearance(doubleClickInterval: Duration(milliseconds: 500));
}
