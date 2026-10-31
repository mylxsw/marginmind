import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/workspace/phone_reader_controls_controller.dart';
import 'package:marginmind/features/workspace/workspace_chrome_controller.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/widgets/phone_reader_controls.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/app/providers.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';
import 'reader_crop_test.dart' show drain;
import 'reflow_fixtures.dart';

Finder key(String value) => find.byKey(ValueKey('phone-reader-$value'));

void main() {
  testWidgets('slot transitions, timer restart, gesture competition and document/dispose cancellation', (tester) async {
    final slots = PhoneReaderControlsController();
    slots.reset('a');
    expect(slots.slot, PhoneReaderSlot.page);
    slots.openScrub();
    slots.setScrubbing(true);
    slots.onReadingScroll();
    expect(slots.slot, PhoneReaderSlot.scrub);
    slots.setScrubbing(false);
    slots.onReadingScroll();
    expect(slots.slot, PhoneReaderSlot.page);
    slots.openTools();
    slots.setDrawing(true);
    slots.onReadingScroll();
    expect(slots.slot, PhoneReaderSlot.tools);
    slots.annotationCompleted('a');
    await tester.pump(const Duration(milliseconds: 700));
    expect(slots.slot, PhoneReaderSlot.tools, reason: 'A late save must not collapse the next active stroke');
    slots.setDrawing(false);
    slots.annotationCompleted('a');
    await tester.pump(const Duration(milliseconds: 640));
    slots.annotationCompleted('a');
    await tester.pump(const Duration(milliseconds: 640));
    expect(slots.slot, PhoneReaderSlot.tools);
    await tester.pump(const Duration(milliseconds: 10));
    expect(slots.slot, PhoneReaderSlot.orb);
    slots.openScrub();
    slots.closeScrub();
    expect(slots.slot, PhoneReaderSlot.orb);
    slots.openTools();
    slots.annotationCompleted('a');
    slots.colorChanged();
    await tester.pump(const Duration(seconds: 1));
    expect(slots.slot, PhoneReaderSlot.tools);
    slots.onBodyTap();
    expect(slots.slot, PhoneReaderSlot.orb);
    slots.selectTool(selection: true);
    await tester.pump(const Duration(milliseconds: 499));
    expect(slots.slot, PhoneReaderSlot.tools);
    await tester.pump(const Duration(milliseconds: 1));
    expect(slots.slot, PhoneReaderSlot.orb);
    slots.openTools();
    slots.annotationCompleted('a');
    slots.reset('b');
    slots.openTools();
    slots.annotationCompleted('a');
    await tester.pump(const Duration(seconds: 1));
    expect(slots.slot, PhoneReaderSlot.tools);
    slots.dock(right: false);
    slots.exitTools();
    expect(slots.dockRight, isFalse);
    expect(slots.slot, PhoneReaderSlot.page);
    slots.selectTool(selection: true);
    slots.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('phone reading controls complete navigation, annotations, docking and immersion ($dark)', (
      tester,
    ) async {
      installTestPdfBackend(pageCount: 12);
      final container = await pumpApp(
        tester,
        renderPdf: true,
        size: const Size(393, 852),
        prefs: {'settings.appearance': dark ? 'dark' : 'light'},
        overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await drain(tester);
      final element = tester.element(find.byType(ReaderPane));
      final slots = PhoneReaderControlsScope.maybeOf(element)!;
      final chrome = WorkspaceChromeScope.maybeOf(element)!;
      final workspace = container.read(workspaceProvider('demo-1').notifier);
      final pdf = tester.widget<MMPdfView>(find.byType(MMPdfView)).controller;
      expect(find.byType(PhoneReaderTopControls), findsOneWidget);
      expect(find.byType(MMThumbDockScope), findsNothing);
      expect(find.byKey(const ValueKey('reader-page-navigation')), findsNothing);
      expect(key('page').hitTestable(), findsOneWidget);
      expect(key('orb'), findsNothing);
      expect(tester.getSize(key('page')).height, greaterThanOrEqualTo(44));
      await tester.tap(key('page'));
      await tester.pumpAndSettle();
      expect(key('scrub'), findsOneWidget);
      expect(key('page'), findsNothing);
      final slider = tester.widget<Slider>(key('slider'));
      slider.onChangeStart!(6);
      slider.onChanged!(6);
      await drain(tester);
      expect(pdf.currentPage, 6);
      slider.onChangeEnd!(6);
      await tester.tap(key('scrub-close'));
      await tester.pumpAndSettle();
      expect(slots.slot, PhoneReaderSlot.page);
      await tester.tap(find.byKey(const ValueKey('phone-workspace-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annotation tools'));
      await tester.pumpAndSettle();
      expect(key('tools'), findsOneWidget);
      expect(key('page'), findsNothing);
      await tester.tap(key('tool-highlight'));
      await tester.pumpAndSettle();
      expect(key('colors'), findsOneWidget);
      expect(container.read(workspaceProvider('demo-1')).tool, AnnotationTool.highlight);
      await tester.tap(find.byTooltip('Green').last);
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).color, MMAnnotationColor.green);
      final sync = container.read(workspaceProvider('demo-1')).syncToMap;
      await tester.tap(key('sync'));
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).syncToMap, !sync);
      final before = workspace.content.annotations.length;
      await workspace.onSelectionCommitted(
        'c1',
        const MMPdfSelection(text: 'A source passage', page: 6, rects: [PageRect(20, 30, 100, 20)]),
      );
      await tester.pump();
      expect(workspace.content.annotations.length, before + 1);
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      expect(slots.slot, PhoneReaderSlot.orb);
      expect(container.read(workspaceProvider('demo-1')).tool, AnnotationTool.highlight);
      final original = tester.getCenter(key('orb'));
      await tester.drag(key('orb'), const Offset(-280, 0));
      await tester.pumpAndSettle();
      expect(slots.dockRight, isFalse);
      expect(container.read(sharedPreferencesProvider).getBool('phoneReader.dockRight'), isFalse);
      expect(tester.getCenter(key('orb')).dx, lessThan(original.dx));
      chrome.onUserScroll(30, atStart: false, geometryKey: 'test');
      await tester.pumpAndSettle();
      expect(chrome.visible, isFalse, reason: 'An armed tool in the orb must not hold the top controls');
      expect(find.byKey(const ValueKey('phone-workspace-more')).hitTestable(), findsNothing);
      expect(key('orb').hitTestable(), findsOneWidget);
      chrome.onUserScroll(-10, atStart: false, geometryKey: 'test');
      await tester.pumpAndSettle();
      expect(chrome.visible, isTrue);
      await tester.tap(key('orb'));
      await tester.pumpAndSettle();
      await tester.tap(key('tool-underline'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Pink').last);
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).underlineColor, MMAnnotationColor.pink);
      await tester.tap(key('tool-ink'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Blue').last);
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).inkColor, MMInkColor.blue);
      await tester.tap(key('collapse'));
      await tester.pumpAndSettle();
      expect(slots.dockRight, isFalse);
      await tester.tap(key('orb'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(slots.slot, PhoneReaderSlot.page);
      expect(container.read(workspaceProvider('demo-1')).tool, AnnotationTool.select);
      slots.openTools();
      await tester.pumpAndSettle();
      await tester.tap(key('tool-select'));
      await tester.pump(const Duration(milliseconds: 499));
      expect(slots.slot, PhoneReaderSlot.tools);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(slots.slot, PhoneReaderSlot.orb);
      await workspace.undo();
      await drain(tester);
      expect(workspace.content.annotations.length, before);
      workspace.openDocument('c2');
      await drain(tester);
      expect(slots.slot, PhoneReaderSlot.page);
      expect(slots.dockRight, isFalse);
      await tester.tap(find.text('Map').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('phone-workspace-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annotation tools'));
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).layout, MMSplitMode.primary);
      expect(key('tools').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drain(tester);
    });
  }

  for (final (phone, touch, size) in [
    (false, true, const Size(500, 900)),
    (false, true, const Size(1194, 834)),
    (false, false, const Size(1280, 820)),
    (true, true, const Size(900, 600)),
  ]) {
    testWidgets('legacy layout stays intact for phone=$phone touch=$touch size=$size', (tester) async {
      final container = await pumpApp(
        tester,
        size: size,
        overrides: [touchPlatformProvider.overrideWithValue(touch), phoneProvider.overrideWithValue(phone)],
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await drain(tester);
      expect(find.byType(PhoneReaderTopControls), findsNothing);
      expect(find.byType(PhoneReaderControls), findsNothing);
      expect(find.byKey(const ValueKey('reader-more')).hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('reader-page-navigation')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drain(tester);
    });
  }

  testWidgets('reflow reader shares the slot, scrubs the whole book and keeps its chapter', (tester) async {
    final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final doc = await storeBook(repo);
    final container = await pumpApp(
      tester,
      content: repo,
      size: const Size(393, 852),
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    container.read(workspaceProvider('demo-1').notifier).openDocument(doc.id);
    await drain(tester);
    final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
    expect(session.ready, isTrue);
    await tester.tap(key('page'));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(key('slider'));
    expect(slider.min, 0);
    expect(slider.max, 1);
    slider.onChanged!(.7);
    await drain(tester);
    expect(session.book!.progress(session.position!), closeTo(.7, .02));
    expect(find.byType(PhoneReaderControls), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
  });

  testWidgets('empty/single-page bounds, keyboard, accessibility and tool cancellation', (tester) async {
    final container = await pumpApp(
      tester,
      size: const Size(320, 568),
      prefs: {'phoneReader.dockRight': false},
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final element = tester.element(find.byType(ReaderPane));
    final slots = PhoneReaderControlsScope.maybeOf(element)!;
    final chrome = WorkspaceChromeScope.maybeOf(element)!;
    expect(slots.dockRight, isFalse);
    final pdf = container.read(readerPdfProvider('demo-1'));
    pdf.debugReport(pageCount: 1, page: 0);
    await tester.tap(key('page'));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(key('slider')).onChanged, isNull);
    expect(tester.widget<Slider>(key('slider')).value, 1);
    slots.openTools();
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    await tester.pumpAndSettle();
    expect(key('tools'), findsNothing);
    chrome.onUserScroll(100, atStart: false, geometryKey: 'keyboard');
    expect(chrome.visible, isTrue);
    tester.view.resetViewInsets();
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      accessibleNavigation: true,
      disableAnimations: true,
      reduceMotion: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpAndSettle();
    chrome.onUserScroll(100, atStart: false, geometryKey: 'accessibility');
    expect(chrome.visible, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
  });
}
