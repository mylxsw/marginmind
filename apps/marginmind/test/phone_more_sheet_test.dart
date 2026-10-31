import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/vocabulary/vocabulary_hints.dart';
import 'package:marginmind/features/workspace/phone_reader_controls_controller.dart';
import 'package:marginmind/features/workspace/reader_margin.dart';
import 'package:marginmind/features/workspace/widgets/phone_more_sheet.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_pane_chrome_controller.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';

void main() {
  testWidgets('PhoneMoreSheet layout, tile toggles, transitions and actions', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final content = demoContent();
    final overrides = await testOverrides(
      prefs: {'settings.appearance': 'light', 'settings.readerStyle': 'paper', 'settings.language': 'zh'},
      content: InMemoryStudySetContentRepository({'demo-1': content}),
    );

    final paneChrome = WorkspacePaneChromeController();
    final phoneControls = PhoneReaderControlsController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [...overrides, touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showPhoneMoreSheet(
                        context,
                        studySetId: 'demo-1',
                        paneChrome: paneChrome,
                        phoneControls: phoneControls,
                      );
                    },
                    child: const Text('Open Sheet'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(ElevatedButton));
    final container = ProviderScope.containerOf(element);

    // Set active document to c1 ("学习的底层逻辑")
    container.read(workspaceProvider('demo-1').notifier).openDocument('c1');
    await tester.pumpAndSettle();

    // Open More Sheet
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('phone-sheet-more')), findsOneWidget);

    // 1. Header: Document title "学习的底层逻辑" and close button
    expect(find.text('学习的底层逻辑'), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-more-close')), findsOneWidget);

    // 2. "资料库" entry must NOT exist in the sheet
    expect(find.text('资料库'), findsNothing);

    // 3. No explanatory secondary copy / "已开启" / "已关闭"
    expect(find.text('已开启'), findsNothing);
    expect(find.text('已关闭'), findsNothing);

    // 4. Three Tiles
    expect(find.byKey(const ValueKey('phone-tile-appearance')), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-tile-margin')), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-tile-vocab')), findsOneWidget);

    // Tile 1: Aa swatch
    expect(find.text('Aa'), findsOneWidget);

    // Tile 2: Margin notes toggle
    expect(container.read(readerMarginProvider('demo-1')).openDocuments.contains('c1'), isFalse);
    await tester.tap(find.byKey(const ValueKey('phone-tile-margin')));
    await tester.pumpAndSettle();
    expect(container.read(readerMarginProvider('demo-1')).openDocuments.contains('c1'), isTrue);
    await tester.tap(find.byKey(const ValueKey('phone-tile-margin')));
    await tester.pumpAndSettle();
    expect(container.read(readerMarginProvider('demo-1')).openDocuments.contains('c1'), isFalse);

    // Tile 3: Vocab hints toggle
    final initialVocab = container.read(vocabularyHintProvider).modeFor('c1') != VocabularyHintMode.off;
    await tester.tap(find.byKey(const ValueKey('phone-tile-vocab')));
    await tester.pumpAndSettle();
    expect(container.read(vocabularyHintProvider).modeFor('c1') != VocabularyHintMode.off, !initialVocab);
    await tester.tap(find.byKey(const ValueKey('phone-tile-vocab')));
    await tester.pumpAndSettle();
    expect(container.read(vocabularyHintProvider).modeFor('c1') != VocabularyHintMode.off, initialVocab);

    // 5. Document Switcher shows "1 / 2"
    expect(find.textContaining('1 / 2'), findsOneWidget);

    // 6. Transition to Appearance Secondary Panel
    await tester.tap(find.byKey(const ValueKey('phone-tile-appearance')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('phone-sheet-appearance')), findsOneWidget);
    expect(find.text('阅读外观'), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-reader-style-paper')), findsOneWidget);

    // Back button returns to More sheet
    await tester.tap(find.byKey(const ValueKey('phone-appearance-back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('phone-sheet-more')), findsOneWidget);

    // Close button dismisses the sheet
    await tester.tap(find.byKey(const ValueKey('phone-more-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('phone-sheet-more')), findsNothing);
  });

  testWidgets('PhoneMoreSheet group actions trigger corresponding commands', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final content = demoContent();
    final overrides = await testOverrides(
      prefs: {'settings.appearance': 'light', 'settings.readerStyle': 'white', 'settings.language': 'zh'},
      content: InMemoryStudySetContentRepository({'demo-1': content}),
    );

    final paneChrome = WorkspacePaneChromeController();
    final phoneControls = PhoneReaderControlsController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [...overrides, touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: PhoneMoreSheet(studySetId: 'demo-1', paneChrome: paneChrome, phoneControls: phoneControls),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(PhoneMoreSheet));
    final container = ProviderScope.containerOf(element);

    container.read(workspaceProvider('demo-1').notifier).openDocument('c1');
    await tester.pumpAndSettle();

    // Verify Group 1 items
    expect(find.text('目录与书签'), findsOneWidget);
    expect(find.text('切换文档'), findsOneWidget);
    expect(find.text('裁掉白边'), findsOneWidget);

    // Verify Group 2 items
    expect(find.text('整理笔记'), findsOneWidget);
    expect(find.text('复习'), findsOneWidget);
    expect(find.text('生词本'), findsOneWidget);

    // Tap "切换文档": document switches from c1 to c2
    await tester.tap(find.text('切换文档'));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).activeDocumentId, 'c2');

    // Tap "复习": navigates to review route
    await tester.tap(find.text('复习'));
    await tester.pumpAndSettle();
    expect(container.read(navigationProvider), isA<ReviewRoute>());
  });
}
