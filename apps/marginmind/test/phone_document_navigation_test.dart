import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_book/mm_book.dart';

import 'helpers.dart';
import 'reader_crop_test.dart' show drain;
import 'reflow_fixtures.dart';

void main() {
  testWidgets('reflow navigation closes once after locating, and stays closed after async jump', (tester) async {
    final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final chapter = const EpubParser().parseHtml('main', '<h1>First</h1><p>Read and return to the source.</p>');
    final doc = await storeBook(
      repo,
      book: Book('Navigation', [chapter], {}, [], toc: [BookTocEntry('first', 'Go to chapter', 'main', 0)]),
    );
    final container = await pumpApp(
      tester,
      size: const Size(393, 852),
      content: repo,
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final owner = container.read(workspaceProvider('demo-1').notifier);
    owner.openDocument(doc.id);
    await drain(tester);
    owner.showReaderPanel(ReaderPanelMode.outline);
    await drain(tester);
    final frame = find.byKey(const ValueKey('phone-document-navigation'));
    expect(tester.getSize(frame).width, 393);
    await tester.tap(find.text('Go to chapter').hitTestable());
    await drain(tester);
    expect(container.read(workspaceProvider('demo-1')).readerPanelVisible, false);
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(workspaceProvider('demo-1')).readerPanelVisible, false);
    expect(frame, findsNothing);
    owner.showReaderPanel(ReaderPanelMode.bookmarks);
    await drain(tester);
    await tester.tap(find.byKey(const ValueKey('phone-document-navigation-close')));
    await drain(tester);
    expect(container.read(workspaceProvider('demo-1')).readerPanelVisible, false);
    expect(tester.takeException(), isNull);
  });
}
