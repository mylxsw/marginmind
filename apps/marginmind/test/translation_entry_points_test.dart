import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/full_translation.dart';
import 'package:marginmind/features/workspace/reader_compare.dart';
import 'package:marginmind/features/workspace/reader_translation.dart';
import 'package:marginmind/features/workspace/translation_task_summary.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_panel.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_sheet.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_capsule.dart';
import 'package:marginmind/features/workspace/widgets/reader_translation_view.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'full_translation_test.dart'
    show MockFullTranslationController, MockReaderCompareSession, SnapshotReaderTranslation, testHost;
import 'helpers.dart';
import 'reader_compare_test.dart' show compareFixture;
import 'translation_lifecycle_test.dart' show job, paragraphs;

void main() {
  test('translation command is localized, disabled when unavailable and has no shortcut', () async {
    for (final locale in [const Locale('en'), const Locale('zh')]) {
      final l = await AppLocalizations.delegate.load(locale);
      var invoked = false;
      final idle = AppCommands.translateDocument(l, enabled: true, hasActiveJob: false, onInvoke: () => invoked = true);
      expect(idle.label, l.fullTranslationMenu);
      expect(idle.shortcut, isNull);
      idle.onInvoke!();
      expect(invoked, true);
      final task = AppCommands.translateDocument(l, enabled: false, hasActiveJob: true, onInvoke: () {});
      expect(task.label, l.fullTranslationTask);
      expect(task.onInvoke, isNull);
      expect(
        AppCommands.translateDocument(l, enabled: true, hasActiveJob: true, progressPercent: 25, onInvoke: () {}).label,
        l.fullTranslationTaskMenu(25),
      );
    }
  });

  testWidgets('sidebar and reader menus share persisted language and progress without extracting other documents', (
    tester,
  ) async {
    final events = StreamController<TranslationTaskSummary?>.broadcast();
    addTearDown(events.close);
    final fixture = compareFixture();
    final state = FullTranslationState(
      studySetId: 'demo-1',
      documentId: 'c1',
      targetLang: 'en',
      loading: false,
      job: job(lang: 'en'),
      paragraphs: paragraphs,
    );
    final container = await pumpApp(
      tester,
      content: InMemoryStudySetContentRepository({'demo-1': fixture}),
      overrides: [
        translationTaskSummaryProvider(('demo-1', 'c1')).overrideWith((ref) => events.stream),
        fullTranslationProvider(('demo-1', 'c1', 'en'))
            .overrideWith(() => MockFullTranslationController('demo-1', 'c1', 'en', state)),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    container.read(workspaceProvider('demo-1').notifier).openDocument('c1');
    await tester.pumpAndSettle();
    for (final doc in fixture.documents) {
      expect(container.exists(translationParagraphsProvider(('demo-1', doc.id))), false);
    }
    events.add(TranslationTaskSummary(job(lang: 'en'), 25));
    await tester.pump();
    await tester.pump();

    final row = find.byKey(const ValueKey('document-row-c1'));
    final ring = find.descendant(of: row, matching: find.byType(CircularProgressIndicator));
    expect(tester.widget<CircularProgressIndicator>(ring).value, .25);
    await tester.tap(row, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full Translation… 25%'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(FullTranslationPanel), findsOneWidget);
    expect(tester.widget<FullTranslationPanel>(find.byType(FullTranslationPanel)).targetLang, 'en');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('reader-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full Translation… 25%'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<FullTranslationPanel>(find.byType(FullTranslationPanel)).targetLang, 'en');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    events.add(TranslationTaskSummary(job(state: TranslationJobState.review, lang: 'en'), 50));
    await tester.pump();
    await tester.pump();
    expect(ring, findsNothing);
    expect(container.exists(translationParagraphsProvider(('demo-1', 'c2'))), false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('AI header offers full translation before a task exists and hides it at compact width', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overrides = await testOverrides(content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}));
    await tester.pumpWidget(
      testHost(
        const MMInput(touchPlatform: true, child: ReaderTranslationView(studySetId: 'demo-1')),
        overrides: [
          ...overrides,
          readerCompareProvider('demo-1').overrideWith(
            () => MockReaderCompareSession(
              'demo-1',
              ComparePair(id: 'pair', leftDocumentId: 'c1', right: AiCompareTarget('zh')),
            ),
          ),
          readerTranslationProvider('demo-1')
              .overrideWith(() => SnapshotReaderTranslation('demo-1', const ReaderTranslationState(loading: false))),
          fullTranslationProvider(('demo-1', 'c1', 'zh')).overrideWith(
            () => MockFullTranslationController(
              'demo-1',
              'c1',
              'zh',
              const FullTranslationState(studySetId: 'demo-1', documentId: 'c1', targetLang: 'zh', loading: false),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FullTranslationCapsule), findsOneWidget);
    expect(find.text('翻译全文'), findsOneWidget);
    tester.view.physicalSize = const Size(500, 900);
    await tester.pumpAndSettle();
    expect(find.byType(FullTranslationCapsule), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('opening from an English title uses detected Chinese content as the source', (tester) async {
    final fixture = compareFixture();
    final container = await pumpApp(
      tester,
      content: InMemoryStudySetContentRepository({'demo-1': fixture}),
      overrides: [
        compareDocumentInfoProvider(('demo-1', 'c2')).overrideWith((ref) async => (language: 'zh', hasText: true)),
        translationParagraphsProvider(('demo-1', 'c2')).overrideWith((ref) async => []),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('document-row-c2')), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Translate Entire Document…'));
    await tester.pumpAndSettle();
    final sheet = tester.widget<FullTranslationSheet>(find.byType(FullTranslationSheet));
    expect(sheet.documentId, 'c2');
    expect(sheet.initialTargetLang, 'en');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
