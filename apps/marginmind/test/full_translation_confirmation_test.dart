import 'package:mm_assistant/mm_assistant.dart';
import 'package:marginmind/features/workspace/document_translation_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/workspace/full_translation.dart';
import 'package:marginmind/features/workspace/reader_compare.dart';
import 'package:marginmind/features/workspace/translation_schedulers.dart';
import 'package:marginmind/features/workspace/translation_task_summary.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_sheet.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'full_translation_test.dart' show TestTranslator;
import 'helpers.dart';
import 'reader_translation_test.dart' show model;
import 'reflow_fixtures.dart';

void main() {
  testWidgets('text document confirms multilingual direction before translating every paragraph', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(
      repo,
      format: DocumentFormat.web,
      book: Book(
        'Article',
        [
          const EpubParser().parseHtml(
            'main',
            '<p>The first paragraph explains how learning works.</p>'
                '<p>The second paragraph describes a useful example.</p>'
                '<p>The final paragraph contains a conclusion.</p>',
          ),
        ],
        {},
        [],
      ),
    );
    final translator = TestTranslator();
    final store = InMemoryTranslationStore();
    final c = await pumpApp(
      tester,
      content: repo,
      overrides: [
        assistantDefaultModelProvider.overrideWithValue(model),
        documentTranslationRouteProvider.overrideWith(
          (ref, model) async => const RoutingRowState(
            effective: ModelReference('fixture', 'model'),
            source: RoutingSource.functionBinding,
            issue: RoutingIssue.none,
          ),
        ),
        documentTranslatorFactoryProvider.overrideWithValue((_, _) async => translator),
        translationStoreProvider('demo-1').overrideWith((ref) async => store),
      ],
    );
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    c.read(workspaceProvider('demo-1').notifier).openDocument(doc.id);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full Translation…'));
    await tester.pumpAndSettle();
    expect(find.byType(FullTranslationSheet), findsOneWidget);
    expect(translator.calls, isEmpty);
    expect(c.read(readerCompareProvider('demo-1')), isNull);
    expect(find.text('Batch Review'), findsNothing);

    final target = find.byKey(const ValueKey('full-translation-target-language'));
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(find.text('Japanese'), findsOneWidget);
    expect(find.text('French'), findsOneWidget);
    await tester.tap(find.text('Japanese'));
    await tester.pumpAndSettle();
    expect(translator.calls, isEmpty);
    final source = find.byKey(const ValueKey('full-translation-source-language'));
    await tester.tap(source);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Japanese').last);
    await tester.pumpAndSettle();
    expect(tester.widget<MMButton>(find.widgetWithText(MMButton, 'Start Translation')).onPressed, isNull);
    expect(find.text('Source and target languages are the same. Choose another target language.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(translator.calls, isEmpty);

    await tester.tap(find.byKey(const ValueKey('reader-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full Translation…'));
    await tester.pumpAndSettle();
    final popup = tester.widget<MMPopUpButton<String>>(target);
    expect(popup.value, 'ja');
    final provider = fullTranslationProvider(('demo-1', doc.id, 'ja'));
    await tester.runAsync(() async {
      for (var i = 0; i < 200 && c.read(provider).loading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    final start = tester.widget<MMButton>(find.widgetWithText(MMButton, 'Start Translation'));
    expect(start.onPressed, isNotNull);
    await tester.tap(find.text('Start Translation'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (var i = 0; i < 200 && c.read(provider).job?.state != TranslationJobState.done; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    final state = c.read(provider);
    expect(state.loadError, isNull);
    expect(state.job?.mode, TranslationMode.all);
    expect(state.job?.state, TranslationJobState.done);
    expect(state.counts().done, 3);
    expect(state.counts().pct, 100);
    expect(translator.calls.toSet(), {0, 1, 2});
    expect(translator.calls.length, 3);
    expect(state.pageStates.length, 3);
    expect(c.read(translationTaskSummaryProvider(('demo-1', doc.id))).value?.targetLang, 'ja');
    expect((c.read(readerCompareProvider('demo-1'))!.right as AiCompareTarget).targetLang, 'ja');
    await c.read(readerCompareProvider('demo-1').notifier).exit();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full Translation…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View Translation'));
    await tester.pumpAndSettle();
    expect(translator.calls.length, 3, reason: 'Viewing saved translations must not issue another request');
    expect(c.read(readerCompareProvider('demo-1')), isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
