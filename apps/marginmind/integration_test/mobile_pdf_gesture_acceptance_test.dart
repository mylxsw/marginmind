import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_browser.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/main.dart' as app;
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:path_provider/path_provider.dart';

import 'mobile_redesign_acceptance_test.dart' show idle;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('PDF pan, interruption and pinch work in the actual phone runtime', (tester) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await app.main();
    await idle(tester, 6);
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    container.read(settingsProvider.notifier)
      ..setLanguage(LanguagePreference.zh)
      ..setAppearance(AppearancePreference.light);
    container.read(navigationProvider.notifier).showLibrary();
    await idle(tester);
    final sample = find.text('打开示例学习集');
    await tester.tap(sample.evaluate().isNotEmpty ? sample : find.textContaining(RegExp(r'^(示例：|Sample:)')).first);
    await idle(tester, 6);
    final route = container.read(navigationProvider) as WorkspaceRoute;
    final workspace = container.read(workspaceProvider(route.studySetId).notifier);
    workspace.openDocument(workspace.content.documents.firstWhere((doc) => doc.fileName.endsWith('.pdf')).id);
    workspace.setLayout(MMSplitMode.primary);
    await workspace.setTool(AnnotationTool.select);
    await idle(tester, 3);
    final view = find.byType(MMPdfView);
    final pdf = tester.widget<MMPdfView>(view).controller;
    expect(pdf.isReady, isTrue);
    final marker = File('${(await getTemporaryDirectory()).path}/mobile-redesign-shot');
    Future<void> shot(String name) async {
      await idle(tester);
      expect(tester.takeException(), isNull);
      if (!const bool.fromEnvironment('CAPTURE_PHONE_UI')) return;
      await tester.runAsync(() async {
        await marker.writeAsString(name);
        // ignore: avoid_print
        print('PHONE_SHOT:$name:${marker.path}');
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (await marker.readAsString() != 'captured:$name') {
          if (DateTime.now().isAfter(deadline)) throw TimeoutException('Host did not capture $name');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
    }

    Future<void> nativeInteraction(String action) async {
      await tester.runAsync(() async {
        await marker.writeAsString('native:$action');
        // ignore: avoid_print
        print('PHONE_NATIVE:$action:${marker.path}');
        final deadline = DateTime.now().add(const Duration(minutes: 4));
        while (await marker.readAsString() != 'native-done:$action') {
          if (DateTime.now().isAfter(deadline)) throw TimeoutException('Native XCTest did not finish $action');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
      await idle(tester);
    }

    Future<void> top() async {
      unawaited(pdf.firstPage());
      await idle(tester, 2);
    }

    await top();
    final origin = tester.getRect(view).center;
    await shot('01-pdf-before-drag');
    final finger = await tester.startGesture(origin);
    await finger.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 16));
    final before = pdf.scrollPosition!.offset;
    await finger.moveBy(const Offset(0, -80));
    await tester.pump(const Duration(milliseconds: 16));
    final moved = pdf.scrollPosition!.offset - before;
    expect(moved, closeTo(80, 2), reason: 'Direct pan must follow the finger at 1:1 speed');
    await finger.cancel();
    await idle(tester);
    await shot('02-pdf-after-drag');
    await top();
    await tester.flingFrom(origin, const Offset(0, -180), 1500);
    await tester.pump(const Duration(milliseconds: 100));
    final stop = await tester.startGesture(origin);
    await tester.pump(const Duration(milliseconds: 16));
    final stopped = pdf.scrollPosition!.offset;
    await tester.pump(const Duration(milliseconds: 200));
    expect(pdf.scrollPosition!.offset, closeTo(stopped, 2), reason: 'A new touch must stop inertia');
    await stop.up();
    await shot('03-pdf-fling-interrupted');
    await top();
    final zoom = pdf.zoom;
    final first = await tester.startGesture(origin - const Offset(65, 0), pointer: 11);
    final second = await tester.startGesture(origin + const Offset(65, 0), pointer: 12);
    for (var step = 0; step < 10; step++) {
      await first.moveBy(const Offset(-4, 0));
      await second.moveBy(const Offset(4, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await first.up();
    await second.up();
    await idle(tester);
    expect(pdf.zoom, greaterThan(zoom));
    final pinched = pdf.zoom;
    await tester.pump(const Duration(milliseconds: 300));
    expect(pdf.zoom, closeTo(pinched, .01));
    await shot('04-pdf-pinch-stable');
    // ignore: avoid_print
    print('PDF_GESTURES:platform=${Platform.operatingSystem},drag=$moved,interrupted=$stopped,zoom=$zoom->$pinched');
    if (MMNativePresentation.available) {
      await top();
      final beforeNativePan = pdf.scrollPosition!.offset;
      // The live-test binding drops OS touches unless explicitly enabled.
      // Restore it so the test cannot change pointer handling for other tests.
      final liveBinding = tester.binding as IntegrationTestWidgetsFlutterBinding;
      final previousPropagation = liveBinding.shouldPropagateDevicePointerEvents;
      liveBinding.shouldPropagateDevicePointerEvents = true;
      try {
        await nativeInteraction('PdfCanvas');
      } finally {
        liveBinding.shouldPropagateDevicePointerEvents = previousPropagation;
      }
      expect(
        pdf.scrollPosition!.offset,
        greaterThan(beforeNativePan + 60),
        reason: 'UIKit-delivered touches must scroll the live PDF',
      );
      await shot('04a-native-pdf-pan');
    }
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await idle(tester);
    final context = tester.element(find.byType(AppShell, skipOffstage: false));
    final widgetRef = tester.element(find.byType(ReaderPane)) as WidgetRef;
    unawaited(showAddWebPage(context, widgetRef, route.studySetId));
    await idle(tester);
    if (MMNativePresentation.available) {
      final beforeNativeForm = pdf.readingPosition!;
      await shot('05-landscape-web-form');
      await nativeInteraction('LandscapeWebForm');
      final afterNativeForm = pdf.readingPosition!;
      expect(afterNativeForm.page, beforeNativeForm.page);
      expect(
        afterNativeForm.y,
        closeTo(beforeNativeForm.y, 2),
        reason: 'Native form keyboard must not move the underlying reader',
      );
      await shot('06-landscape-form-closed');
    } else {
      final address = find.descendant(of: find.byType(MMSheet), matching: find.byType(TextField));
      tester.widget<TextField>(address).focusNode!.unfocus();
      await idle(tester);
      await tester.tap(address);
      await tester.enterText(address, 'https://example.com');
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      for (var attempt = 0; attempt < 50 && tester.view.viewInsets.bottom == 0; attempt++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (attempt % 10 == 0) await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
        });
        await tester.pump();
      }
      await shot('05-landscape-web-form');
      expect(tester.view.viewInsets.bottom, greaterThan(0), reason: 'The actual soft keyboard must be visible');
      expect(find.byKey(const ValueKey('mm-bottom-sheet')), findsOneWidget);
      await tester.ensureVisible(find.text('取消'));
      await idle(tester);
      await shot('06-landscape-form-actions');
      await tester.tap(find.text('取消').hitTestable());
      await idle(tester);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await idle(tester);
    expect(tester.takeException(), isNull);
  });
}
