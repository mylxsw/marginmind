import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

Future<ProviderContainer> openSet(WidgetTester tester, {Size size = const Size(1280, 820)}) async {
  final container = await pumpApp(tester);
  tester.view.physicalSize = size;
  await tester.tap(find.text('Starred'));
  await tester.pumpAndSettle();
  await doubleTap(tester, find.text('认知科学入门'));
  return container;
}

MMToolbar toolbar(WidgetTester tester) => tester.widget<MMToolbar>(find.byType(MMToolbar));

bool selected(WidgetTester tester, IconData icon) =>
    tester.widget<MMToolbarButton>(find.widgetWithIcon(MMToolbarButton, icon)).selected;

/// Reported layout overflows (a toolbar narrower than any real window) are not under test.
void drainOverflow(WidgetTester tester) {
  while (tester.takeException() != null) {}
}

void main() {
  final provider = workspaceProvider('demo-1');

  group('window title (U-R5)', () {
    testWidgets('title is the document, subtitle only the page, no tab bar for one document', (tester) async {
      final container = await openSet(tester);
      expect(container.read(provider).openDocumentIds, hasLength(1));
      final bar = toolbar(tester);
      expect(bar.title, '学习的底层逻辑');
      expect(bar.subtitle, 'Page ${container.read(provider).content?.document('c1')?.lastPage ?? 1}');
      expect(bar.subtitle, isNot(contains('认知科学入门')));
      // The reader pane has no tab bar, so the document name is not repeated.
      expect(find.descendant(of: find.byType(ReaderPane), matching: find.text('学习的底层逻辑')), findsNothing);
    });

    testWidgets('a second document brings the tab bar back; closing it hides it again', (tester) async {
      final container = await openSet(tester);
      container.read(provider.notifier).openDocument('c2');
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(ReaderPane), matching: find.text('学习的底层逻辑')), findsOneWidget);
      expect(find.descendant(of: find.byType(ReaderPane), matching: find.text('论文：检索练习效应')), findsOneWidget);
      container.read(provider.notifier).closeDocument('c2');
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(ReaderPane), matching: find.text('论文：检索练习效应')), findsNothing);
    });

    testWidgets('the page sidebar toggle lives in the toolbar', (tester) async {
      final container = await openSet(tester);
      expect(container.read(provider).readerPanelVisible, isFalse);
      await tester.tap(find.byTooltip(RegExp('Show Page Sidebar')));
      await tester.pumpAndSettle();
      expect(container.read(provider).readerPanelVisible, isTrue);
      expect(find.byTooltip(RegExp('Hide Page Sidebar')), findsOneWidget);
      container.read(provider.notifier).setLayout(MMSplitMode.secondary);
      await tester.pumpAndSettle();
      expect(find.byTooltip(RegExp('Hide Page Sidebar')), findsNothing);
    });
  });

  group('narrow window (U-R6)', () {
    testWidgets('wide window keeps sidebar and split', (tester) async {
      await openSet(tester, size: const Size(1400, 820));
      expect(find.text('Mind Maps').hitTestable(), findsOneWidget);
      expect(selected(tester, MMIcons.layoutSplit), isTrue);
    });

    testWidgets('narrowing collapses the sidebar first and keeps split', (tester) async {
      final container = await openSet(tester, size: const Size(960, 820));
      expect(container.read(provider).sidebarVisible, isTrue, reason: 'the preference is untouched');
      expect(find.text('Mind Maps').hitTestable(), findsNothing);
      expect(selected(tester, MMIcons.layoutSplit), isTrue);
      expect(find.byType(MapPane).hitTestable(), findsOneWidget);
    });

    testWidgets('then falls back to the reader and the layout button says so', (tester) async {
      final container = await openSet(tester, size: const Size(760, 820));
      // Below the window minimum the toolbar itself no longer fits; only the layout is under test.
      drainOverflow(tester);
      expect(container.read(provider).layout, MMSplitMode.split, reason: 'the preference is untouched');
      expect(selected(tester, MMIcons.layoutReader), isTrue);
      expect(selected(tester, MMIcons.layoutSplit), isFalse);
      expect(find.byType(MapPane).hitTestable(), findsNothing);
      drainOverflow(tester);
    });

    testWidgets('widening restores the sidebar', (tester) async {
      await openSet(tester, size: const Size(960, 820));
      tester.view.physicalSize = const Size(1400, 820);
      await tester.pumpAndSettle();
      expect(find.text('Mind Maps').hitTestable(), findsOneWidget);
    });

    testWidgets('showing the sidebar when it has no room switches to the reader', (tester) async {
      final container = await openSet(tester, size: const Size(1000, 820));
      await tester.tap(find.byIcon(MMIcons.sidebar).hitTestable().first);
      await tester.pumpAndSettle();
      expect(container.read(provider).layout, MMSplitMode.primary);
      expect(find.text('Mind Maps').hitTestable(), findsOneWidget);
    });
  });

  testWidgets('toolbar holds tools only; colors live in one pop-up (U-X5)', (tester) async {
    final container = await openSet(tester);
    expect(find.byType(MMColorMenuButton), findsOneWidget);
    expect(find.byType(MMColorPicker), findsNothing);
    await tester.tap(find.byType(MMColorMenuButton));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Pink'));
    await tester.pumpAndSettle();
    expect(container.read(provider).color, MMAnnotationColor.pink);
    expect(find.byType(MMColorPicker), findsNothing);
  });
}
