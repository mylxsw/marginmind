import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/assistant/settings/model_settings.dart' show showServiceList;
import 'package:marginmind/features/assistant/widgets/assistant_quick_actions.dart';
import 'package:marginmind/features/workspace/widgets/annotation_color_button.dart';
import 'package:marginmind/features/workspace/widgets/highlight_color_button.dart';
import 'package:marginmind/features/workspace/widgets/reading_settings.dart';
import 'package:marginmind/features/workspace/widgets/selection_translation.dart';
import 'package:marginmind/features/workspace/widgets/selection_toolbar.dart';
import 'package:marginmind/features/workspace/widgets/underline_style_toolbar.dart';
import 'package:marginmind/features/workspace/widgets/underline_tool_button.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'selection_toolbar_test.dart' show selection;

void expectFullyVisible(WidgetTester tester, Finder surface) {
  expect(surface.hitTestable(), findsOneWidget);
  for (final fade in tester.widgetList<FadeTransition>(
    find.ancestor(of: surface, matching: find.byType(FadeTransition)),
  )) {
    expect(fade.opacity.value, 1, reason: 'a popup must not fade in after its first frame');
  }
}

void main() {
  testWidgets('highlighter palette and color application never wait for preference persistence', (tester) async {
    final saving = Completer<void>();
    MMAnnotationColor? picked;
    await tester.pumpWidget(
      ProviderScope(
        overrides: await testOverrides(),
        child: MaterialApp(
          theme: MMTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: HighlightColorButton(
              color: MMAnnotationColor.yellow,
              onOpen: () => saving.future,
              onChanged: (color) async => picked = color,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(HighlightColorButton));
    await tester.pump();
    expectFullyVisible(tester, find.byKey(const ValueKey('highlight-color-palette')));
    expect(saving.isCompleted, isFalse);
    await tester.tap(find.byTooltip('Green'));
    await tester.pump();
    expect(picked, MMAnnotationColor.green);
    expect(find.byKey(const ValueKey('highlight-color-palette')), findsNothing);
    saving.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('page and selection palettes appear fully visible on their first frame', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    await tester.tap(find.byType(HighlightColorButton).first);
    await tester.pump();
    expectFullyVisible(tester, find.byKey(const ValueKey('highlight-color-palette')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(UnderlineToolButton));
    await tester.pump();
    expectFullyVisible(tester, find.byType(UnderlineStyleToolbar));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await controller.onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AnnotationColorButton));
    await tester.pump();
    expectFullyVisible(tester, find.byKey(const ValueKey('annotation-color-palette')));
    await tester.tap(find.byTooltip('More Colors'));
    await tester.pump();
    expectFullyVisible(tester, find.byKey(const ValueKey('highlight-custom-color-picker')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  for (final tool in [AnnotationTool.highlight, AnnotationTool.underline]) {
    testWidgets('selection ${tool.name} starts neutral, applies once and dismisses without arming a pen', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final provider = workspaceProvider('demo-1');
      final controller = container.read(provider.notifier);
      final before = controller.content.annotations.length;
      await controller.onSelectionCommitted('c1', selection);
      await tester.pumpAndSettle();
      for (final key in ['selection-highlight', 'selection-underline']) {
        expect(tester.widget<MMToolbarButton>(find.byKey(ValueKey(key))).selected, isFalse);
      }
      await tester.tap(find.byKey(ValueKey('selection-${tool.name}')));
      await tester.pumpAndSettle();
      expect(controller.content.annotations.length, before + 1);
      expect(controller.content.annotations.last.kind.name, tool.name);
      expect(container.read(provider).tool, AnnotationTool.select);
      expect(container.read(provider).pending, isNull);
      expect(find.byType(SelectionToolbar), findsNothing);
      await controller.undo();
      await tester.pumpAndSettle();
      expect(controller.content.annotations.length, before);
      await controller.onSelectionCommitted('c1', selection);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(900, 650));
      await tester.pumpAndSettle();
      expect(controller.content.annotations.length, before, reason: 'dismissing a selection never applies a marker');
      expect(find.byType(SelectionToolbar), findsNothing);
    });
  }

  testWidgets('reading, translation, AI and service popovers are complete in their first frame', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reading Settings'));
    await tester.pump();
    expectFullyVisible(tester, find.byType(ReadingSettingsPanel));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final controller = container.read(workspaceProvider('demo-1').notifier);
    await controller.onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-translate')));
    await tester.pump();
    expectFullyVisible(tester, find.byType(SelectionTranslation));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-assistant')));
    await tester.pump();
    expectFullyVisible(tester, find.byType(AssistantQuickActions));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    showServiceList(tester.element(find.byType(SelectionToolbar)));
    await tester.pump();
    expectFullyVisible(tester, find.byKey(const ValueKey('service-list')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });
}
