import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'helpers.dart';

void main() {
  const selection = MMPdfSelection(page: 1, rects: [PageRect(1, 2, 30, 10)], text: '选区');

  test('tool defaults, persists in both directions and restores after restart', () async {
    final overrides = await testOverrides();
    var container = ProviderContainer(overrides: overrides);
    expect(container.read(workspaceProvider('demo-1')).tool, AnnotationTool.select);
    await container.read(workspaceProvider('demo-1').notifier).setTool(AnnotationTool.highlight);
    expect(container.read(sharedPreferencesProvider).getString('settings.annotationTool'), 'highlight');
    container.dispose();
    container = ProviderContainer(overrides: overrides);
    expect(container.read(workspaceProvider('demo-1')).tool, AnnotationTool.highlight);
    await container.read(workspaceProvider('demo-1').notifier).setTool(AnnotationTool.select);
    container.dispose();
    container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    expect(container.read(workspaceProvider('demo-1')).tool, AnnotationTool.select);
  });

  test('unknown saved tool falls back to select', () async {
    final container = ProviderContainer(overrides: await testOverrides(prefs: {'settings.annotationTool': 'unknown'}));
    addTearDown(container.dispose);
    expect(container.read(workspaceProvider('demo-1')).tool, AnnotationTool.select);
  });

  test('switching clears pending actions and preserves color and sync', () async {
    final container = ProviderContainer(overrides: await testOverrides());
    addTearDown(container.dispose);
    container.listen(workspaceProvider('demo-1'), (_, _) {});
    container.listen(workspaceProvider('other'), (_, _) {});
    await container.read(contentProvider('demo-1').future);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    expect(await controller.onSelectionCommitted('c1', selection), isNull);
    expect(controller.content.annotations, hasLength(1));
    expect(container.read(workspaceProvider('demo-1')).pending, isA<PendingSelection>());
    await controller.setColor(MMAnnotationColor.blue);
    expect(container.read(sharedPreferencesProvider).getString('settings.annotationTool'), 'highlight');
    expect(container.read(workspaceProvider('demo-1')).pending, isNull);
    expect(container.read(workspaceProvider('other')).tool, AnnotationTool.highlight);
    controller.toggleSyncToMap();
    expect(await controller.onSelectionCommitted('c1', selection), isA<HighlightedNotice>());
    expect(controller.content.annotations.last.colorIndex, MMAnnotationColor.blue.index);
    await controller.toggleTool();
    expect(await controller.onSelectionCommitted('c1', selection), isNull);
    expect(controller.content.annotations, hasLength(2));
    await controller.toggleTool();
    expect(container.read(workspaceProvider('demo-1')).pending, isNull);
    expect(container.read(workspaceProvider('demo-1')).color, MMAnnotationColor.blue);
    expect(container.read(workspaceProvider('demo-1')).syncToMap, isFalse);
    await container.read(settingsProvider.notifier).setLanguage(LanguagePreference.zh);
    expect(container.read(workspaceProvider('demo-1')).syncToMap, isFalse);
  });

  test('choosing a color in highlight mode preserves the pending highlight', () async {
    final container = ProviderContainer(overrides: await testOverrides());
    addTearDown(container.dispose);
    final provider = workspaceProvider('demo-1');
    container.listen(provider, (_, _) {});
    await container.read(contentProvider('demo-1').future);
    final controller = container.read(provider.notifier);
    await controller.setTool(AnnotationTool.highlight);
    controller.toggleSyncToMap();
    await controller.onSelectionCommitted('c1', selection);
    final annotationId = controller.content.annotations.last.id;
    controller.tapHighlight(annotationId);
    final pending = container.read(provider).pending;
    expect(pending, isA<PendingHighlight>());
    expect((pending as PendingHighlight).annotationId, annotationId);

    await controller.setColor(MMAnnotationColor.blue);

    expect(container.read(provider).pending, same(pending));
    expect(container.read(provider).color, MMAnnotationColor.blue);
    expect(container.read(provider).tool, AnnotationTool.highlight);
    expect(container.read(sharedPreferencesProvider).getString('settings.annotationTool'), 'highlight');
    // Switching to a different tool must still dismiss the pending action.
    await controller.setTool(AnnotationTool.select);
    expect(container.read(provider).pending, isNull);
  });

  testWidgets('shortcut and toolbar choose the same tool and selection behavior', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final provider = workspaceProvider('demo-1');
    final controller = container.read(provider.notifier);
    expect(container.read(provider).tool, AnnotationTool.select);
    await controller.onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
    expect(container.read(provider).pending, isA<PendingSelection>());
    final shortcut = AppShortcuts.toggleAnnotationTool;
    Future<void> toggle() async {
      final modifier = shortcut.meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(shortcut.trigger);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
    }

    await toggle();
    expect(container.read(provider).tool, AnnotationTool.highlight);
    expect(container.read(provider).pending, isNull);
    expect(await controller.onSelectionCommitted('c1', selection), isA<ExcerptedNotice>());
    await tester.tap(find.byIcon(MMIcons.select));
    await tester.pumpAndSettle();
    expect(container.read(provider).tool, AnnotationTool.select);
    await tester.tap(find.byIcon(MMIcons.highlight));
    await tester.pumpAndSettle();
    expect(container.read(provider).tool, AnnotationTool.highlight);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await controller.onSelectionCommitted('c1', selection), isA<ExcerptedNotice>());
    await toggle();
    expect(container.read(provider).tool, AnnotationTool.select);
    expect(await controller.onSelectionCommitted('c1', selection), isNull);
    await settleHud(tester);
  });
}
