import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/features/workspace/widgets/phone_reader_controls.dart';
import 'package:marginmind/features/workspace/widgets/reflow_scroll_reader.dart';
import 'package:marginmind/features/workspace/widgets/reflow_tools.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';
import 'reader_crop_test.dart' show drain;
import 'reflow_fixtures.dart';

void main() {
  testWidgets('phone reflow page number follows finger scrolling before and after a slider jump', (tester) async {
    final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final doc = await storeBook(
      repo,
      book: Book(
        'Long article',
        [
          const EpubParser().parseHtml(
            'main',
            '<h1>Long article</h1>${List.generate(100, (i) => '<p>Paragraph $i: Reading progress must follow the text under your finger.</p>').join()}',
          ),
        ],
        {},
        [],
      ),
    );
    final container = await pumpApp(
      tester,
      content: repo,
      size: const Size(393, 852),
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    container.read(workspaceProvider('demo-1').notifier).openDocument(doc.id);
    await drain(tester);
    final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
    PhoneReaderControls controls() => tester.widget<PhoneReaderControls>(find.byType(PhoneReaderControls));
    expect(controls().page, 1);
    expect(controls().pageCount, greaterThan(5));
    Future<void> pan(double dy) async {
      final finger = await tester.startGesture(tester.getCenter(find.byType(ReflowScrollReader)));
      for (var i = 0; i < 10; i++) {
        await finger.moveBy(Offset(0, dy / 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await finger.cancel();
      await tester.pumpAndSettle();
    }

    await pan(-1000);
    final expected = session.layout!.pageForOffset(session.position!.offset) + 1;
    expect(expected, greaterThan(1));
    expect(controls().page, expected, reason: 'Scrolling must update the capsule without touching its slider');
    await tester.tap(find.byKey(const ValueKey('phone-reader-page')));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byKey(const ValueKey('phone-reader-slider'))).onChanged!(.5);
    await drain(tester);
    final middle = controls().page;
    await pan(-1000);
    expect(controls().page, greaterThan(middle), reason: 'Scrolling must keep updating after a slider jump');
    final later = controls().page;
    await pan(1000);
    expect(controls().page, lessThan(later));
    expect(controls().page, session.layout!.pageForOffset(session.position!.offset) + 1);
    for (var i = 0; i < 20; i++) {
      await pan(-1000);
    }
    expect(controls().page, controls().pageCount, reason: 'At the bottom the capsule must reach the final page');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
  });

  testWidgets('scrolling across chapters uses the visible chapter page count', (tester) async {
    final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final doc = await storeBook(
      repo,
      book: Book(
        'Two chapters',
        [
          for (final (id, count) in [('first', 20), ('second', 60)])
            const EpubParser().parseHtml(
              id,
              '<h1>$id</h1>${List.generate(count, (i) => '<p>Paragraph $i: Each chapter has its own reading layout and page count.</p>').join()}',
            ),
        ],
        {},
        [],
      ),
    );
    final container = await pumpApp(
      tester,
      content: repo,
      size: const Size(393, 852),
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    container.read(workspaceProvider('demo-1').notifier).openDocument(doc.id);
    await drain(tester);
    final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
    PhoneReaderControls controls() => tester.widget<PhoneReaderControls>(find.byType(PhoneReaderControls));
    final firstCount = controls().pageCount;
    Future<void> pan(double dy) async {
      final finger = await tester.startGesture(tester.getCenter(find.byType(ReflowScrollReader)));
      for (var i = 0; i < 10; i++) {
        await finger.moveBy(Offset(0, dy / 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await finger.cancel();
      await tester.pumpAndSettle();
    }

    for (var i = 0; i < 15 && session.position!.chapterId != 'second'; i++) {
      await pan(-600);
    }
    expect(session.position!.chapterId, 'second');
    final visibleLayout = tester
        .widgetList<ReflowTools>(find.byType(ReflowTools))
        .firstWhere((tool) => tool.layout.chapter.id == 'second')
        .layout;
    expect(controls().pageCount, visibleLayout.pages.length);
    expect(controls().pageCount, greaterThan(firstCount));
    expect(controls().page, visibleLayout.pageForOffset(session.position!.offset) + 1);
    final page = controls().page;
    await pan(-1000);
    expect(controls().page, greaterThan(page));
    for (var i = 0; i < 15 && session.position!.chapterId != 'first'; i++) {
      await pan(600);
    }
    expect(session.position!.chapterId, 'first');
    expect(controls().pageCount, firstCount);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
  });
}
