import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'reflow_fixtures.dart';

void main() {
  testWidgets('spreads, source links, history and progress work across chapters', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final parser = const EpubParser();
    final doc = await storeBook(
      repo,
      format: DocumentFormat.epub,
      book: Book(
        'A book',
        [
          parser.parseHtml(
            'a.html',
            '<h1>First</h1><p><a href="b.html#target">Go to target</a></p><p>${'Long source passage. ' * 500}</p>',
          ),
          parser.parseHtml('b.html', '<h1 id="target">Second</h1><p>${'Another chapter. ' * 200}</p>'),
        ],
        {},
        [],
      ),
    );
    final container = await pumpApp(tester, content: repo, size: const Size(1600, 800));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    workspace.openDocument(doc.id);
    workspace.setLayout(MMSplitMode.primary);
    await tester.pumpAndSettle();
    final s = container.read(reflowSessionProvider(('demo-1', doc.id)));
    expect(find.byKey(const ValueKey('reflow-second-page')), findsOneWidget);
    final surface = find.byKey(const ValueKey('reflow-surface'));
    final link = s.layout!.links.single;
    final rect = s.layout!.boxes(link.anchor, page: s.page).first.rect;
    await tester.tapAt(tester.getTopLeft(surface) + rect.center);
    await tester.pumpAndSettle();
    expect(s.position!.chapterId, 'b.html');
    await tester.tap(find.text('Back').last);
    await tester.pumpAndSettle();
    expect(s.position!.chapterId, 'a.html');
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(s.page, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(s.page, 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final point = tester.getTopLeft(surface) + const Offset(300, 60);
    await mouse.addPointer(location: point);
    await tester.pump();
    final progress = find.byKey(const ValueKey('reflow-progress'));
    await tester.tapAt(Offset(tester.getRect(progress).right - 24, tester.getCenter(progress).dy));
    await tester.pumpAndSettle();
    expect(s.position!.chapterId, 'b.html');
    await mouse.removePointer();
    await container.read(settingsProvider.notifier).setReading(doc.format, const ReadingSettings(paged: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reflow-second-page')), findsNothing);
    expect(s.position!.chapterId, 'b.html');
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });
}
