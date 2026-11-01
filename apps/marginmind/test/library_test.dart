import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/library/library_controller.dart';
import 'package:marginmind/features/library/widgets/study_set_card.dart';
import 'package:marginmind/features/library/widgets/study_set_cover.dart';
import 'package:marginmind/shared/pdf_picker.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

/// Importing inspects the files for real; give that I/O real time until the
/// new set is open.
Future<void> importSettled(WidgetTester tester) async {
  final container = ProviderScope.containerOf(tester.element(find.byType(MarginMindApp)));
  for (
    var i = 0;
    i < 50 && container.read(navigationProvider) is! WorkspaceRoute && find.byType(MMSheet).evaluate().isEmpty;
    i++
  ) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Real local inputs exercise the portable importer without native PDFium.
Future<PdfPicker> picker(WidgetTester tester, List<String> names, List<String> labels) async {
  final directory = await tester.runAsync(() => Directory.systemTemp.createTemp('mm_library_import'));
  addTearDown(() => directory!.delete(recursive: true));
  await tester.runAsync(() async {
    for (final name in names) {
      await File('${directory!.path}/$name').writeAsString('# Document\n\nBody');
    }
  });
  return (label) async {
    labels.add(label);
    return [for (final name in names) (path: '${directory!.path}/$name', name: name)];
  };
}

void main() {
  testWidgets('library shows continue learning and all study sets', (tester) async {
    await pumpApp(tester);
    expect(find.text('All Study Sets'), findsNWidgets(2)); // toolbar title + sidebar
    expect(find.text('Continue Learning'), findsOneWidget);
    expect(tester.getSize(find.byType(MMToolbar)).height, 40);
    expect(tester.getCenter(find.descendant(of: find.byType(MMToolbar), matching: find.byIcon(MMIcons.grid))).dy, 20);
    expect(find.text('产品设计方法论'), findsWidgets);
    expect(find.textContaining('6 study sets'), findsOneWidget);
    // Grid covers fill their cell (regression: covers collapsed to 0 width).
    final covers = find.byType(StudySetCover);
    expect(tester.getSize(covers.last).width, greaterThan(150));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar filters and search narrow the grid', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Starred'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 study sets'), findsOneWidget);
    expect(find.text('Continue Learning'), findsNothing);
    expect(find.text('注意力与专注'), findsNothing);

    await tester.tap(find.text('All Study Sets').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '投资');
    await tester.pumpAndSettle();
    expect(find.textContaining('1 study set'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching study sets'), findsOneWidget);
  });

  testWidgets('list view shows a sortable table', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(MMIcons.list));
    await tester.pumpAndSettle();
    expect(find.text('Folder'), findsOneWidget);
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    final first = tester.getTopLeft(find.text('论文文献综述')).dy;
    final second = tester.getTopLeft(find.text('产品设计方法论')).dy;
    expect(first, lessThan(second)); // 214 cards before 128
  });

  group('new study set', () {
    testWidgets('asks for documents first, then imports and opens a set named after the first file', (tester) async {
      final labels = <String>[];
      final container = await pumpApp(tester, pdfPicker: await picker(tester, ['认知心理学.MD', 'b.markdown'], labels));
      await tester.tap(find.byIcon(MMIcons.add));
      await importSettled(tester);

      expect(labels, ['Documents']);
      expect(find.byType(MMSheet), findsNothing); // no name sheet in between
      final sets = container.read(studySetsProvider).value!;
      final created = sets.singleWhere((s) => s.title == '认知心理学');
      expect(created.folderId, isNull);
      expect(container.read(navigationProvider), isA<WorkspaceRoute>());
      final content = await container.read(contentRepositoryProvider).load(created.id);
      expect(content.documents, hasLength(2));
      expect(content.documents.map((d) => d.format), everyElement(DocumentFormat.markdown));
      await settleHud(tester);
    });

    testWidgets('cancelling the open panel creates nothing', (tester) async {
      final container = await pumpApp(tester, pdfPicker: await picker(tester, const [], []));
      final before = container.read(studySetsProvider).value!.length;
      await tester.tap(find.byIcon(MMIcons.add));
      await tester.pumpAndSettle();
      expect(container.read(studySetsProvider).value!.length, before);
      expect(container.read(navigationProvider), isA<LibraryRoute>());
    });

    testWidgets('failed imports keep the library unchanged and show a recoverable error', (tester) async {
      final container = await pumpApp(
        tester,
        pdfPicker: (_) async => [(path: '/missing/book.epub', name: 'book.epub')],
      );
      final before = container.read(studySetsProvider).value!.length;
      await tester.tap(find.byIcon(MMIcons.add));
      await importSettled(tester);
      expect(container.read(studySetsProvider).value!.length, before);
      expect(container.read(navigationProvider), isA<LibraryRoute>());
      expect(find.text('Couldn’t Import “book.epub”'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    });

    testWidgets('a set made while viewing a folder lands in that folder', (tester) async {
      final container = await pumpApp(tester, pdfPicker: await picker(tester, ['notes.md'], []));
      container.read(libraryViewProvider.notifier).setFilter(const FolderFilter('design'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(MMIcons.add));
      await importSettled(tester);
      final created = container.read(studySetsProvider).value!.singleWhere((s) => s.title == 'notes');
      expect(created.folderId, 'design');
      await settleHud(tester);
    });
  });

  testWidgets('clicking a study set selects it and Return opens it', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('交互设计原则笔记'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Mind Maps'), findsOneWidget);
  });

  testWidgets('first run shows only the icon and two buttons', (tester) async {
    final container = await pumpApp(tester, sets: const [], pdfPicker: await picker(tester, ['a.md'], []));
    final empty = find.byType(MMEmptyState);
    expect(find.descendant(of: empty, matching: find.byIcon(MMIcons.studySet)), findsOneWidget);
    expect(find.descendant(of: empty, matching: find.byType(MMButton)), findsNWidgets(2));
    // Button titles are the only text: no title, no description.
    expect(tester.widgetList<Text>(find.descendant(of: empty, matching: find.byType(Text))).map((t) => t.data), [
      'New Study Set',
      'Open Sample Study Set',
    ]);
    // The toolbar does not repeat "No study sets" under the title.
    expect(find.text('No study sets'), findsNothing);
    expect(find.byIcon(MMIcons.import), findsNothing); // drop hint only while dragging

    await tester.tap(find.text('New Study Set'));
    await importSettled(tester);
    expect(container.read(studySetsProvider).value!.single.title, 'a');
    await settleHud(tester);
  });

  group('sidebar', () {
    Finder row(String label) => find.ancestor(of: find.text(label), matching: find.byType(MMSidebarItem));
    int? countIn(WidgetTester tester, String label) {
      final counts = find.descendant(of: row(label), matching: find.byType(MMCount));
      return counts.evaluate().isEmpty ? null : tester.widget<MMCount>(counts).value;
    }

    testWidgets('shows counts that are not zero', (tester) async {
      await pumpApp(tester);
      expect(countIn(tester, 'All Study Sets'), 6);
      expect(countIn(tester, 'Starred'), 2);
      expect(countIn(tester, 'Recent'), isNull);
      expect(countIn(tester, '认知科学'), isNotNull);
    });

    testWidgets('hides zero counts', (tester) async {
      final set = DemoLibrary.studySets(testNow).firstWhere((s) => !s.starred && s.dueCount == 0);
      await pumpApp(tester, sets: [set]);
      expect(countIn(tester, 'All Study Sets'), 1);
      expect(countIn(tester, 'Starred'), isNull);
      expect(countIn(tester, 'Recent'), isNull);
      expect(find.descendant(of: row('Due for Review'), matching: find.byType(MMBadge)), findsNothing);
      // A folder with no sets in it shows no count either.
      final empty = DemoLibrary.folders.firstWhere((f) => f.id != set.folderId).name;
      expect(countIn(tester, empty), isNull);
    });

    testWidgets('VoiceOver reads each row name and count once', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester);
      expect(tester.getSemantics(row('Starred')).label, 'Starred\n2');
      expect(tester.getSemantics(row('Recent')).label, 'Recent');
      semantics.dispose();
    });
  });

  testWidgets('VoiceOver reads a study set title once, with its details and star button', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester);
    final title = DemoLibrary.studySets(testNow).firstWhere((s) => s.starred).title;
    final card = find.ancestor(of: find.text(title).last, matching: find.byType(StudySetCard));
    final label = tester.getSemantics(card).label.split('\n');
    expect(label.where((part) => part == title), hasLength(1));
    expect(label.length, greaterThan(1)); // cards, documents and last opened
    expect(find.descendant(of: card, matching: find.bySemanticsLabel('Remove Star')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('VoiceOver reads the first-run buttons once', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, sets: const []);
    for (final label in ['New Study Set', 'Open Sample Study Set']) {
      final node = tester.getSemantics(find.ancestor(of: find.text(label), matching: find.byType(MMButton)));
      expect(node.label, label);
      expect(node.flagsCollection.isButton, isTrue);
    }
    semantics.dispose();
  });

  testWidgets('language and appearance settings apply to the whole app', (tester) async {
    await pumpApp(tester, prefs: {'settings.language': 'zh', 'settings.appearance': 'dark'});
    expect(find.text('全部学习集'), findsWidgets);
    expect(find.text('继续学习'), findsOneWidget);
    final context = tester.element(find.text('继续学习'));
    expect(context.mmColors.brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });
}
