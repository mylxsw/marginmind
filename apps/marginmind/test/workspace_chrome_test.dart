import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/phone_tabs.dart';
import 'package:marginmind/features/workspace/workspace_chrome_controller.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';
import 'reader_crop_test.dart' show drain;

void scroll(WorkspaceChromeController chrome, double delta, {bool atStart = false, Object geometry = 'viewport'}) =>
    chrome.onUserScroll(delta, atStart: atStart, geometryKey: geometry);

void main() {
  test('direction thresholds, geometry changes, invalid input and independent holds', () {
    final chrome = WorkspaceChromeController();
    addTearDown(chrome.dispose);
    var changes = 0;
    chrome.addListener(() => changes++);
    scroll(chrome, 23);
    expect(chrome.visible, isTrue);
    scroll(chrome, 1);
    expect(chrome.visible, isFalse);
    scroll(chrome, -7);
    expect(chrome.visible, isFalse);
    scroll(chrome, -1);
    expect(chrome.visible, isTrue);
    scroll(chrome, 20);
    scroll(chrome, -1);
    scroll(chrome, 4);
    expect(chrome.visible, isTrue);
    scroll(chrome, 20, geometry: 'rotation');
    expect(chrome.visible, isTrue);
    scroll(chrome, double.nan);
    scroll(chrome, double.infinity);
    scroll(chrome, 0);
    chrome.hold('selection');
    chrome.hold('menu');
    chrome.release('selection');
    scroll(chrome, 100);
    expect(chrome.visible, isTrue);
    chrome.release('menu');
    scroll(chrome, 24);
    expect(chrome.visible, isFalse);
    scroll(chrome, 100, atStart: true);
    expect(chrome.visible, isTrue);
    chrome.reset('document');
    scroll(chrome, 24);
    chrome.reset('document');
    expect(chrome.visible, isFalse);
    chrome.reset('replacement');
    expect(chrome.visible, isTrue);
    expect(changes, 6);
  });

  testWidgets('only vertical user scroll hides; hidden controls lose input and semantics', (tester) async {
    final chrome = WorkspaceChromeController();
    final controller = ScrollController();
    addTearDown(chrome.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceChromeScope(
          controller: chrome,
          child: Stack(
            children: [
              WorkspaceReadingScroll(
                child: ListView(controller: controller, children: const [SizedBox(height: 3000)]),
              ),
              Positioned(
                top: 0,
                child: WorkspaceChromeBar(
                  child: TextButton(onPressed: () {}, child: const Text('Command')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    controller.jumpTo(100);
    await tester.pumpAndSettle();
    expect(chrome.visible, isTrue);
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(chrome.visible, isFalse);
    expect(find.text('Command').hitTestable(), findsNothing);
    expect(
      tester
          .widget<ExcludeSemantics>(
            find.descendant(of: find.byType(WorkspaceChromeBar), matching: find.byType(ExcludeSemantics)).first,
          )
          .excluding,
      isTrue,
    );
    await tester.drag(find.byType(ListView), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(chrome.visible, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final (phone, size) in [
    (true, const Size(402, 874)),
    (false, const Size(1194, 834)),
    (false, const Size(500, 1000)),
  ]) {
    testWidgets('PDF scroll hides both ends and tap restores; phone=$phone size=$size', (tester) async {
      installTestPdfBackend(pageCount: 12);
      final container = await pumpApp(
        tester,
        renderPdf: true,
        size: size,
        overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(phone)],
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await drain(tester);
      final reader = find.byType(ReaderPane);
      final chrome = WorkspaceChromeScope.maybeOf(tester.element(reader))!;
      final pdf = tester.widget<MMPdfView>(find.byType(MMPdfView)).controller;
      final viewportSize = tester.getSize(find.byType(MMPdfView));
      // Programmatic page changes never hide the chrome.
      unawaited(pdf.jumpToPage(2));
      await drain(tester);
      expect(chrome.visible, isTrue);
      await tester.timedDragFrom(
        tester.getCenter(find.byType(MMPdfView)),
        const Offset(0, -160),
        const Duration(milliseconds: 400),
      );
      await drain(tester);
      expect(chrome.visible, isFalse);
      expect(tester.getSize(find.byType(MMPdfView)), viewportSize);
      expect(find.byKey(const ValueKey('reader-more')).hitTestable(), findsNothing);
      await tester.tapAt(tester.getCenter(find.byType(MMPdfView)));
      await tester.pumpAndSettle();
      expect(chrome.visible, isTrue);
      // Menu anchors stay visible until the menu closes.
      await tester.tap(find.byKey(const ValueKey('reader-more')));
      await tester.pumpAndSettle();
      scroll(chrome, 100);
      expect(chrome.visible, isTrue);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      if (phone) {
        expect(find.byType(PhoneTabBar), findsNothing);
        expect(tester.getSize(find.byType(MMThumbDockScope)).height, MMSizes.thumbDock);
      }
      await tester.pumpWidget(const SizedBox());
      await drain(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop, accessibility, keyboard and editing holds reset independently', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final chrome = WorkspaceChromeScope.maybeOf(tester.element(find.byType(ReaderPane)))!;
    scroll(chrome, 100);
    expect(chrome.visible, isTrue);
    expect(container.read(navigationProvider), isA<WorkspaceRoute>());
  });
  testWidgets('accessibility, keyboard, rotation and ink keep touch chrome discoverable', (tester) async {
    final container = await pumpApp(
      tester,
      size: const Size(402, 874),
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final chrome = WorkspaceChromeScope.maybeOf(tester.element(find.byType(ReaderPane)))!;
    scroll(chrome, 24);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(chrome.visible, isFalse);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      accessibleNavigation: true,
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(chrome.visible, isTrue);
    scroll(chrome, 100);
    expect(chrome.visible, isTrue);
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    scroll(chrome, 100);
    expect(chrome.visible, isTrue);
    final bar = find.descendant(of: find.byType(MMThumbDockScope), matching: find.byType(MMToolbar));
    expect(bar.hitTestable(), findsNothing);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final owner = container.read(workspaceProvider('demo-1').notifier);
    await owner.setTool(AnnotationTool.ink);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    scroll(chrome, 100);
    expect(chrome.visible, isTrue);
    await owner.setTool(AnnotationTool.select);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    scroll(chrome, 24);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(chrome.visible, isFalse);
    tester.view.physicalSize = const Size(874, 402);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(chrome.visible, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('phone more opens vocabulary and back keeps the workspace pane', (tester) async {
    final container = await pumpApp(
      tester,
      size: const Size(402, 874),
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Map').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('phone-workspace-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vocabulary').last);
    await tester.pumpAndSettle();
    expect(container.read(navigationProvider), isA<VocabularyRoute>());
    expect(find.byType(PhoneTabBar), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(container.read(navigationProvider), isA<WorkspaceRoute>());
    expect(container.read(workspaceProvider('demo-1')).layout, MMSplitMode.secondary);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion changes visibility immediately without a slide', (tester) async {
    final chrome = WorkspaceChromeController();
    addTearDown(chrome.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: WorkspaceChromeScope(
            controller: chrome,
            child: const WorkspaceChromeBar(child: SizedBox(width: 100, height: 50)),
          ),
        ),
      ),
    );
    scroll(chrome, 24);
    await tester.pump();
    final slide = tester.widget<AnimatedSlide>(find.byType(AnimatedSlide));
    expect(slide.duration, Duration.zero);
    expect(slide.offset, const Offset(0, -1));
    chrome.reveal();
    await tester.pump();
    expect(tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset, Offset.zero);
  });
}
