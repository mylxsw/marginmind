import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/vocabulary/vocabulary_hints.dart';
import 'package:marginmind/features/workspace/widgets/reading_settings.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';
import 'assistant_quick_actions_test.dart' show screenshot;
import 'vocabulary_screenshots.dart' show loadVocabularyScreenshotFonts;
import 'reflow_fixtures.dart';

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('reader-more')));
  await tester.pumpAndSettle();
}

Future<void> closeMenu(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadVocabularyScreenshotFonts);

  for (final dark in [false, true]) {
    testWidgets('Chinese vocabulary submenu fits in ${dark ? 'dark' : 'light'} mode', (tester) async {
      final container = await pumpApp(
        tester,
        size: const Size(1024, 820),
        prefs: {'settings.language': 'zh', 'settings.appearance': dark ? 'dark' : 'light'},
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('reader-vocabulary')));
      await tester.pumpAndSettle();
      expect(find.text('生词提示'), findsOneWidget);
      expect(find.text('显示方式（所有文档）'), findsOneWidget);
      for (final label in ['关闭', '仅标记生词', '标记并显示释义', '仅在本文档隐藏', '包含已掌握的单词']) {
        expect(find.text(label).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'vocabulary-menu-${dark ? 'dark' : 'light'}', target: find.byType(MMWindowScaffold));
      await closeMenu(tester);
    });
  }

  testWidgets('PDF and reflow menus show only supported display controls after switching', (tester) async {
    final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final book = await storeBook(repo);
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final owner = container.read(workspaceProvider('demo-1').notifier);
    owner.openDocument('c1');
    await tester.pumpAndSettle();
    await openMenu(tester);
    expect(find.text('Reading Tools'), findsOneWidget);
    expect(find.text('Display Settings'), findsOneWidget);
    expect(find.text('Reading Theme'), findsOneWidget);
    expect(find.text('Full Translation…'), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-settings')), findsNothing);
    expect(find.byKey(const ValueKey('reader-page-fit')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-crop')), findsOneWidget);
    expect(find.text('Actual Size'), findsNothing);
    await closeMenu(tester);

    owner.openDocument(book.id);
    await tester.pumpAndSettle();
    await openMenu(tester);
    expect(find.byKey(const ValueKey('reader-page-fit')), findsNothing);
    expect(find.byKey(const ValueKey('reader-zoom-control')), findsNothing);
    expect(find.byKey(const ValueKey('reader-crop')), findsNothing);
    expect(find.text('Text & Layout…'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reader-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingSettingsPanel), findsOneWidget);
    expect(find.byKey(const ValueKey('vocabulary-hint-modes')), findsNothing);
    await tester.tapAt(const Offset(10, 300));
    await tester.pumpAndSettle();

    await openMenu(tester);
    expect(
      tester.widget<MMDropdownSubmenu<VoidCallback>>(find.byKey(const ValueKey('reader-vocabulary'))).selected,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('reader-vocabulary')));
    await tester.pumpAndSettle();
    expect(find.text('Vocabulary hints'), findsOneWidget, reason: 'the submenu has no duplicate toggle');
    expect(find.text('Display mode (all documents)'), findsOneWidget);
    expect(find.text('Mark words only'), findsOneWidget);
    expect(find.text('Mark words with meanings'), findsOneWidget);
    expect(find.text('Hide only in this document'), findsOneWidget);
    expect(find.text('Include learned words'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reader-vocabulary-gloss')));
    await tester.pumpAndSettle();
    expect(container.read(vocabularyHintProvider).mode, VocabularyHintMode.gloss);
    await openMenu(tester);
    await tester.tap(find.byKey(const ValueKey('reader-vocabulary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-vocabulary-known')));
    await tester.pumpAndSettle();
    expect(container.read(vocabularyHintProvider).showKnown, isTrue);
    await openMenu(tester);
    expect(
      tester.widget<MMDropdownSubmenu<VoidCallback>>(find.byKey(const ValueKey('reader-vocabulary'))).selected,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('reader-vocabulary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-vocabulary-hidden')));
    await tester.pumpAndSettle();
    final hints = container.read(vocabularyHintProvider);
    expect(hints.modeFor(book.id), VocabularyHintMode.off);
    expect(hints.modeFor('c1'), VocabularyHintMode.gloss);
    await openMenu(tester);
    await tester.tap(find.byKey(const ValueKey('reader-vocabulary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-vocabulary-underline')));
    await tester.pumpAndSettle();
    expect(container.read(vocabularyHintProvider).hiddenDocuments, isNot(contains(book.id)));
    expect(container.read(vocabularyHintProvider).modeFor(book.id), VocabularyHintMode.underline);
    expect(tester.takeException(), isNull);
  });

  testWidgets('textless documents hide vocabulary and translation; unknown documents hide empty groups', (
    tester,
  ) async {
    final base = demoContent();
    final original = base.documents.first;
    final scan = Document.fromJson({
      ...original.toJson(),
      'features': {'text': false, 'outline': true},
    });
    final unknown = Document.fromJson({...original.toJson(), 'id': 'unknown', 'format': 'unknown'});
    final repo = InMemoryStudySetContentRepository({
      'demo-1': base.copyWith(documents: [scan, unknown]),
    });
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final owner = container.read(workspaceProvider('demo-1').notifier);
    await openMenu(tester);
    expect(find.byKey(const ValueKey('reader-vocabulary')), findsNothing);
    expect(find.byKey(const ValueKey('full-translation')), findsNothing);
    expect(find.byKey(const ValueKey('reader-margin')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-crop')), findsOneWidget);
    await closeMenu(tester);
    owner.openDocument(unknown.id);
    await tester.pumpAndSettle();
    await openMenu(tester);
    expect(find.text('Reading Tools'), findsNothing);
    expect(find.text('Display Settings'), findsNothing);
    expect(find.byKey(const ValueKey('reader-appearance')), findsNothing);
    expect(find.byKey(const ValueKey('reader-switch-document')), findsOneWidget);
    await closeMenu(tester);
    owner.closeDocument(unknown.id);
    owner.closeDocument(scan.id);
    await tester.pumpAndSettle();
    await openMenu(tester);
    expect(find.text('Reading Tools'), findsNothing);
    expect(find.text('Display Settings'), findsNothing);
    expect(find.byKey(const ValueKey('reader-switch-document')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
