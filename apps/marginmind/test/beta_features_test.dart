import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/map_generation/widgets/map_empty_state.dart';
import 'package:marginmind/features/study_notes/note_view.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'study_notes_ui_test.dart' show noteFixture;

void main() {
  testWidgets('Settings General page has Advanced card with Enable Beta Features switch', (tester) async {
    final container = await pumpApp(
      tester,
      prefs: const {'settings.language': 'zh'},
    );
    expect(container.read(settingsProvider).betaFeaturesEnabled, isFalse);

    final context = tester.element(find.byType(Navigator).first);
    showSettings(context);
    await tester.pumpAndSettle();

    expect(find.text('高级'), findsOneWidget);
    expect(find.text('启用 Beta 功能'), findsOneWidget);
    final betaSwitch = find.byKey(const ValueKey('settings-beta-features'));
    expect(betaSwitch, findsOneWidget);
    expect(tester.widget<MMSwitch>(betaSwitch).value, isFalse);

    await tester.ensureVisible(betaSwitch);
    await tester.tap(betaSwitch);
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).betaFeaturesEnabled, isTrue);
    expect(container.read(sharedPreferencesProvider).getBool('settings.betaFeaturesEnabled'), isTrue);

    // Maps settings page still shows clear generation cache regardless of Beta toggle
    await tester.tap(find.byKey(const ValueKey('settings-beta-features')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).betaFeaturesEnabled, isFalse);
    await tester.tap(find.text('脑图').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('map-cache-clear')), findsOneWidget);
  });

  testWidgets('Beta features are hidden by default and shown with Beta badge when enabled', (tester) async {
    final container = await pumpApp(
      tester,
      size: const Size(1440, 900),
      prefs: const {'settings.language': 'zh'},
      content: InMemoryStudySetContentRepository({'demo-1': noteFixture()}),
      overrides: [
        assistantCredentialStateProvider.overrideWith((ref) async => AssistantCredentialState.ready),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();

    final ws = container.read(workspaceProvider('demo-1').notifier);

    // 1. Default (betaFeaturesEnabled == false):
    // Study notes section is hidden in sidebar
    expect(find.byKey(const ValueKey('sidebar-note-written')), findsNothing);
    expect(find.byType(MMBetaBadge), findsNothing);

    // Clicking add-map-menu directly opens NewMapSheet instead of a dropdown with "从文档生成…"
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.byKey(ValueKey('sidebar-map-${MindMap.defaultId}'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-map-menu')));
    await tester.pumpAndSettle();
    expect(find.text('从文档生成…'), findsNothing);
    expect(find.text('新建脑图…'), findsOneWidget);
    Navigator.of(tester.element(find.byType(Navigator).first)).pop();
    await tester.pumpAndSettle();

    // Empty map does NOT show MapEmptyState when beta is disabled
    await ws.addMap('空白脑图');
    await tester.pumpAndSettle();
    expect(find.byType(MapEmptyState), findsNothing);

    // Opening a document without an associated map does NOT show document-map-banner
    ws.openDocument('c2');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('document-map-banner')), findsNothing);

    // Reader annotations panel hides select-all and checkboxes when beta is disabled
    ws.showReaderPanel(ReaderPanelMode.annotations);
    ws.openDocument('c1');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('annotations-select-all')), findsNothing);
    expect(find.byKey(const ValueKey('annotation-check-c5')), findsNothing);

    // Node context menu does not show "整理选中项…", but still shows "拓展思路" without Beta badge
    ws.toggleReaderPanel();
    await ws.selectMap(MindMap.defaultId);
    await tester.pumpAndSettle();
    final topicFinder = find.text('遗忘的规律');
    expect(topicFinder, findsOneWidget);
    await tester.tap(topicFinder, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('整理选中项…'), findsNothing);
    expect(find.text('扩展想法'), findsOneWidget);
    // Dismiss menu
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 2. Enable Beta features:
    await container.read(settingsProvider.notifier).setBetaFeaturesEnabled(true);
    await tester.pumpAndSettle();

    // Study notes section appears in sidebar with MMBetaBadge
    expect(find.byKey(const ValueKey('sidebar-note-written')), findsOneWidget);
    expect(find.byType(MMBetaBadge), findsWidgets);

    // Reader annotations panel shows select-all and checkboxes
    ws.showReaderPanel(ReaderPanelMode.annotations);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('annotations-select-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('annotation-check-c5')), findsOneWidget);
    ws.toggleReaderPanel();
    await tester.pumpAndSettle();

    // Clicking add-map-menu shows dropdown with "从文档生成…" and MMBetaBadge
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.byKey(ValueKey('sidebar-map-${MindMap.defaultId}'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-map-menu')));
    await tester.pumpAndSettle();
    expect(find.text('从文档生成…'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Document context menu shows "生成脑图…" with MMBetaBadge
    await tester.tap(find.byKey(const ValueKey('document-row-c1')), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('生成脑图…'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Switching to the empty map shows MapEmptyState
    final emptyMap = ws.content.maps.firstWhere((m) => m.title == '空白脑图');
    await ws.selectMap(emptyMap.id);
    await tester.pumpAndSettle();
    expect(find.byType(MapEmptyState), findsOneWidget);

    // Opening a study note tab, then disabling Beta features closes the note tab
    ws.openStudyNote('written');
    await tester.pumpAndSettle();
    expect(find.byType(StudyNoteView), findsOneWidget);
    expect(container.read(workspaceProvider('demo-1')).activeNoteId, 'written');

    await container.read(settingsProvider.notifier).setBetaFeaturesEnabled(false);
    await tester.pumpAndSettle();
    expect(find.byType(StudyNoteView), findsNothing);
    expect(container.read(workspaceProvider('demo-1')).activeNoteId, isNull);
    await settleHud(tester);
  });
}
