import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/vocabulary/vocabulary_hints.dart';
import 'package:marginmind/features/workspace/widgets/reading_settings.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';
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
    expect(find.byKey(const ValueKey('reader-zoom-slider')), findsNothing);
    expect(find.byKey(const ValueKey('reader-crop')), findsNothing);
    expect(find.text('Text & Layout…'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reader-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingSettingsPanel), findsOneWidget);
    expect(find.byKey(const ValueKey('vocabulary-hint-modes')), findsNothing);
    await tester.tapAt(const Offset(10, 300));
    await tester.pumpAndSettle();

    await openMenu(tester);
    await tester.tap(find.byKey(const ValueKey('reader-vocabulary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-vocabulary-gloss')));
    await tester.pumpAndSettle();
    expect(container.read(vocabularyHintProvider).mode, VocabularyHintMode.gloss);
    await openMenu(tester);
    await tester.tap(find.byKey(const ValueKey('reader-vocabulary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-vocabulary-known')));
    await tester.pumpAndSettle();
    expect(container.read(vocabularyHintProvider).showKnown, isTrue);
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
