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
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/features/workspace/widgets/reader_ink_toolbar.dart';
import 'package:marginmind/features/workspace/workspace_pane_chrome_controller.dart';
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
  testWidgets('event-only scope lookup does not rebuild with the bottom slot', (tester) async {
    final slots = PhoneReaderControlsController();
    var reads = 0, watches = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MMInput(
          touchPlatform: true,
          phone: true,
          child: SizedBox(
            width: 393,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(393, 852)),
              child: PhoneReaderControlsScope(
                controller: slots,
                child: Column(
                  children: [
                    Builder(
                      builder: (context) {
                        reads++;
                        PhoneReaderControlsScope.read(context);
                        return const SizedBox();
                      },
                    ),
                    Builder(
                      builder: (context) {
                        watches++;
                        PhoneReaderControlsScope.maybeOf(context);
                        return const SizedBox();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    slots.openTools();
    await tester.pump();
    expect(reads, 1);
    expect(watches, 2);
    await tester.pumpWidget(const SizedBox());
    slots.dispose();
  });

  test('armed initial state and document resets stay visible and cancel old timers', () {
    final slots = PhoneReaderControlsController(initiallyArmed: true);
    expect(slots.slot, PhoneReaderSlot.orb);
    slots.reset('a', armed: true);
    slots.openTools();
    slots.annotationCompleted('a');
    slots.reset('b', armed: true);
    expect(slots.slot, PhoneReaderSlot.orb);
    slots.reset('c');
    expect(slots.slot, PhoneReaderSlot.page);
    slots.dispose();
  });

  for (final tool in [AnnotationTool.highlight, AnnotationTool.underline, AnnotationTool.area]) {
    testWidgets('restored ${tool.name} shows its orb on open and document switch', (tester) async {
      installTestPdfBackend(pageCount: 12);
      final container = await pumpApp(
        tester,
        renderPdf: true,
        size: const Size(393, 852),
        prefs: {'settings.annotationTool': tool.name},
        overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await drain(tester);
      final workspace = container.read(workspaceProvider('demo-1').notifier);
      void expectArmedOrb() {
        expect(container.read(workspaceProvider('demo-1')).tool, tool);
        expect(key('page'), findsNothing);
        expect(key('orb').hitTestable(), findsOneWidget);
        expect(find.descendant(of: key('orb'), matching: find.byIcon(phoneReaderToolIcon(tool))), findsOneWidget);
        final paint = tester.widget<Container>(find.descendant(of: key('orb'), matching: find.byType(Container)).first);
        expect((paint.decoration as BoxDecoration).border, isNotNull);
        expect(find.descendant(of: key('orb'), matching: find.byType(Positioned)), findsOneWidget);
      }

      expectArmedOrb();
      workspace.openDocument('c2');
      await drain(tester);
      expectArmedOrb();
      if (tool == AnnotationTool.area) {
        final chrome = WorkspaceChromeScope.maybeOf(tester.element(find.byType(ReaderPane)))!;
        chrome.onUserScroll(30, atStart: false, geometryKey: 'area');
        await tester.pumpAndSettle();
        expect(chrome.visible, isFalse);
        final gesture = await tester.startGesture(tester.getCenter(find.byType(MMPdfView)));
        await tester.pump();
        expect(chrome.visible, isFalse, reason: 'Area pointer-down must preserve immersion');
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(chrome.visible, isFalse);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drain(tester);
    });
  }

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
      await tester.tapAt(tester.getCenter(find.byType(MMPdfView)));
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
      for (final width in MMInkWidth.values) {
        expect(key('width-${width.name}').hitTestable(), findsOneWidget);
        await tester.tap(key('width-${width.name}'));
        await tester.pumpAndSettle();
        expect(container.read(workspaceProvider('demo-1')).inkWidth, width);
        expect(tester.widget<MMFloatingToolbarStrokeWidth>(key('width-${width.name}')).selected, isTrue);
      }
      await tester.tap(key('ink-ellipse'));
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).inkTool, MMPdfInkTool.ellipse);
      await tester.tap(key('ink-eraser'));
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).inkTool, MMPdfInkTool.eraser);
      expect(tester.widget<MMFloatingToolbarStrokeWidth>(key('width-bold')).selected, isFalse);
      await tester.tap(find.byKey(const ValueKey('phone-workspace-more')));
      await tester.pumpAndSettle();
      // Keep the route open while external and embedded commands change state.
      workspace.setInkTool(MMPdfInkTool.arrow);
      await tester.pumpAndSettle();
      expect(tester.widget<ReaderInkToolbar>(find.byType(ReaderInkToolbar)).state.inkTool, MMPdfInkTool.arrow);
      expect(MMFlatSurface.of(tester.element(find.byType(ReaderInkToolbar))), isTrue);
      expect(tester.element(find.byType(ReaderInkToolbar)).mmColors.flat, isTrue);
      final menuWidths = find.descendant(
        of: find.byType(ReaderInkToolbar),
        matching: find.byType(MMFloatingToolbarStrokeWidth),
      );
      tester.widgetList<MMFloatingToolbarStrokeWidth>(menuWidths).first.onPressed!();
      await tester.pumpAndSettle();
      expect(tester.widget<ReaderInkToolbar>(find.byType(ReaderInkToolbar)).state.inkWidth, MMInkWidth.thin);
      expect(tester.widgetList<MMFloatingToolbarStrokeWidth>(menuWidths).first.selected, isTrue);
      container.read(settingsProvider.notifier).setReaderStyle(MMReaderStyle.paper);
      await tester.pumpAndSettle();
      expect(find.descendant(of: key('style-paper'), matching: find.byIcon(MMIcons.check)), findsOneWidget);
      expect(find.descendant(of: key('style-white'), matching: find.byIcon(MMIcons.check)), findsNothing);
      final commands = WorkspacePaneChromeScope.maybeOf(element)!.reader!.commands;
      expect(
        commands.keys,
        containsAll([
          'reader-switch-document',
          'reader-zoom-actualSize',
          'reader-zoom-fitWidth',
          'reader-zoom-fitPage',
        ]),
      );
      expect(commands['reader-switch-document']!.enabled, isTrue);
      expect(commands['reader-zoom-fitWidth']!.enabled, isTrue);
      await tester.ensureVisible(key('style-dark'));
      await tester.tap(key('style-dark'));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).readerStyle, MMReaderStyle.dark);
      expect(tester.takeException(), isNull, reason: 'A selected command must not read a disposed menu ref');
      await tester.tap(find.byKey(const ValueKey('phone-workspace-more')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(key('collapse'));
      await tester.pumpAndSettle();
      expect(slots.dockRight, isFalse);
      chrome.onUserScroll(30, atStart: false, geometryKey: 'pen');
      await tester.pumpAndSettle();
      expect(chrome.visible, isFalse);
      final pen = await tester.startGesture(tester.getCenter(find.byType(MMPdfView)));
      await tester.pump();
      expect(chrome.visible, isFalse, reason: 'Pen pointer-down must preserve immersion');
      await pen.up();
      await tester.pumpAndSettle();
      expect(chrome.visible, isFalse, reason: 'A pen tap must not reveal the top bar either');
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
      expect(tester.element(find.byType(ReaderPane)).mmColors.flat, isTrue);
      expect(find.ancestor(of: find.byType(ReaderPane), matching: find.byType(MMFlatSurface)), findsOneWidget);
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
    expect(slider.semanticFormatterCallback!(.5), '50%');
    slider.onChanged!(.7);
    await drain(tester);
    expect(session.book!.progress(session.position!), closeTo(.7, .02));
    final slots = PhoneReaderControlsScope.read(tester.element(find.byType(ReaderPane)))!;
    slots.openTools();
    await tester.pumpAndSettle();
    await tester.tap(key('tool-highlight'));
    await tester.pumpAndSettle();
    final controls = tester.getRect(find.byType(PhoneReaderControls));
    expect(tester.getRect(key('colors')).right, closeTo(controls.right - MMSpacing.m, .01));
    slots.dock(right: false);
    await tester.pumpAndSettle();
    expect(tester.getRect(key('colors')).left, closeTo(controls.left + MMSpacing.m, .01));
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
