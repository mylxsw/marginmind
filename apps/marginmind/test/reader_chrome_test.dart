import 'package:flutter/material.dart';
import 'package:marginmind/features/workspace/widgets/highlight_color_button.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';
import 'package:marginmind/settings/app_settings.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';
import 'reader_crop_test.dart' show drain;

Future<ProviderContainer> openSet(WidgetTester tester, {Size size = const Size(1280, 820)}) async {
  final container = await pumpApp(tester);
  tester.view.physicalSize = size;
  await tester.tap(find.text('Starred'));
  await tester.pumpAndSettle();
  await doubleTap(tester, find.text('认知科学入门'));
  return container;
}

String windowTitle(WidgetTester tester) => tester.widget<Title>(find.byType(Title).last).title;

bool selected(WidgetTester tester, IconData icon) => tester
    .widget<MMToolbarButton>(
      find.descendant(of: find.byType(MMToolbar), matching: find.widgetWithIcon(MMToolbarButton, icon)),
    )
    .selected;

/// Reported layout overflows (a toolbar narrower than any real window) are not under test.
void drainOverflow(WidgetTester tester) {
  while (tester.takeException() != null) {}
}

void main() {
  final provider = workspaceProvider('demo-1');

  for (final appearance in ['light', 'dark']) {
    testWidgets('reader buttons share foreground colors in $appearance', (tester) async {
      installTestPdfBackend();
      final container = await pumpApp(tester, renderPdf: true, prefs: {'settings.appearance': appearance});
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await drain(tester);
      final reader = find.byType(ReaderPane);
      final colors = tester.element(reader).mmColors;
      Color? paintedColor(IconData icon) {
        final glyph = find.descendant(of: reader, matching: find.byIcon(icon)).first;
        final text = tester.widget<RichText>(find.descendant(of: glyph, matching: find.byType(RichText)));
        return (text.text as TextSpan).style!.color;
      }

      for (final icon in [MMIcons.highlight, MMIcons.areaSelect, MMIcons.pen]) {
        expect(paintedColor(icon), colors.label, reason: 'Enabled toolbar icons use one foreground');
      }
      expect(paintedColor(MMIcons.select), colors.accent);
      await tester.tap(find.byKey(const ValueKey('reader-more')));
      await tester.pumpAndSettle();
      expect(find.text('White'), findsOneWidget);
      expect(find.byKey(const ValueKey('reader-margin')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drain(tester);
    });
  }

  group('window title (U-R5)', () {
    testWidgets('title is the document on one line without a page subtitle or single-document tab bar', (tester) async {
      final container = await openSet(tester);
      expect(container.read(provider).openDocumentIds, hasLength(1));
      expect(windowTitle(tester), '学习的底层逻辑 — 认知科学入门 — Foliarc');
      for (final bar in tester.widgetList<MMToolbar>(find.byType(MMToolbar))) {
        expect(bar.title, isEmpty);
        expect(bar.subtitle, isNull);
      }
      // The reader pane has no tab bar, so the document name is not repeated.
      expect(find.descendant(of: find.byType(ReaderPane), matching: find.text('学习的底层逻辑')), findsNothing);
    });

    for (final width in [1280.0, 900.0]) {
      testWidgets('all documents are available from entry at width $width', (tester) async {
        final container = await openSet(tester, size: Size(width, 820));
        final switcher = find.byKey(const ValueKey('reader-documents'));
        expect(container.read(provider).openDocumentIds, ['c1']);
        expect(switcher, findsOneWidget);
        expect(find.descendant(of: switcher, matching: find.byIcon(MMIcons.collections)), findsOneWidget);
        expect(find.descendant(of: switcher, matching: find.byIcon(MMIcons.document)), findsNothing);
        expect(find.descendant(of: switcher, matching: find.byIcon(MMIcons.chevronDown)), findsNothing);
        final reader = find.byType(ReaderPane);
        expect(find.descendant(of: reader, matching: find.text('学习的底层逻辑')), findsNothing);
        expect(tester.getRect(switcher).right, lessThanOrEqualTo(tester.getRect(reader).right));

        await tester.tap(switcher);
        await tester.pumpAndSettle();
        final current = find.ancestor(of: find.text('学习的底层逻辑').last, matching: find.byType(MMDropdownItem<String>));
        expect(find.descendant(of: current, matching: find.byIcon(MMIcons.check)), findsOneWidget);
        final other = find.text('论文：检索练习效应').last;
        final label = tester.widget<Text>(other);
        expect(label.style!.fontSize, 12);
        expect(label.style!.fontWeight, FontWeight.w500);
        final otherRow = find.ancestor(of: other, matching: find.byType(MMDropdownItem<String>));
        expect(tester.getSize(otherRow).height, 30);
        final closeLabel = tester.widget<Text>(find.text('Close Current Document'));
        expect(closeLabel.style, label.style);
        expect(tester.getRect(find.text('Close Current Document')).left, tester.getRect(other).left);

        // The second document has never been clicked in the sidebar.
        await tester.tap(other);
        await tester.pumpAndSettle();
        expect(container.read(provider).activeDocumentId, 'c2');
        expect(windowTitle(tester), '论文：检索练习效应 — 认知科学入门 — Foliarc');
        expect(container.read(provider).openDocumentIds, ['c1', 'c2']);

        await tester.tap(switcher);
        await tester.pumpAndSettle();
        await tester.tap(find.text('论文：检索练习效应').last);
        await tester.pumpAndSettle();
        expect(container.read(provider).openDocumentIds, ['c1', 'c2']);
        await tester.tap(switcher);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Close Current Document'));
        await tester.pumpAndSettle();
        expect(container.read(provider).openDocumentIds, ['c1']);
        expect(container.read(provider).activeDocumentId, 'c1');
        expect(switcher, findsOneWidget);
        // Closing a viewer never removes its document from the switcher.
        await tester.tap(switcher);
        await tester.pumpAndSettle();
        expect(find.text('论文：检索练习效应').last, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('closing the last viewer leaves the menu available to reopen it', (tester) async {
      final container = await openSet(tester);
      final switcher = find.byKey(const ValueKey('reader-documents'));
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close Current Document'));
      await tester.pumpAndSettle();
      expect(container.read(provider).activeDocumentId, isNull);
      expect(switcher, findsOneWidget);
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      final close = find.ancestor(
        of: find.text('Close Current Document'),
        matching: find.byType(MMDropdownItem<String>),
      );
      expect(tester.widget<PopupMenuItem<String>>(close).enabled, isFalse);
      await tester.tap(find.text('学习的底层逻辑').last);
      await tester.pumpAndSettle();
      expect(container.read(provider).activeDocumentId, 'c1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('reader tools control the sidebar and appearance separately', (tester) async {
      final container = await openSet(tester);
      final menu = find.byKey(const ValueKey('reader-more'));
      expect(find.descendant(of: find.byType(ReaderPane), matching: menu), findsOneWidget);
      expect(find.descendant(of: find.byType(MMToolbar), matching: menu), findsOneWidget);
      expect(container.read(provider).readerPanelVisible, isFalse);
      await tapReaderCommand(tester, find.byKey(const ValueKey('reader-navigation')));
      await tester.pumpAndSettle();
      expect(container.read(provider).readerPanelVisible, isTrue);
      await tapReaderCommand(tester, find.byKey(const ValueKey('reader-navigation')));
      await tester.pumpAndSettle();
      expect(container.read(provider).readerPanelVisible, isFalse);
      for (final (label, style) in [
        ('Dark', MMReaderStyle.dark),
        ('Paper', MMReaderStyle.paper),
        ('Light Green', MMReaderStyle.green),
        ('White', MMReaderStyle.white),
      ]) {
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(container.read(settingsProvider).readerStyle, style);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.text(label), findsOneWidget);
        expect(find.byIcon(MMIcons.check), findsWidgets);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      container.read(provider.notifier).setLayout(MMSplitMode.secondary);
      await tester.pumpAndSettle();
      expect(menu.hitTestable(), findsNothing);
    });
  });

  group('narrow window (U-R6)', () {
    testWidgets('wide window keeps sidebar and split', (tester) async {
      await openSet(tester, size: const Size(1400, 820));
      expect(find.text('Mind Maps').hitTestable(), findsOneWidget);
      expect(selected(tester, MMIcons.layoutSplit), isTrue);
    });

    testWidgets('narrowing preserves the sidebar and temporarily shows the reader', (tester) async {
      final container = await openSet(tester, size: const Size(960, 820));
      expect(container.read(provider).sidebarVisible, isTrue, reason: 'the preference is untouched');
      expect(find.text('Mind Maps').hitTestable(), findsOneWidget);
      expect(selected(tester, MMIcons.layoutReader), isTrue);
      expect(find.byType(MapPane).hitTestable(), findsNothing);
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

    testWidgets('hiding the sidebar restores split without changing layout preference', (tester) async {
      final container = await openSet(tester, size: const Size(1000, 820));
      await tester.tap(find.byIcon(MMIcons.sidebar).hitTestable().first);
      await tester.pumpAndSettle();
      expect(container.read(provider).layout, MMSplitMode.split);
      expect(find.text('Mind Maps').hitTestable(), findsNothing);
      expect(find.byType(MapPane).hitTestable(), findsOneWidget);
    });
  });

  group('sidebar commands with no room for it', () {
    testWidgets('sidebar toggles independently and split resumes when space is available', (tester) async {
      final container = await openSet(tester, size: const Size(900, 820));
      expect(container.read(provider).sidebarAutoCollapsed, isFalse);
      expect(find.text('Mind Maps').hitTestable(), findsOneWidget);
      container.read(provider.notifier).toggleSidebar();
      await tester.pumpAndSettle();
      expect(container.read(provider).layout, MMSplitMode.split);
      expect(find.text('Mind Maps').hitTestable(), findsNothing);
      expect(find.byType(MapPane).hitTestable(), findsOneWidget);
      container.read(provider.notifier).toggleSidebar();
      await tester.pumpAndSettle();
      expect(find.text('Mind Maps').hitTestable(), findsOneWidget);
      expect(find.byType(MapPane).hitTestable(), findsNothing);
    });

    testWidgets('find in the sidebar brings it back and focuses the search field', (tester) async {
      final container = await openSet(tester, size: const Size(900, 820));
      await tester.pumpAndSettle();
      container.read(focusRequestsProvider.notifier).request(FocusTarget.search);
      await tester.pumpAndSettle();
      expect(find.text('Mind Maps').hitTestable(), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.focusNode?.hasFocus, isTrue);
    });

    testWidgets('a hidden sidebar is shown by the same commands in a wide window', (tester) async {
      final container = await openSet(tester, size: const Size(1400, 820));
      container.read(provider.notifier).toggleSidebar();
      await tester.pumpAndSettle();
      expect(find.text('Mind Maps').hitTestable(), findsNothing);
      container.read(focusRequestsProvider.notifier).request(FocusTarget.search);
      await tester.pumpAndSettle();
      expect(container.read(provider).sidebarVisible, isTrue);
      expect(container.read(provider).layout, MMSplitMode.split);
      expect(find.text('Mind Maps').hitTestable(), findsOneWidget);
    });
  });

  testWidgets('toolbar holds tools only; colors live in one pop-up (U-X5)', (tester) async {
    final container = await openSet(tester);
    expect(find.byType(HighlightColorButton), findsOneWidget);
    expect(find.byType(MMColorMenuButton), findsNothing);
    expect(find.byType(MMColorPicker), findsNothing);
    await tester.tap(find.byType(HighlightColorButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More Colors'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Pink'));
    await tester.pumpAndSettle();
    expect(container.read(provider).color, MMAnnotationColor.pink);
    expect(find.byType(MMColorPicker), findsNothing);
  });
}
