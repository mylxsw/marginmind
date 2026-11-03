import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/app.dart' show touchPlatformProvider, phoneProvider;
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/quick_tasks.dart';
import 'package:marginmind/features/assistant/widgets/assistant_quick_actions.dart';
import 'package:marginmind/features/assistant/widgets/expansion_widgets.dart' show ExpansionSection;
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/widgets/selection_lookup.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/widgets/selection_translation.dart';
import 'package:marginmind/features/workspace/word_lookup.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import 'helpers.dart';
import 'reader_translation_test.dart' show model;
import 'selection_lookup_test.dart' show LookupFixture, lookupResult;
import 'selection_translation_test.dart' show SelectionTestTranslator;

void main() {
  for (final dark in [false, true]) {
    testWidgets('phone lookup, translation and quick actions use the shared frame (${dark ? 'dark' : 'light'})', (
      tester,
    ) async {
      final lookup = LookupFixture();
      final translator = SelectionTestTranslator();
      final container = await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'settings.appearance': dark ? 'dark' : 'light', 'settings.language': 'zh'},
        overrides: [
          touchPlatformProvider.overrideWithValue(true),
          phoneProvider.overrideWithValue(true),
          assistantDefaultModelProvider.overrideWithValue(model),
          wordLookupProvider('demo-1').overrideWithValue(lookup),
          selectionTranslatorProvider('demo-1').overrideWithValue(() async => translator),
        ],
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      BuildContext context() => tester.element(find.byType(ReaderPane));
      final viewport = const Rect.fromLTWH(0, 0, 390, 844);
      void safeFrame() {
        final rect = tester.getRect(find.byKey(const ValueKey('mm-bottom-sheet')));
        expect(rect.left, greaterThan(0));
        expect(rect.right, lessThan(390));
        expect(rect.bottom, lessThan(844));
        expect(tester.takeException(), isNull);
      }

      unawaited(
        showSelectionLookup(
          context(),
          studySetId: 'demo-1',
          paragraph: TranslationParagraph(documentId: 'c1', page: 1, index: 0, text: 'meticulous', fingerprint: ''),
          toolbar: const Rect.fromLTWH(10, 100, 300, 44),
          selection: Rect.zero,
          viewport: viewport,
        ),
      );
      await tester.pump();
      lookup.pending.complete(lookupResult);
      await tester.pumpAndSettle();
      expect(find.byType(SelectionLookup), findsOneWidget);
      safeFrame();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SelectionLookup), findsNothing);
      unawaited(
        showSelectionTranslation(
          context(),
          studySetId: 'demo-1',
          paragraph: TranslationParagraph(
            documentId: 'c1',
            page: 1,
            index: 0,
            text: 'A sample sentence.',
            fingerprint: '',
          ),
          toolbar: const Rect.fromLTWH(10, 100, 300, 44),
          selection: Rect.zero,
          viewport: viewport,
        ),
      );
      await tester.pump();
      translator.pending.complete(const ParagraphTranslation('测试译文'));
      await tester.pumpAndSettle();
      expect(find.text('测试译文'), findsOneWidget);
      safeFrame();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      unawaited(
        showAssistantQuickActions(
          context(),
          studySetId: 'demo-1',
          passage: const ContextItem(id: 'passage', kind: ContextKind.selection, displayText: 'Sample passage'),
          origin: PanelOrigin.map,
          insertionTarget: (mapId: container.read(workspaceProvider('demo-1')).activeMapId, parentId: null),
          toolbar: const Rect.fromLTWH(10, 100, 300, 44),
          selection: Rect.zero,
          viewport: viewport,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AssistantQuickActions), findsOneWidget);
      safeFrame();
      await tester.tap(find.byKey(const ValueKey('quick-expand-ideas')));
      await tester.pumpAndSettle();
      expect(find.byType(ExpansionSection), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ExpansionSection), findsNothing);
      expect(find.byType(AssistantQuickActions), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AssistantQuickActions), findsNothing);
    }, variant: TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));
  }
}
