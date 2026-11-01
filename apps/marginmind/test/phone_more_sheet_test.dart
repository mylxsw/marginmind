import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/library/library_screen.dart';
import 'package:marginmind/features/vocabulary/vocabulary_hints.dart';
import 'package:marginmind/features/workspace/reader_margin.dart';
import 'package:marginmind/features/workspace/widgets/phone_more_sheet.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_pane_chrome_controller.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

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
                      showPhoneMoreSheet(context, studySetId: 'demo-1', paneChrome: paneChrome);
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

    // 1. Header: Document title "学习的底层逻辑", undo button, and close button with accessibility
    expect(find.text('学习的底层逻辑'), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-more-undo')), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-more-close')), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(find.byTooltip('撤销'), findsOneWidget);

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
    expect(find.byTooltip('返回'), findsOneWidget);

    // Back button returns to More sheet
    await tester.tap(find.byKey(const ValueKey('phone-appearance-back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('phone-sheet-more')), findsOneWidget);

    // Close button dismisses the sheet
    await tester.tap(find.byKey(const ValueKey('phone-more-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('phone-sheet-more')), findsNothing);
  });

  testWidgets('PhoneMoreSheet capabilities, switch document picker, reading settings and organize notes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final content = demoContent();
    final overrides = await testOverrides(
      // 整理笔记 is a Beta feature; this test covers its entry.
      prefs: {
        'settings.appearance': 'light',
        'settings.readerStyle': 'white',
        'settings.language': 'zh',
        'settings.betaFeaturesEnabled': true,
      },
      content: InMemoryStudySetContentRepository({'demo-1': content}),
    );

    final paneChrome = WorkspacePaneChromeController();
    var switchDocumentCalled = false;
    var readingSettingsCalled = false;
    var navigationCalled = false;
    var cropCalled = false;
    var organizeNotesCalled = false;

    paneChrome.bindReader(
      'test-owner',
      WorkspacePaneCommands('c1', {
        'reader-switch-document': WorkspacePaneCommand(() => switchDocumentCalled = true),
        'reader-settings': WorkspacePaneCommand(() => readingSettingsCalled = true),
        'reader-navigation': WorkspacePaneCommand(() => navigationCalled = true),
        'reader-crop': WorkspacePaneCommand(() => cropCalled = true),
        'reader-margin': WorkspacePaneCommand(() {}, selected: true),
      }),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [...overrides, touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: PhoneMoreSheet(
              studySetId: 'demo-1',
              paneChrome: paneChrome,
              onOrganizeNotes: () => organizeNotesCalled = true,
            ),
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

    // Reading settings appears because reader-settings is enabled
    expect(find.text('阅读设置'), findsOneWidget);

    // Verify Group 2 items
    expect(find.text('整理笔记'), findsOneWidget);
    expect(find.text('复习'), findsOneWidget);
    expect(find.text('生词本'), findsOneWidget);

    // Tap "切换文档": MUST execute reader-switch-document picker command, NOT auto-jump
    await tester.tap(find.text('切换文档'));
    await tester.pumpAndSettle();
    expect(switchDocumentCalled, isTrue);
    // Active document remains c1 (does not blindly cycle to next)
    expect(container.read(workspaceProvider('demo-1')).activeDocumentId, 'c1');

    // Tap "阅读设置": executes reader-settings command
    await tester.tap(find.text('阅读设置'));
    await tester.pumpAndSettle();
    expect(readingSettingsCalled, isTrue);

    // Tap "目录与书签": executes reader-navigation command
    await tester.tap(find.text('目录与书签'));
    await tester.pumpAndSettle();
    expect(navigationCalled, isTrue);

    // Tap "裁掉白边": executes reader-crop command
    await tester.tap(find.text('裁掉白边'));
    await tester.pumpAndSettle();
    expect(cropCalled, isTrue);

    // Tap "整理笔记": calls onOrganizeNotes callback
    await tester.tap(find.text('整理笔记'));
    await tester.pumpAndSettle();
    expect(organizeNotesCalled, isTrue);

    // Tap "复习": activates the workspace review tab
    await tester.tap(find.text('复习'));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).tabs.activeId, WorkspaceTab.review.id);
  });

  testWidgets('iPad and macOS isolation: original toolbar and dropdown menus remain intact', (tester) async {
    // 1. iPad tablet size (834 x 1194)
    final content = demoContent();
    final overrides = await testOverrides(
      prefs: {'settings.appearance': 'light', 'settings.readerStyle': 'white', 'settings.language': 'zh'},
      content: InMemoryStudySetContentRepository({'demo-1': content}),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides,
          touchPlatformProvider.overrideWithValue(true),
          phoneProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: LibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // iPad uses the standard MMToolbar with search field inside the toolbar or compact bottom, NOT phone glass buttons
    expect(find.byType(MMToolbar), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-workspace-more')), findsNothing);

    // 2. macOS desktop size (1200 x 800)
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides,
          touchPlatformProvider.overrideWithValue(false),
          phoneProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: LibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MMToolbar), findsOneWidget);
    // Standard view mode buttons present in toolbar on desktop
    expect(find.descendant(of: find.byType(MMToolbar), matching: find.byIcon(MMIcons.grid)), findsOneWidget);
    expect(find.descendant(of: find.byType(MMToolbar), matching: find.byIcon(MMIcons.list)), findsOneWidget);
  });
}
