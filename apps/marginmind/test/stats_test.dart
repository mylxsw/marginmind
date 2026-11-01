import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/review/stats_screen.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';

StudySetContent ratedContent(List<(DateTime, Rating)> ratings) {
  var n = 0;
  var content = demoContent();
  final cardId = content.reviewableCards.first.id;
  for (final (at, rating) in ratings) {
    content = StudySetEditor(newId: () => 'log${++n}', now: () => at).rate(content, cardId, rating);
  }
  return content;
}

List<StudySet> setsWithLogs(int logs) => [
  for (final s in DemoLibrary.studySets(testNow)) s.id == 'demo-1' ? s.copyWith(reviewLogCount: logs) : s,
];

void main() {
  final today = DateTime(2026, 10, 25, 9);
  final content = ratedContent([
    (today.subtract(const Duration(days: 2)), Rating.good),
    (today, Rating.again),
    (today, Rating.good),
    (today, Rating.easy),
  ]);

  Text value(WidgetTester tester, String section) => tester.widget<Text>(
    find.descendant(of: find.byKey(ValueKey(section)), matching: find.byKey(const ValueKey('stats-value'))),
  );

  testWidgets('no review log: no entry in the library or the study set', (tester) async {
    final container = await pumpApp(tester);
    expect(find.text('Statistics'), findsNothing);
    expect(find.text('Learn'), findsNothing);
    await tester.tap(find.text('Starred'));
    await tester.pumpAndSettle();
    await doubleTap(tester, find.text('认知科学入门'));
    expect(find.text('Review'), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar-statistics')), findsNothing);
    expect(container.read(navigationProvider), isA<WorkspaceRoute>());
  });

  testWidgets('library entry opens statistics across study sets and goes back', (tester) async {
    final container = await pumpApp(
      tester,
      sets: setsWithLogs(4),
      content: InMemoryStudySetContentRepository({'demo-1': content}),
    );
    await tester.tap(find.byKey(const ValueKey('library-statistics')));
    await tester.pumpAndSettle();
    expect(container.read(navigationProvider), isA<StatsRoute>());
    expect(find.byType(StatsScreen), findsOneWidget);
    expect(find.text('Reviews'), findsOneWidget);
    expect(find.text('Retained'), findsOneWidget);
    expect(find.text('Next 30 Days'), findsOneWidget);
    expect(value(tester, 'stats-reviewed').data, '4');
    expect(value(tester, 'stats-retention').data, '75%');
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.tap(find.byTooltip('Show Library'));
    await tester.pumpAndSettle();
    expect(container.read(navigationProvider), isA<LibraryRoute>());
  });

  testWidgets('study set statistics use a reusable content tab that switches and closes', (tester) async {
    final container = await pumpApp(
      tester,
      sets: setsWithLogs(4),
      content: InMemoryStudySetContentRepository({'demo-1': content}),
    );
    await tester.tap(find.text('Starred'));
    await tester.pumpAndSettle();
    await doubleTap(tester, find.text('认知科学入门'));
    await tester.tap(find.byKey(const ValueKey('sidebar-statistics')));
    await tester.pumpAndSettle();
    expect(container.read(navigationProvider), isA<WorkspaceRoute>());
    final owner = container.read(workspaceProvider('demo-1').notifier);
    expect(container.read(workspaceProvider('demo-1')).tabs.activeId, 'statistics');
    expect(find.byKey(const ValueKey('workspace-tab-statistics')), findsOneWidget);
    final sidebar = tester.widget<MMSidebarItem>(find.byKey(const ValueKey('sidebar-statistics')));
    expect(sidebar.selected, isTrue);
    expect(find.byTooltip('Back to Study Set'), findsNothing);
    expect(value(tester, 'stats-reviewed').data, '4');

    await tester.tap(find.byKey(const ValueKey('sidebar-statistics')));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).tabs.open.length, 2);
    await tester.tap(find.byKey(const ValueKey('workspace-tab-documentMap')));
    await tester.pumpAndSettle();
    expect(find.byType(StatsScreen), findsNothing);
    await tester.tap(find.byKey(const ValueKey('workspace-tab-statistics')));
    await tester.pumpAndSettle();
    expect(value(tester, 'stats-reviewed').data, '4');
    await tester.tap(find.byKey(const ValueKey('close-workspace-tab-statistics')));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).tabs.activeId, 'documentMap');
    expect(find.byType(StatsScreen, skipOffstage: false), findsNothing);
    owner.activateTab(WorkspaceTab.statistics);
    await tester.pumpAndSettle();
    expect(value(tester, 'stats-reviewed').data, '4');
    expect(container.read(navigationProvider), isA<WorkspaceRoute>());
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });

  testWidgets('logs older than the window leave an empty retention', (tester) async {
    await pumpApp(
      tester,
      sets: setsWithLogs(1),
      content: InMemoryStudySetContentRepository({
        'demo-1': ratedContent([(today.subtract(const Duration(days: 60)), Rating.good)]),
      }),
    );
    await tester.tap(find.byKey(const ValueKey('library-statistics')));
    await tester.pumpAndSettle();
    expect(value(tester, 'stats-reviewed').data, '0');
    expect(value(tester, 'stats-retention').data, '—');
    expect(value(tester, 'stats-upcoming').data, '1');
  });

  group('BarChartPainter', () {
    const bar = Color(0xFF0A84FF);
    const stub = Color(0xFFCCCCCC);

    test('scales to the largest value, or to a fixed maximum', () {
      expect(const BarChartPainter(values: [0, 2, 4], bar: bar, stub: stub).fractions, [0, .5, 1]);
      expect(const BarChartPainter(values: [0, 0], bar: bar, stub: stub).fractions, [0, 0]);
      expect(const BarChartPainter(values: [null, 4, null], bar: bar, stub: stub).fractions, [null, 1, null]);
      expect(const BarChartPainter(values: [.5, 2], max: 1, bar: bar, stub: stub).fractions, [.5, 1]);
    });

    test('draws a zero in the accent color and a missing value in the neutral one', () async {
      const painter = BarChartPainter(values: [null, 0], max: 1, bar: bar, stub: stub);
      final recorder = PictureRecorder();
      painter.paint(Canvas(recorder), const Size(23, 10));
      final image = await recorder.endRecording().toImage(23, 10);
      final data = (await image.toByteData())!;
      Color at(int x) {
        final i = (9 * 23 + x) * 4;
        return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
      }

      expect(at(4), stub);
      expect(at(17), bar);
    });

    test('paints every bar and repaints only on change', () {
      const painter = BarChartPainter(values: [0, 1, 2], bar: bar, stub: stub);
      final recorder = PictureRecorder();
      painter.paint(Canvas(recorder), const Size(90, 50));
      recorder.endRecording().dispose();
      const empty = BarChartPainter(values: [], bar: bar, stub: stub);
      empty.paint(Canvas(PictureRecorder()), const Size(90, 50));
      expect(painter.shouldRepaint(painter), isFalse);
      expect(painter.shouldRepaint(const BarChartPainter(values: [0, 1, 3], bar: bar, stub: stub)), isTrue);
      expect(painter.shouldRepaint(const BarChartPainter(values: [0, 1, 2], bar: stub, stub: stub)), isTrue);
    });
  });
}
